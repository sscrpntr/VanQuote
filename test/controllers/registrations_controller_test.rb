require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "shows registration form" do
    get new_registration_path

    assert_response :success
    assert_select "h1", "Crea tu cuenta"
    assert_select "form"
  end

  test "creates a user and starts a session" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          email_address: "new-user@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    user = User.find_by!(email_address: "new-user@example.com")

    assert_response :redirect
    assert_equal root_path, URI.parse(response.location).path
    assert_equal user.id, Session.find_by(user_id: user.id).user_id
  end

  test "EMAIL_QUOTE registration authenticates the new user and retains the selected quote context" do
    quote = create_public_quote

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    assert_response :success
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          email_address: "quote-customer@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    user = User.find_by!(email_address: "quote-customer@example.com")
    assert_response :redirect
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal user.id, Session.find_by!(user_id: user.id).user_id
    assert_equal user.id, quote.reload.user_id
    assert_equal "EMAIL_QUOTE", quote.lead.reload.contact_preference

    follow_redirect!
    assert_response :success
    assert_select ".quote-card.quote-result-card"
    assert_select ".route-address", "Barcelona"
    assert_select ".route-address", "Madrid"
  end

  test "invalid registration preserves quote context for the next attempt" do
    quote = create_public_quote

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }
    post registration_path, params: { user: {
      email_address: "", password: "password123", password_confirmation: "password123"
    } }

    assert_response :unprocessable_entity
    post registration_path, params: { user: {
      email_address: "retry@example.com", password: "password123", password_confirmation: "password123"
    } }

    user = User.find_by!(email_address: "retry@example.com")
    assert_response :redirect
    assert_equal user.id, quote.reload.user_id
    assert_equal "EMAIL_QUOTE", quote.lead.reload.contact_preference
  end

  test "invalid registration token cannot attach a quote" do
    quote = create_public_quote
    get new_registration_path, params: { quote_token: "invalid-token", contact_preference: "EMAIL_QUOTE" }
    post registration_path, params: { user: {
      email_address: "invalid-token-user@example.com", password: "password123", password_confirmation: "password123"
    } }

    assert_response :redirect
    assert_equal root_path, URI.parse(response.location).path
    assert_nil quote.reload.user_id
    assert_nil quote.lead.reload.contact_preference
  end

  test "does not create a user with an invalid email" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          email_address: "",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Crea tu cuenta"
  end

  test "does not create a user with mismatched passwords" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          email_address: "new-user@example.com",
          password: "password123",
          password_confirmation: "different-password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Crea tu cuenta"
  end

  test "does not create a user with an existing email" do
    User.create!(
      email_address: "existing@example.com",
      password: "password123"
    )

    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          email_address: "EXISTING@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Crea tu cuenta"
  end

  private

  def public_token_for(quote)
    quote.signed_id(purpose: :public_view, expires_in: 24.hours)
  end

  def create_public_quote
    quote = Quote.create!(origin: "Barcelona", destination: "Madrid", distance_km: 620,
      estimated_duration_minutes: 360, fuel_cost: 74.4, toll_cost: 0, vehicle_cost: 62,
      driver_cost: 150, loading_cost: 20, waiting_cost: 0, other_cost: 10,
      total_cost: 316.4, margin: 25, recommended_price: 395.5)
    quote.create_lead!(email: "customer@example.com", consent_given: true,
      consent_at: Time.current, status: "NEW")
    quote
  end
end
