require "test_helper"

class OauthControllerTest < ActionDispatch::IntegrationTest
  test "new Google account requires in-app terms acceptance before account creation" do
    auth = oauth_auth("google_oauth2", "google-new", "google-new@example.com")

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end

    assert_redirected_to new_registration_path
    follow_redirect!
    assert_response :success
    assert_select "input[name='user[accept_terms]'][required]"
    assert_select "input[name='user[accept_operational_email]']:not([checked])"
    assert_includes response.body, "google-new@example.com"

    assert_difference [ "User.count", "Identity.count", "Session.count" ], 1 do
      post registration_path, params: { user: { accept_terms: "1" } }
    end

    user = User.find_by!(email_address: "google-new@example.com")
    assert_redirected_to dashboard_path
    assert user.terms_accepted?
    assert_not user.operational_email_consent_valid?
    assert_equal user.id, Identity.find_by!(provider: "google", uid: "google-new").user_id
  end

  test "new Google account can grant optional operational communications explicitly" do
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-consent", "google-consent@example.com")
    }

    post registration_path, params: { user: { accept_terms: "1", accept_operational_email: "1" } }

    user = User.find_by!(email_address: "google-consent@example.com")
    assert_redirected_to dashboard_path
    assert user.operational_email_consent_valid?
    event = user.operational_email_consent_events.find_by!(action: "granted")
    assert_equal User::OPERATIONAL_EMAIL_CONSENT_PURPOSE, event.purpose
    assert_equal I18n.t("registrations.new.operational_consent_text"), event.consent_text
  end

  test "rejecting terms leaves no OAuth account, identity, or session" do
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-reject", "google-reject@example.com")
    }

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post registration_path, params: { user: { accept_terms: "0", accept_operational_email: "1" } }
    end
    assert_response :unprocessable_entity
    assert_select ".auth-alert", text: /términos y condiciones/
  end

  test "canceling Google registration clears temporary identity and preserves quote token" do
    quote = create_quote(contact_email: "google-quote@example.com")
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_registration_path, params: { quote_token: token }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-cancel", "google-cancel@example.com")
    }

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post cancel_oauth_registration_path
    end
    assert_redirected_to public_quotes_path(token: token)
    assert_nil quote.reload.user_id
  end

  test "OAuth registration restores the signed anonymous quote and gates contact until explicit consent" do
    quote = create_quote(contact_email: "google-quote@example.com")
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_registration_path, params: { quote_token: token, contact_preference: "EMAIL_CONTACT" }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-quote", "google-quote@example.com")
    }

    assert_no_difference "Quote.count" do
      post registration_path, params: { user: { accept_terms: "1" } }
    end

    user = User.find_by!(email_address: "google-quote@example.com")
    assert_redirected_to new_operational_consent_path
    assert_equal user.id, quote.reload.user_id
    assert_nil quote.lead
    assert_not user.operational_email_consent_valid?

    assert_difference "Lead.count", 1 do
      post operational_consent_path, params: { accept_operational_email: "1" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_CONTACT", quote.reload.lead.contact_preference
    assert_equal user.email_address, quote.lead.email
  end

  test "existing accepted account is linked and signed in without new consent" do
    user = User.create!(first_name: "Existing", last_name: "Google", email_address: "existing@example.com", password: "password123",
      terms_accepted_at: Time.current, terms_version: User::TERMS_VERSION)
    auth = oauth_auth("google_oauth2", "google-existing", user.email_address)

    assert_no_difference "User.count" do
      assert_difference [ "Identity.count", "Session.count" ], 1 do
        post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
      end
    end
    assert_redirected_to dashboard_path
    assert_not user.reload.operational_email_consent_valid?
  end

  test "existing account without terms must accept them before Google identity is linked" do
    user = User.create!(first_name: "Existing", last_name: "Google", email_address: "legacy@example.com", password: "password123")
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-legacy", user.email_address)
    }

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post registration_path, params: { user: { accept_terms: "0" } }
    end
    assert_response :unprocessable_entity
    assert_nil user.reload.terms_accepted_at

    post registration_path, params: { user: { accept_terms: "1" } }
    assert_redirected_to dashboard_path
    assert_equal user.id, Identity.find_by!(provider: "google", uid: "google-legacy").user_id
    assert_not user.reload.operational_email_consent_valid?
  end

  test "unverified OAuth email cannot create or link an account" do
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: {
        "omniauth.auth" => oauth_auth("google_oauth2", "google-unverified", "unverified@example.com", verified: false)
      }
    end
    assert_redirected_to new_session_path
  end

  test "provider errors and malformed callback fail without creating accounts" do
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      get "/auth/failure", params: { message: "access_denied" }
    end
    assert_redirected_to new_session_path
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback"
    end
    assert_redirected_to new_session_path
  end

  private

  def oauth_auth(provider, uid, email, verified: true)
    {
      "provider" => provider,
      "uid" => uid,
      "info" => { "email" => email, "first_name" => "Ari", "last_name" => "Google", "name" => "Ari Google" },
      "extra" => { "id_info" => { "email_verified" => verified } }
    }
  end

  def create_quote(contact_email: "quote@example.com")
    Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: contact_email,
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 10, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 10, loading_cost: 0, waiting_cost: 0, other_cost: 0,
      margin: 25, total_cost: 30, recommended_price: 37.5)
  end
end
