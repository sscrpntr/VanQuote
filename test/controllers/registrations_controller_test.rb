require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  class FakeRoutesService
    def initialize(origin:, destination:); end

    def call
      { distance_km: 620, duration_minutes: 360 }
    end
  end

  test "shows registration form" do
    get new_registration_path

    assert_response :success
    assert_select "h1", "Crea tu cuenta"
    assert_select "form"
    assert_select "form input[name='user[phone]']", count: 0
    assert_select "form input[type=tel]", count: 0
    assert_select "label[for='user_first_name']", text: "Nombre"
    assert_select "label[for='user_last_name']", text: "Apellidos"
    assert_select "label[for='user_email_address']", text: "Email"
    assert_select "label[for='user_password']", text: "Contraseña"
    assert_select "label[for='user_password_confirmation']", text: "Repite tu contraseña"
    assert_select "a[href=?]", new_session_path, text: "Iniciar sesión"
    assert_select "form[action=?] button.auth-social-button-google", oauth_initiation_path(provider: "google_oauth2") do
      assert_select "img.auth-social-google-logo[src=?][alt='']", "/google-g-logo.png"
    end
    assert_select "form[action=?]", oauth_initiation_path(provider: "apple"), count: 0
    assert_not_includes response.body, "Continuar con Apple"
    assert_not_includes response.body, "translation_missing"
    assert_not_includes response.body, "Próximamente"
    assert_select "input[name='user[accept_terms]'][required]"
    assert_select "input[name='user[accept_operational_email]']:not([required])"
    assert_select "input[type=submit][disabled][value='Crear cuenta']"
    assert_select "a[href=?]", terms_path, text: "términos y condiciones"
    terms_checkbox_position = response.body.index('name="user[accept_terms]"')
    communications_checkbox_position = response.body.index('name="user[accept_operational_email]"')
    heading_position = response.body.index("Create your account") || response.body.index("Crea tu cuenta")
    assert_operator terms_checkbox_position, :<, heading_position
    assert_operator communications_checkbox_position, :<, heading_position
  end

  test "registration fields and social actions are translated in every supported locale" do
    translations = {
      "es" => [ "Nombre", "Apellidos", "Email", "Contraseña", "Repite tu contraseña", "Continuar con Google", "¿Ya tienes una cuenta?", "Iniciar sesión" ],
      "ca" => [ "Nom", "Cognoms", "Email", "Contrasenya", "Repeteix la teva contrasenya", "Continua amb Google", "Ja tens un compte?", "Iniciar sessió" ],
      "en" => [ "First name", "Last name", "Email", "Password", "Repeat your password", "Continue with Google", "Already have an account?", "Sign in" ]
    }

    translations.each do |locale, labels|
      post locale_path, params: { locale: locale, return_to: new_registration_path }
      get new_registration_path

      assert_response :success
      labels.each { |label| assert_includes response.body, label }
      assert_not_includes response.body, "translation_missing"
      assert_not_includes response.body, "Apple"
      assert_select "form input[type=tel]", count: 0
      assert_select "a[href=?]", new_session_path, text: labels.last
    end
  end

  test "OAuth initiation falls back with a translated setup notice when credentials are absent" do
    post oauth_initiation_path(provider: "google_oauth2")

    assert_redirected_to new_registration_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "El acceso con Google requiere configuración externa."
  end

  test "creates a user and starts a session" do
    assert_difference "User.count", 1 do
      submit_registration({
          first_name: "Test",
          last_name: "User",
          phone: "+34600000000",
          email_address: "new-user@example.com",
          password: "password123",
          password_confirmation: "password123"
      })
    end

    user = User.find_by!(email_address: "new-user@example.com")

    assert_response :redirect
    assert_equal dashboard_path, URI.parse(response.location).path
    assert_equal user.id, Session.find_by(user_id: user.id).user_id
    assert_nil user.phone
    assert user.operational_email_consent_valid?
    assert_equal "2026-10-v1", user.terms_version
    assert_equal 1, user.operational_email_consent_events.where(action: "granted").count
    event = user.operational_email_consent_events.find_by!(action: "granted")
    assert_equal I18n.t("registrations.new.operational_consent_text"), event.consent_text
    assert_equal User::OPERATIONAL_EMAIL_CONSENT_PURPOSE, event.purpose
  end

  test "a password account cannot authenticate until its email verification link is used" do
    ActionMailer::Base.deliveries.clear
    assert_no_difference "Session.count" do
      post registration_path, params: { user: {
        first_name: "Verify", last_name: "Me", email_address: "verify-me@example.com",
        password: "password123", password_confirmation: "password123",
        accept_terms: "1", accept_operational_email: "0"
      } }
    end

    user = User.find_by!(email_address: "verify-me@example.com")
    assert_not user.email_verified?
    assert_equal "verify-me@example.com", ActionMailer::Base.deliveries.last.to.first
    post session_path, params: { email_address: user.email_address, password: "password123" }
    assert_redirected_to new_session_path
    assert_empty user.sessions

    link = ActionMailer::Base.deliveries.last.body.to_s.lines.find { |line| line.include?("/email-verification?") }.strip
    assert_difference "Session.count", 1 do
      get URI.parse(link).request_uri
    end
    assert_redirected_to dashboard_path
    assert user.reload.email_verified?
    get dashboard_path
    assert_response :success
  end

  test "new registration requires terms but keeps operational communications optional" do
    assert_no_difference [ "User.count", "Session.count", "OperationalEmailConsentEvent.count" ] do
      submit_registration({
        first_name: "No", last_name: "Consent", email_address: "no-consent@example.com",
        password: "password123", password_confirmation: "password123"
      }, terms: false)
    end

    assert_response :unprocessable_entity
    assert_select ".auth-alert", text: /términos y condiciones/
    assert_select "input[name='user[accept_terms]']:not([checked])"
    assert_select "input[name='user[accept_operational_email]'][checked]"

    assert_difference [ "User.count", "Session.count" ], 1 do
      assert_no_difference "OperationalEmailConsentEvent.count" do
        submit_registration({
        first_name: "Optional", last_name: "Consent", email_address: "optional@example.com",
        password: "password123", password_confirmation: "password123"
        }, operational_email: false)
      end
    end
    user = User.find_by!(email_address: "optional@example.com")
    assert_redirected_to dashboard_path
    assert user.terms_accepted?
    assert_not user.operational_email_consent_valid?
  end

  test "registration cannot set consent fields through client submitted account attributes" do
    assert_no_difference [ "User.count", "OperationalEmailConsentEvent.count" ] do
      post registration_path, params: {
        user: {
          first_name: "Forged", last_name: "Consent", email_address: "forged@example.com",
          password: "password123", password_confirmation: "password123",
          operational_email_consent: "1",
          operational_email_consent_at: Time.current.iso8601,
          operational_email_consent_text_version: User::OPERATIONAL_EMAIL_CONSENT_VERSION,
          operational_email_consent_purpose: User::OPERATIONAL_EMAIL_CONSENT_PURPOSE
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "withdrawal changes current consent state and keeps an event history" do
    submit_registration({
      first_name: "Audit", last_name: "User", email_address: "audit@example.com",
      password: "password123", password_confirmation: "password123"
    })
    user = User.find_by!(email_address: "audit@example.com")
    granted_at = user.operational_email_consent_at
    grant_event = user.operational_email_consent_events.find_by!(action: "granted")
    quote_specific = create_public_quote
    quote_specific.update!(user: user)
    account_quote = Quote.create!(
      user: user,
      origin: "Lausanne", destination: "Geneva", contact_email: user.email_address,
      distance_km: 60, estimated_duration_minutes: 60, fuel_cost: 7.2,
      toll_cost: 0, vehicle_cost: 6, driver_cost: 25, loading_cost: 20,
      waiting_cost: 0, other_cost: 10, margin: 25, total_cost: 68.2,
      recommended_price: 85.25
    )
    account_lead = account_quote.create_lead!(
      email: user.email_address,
      consent_given: true,
      consent_at: granted_at,
      consent_basis: "account_operational_email",
      status: "NEW"
    )

    delete operational_consent_path

    assert_redirected_to profile_path
    user.reload
    assert_not user.operational_email_consent_valid?
    assert_nil user.operational_email_consent_at
    assert_equal grant_event.id, user.operational_email_consent_events.find_by!(action: "granted").id
    assert_equal "withdrawn", user.operational_email_consent_events.order(:occurred_at).last.action
    assert_operator granted_at, :<=, user.operational_email_consent_events.order(:occurred_at).last.occurred_at
    assert_not_nil account_lead.reload.consent_withdrawn_at
    assert_not Lead.with_consent.exists?(account_lead.id)
    assert Lead.with_consent.exists?(quote_specific.lead.id)
  end

  test "terms page is publicly accessible and contains the service conditions" do
    get terms_path

    assert_response :success
    assert_select "h1", "Términos y condiciones"
    assert_select ".terms-card section", count: 9
    assert_includes response.body, "no equivale al consentimiento"
  end

  test "a newly registered user can sign in after signing out" do
    submit_registration({
        first_name: "New",
        last_name: "User",
        email_address: "new-sign-in@example.com",
        password: "password123",
        password_confirmation: "password123"
    })

    user = User.find_by!(email_address: "new-sign-in@example.com")
    assert_redirected_to dashboard_path

    delete session_path

    assert_difference "Session.count", 1 do
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }
    end

    assert_redirected_to dashboard_path
    assert_equal user.id, Session.order(:created_at).last.user_id
  end

  test "EMAIL_QUOTE registration authenticates the new user and retains the selected quote context" do
    quote = create_public_quote(contact_email: "quote-customer@example.com")

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    assert_response :success
    assert_select "form input[type=tel]", count: 0
    assert_difference "User.count", 1 do
      submit_registration({
          first_name: "Quote",
          last_name: "Customer",
          email_address: "quote-customer@example.com",
          password: "password123",
          password_confirmation: "password123"
      })
    end

    user = User.find_by!(email_address: "quote-customer@example.com")
    assert_response :redirect
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_equal user.id, Session.find_by!(user_id: user.id).user_id
    assert_nil user.phone
    assert_equal user.id, quote.reload.user_id
    assert_nil quote.reload.lead.contact_preference

    follow_redirect!
    assert_response :success
    assert_includes response.body, quote.origin
    assert_select "form[action=?]", request_quote_contact_path, count: 3
  end

  test "registration resumes an anonymous quote without duplicating the quote" do
    quote = create_anonymous_quote_through_form("resume@example.com")
    token = public_token_for(quote)
    get new_registration_path, params: { quote_token: token, contact_preference: "EMAIL_CONTACT" }

    assert_no_difference "Quote.count" do
      submit_registration({
        first_name: "Resume", last_name: "Quote", email_address: "resume@example.com",
        password: "password123", password_confirmation: "password123"
      })
    end

    user = User.find_by!(email_address: "resume@example.com")
    assert_equal user.id, quote.reload.user_id
    assert_equal 0, Lead.where(quote: quote).count
    assert_equal public_quotes_path, URI.parse(response.location).path
    assert user.operational_email_consent_valid?
  end

  test "canceling registration keeps a recoverable signed quote link" do
    quote = Quote.create!(
      origin: "Barcelona", destination: "Madrid", contact_email: "cancel@example.com",
      distance_km: 620, estimated_duration_minutes: 360, fuel_cost: 74.4,
      toll_cost: 0, vehicle_cost: 62, driver_cost: 150, loading_cost: 20,
      other_cost: 10, waiting_cost: 0, margin: 25,
      total_cost: 316.4, recommended_price: 395.5
    )
    token = public_token_for(quote)

    get new_registration_path, params: { quote_token: token }

    assert_select "a[href=?]", public_quotes_path(token: token), text: "← Volver a VanQuote"
    get public_quotes_path(token: token)
    assert_response :success
    assert_nil quote.reload.user_id
    assert_nil quote.lead
  end

  test "invalid registration preserves quote context for the next attempt" do
    quote = create_public_quote(contact_email: "retry@example.com")

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }
    submit_registration({
      first_name: "Test", last_name: "User",
      email_address: "", password: "password123", password_confirmation: "password123"
    })

    assert_response :unprocessable_entity
    submit_registration({
      first_name: "Retry", last_name: "User",
      email_address: "retry@example.com", password: "password123", password_confirmation: "password123"
    })

    user = User.find_by!(email_address: "retry@example.com")
    assert_response :redirect
    assert_equal user.id, quote.reload.user_id
    assert_nil quote.reload.lead.contact_preference
    assert_equal public_quotes_path, URI.parse(response.location).path
  end

  test "invalid registration token cannot attach a quote" do
    quote = create_public_quote
    get new_registration_path, params: { quote_token: "invalid-token", contact_preference: "EMAIL_QUOTE" }
    submit_registration({
      first_name: "Invalid", last_name: "Token",
      email_address: "invalid-token-user@example.com", password: "password123", password_confirmation: "password123"
    })

    assert_response :redirect
    assert_equal dashboard_path, URI.parse(response.location).path
    assert_nil quote.reload.user_id
    assert_nil quote.lead.reload.contact_preference
  end

  test "EMAIL_CONTACT registration does not require or save a phone" do
    quote = create_public_quote(contact_email: "email-contact@example.com")

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_CONTACT"
    }
    assert_response :success
    assert_select "form input[type=tel]", count: 0
    submit_registration({
        first_name: "Email",
        last_name: "Contact",
        email_address: "email-contact@example.com",
        password: "password123",
        password_confirmation: "password123"
    })

    user = User.find_by!(email_address: "email-contact@example.com")
    assert_nil user.phone
    assert_nil quote.reload.lead.contact_preference
    assert_equal public_quotes_path, URI.parse(response.location).path
  end

  test "PHONE registration collects phone only on the locked contact screen" do
    quote = create_public_quote(contact_email: "phone-customer@example.com")

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "PHONE"
    }
    submit_registration({
        first_name: "Phone",
        last_name: "Customer",
        email_address: "phone-customer@example.com",
        password: "password123",
        password_confirmation: "password123"
    })

    user = User.find_by!(email_address: "phone-customer@example.com")
    assert_nil user.phone
    assert_nil quote.reload.lead.contact_preference
    assert_equal public_quotes_path, URI.parse(response.location).path
  end

  test "does not create a user with an invalid email" do
    assert_no_difference "User.count" do
      submit_registration({
        email_address: "",
        password: "password123",
        password_confirmation: "password123"
      })
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Crea tu cuenta"
    assert_select ".auth-alert li", text: /Email address can't be blank/
    assert_not_includes response.body, I18n.t("sessions.alerts.invalid_credentials")
  end

  test "does not create a user with mismatched passwords" do
    assert_no_difference "User.count" do
      submit_registration({
          first_name: "Test",
          last_name: "User",
          email_address: "new-user@example.com",
          password: "password123",
          password_confirmation: "different-password"
      })
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Crea tu cuenta"
    assert_select ".auth-alert li", text: /Password confirmation doesn't match Password/
    assert_not_includes response.body, I18n.t("sessions.alerts.invalid_credentials")
  end

  test "does not create a user with an existing email" do
    User.create!(
      first_name: "Existing",
      last_name: "User",
      phone: "+34600000006",
      email_address: "existing@example.com",
      password: "password123"
    )

    assert_no_difference "User.count" do
      submit_registration({
          email_address: "EXISTING@example.com",
          password: "password123",
          password_confirmation: "password123"
      })
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Crea tu cuenta"
    assert_select ".auth-alert li", text: /Email address has already been taken/
    assert_not_includes response.body, I18n.t("sessions.alerts.invalid_credentials")
  end

  private

  def submit_registration(attributes, terms: true, operational_email: true)
    delivery_count = ActionMailer::Base.deliveries.size
    post registration_path, params: {
      user: attributes.merge(
        accept_terms: terms ? "1" : nil,
        accept_operational_email: operational_email ? "1" : nil
      )
    }

    verification_email = ActionMailer::Base.deliveries.last
    return unless ActionMailer::Base.deliveries.size > delivery_count
    return unless verification_email&.body&.to_s&.include?("/email-verification?")

    link = verification_email.body.to_s.lines.find { |line| line.include?("/email-verification?") }&.strip
    get URI.parse(link).request_uri if link
  end

  def public_token_for(quote)
    quote.signed_id(purpose: :public_view, expires_in: 24.hours)
  end

  def create_public_quote(contact_email: nil)
    quote = create_anonymous_quote_through_form(contact_email)
    quote.create_lead!(email: "customer@example.com", consent_given: true,
      consent_at: Time.current, status: "NEW")
    quote
  end

  def create_anonymous_quote_through_form(contact_email)
    original_service = QuotesController.routes_service_class
    QuotesController.routes_service_class = FakeRoutesService
    post quotes_path, params: {
      quote: { origin: "Barcelona", destination: "Madrid" }, email: contact_email.presence || "quote@example.com"
    }
    Quote.order(:id).last
  ensure
    QuotesController.routes_service_class = original_service
  end
end
