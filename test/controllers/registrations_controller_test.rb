require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
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
      post registration_path, params: {
        user: {
          first_name: "Test",
          last_name: "User",
          phone: "+34600000000",
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
    assert_nil user.phone
  end

  test "EMAIL_QUOTE registration authenticates the new user and retains the selected quote context" do
    quote = create_public_quote

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }

    assert_response :success
    assert_select "form input[type=tel]", count: 0
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          first_name: "Quote",
          last_name: "Customer",
          email_address: "quote-customer@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    user = User.find_by!(email_address: "quote-customer@example.com")
    assert_response :redirect
    assert_equal contact_confirmation_path, URI.parse(response.location).path
    assert_equal user.id, Session.find_by!(user_id: user.id).user_id
    assert_nil user.phone
    assert_equal user.id, quote.reload.user_id
    assert_equal "EMAIL_QUOTE", quote.lead.reload.contact_preference

    follow_redirect!
    assert_response :success
    assert_select "#contact-confirmation-title", "¡Solicitud recibida!"
    assert_select "[role=status]", text: /Solicitud recibida/
  end

  test "invalid registration preserves quote context for the next attempt" do
    quote = create_public_quote

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_QUOTE"
    }
    post registration_path, params: { user: {
      first_name: "Test", last_name: "User",
      email_address: "", password: "password123", password_confirmation: "password123"
    } }

    assert_response :unprocessable_entity
    post registration_path, params: { user: {
      first_name: "Retry", last_name: "User",
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
      first_name: "Invalid", last_name: "Token",
      email_address: "invalid-token-user@example.com", password: "password123", password_confirmation: "password123"
    } }

    assert_response :redirect
    assert_equal root_path, URI.parse(response.location).path
    assert_nil quote.reload.user_id
    assert_nil quote.lead.reload.contact_preference
  end

  test "EMAIL_CONTACT registration does not require or save a phone" do
    quote = create_public_quote

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "EMAIL_CONTACT"
    }
    assert_response :success
    assert_select "form input[type=tel]", count: 0
    post registration_path, params: {
      user: {
        first_name: "Email",
        last_name: "Contact",
        email_address: "email-contact@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    user = User.find_by!(email_address: "email-contact@example.com")
    assert_nil user.phone
    assert_equal "EMAIL_CONTACT", quote.lead.reload.contact_preference
    assert_equal contact_confirmation_path, URI.parse(response.location).path
  end

  test "PHONE registration collects phone only on the locked contact screen" do
    quote = create_public_quote

    get new_registration_path, params: {
      quote_token: public_token_for(quote),
      contact_preference: "PHONE"
    }
    post registration_path, params: {
      user: {
        first_name: "Phone",
        last_name: "Customer",
        email_address: "phone-customer@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    user = User.find_by!(email_address: "phone-customer@example.com")
    lead = quote.lead.reload
    assert_nil user.phone
    assert_nil lead.contact_preference
    assert_redirected_to edit_lead_path(lead)

    follow_redirect!
    assert_response :success
    assert_select "select[name='lead[contact_preference]']", count: 0
    assert_select ".contact-preference-value", text: "Llamada telefónica"
    assert_select "input[type=tel][name='lead[phone]']", count: 1

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "EMAIL_CONTACT",
        phone: " "
      }
    }

    assert_response :unprocessable_entity
    assert_select "select[name='lead[contact_preference]']", count: 0
    assert_select ".contact-preference-value", text: "Llamada telefónica"
    assert_nil user.reload.phone
    assert_nil lead.reload.contact_preference

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "EMAIL_QUOTE",
        phone: "+41 79 555 01 02"
      }
    }

    assert_redirected_to quote_path(quote)
    assert_equal "+41 79 555 01 02", user.reload.phone
    assert_equal "PHONE", lead.reload.contact_preference
    assert_equal "+41 79 555 01 02", lead.phone
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
          first_name: "Test",
          last_name: "User",
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
      first_name: "Existing",
      last_name: "User",
      phone: "+34600000006",
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
