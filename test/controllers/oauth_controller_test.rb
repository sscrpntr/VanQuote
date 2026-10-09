require "test_helper"

class OauthControllerTest < ActionDispatch::IntegrationTest
  GOOGLE_TEST_KEY_ID = "vanquote-test-google-key".freeze
  GOOGLE_TEST_KEY = OpenSSL::PKey::RSA.generate(2048)

  class FakeRoutesService
    def initialize(origin:, destination:); end

    def call
      { distance_km: 100, duration_minutes: 60 }
    end
  end

  setup do
    jwk = JWT::JWK.new(GOOGLE_TEST_KEY.public_key).export.transform_keys(&:to_s)
    jwk["kid"] = GOOGLE_TEST_KEY_ID
    Rails.application.config.x.oauth.google_jwks = { "keys" => [ jwk ] }
  end

  test "new Google account requires terms but keeps operational consent optional" do
    auth = oauth_auth("google_oauth2", "google-new", "google-new@example.com")

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end

    assert_redirected_to new_registration_path
    follow_redirect!
    assert_response :success
    assert_select "input[name='user[accept_terms]'][required]"
    assert_select "input[name='user[accept_operational_email]']:not([required])"
    assert_select "input[name='user[accept_operational_email]']:not([checked])"
    assert_select "form[action=?] button.button-primary.oauth-cancel-button:not([disabled])",
      cancel_oauth_registration_path
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

  test "new Google account records explicit operational communications acceptance" do
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

  test "legacy Google account with blank migrated names accepts terms without duplication or losing admin access" do
    admin = User.create!(first_name: "Legacy", last_name: "Admin", email_address: "legacy-admin@example.com",
      password: "password123", admin: true)
    admin.update_columns(first_name: "", last_name: "")
    admin.identities.create!(provider: "google", uid: "legacy-admin-google")

    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "legacy-admin-google", admin.email_address)
    }
    assert_redirected_to new_registration_path
    pending = session[:pending_oauth_signup]
    assert pending.is_a?(Hash), "expected an OAuth signup in session"
    assert_equal admin.id, pending["user_id"] || pending[:user_id]
    follow_redirect!
    assert_response :success
    assert_select "input[name='user[first_name]']", count: 0
    assert_select "input[name='user[last_name]']", count: 0

    assert_no_difference [ "User.count", "Identity.count" ] do
      post registration_path, params: { user: { accept_terms: "1" } }
    end

    assert_redirected_to dashboard_path
    admin.reload
    assert_equal "Ari", admin.first_name
    assert_equal "Google", admin.last_name
    assert admin.terms_accepted?
    assert admin.admin?
    assert_not admin.operational_email_consent_valid?

    get admin_path
    assert_response :success
  end

  test "canceling acceptance for a legacy Google account leaves it unchanged" do
    user = User.create!(first_name: "Legacy", last_name: "Cancel", email_address: "legacy-cancel@example.com",
      password: "password123")
    user.update_columns(first_name: "", last_name: "")
    user.identities.create!(provider: "google", uid: "legacy-cancel-google")

    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "legacy-cancel-google", user.email_address)
    }
    assert_redirected_to new_registration_path

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post cancel_oauth_registration_path
    end

    assert_redirected_to root_path
    user.reload
    assert_equal "", user.first_name
    assert_equal "", user.last_name
    assert_not user.terms_accepted?
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
    assert_select "input[name='user[accept_terms]']:not([checked])"
    assert_select "input[name='user[accept_operational_email]'][checked]"
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

  test "OAuth registration restores the same quote before contact selection and gates contact until consent" do
    quote = create_quote(contact_email: "google-quote@example.com")
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_registration_path, params: { quote_token: token, contact_preference: "EMAIL_CONTACT" }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-quote", "google-quote@example.com")
    }

    assert_no_difference [ "Quote.count", "Lead.count" ] do
      post registration_path, params: { user: { accept_terms: "1" } }
    end
    user = User.find_by!(email_address: "google-quote@example.com")
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal user.id, quote.reload.user_id
    assert_equal 0, Lead.where(quote: quote).count
    assert_not user.operational_email_consent_valid?

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Barcelona"
    assert_select "form[action=?]", request_quote_contact_path, count: 3

    assert_no_difference "Lead.count" do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "EMAIL_CONTACT" }
    end
    assert_redirected_to new_operational_consent_path
    assert_nil quote.reload.lead

    assert_difference "Lead.count", 1 do
      post operational_consent_path, params: { accept_operational_email: "1" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_CONTACT", quote.reload.lead.contact_preference
    assert_equal user.email_address, quote.lead.email
  end

  test "matching email alone does not link Google until the account password is confirmed" do
    user = User.create!(first_name: "Existing", last_name: "Google", email_address: "existing@example.com", password: "password123",
      terms_accepted_at: Time.current, terms_version: User::TERMS_VERSION)
    user.grant_operational_email_consent!(consent_text: "previous explicit grant")
    user.verify_email!
    auth = oauth_auth("google_oauth2", "google-existing", user.email_address)

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end
    assert_redirected_to new_session_path
    assert_difference [ "Identity.count", "Session.count" ], 1 do
      post session_path, params: { email_address: user.email_address, password: "password123" }
    end
    assert_redirected_to dashboard_path
    assert user.reload.operational_email_consent_valid?
    assert_equal 1, user.operational_email_consent_events.where(action: "granted").count
  end

  test "existing Google account with both acceptances returns to its pending quote without duplicating records" do
    user = User.create!(first_name: "Existing", last_name: "Ready", email_address: "ready@example.com", password: "password123",
      terms_accepted_at: Time.current, terms_version: User::TERMS_VERSION)
    user.identities.create!(provider: "google", uid: "google-ready")
    user.grant_operational_email_consent!(consent_text: "previous explicit grant")
    quote = create_quote(contact_email: "original-quote@example.com")
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_session_path, params: { quote_token: token, contact_preference: "EMAIL_CONTACT" }

    assert_no_difference [ "User.count", "OperationalEmailConsentEvent.count", "Quote.count", "Lead.count" ] do
      assert_no_difference "Identity.count" do
        assert_difference "Session.count", 1 do
        post "/auth/google_oauth2/callback", env: {
          "omniauth.auth" => oauth_auth("google_oauth2", "google-ready", user.email_address)
        }
        end
      end
    end

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal user.id, quote.reload.user_id
    assert_equal 1, user.operational_email_consent_events.where(action: "granted").count
    follow_redirect!
    assert_response :success
    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "EMAIL_CONTACT" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_CONTACT", quote.reload.lead.contact_preference
  end

  test "existing matching email requires password authentication and explicit terms acceptance before linking" do
    user = User.create!(first_name: "Existing", last_name: "Google", email_address: "legacy@example.com", password: "password123")
    user.verify_email!
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-legacy", user.email_address)
    }

    assert_redirected_to new_session_path
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post session_path, params: { email_address: user.email_address, password: "password123" }
    end
    assert_redirected_to new_registration_path
    assert_nil user.reload.terms_accepted_at
    follow_redirect!
    assert_select "input[type=submit][value='Aceptar']"
    assert_select "input[name='user[accept_terms]'][required]"
    assert_select "input[name='user[accept_operational_email]']", count: 0

    post registration_path, params: { user: { accept_terms: "1" } }
    assert_redirected_to dashboard_path
    assert_equal user.id, Identity.find_by!(provider: "google", uid: "google-legacy").user_id
    assert_not user.reload.operational_email_consent_valid?
  end

  test "already linked Google account accepts pending terms and recovers the quote without duplicates" do
    user = User.create!(first_name: "Existing", last_name: "Linked", email_address: "linked-pending@example.com",
      password: "password123")
    user.identities.create!(provider: "google", uid: "linked-pending-uid")
    quote = create_quote(contact_email: "original-quote@example.com")
    token = public_token_for(quote)
    get new_session_path, params: { quote_token: token }

    assert_no_difference [ "User.count", "Identity.count", "Quote.count", "Lead.count" ] do
      post "/auth/google_oauth2/callback", env: {
        "omniauth.auth" => oauth_auth("google_oauth2", "linked-pending-uid", user.email_address)
      }
    end
    assert_redirected_to new_registration_path
    follow_redirect!

    assert_response :success
    assert_select "form.auth-form[action=?][method=post]", registration_path do
      assert_select "input[name='user[accept_terms]'][required]:not([checked])"
      assert_select "input[type=submit][value='Aceptar']"
    end

    assert_no_difference [ "User.count", "Identity.count", "Quote.count", "Lead.count" ] do
      post registration_path, params: { user: { accept_terms: "1" } }
    end

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert user.reload.terms_accepted?
    assert_not user.operational_email_consent_valid?
    assert_equal user.id, quote.reload.user_id
    assert_equal "original-quote@example.com", quote.contact_email
    assert_equal 100, quote.distance_km
    assert_equal 60, quote.estimated_duration_minutes
    assert_equal 37.5, quote.recommended_price
    assert_equal [ "linked-pending-uid" ], user.identities.pluck(:uid)
    assert_nil quote.lead
    follow_redirect!
    assert_response :success
    assert_select ".auth-notice[role=status][aria-live=polite]",
      text: I18n.t("quotes.public.contact.owner_updated", email: user.email_address)
    assert_includes response.body, quote.origin
    assert_includes response.body, quote.destination
  end

  test "failed existing Google acceptance preserves selections and pending quote" do
    user = User.create!(first_name: "Existing", last_name: "Retry", email_address: "linked-retry@example.com",
      password: "password123")
    user.identities.create!(provider: "google", uid: "linked-retry-uid")
    quote = create_quote(contact_email: user.email_address)
    token = public_token_for(quote)
    get new_session_path, params: { quote_token: token, contact_preference: "EMAIL_CONTACT" }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "linked-retry-uid", user.email_address)
    }
    follow_redirect!

    assert_no_difference [ "User.count", "Identity.count", "Quote.count", "Lead.count" ] do
      post registration_path,
        params: { user: { accept_terms: "0", accept_operational_email: "1" } }
    end

    assert_response :unprocessable_entity
    assert_select ".auth-alert[role=alert]"
    assert_select "input[name='user[accept_terms]']:not([checked])"
    assert_select "input[name='user[accept_operational_email]'][checked]"
    assert_nil user.reload.terms_accepted_at
    assert_nil quote.reload.user_id

    post registration_path, params: { user: { accept_terms: "1" } }
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal user.id, quote.reload.user_id
    assert_equal 1, User.where(email_address: user.email_address).count
  end

  test "unavailable acceptance schema returns a clear error and preserves checkbox and quote context" do
    user = User.create!(first_name: "Existing", last_name: "Schema", email_address: "schema-pending@example.com",
      password: "password123")
    user.identities.create!(provider: "google", uid: "schema-pending-uid")
    quote = create_quote(contact_email: user.email_address)
    token = public_token_for(quote)
    get new_session_path, params: { quote_token: token }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "schema-pending-uid", user.email_address)
    }

    original_column_names = User.method(:column_names)
    User.define_singleton_method(:column_names) do
      original_column_names.call - [ "terms_accepted_at" ]
    end
    begin
      post registration_path, params: { user: { accept_terms: "1" } }
    ensure
      User.define_singleton_method(:column_names, original_column_names)
    end

    assert_response :service_unavailable
    assert_select ".auth-alert[role=alert]", text: /guardar tu aceptación/
    assert_select "input[name='user[accept_terms]'][checked]"
    assert_not user.reload.terms_accepted?
    assert_nil quote.reload.user_id
    assert session[:quote_token_after_authenticating].present?
    assert session[:pending_oauth_signup].present?
  end

  test "acceptance refreshes a stale Active Record column cache before processing" do
    user = User.create!(first_name: "Existing", last_name: "Cached", email_address: "stale-schema@example.com",
      password: "password123")
    user.identities.create!(provider: "google", uid: "stale-schema-uid")
    quote = create_quote(contact_email: user.email_address)
    get new_session_path, params: { quote_token: public_token_for(quote) }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "stale-schema-uid", user.email_address)
    }
    assert_redirected_to new_registration_path

    original_method_defined = User.method(:method_defined?)
    User.define_singleton_method(:method_defined?) do |name, inherit = true|
      name.to_s == "terms_accepted_at=" ? false : original_method_defined.call(name, inherit)
    end
    begin
      post registration_path, params: { user: { accept_terms: "1" } }
    ensure
      User.define_singleton_method(:method_defined?, original_method_defined)
    end

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert user.reload.terms_accepted?
    assert_equal user.id, quote.reload.user_id
  end

  test "existing Google user can accept terms without consenting when no contact action is pending" do
    user = User.create!(first_name: "Legacy", last_name: "Google", email_address: "legacy-terms@example.com", password: "password123")
    user.identities.create!(provider: "google", uid: "google-legacy-terms")
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-legacy-terms", user.email_address)
    }

    get new_registration_path
    assert_response :success
    assert_select "input[type=submit][value='Aceptar'][disabled]"
    assert_select "input[name='user[accept_terms]'][required]"
    assert_select "input[name='user[accept_operational_email]']", count: 0

    post registration_path, params: { user: { accept_terms: "1" } }
    assert_redirected_to dashboard_path
    assert user.reload.terms_accepted?
    assert_not user.operational_email_consent_valid?
  end

  test "existing Google user with pending quote can accept terms alone and then choose whether to contact" do
    user = User.create!(first_name: "Legacy", last_name: "Google", email_address: "legacy-quote@example.com", password: "password123")
    user.identities.create!(provider: "google", uid: "google-legacy-quote")
    quote = create_quote(contact_email: user.email_address)
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_session_path, params: { quote_token: token, contact_preference: "EMAIL_QUOTE" }
    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-legacy-quote", user.email_address)
    }
    assert_redirected_to new_registration_path
    follow_redirect!

    assert_select "form[data-registration-consent-require-communications-value='false']"
    assert_select "input[type=submit][value='Aceptar'][disabled]"
    assert_select "input[name='user[accept_operational_email]']:not([required])"
    assert_no_difference "User.count" do
      post registration_path, params: { user: { accept_terms: "1" } }
    end

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal user.id, quote.reload.user_id
    assert_nil quote.lead
    assert_not user.reload.operational_email_consent_valid?
    follow_redirect!
    assert_response :success
    assert_select "form[action=?]", request_quote_contact_path, count: 3

    post request_quote_contact_path,
      params: { token: public_token_for(quote), contact_preference: "EMAIL_QUOTE" }
    assert_redirected_to new_operational_consent_path
  end

  test "existing terms-accepted Google user with no communications consent completes pending contact through Accept" do
    user = User.create!(first_name: "Existing", last_name: "Customer", phone: "+41791234567", email_address: "existing-contact@example.com",
      password: "password123", terms_accepted_at: Time.current, terms_version: User::TERMS_VERSION)
    user.identities.create!(provider: "google", uid: "google-existing-contact")
    quote = create_quote(contact_email: user.email_address)
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_session_path, params: { quote_token: token, contact_preference: "PHONE" }

    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-existing-contact", user.email_address)
    }

    assert_equal public_quotes_path, URI.parse(response.location).path
    follow_redirect!
    assert_response :success
    assert_nil quote.reload.lead
    assert_select "form[action=?]", request_quote_contact_path, count: 3

    post request_quote_contact_path,
      params: { token: public_token_for(quote), contact_preference: "PHONE" }
    assert_redirected_to new_operational_consent_path
    follow_redirect!
    assert_select "input[type=submit][value='Aceptar']"
    assert_select "input[name='accept_operational_email'][required]"

    post operational_consent_path, params: { accept_operational_email: "1" }
    assert_redirected_to contact_confirmation_path
    assert_equal user.id, quote.reload.user_id
    assert_equal "PHONE", quote.lead.contact_preference
    assert user.reload.operational_email_consent_valid?
  end

  test "withdrawn Google consent is not restored by OAuth and needs an explicit Accept action" do
    user = User.create!(first_name: "Existing", last_name: "Withdrawn", email_address: "withdrawn@example.com",
      password: "password123", terms_accepted_at: Time.current, terms_version: User::TERMS_VERSION)
    user.identities.create!(provider: "google", uid: "google-withdrawn")
    user.grant_operational_email_consent!(consent_text: "previous explicit grant")
    user.withdraw_operational_email_consent!
    quote = create_quote(contact_email: user.email_address)
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_session_path, params: { quote_token: token, contact_preference: "EMAIL_CONTACT" }

    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => oauth_auth("google_oauth2", "google-withdrawn", user.email_address)
    }
    assert_equal public_quotes_path, URI.parse(response.location).path
    follow_redirect!
    assert_response :success
    assert_select "form[action=?]", request_quote_contact_path, count: 3
    assert_not user.reload.operational_email_consent_valid?
    assert_nil quote.reload.lead

    post request_quote_contact_path,
      params: { token: public_token_for(quote), contact_preference: "EMAIL_CONTACT" }
    assert_redirected_to new_operational_consent_path
    follow_redirect!
    assert_select "input[type=submit][value='Aceptar']"

    post operational_consent_path, params: { accept_operational_email: "1" }
    assert_redirected_to contact_confirmation_path
    events = user.operational_email_consent_events.order(:id).pluck(:action)
    assert_equal %w[granted withdrawn granted], events
    assert_equal "EMAIL_CONTACT", quote.reload.lead.contact_preference
  end

  test "unverified OAuth email cannot create or link an account" do
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: {
        "omniauth.auth" => oauth_auth("google_oauth2", "google-unverified", "unverified@example.com", verified: false)
      }
    end
    assert_redirected_to new_session_path
  end

  test "Google OAuth rejects a missing ID token" do
    auth = oauth_auth("google_oauth2", "google-no-id-token", "missing-token@example.com")
    auth.fetch("extra").delete("id_token")

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end
    assert_redirected_to new_session_path
  end

  test "Google OAuth rejects malformed and expired ID tokens" do
    malformed = oauth_auth("google_oauth2", "google-malformed", "malformed@example.com")
    malformed.fetch("extra")["id_token"] = "not-a-jwt"
    expired = oauth_auth("google_oauth2", "google-expired", "expired@example.com", expires_at: 1.minute.ago.to_i)

    [ malformed, expired ].each do |auth|
      assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
        post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
      end
      assert_redirected_to new_session_path
    end
  end

  test "Google OAuth rejects a token with an invalid signature" do
    auth = oauth_auth("google_oauth2", "google-invalid-signature", "invalid-signature@example.com")
    audience = Rails.application.config.x.oauth.google_client_id.presence || "test-google-client-id"
    auth.fetch("extra")["id_token"] = JWT.encode(
      { "iss" => "https://accounts.google.com", "aud" => audience,
        "sub" => "google-invalid-signature", "email" => "invalid-signature@example.com",
        "email_verified" => true, "iat" => Time.current.to_i, "exp" => 5.minutes.from_now.to_i },
      OpenSSL::PKey::RSA.generate(2048), "RS256", { "kid" => GOOGLE_TEST_KEY_ID }
    )

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
    end
    assert_redirected_to new_session_path
  end

  test "Google OAuth rejects an unexpected issuer or audience" do
    [
      oauth_auth("google_oauth2", "google-invalid-issuer", "invalid-issuer@example.com", issuer: "attacker.example"),
      oauth_auth("google_oauth2", "google-invalid-audience", "invalid-audience@example.com", audience: "attacker-client")
    ].each do |auth|
      assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
        post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
      end
      assert_redirected_to new_session_path
    end
  end

  test "Google OAuth rejects an ID token for a different subject" do
    auth = oauth_auth("google_oauth2", "google-oauth-subject", "subject@example.com", token_subject: "different-google-subject")

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      post "/auth/google_oauth2/callback", env: { "omniauth.auth" => auth }
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

  def oauth_auth(provider, uid, email, verified: true, issuer: "https://accounts.google.com",
    audience: nil, token_subject: uid, expires_at: 5.minutes.from_now.to_i)
    {
      "provider" => provider,
      "uid" => uid,
      "info" => { "email" => email, "first_name" => "Ari", "last_name" => "Google", "name" => "Ari Google" },
      "extra" => {
        "id_token" => google_id_token(
          sub: token_subject,
          email: email,
          email_verified: verified,
          issuer: issuer,
          audience: audience || Rails.application.config.x.oauth.google_client_id.presence || "test-google-client-id",
          expires_at: expires_at
        )
      }
    }
  end

  def google_id_token(sub:, email:, email_verified:, issuer:, audience:, expires_at:)
    JWT.encode(
      { "iss" => issuer, "aud" => audience, "sub" => sub, "email" => email,
        "email_verified" => email_verified, "iat" => Time.current.to_i, "exp" => expires_at },
      GOOGLE_TEST_KEY,
      "RS256",
      { "kid" => GOOGLE_TEST_KEY_ID }
    )
  end

  def public_token_for(quote)
    quote.signed_id(purpose: :public_view, expires_in: 24.hours)
  end

  def create_quote(contact_email: "quote@example.com")
    original_service = QuotesController.routes_service_class
    QuotesController.routes_service_class = FakeRoutesService
    post quotes_path, params: { quote: { origin: "Barcelona", destination: "Girona" }, email: contact_email }
    Quote.order(:id).last.tap do |quote|
      quote.update!(fuel_cost: 10, toll_cost: 0, vehicle_cost: 10, driver_cost: 10,
        loading_cost: 0, waiting_cost: 0, other_cost: 0, margin: 25,
        total_cost: 30, recommended_price: 37.5)
    end
  ensure
    QuotesController.routes_service_class = original_service
  end
end
