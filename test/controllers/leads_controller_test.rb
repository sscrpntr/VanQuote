require "test_helper"

class LeadsControllerTest < ActionDispatch::IntegrationTest
  test "shows leads" do
    quote = quotes(:one)

    Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    get leads_path

    assert_response :success
    assert_includes response.body, "customer@example.com"
    assert_includes response.body, "Barcelona"
    assert_includes response.body, "Madrid"
    assert_includes response.body, "NEW"
    assert_includes response.body, "€556.25"
  end

  test "shows an empty message when there are no leads" do
    get leads_path

    assert_response :success
    assert_includes response.body, "No hay leads todavía."
  end

  test "updates contact preference to email quote" do
    quote = quotes(:one)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "EMAIL_QUOTE"
      }
    }

    lead.reload

    assert_redirected_to quote_path(quote)
    assert_equal "EMAIL_QUOTE", lead.contact_preference
    assert_nil lead.phone
    assert_equal "Te enviaremos el presupuesto por email.", flash[:notice]
  end

  test "updates contact preference to phone" do
    quote = quotes(:one)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "PHONE",
        phone: "+41 79 123 45 67"
      }
    }

    lead.reload

    assert_redirected_to quote_path(quote)
    assert_equal "PHONE", lead.contact_preference
    assert_equal "+41 79 123 45 67", lead.phone
    assert_equal "Perfecto. Nos pondremos en contacto contigo por teléfono.", flash[:notice]
  end

  test "updates contact preference to email contact" do
    quote = quotes(:one)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "EMAIL_CONTACT"
      }
    }

    lead.reload

    assert_redirected_to quote_path(quote)
    assert_equal "EMAIL_CONTACT", lead.contact_preference
    assert_nil lead.phone
    assert_equal "Perfecto. Nos pondremos en contacto contigo por email.", flash[:notice]
  end

  test "rejects an invalid contact preference" do
    quote = quotes(:one)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "INVALID"
      }
    }

    assert_response :bad_request

    lead.reload

    assert_nil lead.contact_preference
    assert_nil lead.phone
  end

  test "rejects phone preference without a phone number" do
    quote = quotes(:one)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "PHONE"
      }
    }

    assert_response :unprocessable_entity

    lead.reload

    assert_nil lead.contact_preference
    assert_nil lead.phone
  end
end
