require "test_helper"

class LeadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      first_name: "Test", last_name: "User", phone: "+34600000000",
      email_address: "user@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
  end

  def sign_in
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }
  end

  test "shows leads" do
    quote = quotes(:one)
    quote.update!(user: @user)

    Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

    get leads_path

    assert_response :success
    assert_includes response.body, "customer@example.com"
    assert_includes response.body, "Barcelona"
    assert_includes response.body, "Madrid"
    assert_includes response.body, "NEW"
    assert_includes response.body, "€556.25"
  end

  test "does not show leads from another user's quotes" do
    quote = quotes(:one)
    quote.update!(user: User.create!(first_name: "Other", last_name: "User", phone: "+34600000002",
      email_address: "other@example.com", password: "password123"))

    Lead.create!(
      quote: quote,
      email: "other-customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

    get leads_path

    assert_response :success
    assert_not_includes response.body, "other-customer@example.com"
  end

  test "admin sees leads from all users' quotes" do
    admin = User.create!(
      first_name: "Admin", last_name: "User", phone: "+34600000001",
      email_address: "admin@example.com",
      password: "password123",
      admin: true,
      email_verified_at: Time.current
    )
    quote = quotes(:one)
    quote.update!(user: @user)

    Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    post session_path, params: {
      email_address: admin.email_address,
      password: "password123"
    }

    get leads_path

    assert_response :success
    assert_includes response.body, "customer@example.com"
  end

  test "redirects unauthenticated users to login" do
    get leads_path

    assert_redirected_to new_session_path
  end

  test "shows an empty message when there are no leads" do
    sign_in

    get leads_path

    assert_response :success
    assert_includes response.body, "No hay leads todavía."
  end

  test "updates contact preference to email quote" do
    quote = quotes(:one)
    quote.update!(user: @user)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

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
    quote.update!(user: @user)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

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
    assert_equal "+41 79 123 45 67", @user.reload.phone
    assert_equal "Perfecto. Nos pondremos en contacto contigo por teléfono.", flash[:notice]
  end

  test "phone preference is shown as non-editable while the phone remains editable" do
    lead = create_phone_lead
    sign_in

    get edit_lead_path(lead)

    assert_response :success
    assert_includes response.body, "Llamada telefónica"
    assert_select "select[name='lead[contact_preference]']", count: 0
    assert_select "input[name='lead[contact_preference]']", count: 0
    assert_select "input[type=tel][name='lead[phone]']", count: 1
  end

  test "phone confirmation updates the signed-in user's phone and locks the preference" do
    lead = create_phone_lead
    sign_in

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "EMAIL_QUOTE",
        phone: "+41 79 555 01 02"
      }
    }

    assert_redirected_to quote_path(lead.quote)
    lead.reload
    @user.reload
    assert_equal "PHONE", lead.contact_preference
    assert_equal "+41 79 555 01 02", lead.phone
    assert_equal "+41 79 555 01 02", @user.phone
    assert_equal "Test", @user.first_name
  end

  test "phone confirmation rejects an empty phone without changing the user or preference" do
    lead = create_phone_lead(phone: "+41 79 123 45 67")
    sign_in

    patch lead_path(lead), params: { lead: { phone: " " } }

    assert_response :unprocessable_entity
    assert_select ".auth-alert"
    assert_equal "PHONE", lead.reload.contact_preference
    assert_equal "+41 79 123 45 67", lead.phone
    assert_equal "+34600000000", @user.reload.phone
  end

  test "updates contact preference to email contact" do
    quote = quotes(:one)
    quote.update!(user: @user)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

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
    quote.update!(user: @user)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

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
    quote.update!(user: @user)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    sign_in

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

  private

  def create_phone_lead(phone: "+34600000000")
    quote = quotes(:one)
    quote.update!(user: @user)
    Lead.create!(
      quote: quote,
      email: "customer@example.com",
      phone: phone,
      contact_preference: "PHONE",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )
  end
end
