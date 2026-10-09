require "test_helper"

class QuotesControllerTest < ActionDispatch::IntegrationTest
  class FailingDeliveryMethod
    def initialize(*)
    end

    def deliver!(_mail)
      raise IOError, "SMTP delivery rejected"
    end
  end

  ActionMailer::Base.add_delivery_method :van_quote_failing_quote, FailingDeliveryMethod

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

  class CountingRoutesService
    class << self
      attr_accessor :calls
    end

    def initialize(origin:, destination:); end

    def call
      self.class.calls = self.class.calls.to_i + 1
      { distance_km: 620, duration_minutes: 360 }
    end
  end

  class FailingRoutesService
    def initialize(origin:, destination:); end

    def call
      raise IOError, "route provider unavailable"
    end
  end

  setup do
    @original_routes_service_class = QuotesController.routes_service_class
    QuotesController.routes_service_class = FakeRoutesService

    @user = User.create!(
      first_name: "Test", last_name: "User", phone: "+34600000000",
      email_address: "user@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
  end

  teardown do
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "home shows account links outside the quote form" do
    get "/"

    assert_response :success
    assert_select "a.site-brand[href=?] img.site-brand-logo[alt='VanQuote']", root_path
    assert_select "a[href=?]", new_session_path, text: "Iniciar sesión"
    assert_select "a[href=?]", new_registration_path, text: "Crear una cuenta"
    assert_select ".quote-card form" do
      assert_select "a[href=?]", new_session_path, count: 0
      assert_select "a[href=?]", new_registration_path, count: 0
    end
  end

  test "anonymous users can create only three quotes and the fourth is rejected before route lookup" do
    CountingRoutesService.calls = 0
    QuotesController.routes_service_class = CountingRoutesService

    3.times do
      assert_difference "Quote.count", 1 do
        post quotes_path, params: {
          quote: { origin: "Barcelona", destination: "Madrid" }, email: "customer@example.com"
        }
      end
      assert_response :redirect
    end

    assert_equal 3, CountingRoutesService.calls
    alternate_browser = open_session
    assert_no_difference [ "Quote.count", "Lead.count" ] do
      alternate_browser.post quotes_path, params: {
        quote: { origin: "Barcelona", destination: "Madrid" }, email: "customer@example.com",
        idempotency_key: QuoteCreationRequest.generate_key
      }
    end
    assert_equal 429, alternate_browser.response.status
    assert_equal 3, CountingRoutesService.calls
    assert_includes alternate_browser.response.body, I18n.t("quotes.errors.anonymous_limit")

    authenticate_as(@user)
    assert_difference "Quote.count", 1 do
      post quotes_path, params: {
        quote: { origin: "Barcelona", destination: "Madrid" }, email: "customer@example.com"
      }
    end
  ensure
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "quote request sends the estimate to its contact email" do
    ActionMailer::Base.deliveries.clear

    assert_difference "Quote.count", 1 do
      post quotes_path, params: valid_quote_params
    end

    assert_response :redirect
    quote = Quote.order(:id).last
    assert_equal "customer@example.com", quote.contact_email
    assert quote.result_email_sent_at
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal [ "customer@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "failed quote email does not claim it was sent" do
    original_method = QuoteMailer.delivery_method
    QuoteMailer.delivery_method = :van_quote_failing_quote

    assert_difference "Quote.count", 1 do
      post quotes_path, params: valid_quote_params
    end

    quote = Quote.order(:id).last
    assert_match %r{/quotes/public\?token=}, response.location
    assert_equal I18n.t("quotes.errors.email_delivery_failed"), flash[:alert]
    assert_nil flash[:notice]
    assert_nil quote.result_email_sent_at
  ensure
    QuoteMailer.delivery_method = original_method
  end

  test "repeating a quote request with the same key reuses the quote and email" do
    ActionMailer::Base.deliveries.clear
    key = QuoteCreationRequest.generate_key

    assert_difference "Quote.count", 1 do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end
    assert_response :redirect
    quote_id = Quote.order(:id).last.id
    assert_equal 1, ActionMailer::Base.deliveries.size

    assert_no_difference "Quote.count" do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end

    assert_response :redirect
    assert_equal quote_id, Quote.order(:id).last.id
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "incompatible parameters cannot reuse a quote request key" do
    CountingRoutesService.calls = 0
    QuotesController.routes_service_class = CountingRoutesService
    key = QuoteCreationRequest.generate_key
    quote_count = Quote.count

    assert_difference "Quote.count", 1 do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end
    assert_response :redirect
    assert_equal quote_count + 1, Quote.count

    assert_no_difference "Quote.count" do
      post quotes_path, params: valid_quote_params.deep_merge(quote: { destination: "Valencia" })
        .merge(idempotency_key: key)
    end

    assert_response :conflict
    assert_equal 1, CountingRoutesService.calls
    assert_includes response.body, I18n.t("quotes.errors.quote_request_conflict")
  ensure
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "invalid idempotency keys are rejected before route lookup" do
    CountingRoutesService.calls = 0
    QuotesController.routes_service_class = CountingRoutesService

    assert_no_difference "Quote.count" do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: "invalid")
    end

    assert_response :unprocessable_entity
    assert_equal 0, CountingRoutesService.calls
  ensure
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "another anonymous session cannot use an idempotency key to access a quote" do
    key = QuoteCreationRequest.generate_key
    post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    assert_response :redirect
    quote = Quote.order(:id).last

    alternate_browser = open_session
    assert_no_difference "Quote.count" do
      alternate_browser.post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end

    assert_equal 409, alternate_browser.response.status
    assert_not_includes alternate_browser.response.body, quote.id.to_s
  end

  test "a different authenticated user cannot use an idempotency key to access a quote" do
    CountingRoutesService.calls = 0
    QuotesController.routes_service_class = CountingRoutesService
    key = QuoteCreationRequest.generate_key
    authenticate_as(@user)
    post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    quote = Quote.order(:id).last

    other_user = User.create!(
      first_name: "Other",
      last_name: "User",
      email_address: "other-user@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
    authenticate_as(other_user)
    assert_no_difference "Quote.count" do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end

    assert_response :conflict
    assert_equal 1, CountingRoutesService.calls
    assert_not_includes response.body, quote.id.to_s
  ensure
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "failed quote email can be retried on the same persisted quote" do
    ActionMailer::Base.deliveries.clear
    original_method = QuoteMailer.delivery_method
    QuoteMailer.delivery_method = :van_quote_failing_quote
    key = QuoteCreationRequest.generate_key

    assert_difference "Quote.count", 1 do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end
    quote = Quote.order(:id).last
    assert_nil quote.result_email_sent_at

    QuoteMailer.delivery_method = original_method
    assert_no_difference "Quote.count" do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end

    assert_response :redirect
    assert_equal quote.id, Quote.order(:id).last.id
    assert quote.reload.result_email_sent_at
    assert_equal 1, ActionMailer::Base.deliveries.size
  ensure
    QuoteMailer.delivery_method = original_method
  end

  test "route failure leaves a retryable operation without creating a quote" do
    QuotesController.routes_service_class = FailingRoutesService
    key = QuoteCreationRequest.generate_key
    assert_no_difference "Quote.count" do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end
    assert_response :unprocessable_entity

    QuotesController.routes_service_class = FakeRoutesService
    assert_difference "Quote.count", 1 do
      post quotes_path, params: valid_quote_params.merge(idempotency_key: key)
    end
    assert_response :redirect
    assert_equal 1, QuoteCreationRequest.where(status: "completed").count
  ensure
    QuotesController.routes_service_class = @original_routes_service_class
  end

  test "public landing renders production Open Graph and Twitter preview metadata" do
    get root_path

    assert_response :success
    assert_select 'meta[name="description"][content="Calcula cuánto cuesta transportar tus cosas de forma rápida y sencilla."]'
    assert_select 'meta[property="og:title"][content="VanQuote — Calcula tu presupuesto de transporte"]'
    assert_select 'meta[property="og:description"][content="Calcula cuánto cuesta transportar tus cosas de forma rápida y sencilla."]'
    assert_select 'meta[property="og:type"][content="website"]'
    assert_select 'meta[property="og:url"][content="https://van-quote.vercel.app/"]'
    assert_select 'meta[property="og:image"][content="https://van-quote.vercel.app/vanquote-social.png"]'
    assert_select 'meta[property="og:image:width"][content="1200"]'
    assert_select 'meta[property="og:image:height"][content="630"]'
    assert_select 'meta[name="twitter:card"][content="summary_large_image"]'
    assert_select 'meta[name="twitter:title"][content="VanQuote — Calcula tu presupuesto de transporte"]'
    assert_select 'meta[name="twitter:description"][content="Calcula cuánto cuesta transportar tus cosas de forma rápida y sencilla."]'
    assert_select 'meta[name="twitter:image"][content="https://van-quote.vercel.app/vanquote-social.png"]'
    assert_not_includes response.body, "localhost"
  end

  test "social preview image is served as a public asset" do
    get "/vanquote-social.png"

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "brand logo and van icon are served as public SVG assets" do
    get "/vanquote-logo.svg"

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_includes response.body, "VanQuote"

    get "/icon.svg"

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_includes response.body, "#3478D4"

    get "/icon.png"

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "home account links use the selected locale" do
    {
      "ca" => {
        sign_in_prompt: "Ja tens un compte?",
        sign_in: "Inicia sessió",
        register_prompt: "Encara no tens un compte?",
        register: "Crea un compte",
        landing_headline: "Quant costa transportar els teus somnis?",
        how_title: "Com funciona?",
        uses_title: "Per a què necessites VanQuote?",
        pricing_title: "Com calculem el teu preu?",
        cta_title: "Necessites transportar alguna cosa?",
        cta: "Calcula el meu pressupost"
      },
      "es" => {
        sign_in_prompt: "¿Ya tienes una cuenta?",
        sign_in: "Iniciar sesión",
        register_prompt: "¿Todavía no tienes una cuenta?",
        register: "Crear una cuenta",
        landing_headline: "¿Cuánto cuesta transportar tus sueños?",
        how_title: "¿Cómo funciona?",
        uses_title: "¿Para qué necesitas VanQuote?",
        pricing_title: "¿Cómo calculamos tu precio?",
        cta_title: "¿Necesitas transportar algo?",
        cta: "Calcular mi presupuesto"
      },
      "en" => {
        sign_in_prompt: "Already have an account?",
        sign_in: "Sign in",
        register_prompt: "Don't have an account yet?",
        register: "Create an account",
        landing_headline: "How much does it cost to move your dreams?",
        how_title: "How does it work?",
        uses_title: "What do you need VanQuote for?",
        pricing_title: "How do we calculate your price?",
        cta_title: "Need to transport something?",
        cta: "Calculate my quote"
      }
    }.each do |locale, translations|
      post locale_path, params: { locale: locale, return_to: root_path }
      assert_redirected_to root_path

      get "/"

      assert_response :success
      assert_select "header.site-header a.site-brand[href=?] img[alt='VanQuote']", root_path
      assert_select "header.site-header nav.language-selector", count: 1 do
        assert_select "input.language-selector-button", count: 3
      end
      assert_select ".quote-account-option p", text: translations[:sign_in_prompt]
      assert_select ".quote-account-option a[href=?]", new_session_path, text: translations[:sign_in]
      assert_select ".quote-account-option p", text: translations[:register_prompt]
      assert_select ".quote-account-option a[href=?]", new_registration_path, text: translations[:register]
      assert_select ".landing-copy h1", text: translations[:landing_headline]
      assert_select ".landing-eyebrow", count: 0
      assert_not_includes response.body, "PRESUPUESTO DE TRANSPORTE"
      assert_select "#landing-how-title", text: translations[:how_title]
      assert_select "#landing-use-cases-title", text: translations[:uses_title]
      assert_select "#landing-pricing-title", text: translations[:pricing_title]
      assert_select "#landing-cta-title", text: translations[:cta_title]
      assert_select ".landing-cta-button[href=?]", new_quote_path, text: translations[:cta]
    end
  end

  test "authenticated user can visit home and create a quote" do
    authenticate_as(@user)

    get "/"
    assert_response :success
    assert_select "form.quote-form"

    assert_difference("Quote.count", 1) do
      post quotes_path, params: valid_quote_params
    end

    assert_equal @user.id, Quote.last.user_id
  end

  test "authenticated user retains their session and navigation on the new quote page" do
    authenticate_as(@user)

    get new_quote_path

    assert_response :success
    assert_select "html.landing-page-layout.landing-authenticated"
    assert_select "header.site-header nav.site-navigation" do
      assert_select "a[href=?]", quotes_path
      assert_select "a[href=?]", new_quote_path, text: "Nueva cotización"
      assert_select "a[href=?]", profile_path
    end
    assert_select "form.quote-form"
  end

  test "anonymous user can access the public new quote page" do
    get new_quote_path

    assert_response :success
    assert_select "html.landing-page-layout"
    assert_select "html.landing-authenticated", count: 0
    assert_select ".landing-hero-inner"
    assert_select ".landing-page > section", count: 5
    assert_select ".landing-benefits li", count: 3
    assert_select ".landing-benefits li:nth-child(1) span", text: "⚡"
    assert_select ".landing-benefits li:nth-child(2) span", text: "📍"
    assert_select ".landing-benefits li:nth-child(3) span", text: "🚐"
    assert_select ".landing-form-card h2", text: "Tu presupuesto"
    assert_select "#quote-form form.quote-form"
    assert_select "#quote-form input[name='quote[origin]']"
    assert_select "#quote-form input[name='quote[destination]']"
    assert_select "#quote-form input[name='email']"
    assert_select "#quote-form input[name='phone']", count: 0
    assert_select "#quote-form input[name='consent_given']", count: 0
    assert_select "#quote-form .landing-email-info summary[aria-label]"
    assert_includes response.body, I18n.t("quotes.new.email.info")
    assert_select ".landing-steps li", count: 3
    assert_select ".landing-category-list li", count: 3
    assert_select "form.quote-form"
    assert_select "header.site-header nav.site-navigation", count: 0
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
        phone: "+34600000099",
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
    assert_nil quote.lead
    assert_equal "customer@example.com", quote.contact_email
  end

  test "authenticated user sees only their quotes with a link to each detail" do
    own_quote = create_quote_for(@user, origin: "Barcelona", destination: "Madrid")
    other_user = User.create!(first_name: "Other", last_name: "User", phone: "+34600000002",
      email_address: "other@example.com", password: "password123")
    create_quote_for(other_user, origin: "Paris", destination: "Lyon")

    authenticate_as(@user)
    get quotes_path

    assert_response :success
    assert_includes response.body, "Barcelona"
    assert_includes response.body, quote_path(own_quote)
    assert_not_includes response.body, "Paris"
  end

  test "quotes index renders a permanent grid with one card per quote" do
    quotes = 5.times.map { |index| create_quote_for(@user, origin: "Origin #{index}", destination: "Destination #{index}") }
    authenticate_as(@user)

    get quotes_path

    assert_response :success
    assert_select ".quotes-grid"
    assert_select ".quote-index-card", count: 5
    assert_select ".quotes-new-link-row > a.quotes-new-link[href=?]", new_quote_path
    quotes.each do |quote|
      assert_select ".quote-index-card a[href=?]", quote_path(quote), count: 1
    end
    assert_not_includes response.body, "carousel"
    assert_not_includes response.body, "slider"
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
    admin = User.create!(first_name: "Admin", last_name: "User", phone: "+34600000001",
      email_address: "admin@example.com", password: "password123", admin: true,
      email_verified_at: Time.current)
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
    post quotes_path, params: valid_quote_params.merge(email: @user.email_address)
    quote = Quote.last
    token = URI.decode_www_form(URI(response.location).query).to_h.fetch("token")

    get new_session_path, params: { quote_token: token }
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }

    assert_equal @user.id, quote.reload.user_id
  end

  test "quote creation grants claim authority only in the creating browser session" do
    post quotes_path, params: valid_quote_params.merge(email: @user.email_address)
    quote = Quote.last

    assert_equal 1, Quote.where(id: quote.id).count
    assert_nil quote.user_id
    token = URI.decode_www_form(URI(response.location).query).to_h.fetch("token")
    get new_session_path, params: { quote_token: token }
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    assert_equal @user.id, quote.reload.user_id
  end

  test "does not reassign a quote that belongs to another user" do
    owner = User.create!(first_name: "Owner", last_name: "User", phone: "+34600000003",
      email_address: "owner@example.com", password: "password123")
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

  test "anonymous quote calculation does not create a lead or consent" do
    assert_no_difference("Lead.count") do
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

    quote = Quote.last
    assert_nil quote.lead
    assert_equal "customer@example.com", quote.contact_email
  end

  test "authenticated user does not see an email field on the quote form" do
    authenticate_as(@user)

    get "/"

    assert_response :success
    assert_select "form.quote-form", count: 1
    assert_select "form.quote-form input[name='email']", count: 0
    assert_select "form.quote-form label[for='email']", count: 0
    assert_select "form.quote-form input[name='phone']", count: 0
    assert_select "form.quote-form input[name='consent_given']", count: 0
    assert_select "form.quote-form input[name='idempotency_key'][value]", count: 1
  end

  test "authenticated quote ignores an email submitted by a modified client" do
    authenticate_as(@user)

    assert_difference("Quote.count", 1) do
      post quotes_path, params: valid_quote_params.merge(email: "attacker@example.com")
    end

    quote = Quote.order(:id).last
    assert_equal @user.email_address, quote.contact_email
    assert_equal @user.id, quote.user_id
    assert_nil quote.lead
  end

  test "authenticated contact request checks consent before creating a lead" do
    quote = create_anonymous_quote(contact_email: @user.email_address)
    authenticate_as(@user)
    token = public_token_for(quote)

    assert_no_difference "Lead.count" do
      post request_quote_contact_path, params: { token: token, contact_preference: "EMAIL_QUOTE" }
    end

    assert_redirected_to new_operational_consent_path
    assert_equal @user.id, quote.reload.user_id
    assert_nil quote.lead

    assert_difference "Lead.count", 1 do
      post operational_consent_path, params: { accept_operational_email: "1" }
    end

    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_QUOTE", quote.reload.lead.contact_preference
    assert_equal @user.email_address, quote.lead.email
  end

  test "authorized quote token allows claiming an anonymous quote with a different email" do
    quote = create_anonymous_quote(contact_email: "someone-else@example.com")
    lead = quote.create_lead!(email: "someone-else@example.com", phone: "+34600000000",
      contact_preference: "PHONE", consent_given: true, consent_at: Time.current, status: "NEW")
    authenticate_as(@user)

    assert_no_difference [ "Quote.count", "Lead.count" ] do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "EMAIL_CONTACT" }
    end

    assert_redirected_to new_operational_consent_path
    assert_equal @user.id, quote.reload.user_id
    assert_equal "someone-else@example.com", quote.contact_email
    assert_equal lead.id, quote.reload.lead.id
    assert_equal "someone-else@example.com", lead.reload.email
    assert_equal "PHONE", lead.contact_preference
    follow_redirect!
    assert_response :success
    assert_select ".auth-notice[role=status][aria-live=polite]",
      text: I18n.t("quotes.public.contact.owner_updated", email: @user.email_address)
  end

  test "public view token alone cannot authorize claiming an anonymous quote" do
    quote = Quote.create!(origin: "Barcelona", destination: "Madrid", contact_email: "someone-else@example.com",
      distance_km: 620, estimated_duration_minutes: 360, fuel_cost: 74.4, toll_cost: 0,
      vehicle_cost: 62, driver_cost: 150, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 316.4, recommended_price: 395.5)
    authenticate_as(@user)
    token = public_token_for(quote)

    post request_quote_contact_path,
      params: { token: token, contact_preference: "EMAIL_CONTACT" }

    assert_redirected_to public_quotes_path(token: token)
    assert_equal I18n.t("quotes.public.contact.account_mismatch"), flash[:alert]
    assert_nil flash[:notice]
    assert_nil quote.reload.user_id
  end

  test "repeated authorized contact requests reuse the same quote and lead" do
    @user.grant_operational_email_consent!(consent_text: "Explicit test consent")
    quote = create_anonymous_quote(contact_email: "original@example.com")
    token = public_token_for(quote)
    authenticate_as(@user)

    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: token, contact_preference: "EMAIL_CONTACT" }
    end
    assert_redirected_to contact_confirmation_path
    lead_id = quote.reload.lead.id

    assert_no_difference [ "Quote.count", "Lead.count" ] do
      post request_quote_contact_path,
        params: { token: token, contact_preference: "EMAIL_CONTACT" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal lead_id, quote.reload.lead.id
    assert_equal "original@example.com", quote.contact_email
    assert_equal @user.id, quote.user_id
  end

  test "claim authorization for one quote cannot be reused for a different quote" do
    authorized_quote = create_anonymous_quote(contact_email: "created-here@example.com")
    other_quote = Quote.create!(origin: "Lleida", destination: "Tarragona", contact_email: "other@example.com",
      distance_km: 100, estimated_duration_minutes: 90, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 40, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 92, recommended_price: 115)
    authenticate_as(@user)
    token = public_token_for(other_quote)

    post request_quote_contact_path,
      params: { token: token, contact_preference: "EMAIL_CONTACT" }

    assert_redirected_to public_quotes_path(token: token)
    assert_nil other_quote.reload.user_id
    assert_nil flash[:notice]
    post request_quote_contact_path,
      params: { token: public_token_for(authorized_quote), contact_preference: "EMAIL_CONTACT" }
    assert_equal @user.id, authorized_quote.reload.user_id
  end

  test "quote id alone cannot authorize claiming an anonymous quote" do
    quote = Quote.create!(origin: "Barcelona", destination: "Madrid", contact_email: "someone-else@example.com",
      distance_km: 620, estimated_duration_minutes: 360, fuel_cost: 74.4, toll_cost: 0,
      vehicle_cost: 62, driver_cost: 150, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 316.4, recommended_price: 395.5)
    authenticate_as(@user)

    assert_no_difference [ "Quote.count", "Lead.count" ] do
      post request_quote_contact_path,
        params: { quote_id: quote.id, contact_preference: "EMAIL_CONTACT" }
    end

    assert_redirected_to dashboard_path
    assert_nil quote.reload.user_id
    assert_nil quote.lead
  end

  test "creating a lead sends one administrator notification" do
    quote = create_anonymous_quote(contact_email: @user.email_address)
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")
    ActionMailer::Base.deliveries.clear
    authenticate_as(@user)

    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: public_token_for(quote), contact_preference: "EMAIL_QUOTE" }
    end

    assert_redirected_to contact_confirmation_path
    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "sergiescarpenter@gmail.com" ], mail.to
    assert_equal "New VanQuote lead", mail.subject
    assert quote.reload.lead.admin_notification_sent_at
  end

  test "retrying a contact request reuses its lead and does not resend the notice" do
    quote = create_anonymous_quote(contact_email: @user.email_address)
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")
    ActionMailer::Base.deliveries.clear
    authenticate_as(@user)
    token = public_token_for(quote)

    assert_difference "Lead.count", 1 do
      2.times do
        post request_quote_contact_path,
          params: { token: token, contact_preference: "EMAIL_QUOTE" }
      end
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert quote.reload.lead.present?
  end

  test "failed lead notification can be retried without duplicating the lead" do
    quote = create_anonymous_quote(contact_email: @user.email_address)
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")
    authenticate_as(@user)
    token = public_token_for(quote)
    original_method = LeadsMailer.delivery_method
    LeadsMailer.delivery_method = :van_quote_failing_quote

    assert_difference "Lead.count", 1 do
      post request_quote_contact_path,
        params: { token: token, contact_preference: "EMAIL_QUOTE" }
    end

    lead = quote.reload.lead
    assert_nil lead.admin_notification_sent_at
    assert_equal I18n.t("quotes.public.contact.email_failed"), flash[:alert]
    assert_not_equal I18n.t("quotes.contact_confirmation.flash"), flash[:notice]
    LeadsMailer.delivery_method = original_method
    ActionMailer::Base.deliveries.clear

    assert_no_difference "Lead.count" do
      post request_quote_contact_path,
        params: { token: token, contact_preference: "EMAIL_QUOTE" }
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert lead.reload.admin_notification_sent_at
  ensure
    LeadsMailer.delivery_method = original_method
  end

  test "failed quote claim keeps the quote anonymous and shows no success notice" do
    quote = create_anonymous_quote(contact_email: "someone-else@example.com")
    quote.update_columns(origin: nil)
    authenticate_as(@user)
    token = public_token_for(quote)

    assert_no_difference [ "Quote.count", "Lead.count" ] do
      post request_quote_contact_path,
        params: { token: token, contact_preference: "EMAIL_CONTACT" }
    end

    assert_redirected_to public_quotes_path(token: token)
    assert_equal I18n.t("quotes.public.contact.request_failed"), flash[:alert]
    assert_nil flash[:notice]
    assert_nil quote.reload.user_id
  end

  test "anonymous user sees email but not phone on the quote form" do
    get "/"

    assert_response :success
    assert_select "form.quote-form", count: 1
    assert_select "form.quote-form input[name='email']", count: 1
    assert_select "form.quote-form input[name='phone']", count: 0
    assert_select "form.quote-form input[name='consent_given']", count: 0
    assert_select ".landing-email-info summary[aria-label]"
    assert_select ".landing-email-info p", text: I18n.t("quotes.new.email.info")
  end

  test "authenticated user can create a quote without creating a contact lead" do
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")
    authenticate_as(@user)

    assert_difference("Quote.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 999,
          estimated_duration_minutes: 999
        }
      }
    end

    assert_response :redirect

    quote = Quote.last
    assert_equal @user.id, quote.user_id
    assert_equal @user.email_address, quote.contact_email
    assert_nil quote.lead
  end

  test "authenticated user without saved consent can calculate without creating a lead" do
    authenticate_as(@user)

    assert_difference("Quote.count", 1) do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Barcelona",
            destination: "Madrid"
          }
        }
      end
    end

    assert_response :redirect
    assert_nil Quote.last.lead
  end

  test "withdrawing consent leaves calculations available and gates a later contact request" do
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")
    authenticate_as(@user)
    delete operational_consent_path
    post quotes_path, params: { quote: { origin: "Barcelona", destination: "Madrid" } }
    quote = Quote.last
    assert_equal @user.email_address, quote.contact_email
    assert_nil quote.lead

    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    get new_session_path, params: { quote_token: token, contact_preference: "EMAIL_QUOTE" }

    assert_equal public_quotes_path, URI.parse(response.location).path
    assert_nil quote.reload.lead
    assert_not @user.reload.operational_email_consent_valid?
    follow_redirect!
    assert_response :success

    post request_quote_contact_path, params: { token: public_token_for(quote), contact_preference: "EMAIL_QUOTE" }
    assert_redirected_to new_operational_consent_path

    assert_difference "Lead.count", 1 do
      post operational_consent_path, params: { accept_operational_email: "1" }
    end
    assert_redirected_to contact_confirmation_path
    assert_equal "EMAIL_QUOTE", quote.reload.lead.contact_preference
    assert @user.reload.operational_email_consent_valid?
  end

  test "consent on a previous lead does not become account consent" do
    previous_quote = create_quote_for(@user, origin: "Barcelona", destination: "Madrid")
    previous_quote.create_lead!(
      email: @user.email_address,
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )
    authenticate_as(@user)

    assert_difference("Quote.count", 1) do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Valencia",
            destination: "Zaragoza"
          }
        }
      end
    end

    assert_response :redirect
    assert_not @user.operational_email_consent_valid?
    assert_nil Quote.last.lead
  end

  test "new explicit consent reauthorizes a request without deleting its withdrawal history" do
    @user.grant_operational_email_consent!(consent_text: "Initial explicit grant")
    quote = create_quote_for(@user, origin: "Barcelona", destination: "Madrid")
    authenticate_as(@user)
    token = public_token_for(quote)

    assert_difference "Lead.count", 1 do
      post request_quote_contact_path, params: { token: token, contact_preference: "EMAIL_QUOTE" }
    end
    lead = quote.reload.lead
    original_grant = lead.consent_at

    delete operational_consent_path
    withdrawal = lead.reload.consent_withdrawn_at
    assert_not_nil withdrawal
    assert_not Lead.with_consent.exists?(lead.id)

    post request_quote_contact_path, params: { token: token, contact_preference: "EMAIL_CONTACT" }
    assert_redirected_to new_operational_consent_path
    assert_difference "OperationalEmailConsentEvent.count", 1 do
      assert_no_difference "Lead.count" do
        post operational_consent_path, params: { accept_operational_email: "1" }
      end
    end

    lead.reload
    assert lead.consent_at > original_grant
    assert_equal withdrawal.to_i, lead.consent_withdrawn_at.to_i
    assert_not lead.consent_withdrawn?
    assert Lead.with_consent.exists?(lead.id)
    assert_equal "EMAIL_CONTACT", lead.contact_preference
    assert_equal %w[granted withdrawn granted], @user.operational_email_consent_events.order(:id).pluck(:action)
  end

  test "authenticated user cannot override their email or phone when creating a quote" do
    @user.grant_operational_email_consent!(consent_text: "Test operational email consent")
    authenticate_as(@user)

    assert_difference("Quote.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 999,
          estimated_duration_minutes: 999
        },
        email: "attacker@example.com",
        phone: "+34999999999"
      }
    end

    assert_response :redirect

    quote = Quote.last

    assert_equal @user.email_address, quote.contact_email
    assert_nil quote.lead
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

  test "calculates a quote without asking for contact consent" do
    assert_difference("Quote.count", 1) do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Barcelona",
            destination: "Madrid",
            distance_km: 999,
            estimated_duration_minutes: 999
          },
          email: "customer@example.com"
        }
      end
    end

    assert_response :redirect
    assert_nil Quote.last.lead
  end

  test "does not save a quote with an invalid email" do
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

  test "strips whitespace from quote contact email" do
    assert_no_difference("Lead.count") do
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

    assert_equal "customer@example.com", Quote.last.contact_email
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

  def create_anonymous_quote(contact_email:)
    post quotes_path, params: {
      quote: { origin: "Barcelona", destination: "Madrid" },
      email: contact_email
    }
    Quote.order(:id).last
  end

  def public_token_for(quote)
    quote.signed_id(purpose: :public_view, expires_in: 24.hours)
  end
end
