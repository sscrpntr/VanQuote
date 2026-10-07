require "test_helper"

class QuotesControllerTest < ActionDispatch::IntegrationTest
  class FakeRoutesService
    def initialize(origin:, destination:)
      @origin = origin
      @destination = destination
    end

    def call
      {
        distance_km: 620,
        duration_minutes: 360
      }
    end
  end

  setup do
    @original_routes_service_class = QuotesController.routes_service_class
    QuotesController.routes_service_class = FakeRoutesService

    @user = User.create!(
      email_address: "user@example.com",
      password: "password123"
    )
  end

  teardown do
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "home shows account links outside the quote form" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_session_path, text: "Iniciar sesión"
    assert_select "a[href=?]", new_registration_path, text: "Crear una cuenta"
    assert_select ".quote-card form" do
      assert_select "a[href=?]", new_session_path, count: 0
      assert_select "a[href=?]", new_registration_path, count: 0
    end
  end

  test "home account links use the selected locale" do
    {
      "ca" => {
        sign_in_prompt: "Ja tens un compte?",
        sign_in: "Inicia sessió",
        register_prompt: "Encara no tens un compte?",
        register: "Crea un compte"
      },
      "es" => {
        sign_in_prompt: "¿Ya tienes una cuenta?",
        sign_in: "Iniciar sesión",
        register_prompt: "¿Todavía no tienes una cuenta?",
        register: "Crear una cuenta"
      },
      "en" => {
        sign_in_prompt: "Already have an account?",
        sign_in: "Sign in",
        register_prompt: "Don't have an account yet?",
        register: "Create an account"
      }
    }.each do |locale, translations|
      post locale_path, params: { locale: locale, return_to: root_path }
      assert_redirected_to root_path

      get root_path

      assert_response :success
      assert_select "header.site-header nav.language-selector", count: 1 do
        assert_select "input.language-selector-button", count: 3
      end
      assert_select ".quote-account-option p", text: translations[:sign_in_prompt]
      assert_select ".quote-account-option a[href=?]", new_session_path, text: translations[:sign_in]
      assert_select ".quote-account-option p", text: translations[:register_prompt]
      assert_select ".quote-account-option a[href=?]", new_registration_path, text: translations[:register]
    end
  end

  test "authenticated user can visit home and create a quote" do
    authenticate_as(@user)

    get root_path
    assert_response :success
    assert_select "form.quote-form"

    assert_difference("Quote.count", 1) do
      post quotes_path, params: valid_quote_params
    end

    assert_equal @user.id, Quote.last.user_id
  end

  test "creates a quote" do
    assert_difference("Quote.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 999,
          estimated_duration_minutes: 999,
          fuel_cost: 80,
          toll_cost: 35,
          vehicle_cost: 120,
          driver_cost: 150,
          loading_cost: 20,
          waiting_cost: 30,
          other_cost: 10,
          margin: 25
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    quote = Quote.last

    assert_response :redirect
    assert_match %r{/quotes/public\?token=}, response.location

    assert_equal 316.4.to_d, quote.total_cost
    assert_equal 395.5.to_d, quote.recommended_price
    assert_equal 620.to_d, quote.distance_km
    assert_equal 360.to_d, quote.estimated_duration_minutes
    assert_nil quote.user_id
  end

  test "authenticated user sees only their quotes with a link to each detail" do
    own_quote = create_quote_for(@user, origin: "Barcelona", destination: "Madrid")
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    create_quote_for(other_user, origin: "Paris", destination: "Lyon")

    authenticate_as(@user)
    get quotes_path

    assert_response :success
    assert_includes response.body, "Barcelona"
    assert_includes response.body, quote_path(own_quote)
    assert_not_includes response.body, "Paris"
  end

  test "shows an empty state when the user has no quotes" do
    authenticate_as(@user)

    get quotes_path

    assert_response :success
    assert_includes response.body, I18n.t("quotes.index.empty")
  end

  test "redirects unauthenticated users from quotes to login" do
    get quotes_path

    assert_redirected_to new_session_path
  end

  test "admin can access quotes index" do
    admin = User.create!(email_address: "admin@example.com", password: "password123", admin: true)
    authenticate_as(admin)

    get quotes_path

    assert_response :success
  end

  test "associates a quote created by an authenticated user with that user" do
    authenticate_as(@user)
    assert_response :redirect

    assert_difference("Quote.count", 1) do
      post quotes_path, params: valid_quote_params
    end

    assert_equal @user.id, Quote.last.user_id
  end

  test "attaches an anonymous quote to the user after authentication with its token" do
    post quotes_path, params: valid_quote_params
    quote = Quote.last
    token = URI.decode_www_form(URI(response.location).query).to_h.fetch("token")

    get new_session_path, params: { quote_token: token }
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_equal @user.id, quote.reload.user_id
  end

  test "does not reassign a quote that belongs to another user" do
    owner = User.create!(email_address: "owner@example.com", password: "password123")
    quote = Quote.create!(
      user: owner,
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
      margin: 25,
      total_cost: 336.4,
      recommended_price: 420.5
    )
    quote.create_lead!(
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    get new_session_path, params: { quote_token: public_token_for(quote) }
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_equal owner.id, quote.reload.user_id
  end

  test "creates a lead when creating a quote" do
    assert_difference("Lead.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 999,
          estimated_duration_minutes: 999
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    lead = Lead.last

    assert_equal "customer@example.com", lead.email
    assert_equal true, lead.consent_given
    assert_not_nil lead.consent_at
    assert_equal "NEW", lead.status
    assert_equal Quote.last.id, lead.quote_id
  end

  test "ignores internal costs submitted by the customer" do
    assert_difference("Quote.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 999,
          estimated_duration_minutes: 999,
          fuel_cost: 9999,
          toll_cost: 9999,
          vehicle_cost: 9999,
          driver_cost: 9999,
          loading_cost: 9999,
          waiting_cost: 9999,
          other_cost: 9999,
          margin: 999
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    quote = Quote.last

    assert_equal 74.4.to_d, quote.fuel_cost
    assert_equal 0.to_d, quote.toll_cost
    assert_equal 62.to_d, quote.vehicle_cost
    assert_equal 150.to_d, quote.driver_cost
    assert_equal 20.to_d, quote.loading_cost
    assert_equal 0.to_d, quote.waiting_cost
    assert_equal 10.to_d, quote.other_cost
    assert_equal 25.to_d, quote.margin
    assert_equal 395.5.to_d, quote.recommended_price
  end

  test "shows the public transport price without authentication" do
    quote = quotes(:one)

    token = quote.signed_id(
      purpose: :public_view,
      expires_in: 24.hours
    )

  get public_quotes_path,
    params: { token: token },
    headers: {
      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    }

    puts "TEST REQUEST USER AGENT: #{request.user_agent.inspect}"
    puts "TEST RESPONSE STATUS: #{response.status}"
    puts "TEST RESPONSE CONTENT TYPE: #{response.media_type.inspect}"
    puts "TEST RESPONSE BODY:"
    puts response.body

assert_response :success

    assert_response :success
    assert_includes response.body, "556.25 €"
  end

  test "shows the private quote to its owner" do
    quote = quotes(:one)
    quote.update!(user: @user)

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    get quote_path(quote)
    puts "TEST USER AGENT: #{request.user_agent.inspect}"
    puts "TEST RESPONSE STATUS: #{response.status}"
    puts "TEST RESPONSE LOCATION: #{response.location.inspect}"
    assert_response :success
    assert_includes response.body, "556.25 €"
  end

  test "does not allow an unauthenticated user to access a private quote" do
    quote = quotes(:one)
    quote.update!(user: @user)

    get quote_path(quote)

    assert_redirected_to new_session_path
  end

  test "shows change contact method after selecting a preference" do
    quote = quotes(:one)
    quote.update!(user: @user)

    lead = Lead.create!(
      quote: quote,
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    patch lead_path(lead), params: {
      lead: {
        contact_preference: "PHONE",
        phone: "+41 79 123 45 67"
      }
    }

    follow_redirect!

    assert_response :success
    assert_includes response.body, "Perfecto. Nos pondremos en contacto contigo por teléfono."
    assert_includes response.body, "Cambiar método de contacto"
  end

  test "does not create a lead without consent" do
    assert_no_difference("Quote.count") do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Barcelona",
            destination: "Madrid",
            distance_km: 999,
            estimated_duration_minutes: 999
          },
          email: "customer@example.com",
          consent_given: "0"
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "does not create a lead with an invalid email" do
    assert_no_difference("Quote.count") do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Barcelona",
            destination: "Madrid",
            distance_km: 999,
            estimated_duration_minutes: 999
          },
          email: "not-an-email",
          consent_given: "1"
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "does not create an invalid quote" do
    assert_no_difference("Quote.count") do
      post quotes_path, params: {
        quote: {
          origin: "",
          destination: "",
          distance_km: 0,
          estimated_duration_minutes: 0,
          fuel_cost: -10,
          margin: -5
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    assert_response :unprocessable_entity
  end

  test "strips whitespace from lead email" do
    assert_difference("Lead.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 999,
          estimated_duration_minutes: 999
        },
        email: "  customer@example.com  ",
        consent_given: "1"
      }
    end

    lead = Lead.last

    assert_equal "customer@example.com", lead.email
  end

  private

  def authenticate_as(user)
    post session_path, params: {
      email_address: user.email_address,
      password: "password123"
    }
  end

  def valid_quote_params
    {
      quote: { origin: "Barcelona", destination: "Madrid" },
      email: "customer@example.com",
      consent_given: "1"
    }
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

  def public_token_for(quote)
    quote.signed_id(purpose: :public_view, expires_in: 24.hours)
  end
end
