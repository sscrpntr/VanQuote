require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "user@example.com",
      password: "password123"
    )
  end

  test "shows login form" do
    get new_session_path

    assert_response :success
    assert_select "h1", "Inicia sesión"
    assert_select "form"
  end

  test "creates a session with valid credentials" do
    assert_difference "Session.count", 1 do
      post session_path, params: {
        email_address: "user@example.com",
        password: "password123"
      }
    end

    assert_response :redirect
    assert_equal root_path, URI.parse(response.location).path
  end

  test "rejects invalid credentials" do
    assert_no_difference "Session.count" do
      post session_path, params: {
        email_address: "user@example.com",
        password: "wrong-password"
      }
    end

    assert_response :redirect
    assert_equal new_session_path, URI.parse(response.location).path
  end

  test "preserves return location after authentication" do
    get quote_path(create_quote_for(@user))

    assert_response :redirect
    assert_equal new_session_path, URI.parse(response.location).path

    post session_path, params: {
      email_address: "user@example.com",
      password: "password123"
    }

    assert_response :redirect
  end

  test "attaches the public quote to the user after authentication" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: quote.signed_id(
        purpose: :public_view,
        expires_in: 24.hours
      )
    }

    assert_response :success

    post session_path, params: {
      email_address: "user@example.com",
      password: "password123"
    }

    assert_response :redirect

    quote.reload

    assert_equal @user.id, quote.user_id
  end

  private

  def create_quote_for(user)
    Quote.create!(
      user: user,
      origin: "Barcelona",
      destination: "Madrid",
      distance_km: 620,
      estimated_duration_minutes: 360,
      fuel_cost: 74.4,
      toll_cost: 0,
      vehicle_cost: 62,
      driver_cost: 150,
      loading_cost: 20,
      waiting_cost: 0,
      other_cost: 10,
      total_cost: 316.4,
      margin: 25,
      recommended_price: 395.5
    ).id
  end

  def create_public_quote
    Quote.create!(
      origin: "Barcelona",
      destination: "Madrid",
      distance_km: 620,
      estimated_duration_minutes: 360,
      fuel_cost: 74.4,
      toll_cost: 0,
      vehicle_cost: 62,
      driver_cost: 150,
      loading_cost: 20,
      waiting_cost: 0,
      other_cost: 10,
      total_cost: 316.4,
      margin: 25,
      recommended_price: 395.5
    )
  end
end
