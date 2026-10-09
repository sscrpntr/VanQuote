require "test_helper"

class AdminControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(first_name: "Admin", last_name: "User", phone: "+34600000001",
      email_address: "admin@example.com", password: "password123", admin: true, email_verified_at: Time.current)
    @user = User.create!(first_name: "Test", last_name: "User", phone: "+34600000000",
      email_address: "user@example.com", password: "password123", email_verified_at: Time.current)
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

  test "admin table shows the associated customer name and a fallback without a user" do
    named_quote = create_quote_for(@user, origin: "Barcelona", destination: "Girona")
    named_lead = create_lead("named@example.com")
    named_lead.update!(quote: named_quote)

    anonymous_quote = create_quote_for(nil, origin: "Vic", destination: "Reus")
    anonymous_lead = create_lead("anonymous@example.com")
    anonymous_lead.update!(quote: anonymous_quote)

    sign_in(@admin)
    get admin_path

    assert_response :success
    assert_select "th", text: "Cliente"
    assert_select "td", text: "Test User"
    assert_select "td", text: "Cliente no registrado"
  end

  test "admin interface follows the selected locale" do
    create_lead("locale@example.com")
    sign_in(@admin)

    { "ca" => "Administració", "en" => "Administration" }.each do |locale, heading|
      post locale_path, params: { locale: locale, return_to: admin_path }
      assert_redirected_to admin_path
      get admin_path
      assert_response :success
      assert_select "h1", text: "VanQuote · #{heading}"
      assert_select "th", text: locale == "ca" ? "Client" : "Customer"
      assert_select "th", text: locale == "ca" ? "Data" : "Date"
    end
  end

  private

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def create_lead(email)
    Lead.create!(
      quote: create_quote_for(nil, origin: "Lead origin", destination: "Lead destination"),
      email: email,
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )
  end

  def create_quote_for(user, origin:, destination:)
    Quote.create!(
      user: user,
      origin: origin,
      destination: destination,
      distance_km: 620,
      estimated_duration_minutes: 360,
      fuel_cost: 74.4,
      toll_cost: 0,
      vehicle_cost: 62,
      driver_cost: 150,
      loading_cost: 20,
      waiting_cost: 0,
      other_cost: 10,
      margin: 25,
      total_cost: 316.4,
      recommended_price: 395.5
    )
  end
end
