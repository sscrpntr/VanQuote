require "test_helper"

class OauthControllerTest < ActionDispatch::IntegrationTest
  test "Google callback creates an identity and session and redirects to dashboard" do
    auth = oauth_auth("google_oauth2", "google-uid", "google@example.com",
      claims: { "email_verified" => true })

    assert_difference [ "User.count", "Identity.count", "Session.count" ], 1 do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end

    user = User.find_by!(email_address: "google@example.com")
    assert_redirected_to dashboard_path
    assert_equal "Ari", user.first_name
    assert_equal "Google", user.last_name
    assert_nil user.phone
    assert_equal user.id, Identity.find_by!(provider: "google", uid: "google-uid").user_id
    assert_equal user.id, Session.order(:created_at).last.user_id
  end

  test "Apple callback creates an identity and session and redirects to dashboard" do
    auth = oauth_auth("apple", "apple-uid", "apple@example.com",
      claims: { "email_verified" => "true" })

    assert_difference [ "User.count", "Identity.count", "Session.count" ], 1 do
      post "/auth/apple/callback", env: { "omniauth.auth" => auth }
    end

    user = User.find_by!(email_address: "apple@example.com")
    assert_redirected_to dashboard_path
    assert_equal user.id, Identity.find_by!(provider: "apple", uid: "apple-uid").user_id
    assert_equal user.id, Session.order(:created_at).last.user_id
    assert_nil user.phone
  end

  test "callback recovers an existing identity without creating another user" do
    user = User.create!(
      first_name: "Existing",
      last_name: "Google",
      email_address: "existing-google@example.com",
      password: "password123"
    )
    user.identities.create!(provider: "google", uid: "existing-uid")
    auth = oauth_auth("google_oauth2", "existing-uid", nil)

    assert_no_difference [ "User.count", "Identity.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end

    assert_redirected_to dashboard_path
    assert_equal user.id, Session.order(:created_at).last.user_id
  end

  test "verified OAuth email attaches to a matching existing user" do
    user = User.create!(
      first_name: "Existing",
      last_name: "Account",
      email_address: "verified@example.com",
      password: "password123"
    )
    auth = oauth_auth("google_oauth2", "verified-uid", user.email_address,
      claims: { "email_verified" => true })

    assert_no_difference "User.count" do
      assert_difference "Identity.count", 1 do
        post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
      end
    end

    assert_redirected_to dashboard_path
    assert_equal user.id, Identity.find_by!(provider: "google", uid: "verified-uid").user_id
  end

  test "OAuth preserves the public quote contact flow through registration" do
    quote = Quote.create!(
      origin: "Barcelona",
      destination: "Girona",
      distance_km: 100,
      estimated_duration_minutes: 60,
      fuel_cost: 10,
      toll_cost: 0,
      vehicle_cost: 10,
      driver_cost: 10,
      loading_cost: 0,
      waiting_cost: 0,
      other_cost: 0,
      margin: 25,
      total_cost: 30,
      recommended_price: 37.5
    )
    Lead.create!(
      quote: quote,
      email: "quote-customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_registration_path, params: { quote_token: token, contact_preference: "EMAIL_QUOTE" }
    auth = oauth_auth("google_oauth2", "quote-user", "quote-oauth@example.com",
      claims: { "email_verified" => true })

    post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }

    user = User.find_by!(email_address: "quote-oauth@example.com")
    assert_redirected_to contact_confirmation_path
    assert_equal user.id, quote.reload.user_id
    assert_equal "EMAIL_QUOTE", quote.lead.reload.contact_preference
  end

  test "unverified OAuth email cannot create or link an account" do
    existing = User.create!(
      first_name: "Existing",
      last_name: "User",
      email_address: "unverified@example.com",
      password: "password123"
    )
    auth = oauth_auth("google_oauth2", "unverified-uid", existing.email_address,
      claims: { "email_verified" => false })

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end

    assert_redirected_to new_session_path
  end

  test "provider errors return to login without creating a session" do
    assert_no_difference "Session.count" do
      get "/auth/failure", params: { message: "access_denied" }
    end

    assert_redirected_to new_session_path
    assert_equal I18n.t("oauth.errors.authentication_failed"), flash[:alert]
  end

  test "callback without a provider payload fails safely" do
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback"
    end

    assert_redirected_to new_session_path
    assert_equal I18n.t("oauth.errors.authentication_failed"), flash[:alert]
  end

  private

  def oauth_auth(provider, uid, email, claims: {})
    {
      "provider" => provider,
      "uid" => uid,
      "info" => {
        "email" => email,
        "first_name" => "Ari",
        "last_name" => provider == "apple" ? "Apple" : nil,
        "name" => "Ari Google"
      }.compact,
      "extra" => { "id_info" => claims }
    }
  end
end
