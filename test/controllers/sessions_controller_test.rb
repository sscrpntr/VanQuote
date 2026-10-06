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
      quote_token: public_token_for(quote)
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

  test "EMAIL_QUOTE preference is stored after authentication" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    quote.reload
    quote.lead.reload

    assert_equal @user.id, quote.user_id
    assert_equal "EMAIL_QUOTE", quote.lead.contact_preference
    assert_equal public_quotes_path, URI.parse(response.location).path
  end

  test "EMAIL_CONTACT preference is stored after authentication" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_CONTACT"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    quote.reload
    quote.lead.reload

    assert_equal @user.id, quote.user_id
    assert_equal "EMAIL_CONTACT", quote.lead.contact_preference
    assert_equal public_quotes_path, URI.parse(response.location).path
  end

  test "PHONE preference redirects to the phone form" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "PHONE"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    quote.reload
    quote.lead.reload

    assert_equal @user.id, quote.user_id
    assert_nil quote.lead.contact_preference
    assert_equal edit_lead_path(quote.lead),
                URI.parse(response.location).path
  end

  test "invalid public token does not attach a quote" do
    get new_session_path, params: {
      quote_token: "invalid-token",
      contact_preference: "EMAIL_QUOTE"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect
  end

  test "cannot modify another user's quote with a public token" do
    owner = User.create!(
      email_address: "owner@example.com",
      password: "password123"
    )

    quote = create_quote_for(owner)

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_CONTACT"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    quote.reload
    quote.lead.reload

    assert_equal owner.id, quote.user_id
    assert_nil quote.lead.contact_preference
  end

  private

  def public_token_for(quote)
    quote.signed_id(
      purpose: :public_view,
      expires_in: 24.hours
    )
  end

  def create_quote_for(user)
    quote = Quote.create!(
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
    )

    quote.create_lead!(
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    quote
  end

  def create_public_quote
    create_quote_for(nil)
  end
end
