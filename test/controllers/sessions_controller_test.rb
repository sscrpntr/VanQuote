require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  class FakeRoutesService
    def initialize(origin:, destination:); end

    def call
      { distance_km: 620, duration_minutes: 360 }
    end
  end
  setup do
    @user = User.create!(
      first_name: "Test",
      last_name: "User",
      phone: "+34600000000",
      email_address: "user@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
  end

  test "shows login form" do
    get new_session_path

    assert_response :success
    assert_select "h1", "Inicia sesión"
    assert_select "form"
  end

  test "login page offers Google OAuth and hides Apple when it is not configured" do
    get new_session_path

    assert_response :success
    assert_select "form[action=?]", oauth_initiation_path(provider: "google_oauth2") do
      assert_select "button.auth-social-button-google[aria-label='Continuar con Google']" do
        assert_select "img.auth-social-google-logo[src=?][alt='']", "/google-g-logo.png"
      end
    end
    assert_select "form[action=?]", oauth_initiation_path(provider: "apple"), count: 0
    assert_not_includes response.body, "Continuar con Apple"
    assert_not_includes response.body, "Próximamente"
  end

  test "login page hides Apple and keeps Google in every supported locale" do
    translations = {
      "es" => [ "Continuar con Google", "Continuar con Apple" ],
      "ca" => [ "Continua amb Google", "Continua amb Apple" ],
      "en" => [ "Continue with Google", "Continue with Apple" ]
    }

    translations.each do |locale, (google_label, apple_label)|
      post locale_path, params: { locale: locale, return_to: new_session_path }
      get new_session_path

      assert_response :success
      assert_select "button.auth-social-button-google[aria-label=?]", google_label
      assert_select "form[action=?]", oauth_initiation_path(provider: "apple"), count: 0
      assert_not_includes response.body, apple_label
      assert_not_includes response.body, "translation_missing"
    end
  end

  test "creates a session with valid credentials" do
    assert_difference "Session.count", 1 do
      post session_path, params: {
        email_address: "user@example.com",
        password: "password123"
      }
    end

    assert_response :redirect
    assert_equal dashboard_path, URI.parse(response.location).path
  end

  test "authenticated user sees the logout control next to the profile link" do
    authenticate_as(@user)

    get root_path

    assert_response :success
    assert_select "nav.site-navigation a[href=?]", profile_path, text: "Mi perfil"
    assert_select "nav.site-navigation form[action=?]", session_path do
      assert_select "input[name=_method][value=delete]"
      assert_select "button[type=submit]", text: "Cerrar sesión"
    end
  end

  test "logout destroys the session and redirects to the public landing page" do
    authenticate_as(@user)
    session_record = Session.find_by!(user: @user)
    get dashboard_path
    assert_response :success

    assert_difference "Session.count", -1 do
      delete session_path
    end

    assert_response :see_other
    assert_redirected_to root_path
    assert_not Session.exists?(session_record.id)

    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "anonymous user does not see the logout control" do
    get root_path

    assert_response :success
    assert_select "nav.site-navigation", count: 0
    assert_select "form[action=?] input[type=submit][value='Cerrar sesión']", session_path, count: 0
  end

  test "login from the landing page opens the dashboard" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_session_path, text: "Iniciar sesión"

    get new_session_path
    assert_response :success

    post session_path, params: {
      email_address: "user@example.com",
      password: "password123"
    }

    assert_redirected_to dashboard_path
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

    follow_redirect!

    assert_response :success
    assert_select ".auth-alert", text: I18n.t("sessions.alerts.invalid_credentials")
  end

  test "preserves return location after authentication" do
    quote = create_quote_for(@user)
    get quote_path(quote)

    assert_redirected_to new_session_path
    assert_equal new_session_path, URI.parse(response.location).path

    post session_path, params: {
      email_address: "user@example.com",
      password: "password123"
    }

    assert_response :redirect
    assert_redirected_to quote_path(quote)
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

    assert_equal @user.id, quote.reload.user_id
  end

  test "login preserves an unconsented quote until the user explicitly accepts operational email" do
    quote = create_unconsented_quote(contact_email: @user.email_address)

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }
    assert quote.contact_email.casecmp?(@user.email_address)
    assert session[:quote_token_after_authenticating].present?
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.lead
    assert_not @user.reload.operational_email_consent_valid?
    follow_redirect!
    assert_response :success

    post request_quote_contact_path,
      params: { token: public_token_for(quote), contact_preference: "EMAIL_QUOTE" }
    assert_redirected_to new_operational_consent_path

    assert_difference "Lead.count", 1 do
      post operational_consent_path, params: { accept_operational_email: "1" }
    end

    assert_redirected_to contact_confirmation_path
    lead = quote.reload.lead
    assert_equal "EMAIL_QUOTE", lead.contact_preference
    assert_equal @user.email_address, lead.email
    assert_equal @user.reload.operational_email_consent_at, lead.consent_at
    assert_equal "account_operational_email", lead.consent_basis
  end

  test "signed quote context lets an authenticated user claim an anonymous quote with a different email" do
    quote = create_unconsented_quote(contact_email: "different-owner@example.com")
    get new_session_path, params: { quote_token: public_token_for(quote) }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal @user.id, quote.reload.user_id
    assert_equal "different-owner@example.com", quote.contact_email
    assert_nil quote.lead
    follow_redirect!
    assert_response :success
    assert_select ".auth-notice[role=status][aria-live=polite]",
      text: I18n.t("quotes.public.contact.owner_updated", email: @user.email_address)
  end

  test "quote already owned by the authenticated user is recovered without a claim notice or duplicates" do
    quote = create_quote_for(@user)
    token = public_token_for(quote)
    lead_id = quote.lead.id

    get new_session_path, params: { quote_token: token }
    assert_no_difference [ "Quote.count", "Lead.count" ] do
      post session_path, params: {
        email_address: @user.email_address,
        password: "password123"
      }
    end

    assert_equal public_quotes_path, URI.parse(response.location).path
    follow_redirect!
    assert_response :success
    assert_select ".auth-notice", count: 0
    assert_equal @user.id, quote.reload.user_id
    assert_equal lead_id, quote.lead.id
  end

  test "rejecting operational consent does not create a lead or confirmation" do
    quote = create_unconsented_quote(contact_email: @user.email_address)
    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_CONTACT"
    }
    assert session[:quote_token_after_authenticating].present?
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_equal public_quotes_path, URI.parse(response.location).path
    follow_redirect!
    assert_response :success
    post request_quote_contact_path,
      params: { token: public_token_for(quote), contact_preference: "EMAIL_CONTACT" }
    assert_redirected_to new_operational_consent_path
    assert_no_difference "Lead.count" do
      post operational_consent_path, params: { accept_operational_email: "0" }
    end

    assert_response :unprocessable_entity
    assert_nil quote.reload.lead
    assert_not @user.reload.operational_email_consent_valid?
  end

  test "preserves valid consent for the same public quote when attaching it to the user" do
    quote = create_public_quote
    lead = quote.lead
    consent_at = lead.consent_at

    get new_session_path, params: {
      quote_token: public_token_for(quote)
    }

    assert_no_difference("Lead.count") do
      post session_path, params: {
        email_address: @user.email_address,
        password: "password123"
      }
    end

    assert_response :redirect
    assert_equal @user.id, quote.reload.user_id
    assert_equal true, lead.reload.consent_given
    assert_equal consent_at, lead.consent_at
    assert_nil lead.contact_preference
  end

  test "EMAIL_QUOTE authentication returns the same quote before creating a lead" do
    quote = create_unconsented_quote(contact_email: @user.email_address)
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.lead
    follow_redirect!
    assert_response :success

    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "EMAIL_QUOTE" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_QUOTE", quote.reload.lead.contact_preference
  end

  test "EMAIL_QUOTE login authenticates the user and retains the selected quote context" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    assert_response :success

    assert_difference "Session.count", 1 do
      post session_path, params: {
        email_address: @user.email_address,
        password: "password123"
      }
    end

    assert_response :redirect
    assert_equal @user.id, Session.order(:created_at).last.user_id
    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.reload.lead.contact_preference
    assert_equal public_quotes_path, URI.parse(response.location).path

    get quote_path(quote)
    assert_response :success
  end

  test "EMAIL_CONTACT can be requested from the recovered quote" do
    quote = create_unconsented_quote(contact_email: @user.email_address)
    assert quote.contact_email.casecmp?(@user.email_address)
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_CONTACT"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.lead
    follow_redirect!

    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "EMAIL_CONTACT" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_CONTACT", quote.reload.lead.contact_preference
  end

  test "PHONE preference is selected after authentication and routes to confirmation" do
    quote = create_unconsented_quote(contact_email: @user.email_address)
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "PHONE"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect

    assert_equal @user.id, quote.reload.user_id
    follow_redirect!
    assert_response :success
    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "PHONE" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "PHONE", quote.reload.lead.contact_preference
    assert_equal @user.phone, quote.lead.phone
  end

  test "invalid public token does not attach a quote" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: "invalid-token",
      contact_preference: "EMAIL_QUOTE"
    }

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect
    assert_not_equal public_quotes_path, URI.parse(response.location).path
    assert_nil quote.reload.user_id
    assert_nil quote.lead.reload.contact_preference
  end

  test "expired public token does not attach or expose its quote" do
    quote = create_public_quote
    token = quote.signed_id(purpose: :public_view, expires_in: -1.second)

    get new_session_path, params: {
      quote_token: token,
      contact_preference: "EMAIL_QUOTE"
    }
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect
    assert_not_equal public_quotes_path, URI.parse(response.location).path
    assert_nil quote.reload.user_id
    assert_nil quote.lead.reload.contact_preference
  end

  test "invalid login keeps the quote context available for another attempt" do
    quote = create_public_quote
    token = public_token_for(quote)

    get new_session_path, params: {
      quote_token: token,
      contact_preference: "EMAIL_QUOTE"
    }
    post session_path, params: {
      email_address: @user.email_address,
      password: "wrong-password"
    }

    assert_redirected_to new_session_path
    get new_session_path

    assert_select "a[href*='quote_token=#{token}']"
    assert_select "a[href*='contact_preference=EMAIL_QUOTE']"

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.reload.lead.contact_preference
  end

  test "an authenticated user is not asked to sign in again for an EMAIL_QUOTE flow" do
    quote = create_public_quote
    authenticate_as(@user)
    existing_session = Session.find_by!(user_id: @user.id)

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    assert_response :redirect
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal existing_session.id, Session.find_by!(user_id: @user.id).id
    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.reload.lead.contact_preference

    follow_redirect!
    assert_response :success
    assert_includes response.body, quote.origin
    assert_select "form[action=?]", request_quote_contact_path, count: 3
    assert_select "nav.site-navigation a[href=?]", profile_path
    assert_select "nav.site-navigation form[action=?]", session_path
  end

  test "anonymous user can visit email contact confirmation without authenticated navigation" do
    get contact_confirmation_path

    assert_redirected_to root_path
  end

  test "EMAIL_QUOTE authentication cannot redirect to an external return target" do
    quote = create_public_quote

    get new_session_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE",
      return_to_after_authenticating: "https://evil.example.com"
    }
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_response :redirect
    assert_equal request.host, URI.parse(response.location).host
    assert_equal public_quotes_path, URI.parse(response.location).path
  end

  test "cannot modify another user's quote with a public token" do
    owner = User.create!(
      first_name: "Owner", last_name: "User", phone: "+34600000003",
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

  def create_unconsented_quote(contact_email:)
    create_quote_in_current_browser(contact_email)
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
    create_unconsented_quote(contact_email: "user@example.com").tap do |quote|
      quote.create_lead!(email: "customer@example.com", consent_given: true,
        consent_at: Time.current, status: "NEW")
    end
  end

  def create_quote_in_current_browser(email)
    original_service = QuotesController.routes_service_class
    QuotesController.routes_service_class = FakeRoutesService
    post quotes_path, params: { quote: { origin: "Barcelona", destination: "Madrid" }, email: email }
    Quote.order(:id).last
  ensure
    QuotesController.routes_service_class = original_service
  end

  def authenticate_as(user)
    post session_path, params: {
      email_address: user.email_address,
      password: "password123"
    }
  end
end
