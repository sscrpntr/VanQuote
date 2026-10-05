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
end
