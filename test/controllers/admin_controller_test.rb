require "test_helper"

class AdminControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", password: "password123", admin: true)
    @user = User.create!(email_address: "user@example.com", password: "password123")
  end

  test "admin can access the dashboard" do
    sign_in(@admin)

    get admin_path

    assert_response :success
    assert_includes response.body, "Total de leads"
    assert_includes response.body, "Leads con consentimiento"
  end

  test "regular user is denied access" do
    sign_in(@user)

    get admin_path

    assert_response :forbidden
  end

  test "unauthenticated user is redirected to login" do
    get admin_path

    assert_redirected_to new_session_path
  end

  test "admin returns to the dashboard after signing in" do
    get admin_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @admin.email_address, password: "password123" }

    assert_redirected_to admin_path
    get admin_path
    assert_response :success
  end

  test "dashboard counts all leads and only consented requests" do
    opted_in = create_lead("yes@example.com")
    opted_out = create_lead("no@example.com")
    opted_out.update_columns(consent_given: false)

    sign_in(@admin)
    get admin_path

    assert_response :success
    assert_includes response.body, "Total de leads</h2>\n      <p>#{Lead.count}</p>"
    assert_includes response.body, "Total de peticiones</h2>\n      <p>#{Lead.with_consent.count}</p>"
    assert_includes response.body, opted_in.email
    assert_not_includes response.body, opted_out.email
  end

  private

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def create_lead(email)
    Lead.create!(
      quote: quotes(:one),
      email: email,
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )
  end
end
