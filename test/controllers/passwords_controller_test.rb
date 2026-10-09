require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  class FailingDeliveryMethod
    def initialize(*)
    end

    def deliver!(_mail)
      raise IOError, "SMTP delivery rejected"
    end
  end

  ActionMailer::Base.add_delivery_method :van_quote_failing, FailingDeliveryMethod

  setup do
    @user = User.create!(
      first_name: "Password",
      last_name: "User",
      email_address: "password-reset@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
    ActionMailer::Base.deliveries.clear
  end

  test "existing and unknown addresses receive the same generic response" do
    post passwords_path, params: { email_address: @user.email_address }
    existing_response = [ response.status, response.location, flash[:notice], flash[:alert] ]
    assert_equal 1, ActionMailer::Base.deliveries.length

    post passwords_path, params: { email_address: "unknown@example.com" }
    unknown_response = [ response.status, response.location, flash[:notice], flash[:alert] ]

    assert_equal existing_response, unknown_response
    assert_redirected_to new_session_path
    assert_equal I18n.t("passwords.notices.reset_instructions"), flash[:notice]
    assert_nil flash[:alert]
    assert_equal 1, ActionMailer::Base.deliveries.length
  end

  test "reset email uses the account recipient and a clean fragment URL" do
    post passwords_path, params: { email_address: @user.email_address }

    mail = ActionMailer::Base.deliveries.fetch(0)
    assert_equal [ @user.email_address ], mail.to
    assert_equal [ "theoriginalvanquote@gmail.com" ], mail.from
    assert_equal "Reset your password", mail.subject

    uri = reset_uri_from(mail)
    assert_equal "/passwords/reset", uri.path
    assert uri.fragment.present?
    assert_equal "example.com", uri.host
    assert_token_absent(uri.path, uri.fragment)
  end

  test "fragment link renders a token-free interstitial with safe headers and return path" do
    token = request_reset_token
    get new_password_reset_path

    assert_response :success
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "form[action='#{verify_password_reset_path}']"
    assert_select "input[name='token'][value='']"
    assert_select "input[name='return_to'][value='#{new_password_reset_path}']"
    assert_token_absent(response.body, token)
  end

  test "reset navigation remains translated in Catalan Spanish and English" do
    {
      "ca" => "Continua amb el canvi de contrasenya",
      "es" => "Continuar con el cambio de contraseña",
      "en" => "Continue password reset"
    }.each do |locale, title|
      post locale_path, params: { locale: locale, return_to: new_password_reset_path }
      get new_password_reset_path

      assert_response :success
      assert_includes response.body, title
      assert_select "a[href=?]", new_session_path
    end
  end

  test "valid token is consumed in a POST and redirects without carrying it" do
    token = request_reset_token

    post verify_password_reset_path, params: { token: token }

    assert_redirected_to edit_password_reset_path
    assert_token_absent(response.location, token)
    assert_token_absent(response.body, token)
    get edit_password_reset_path
    assert_response :success
    assert_select "form[action='#{update_password_reset_path}']"
    assert_select "input[name='token']", count: 0
    assert_token_absent(response.body, token)
  end

  test "expired token is rejected without echoing the token" do
    token = request_reset_token

    travel 16.minutes do
      post verify_password_reset_path, params: { token: token }
    end

    assert_redirected_to new_password_path
    assert_equal I18n.t("passwords.alerts.invalid_or_expired_link"), flash[:alert]
    assert_token_absent(response.location, token)
    assert_token_absent(response.body, token)
  end

  test "a token can be verified only once" do
    token = request_reset_token

    post verify_password_reset_path, params: { token: token }
    assert_redirected_to edit_password_reset_path

    post verify_password_reset_path, params: { token: token }
    assert_redirected_to new_password_path
    assert_equal I18n.t("passwords.alerts.invalid_or_expired_link"), flash[:alert]
    assert_token_absent(response.body, token)
  end

  test "a later reset email is managed and the first consumed token invalidates the others" do
    first_token = request_reset_token
    second_token = request_reset_token
    assert first_token.present? && second_token.present?, "both reset requests should produce usable signed links"

    post verify_password_reset_path, params: { token: first_token }
    assert_redirected_to edit_password_reset_path
    post verify_password_reset_path, params: { token: second_token }

    assert_redirected_to new_password_path
    assert_equal I18n.t("passwords.alerts.invalid_or_expired_link"), flash[:alert]
  end

  test "changing the password invalidates the consumed token and clears reset authorization" do
    token = request_reset_token
    post verify_password_reset_path, params: { token: token }
    assert_redirected_to edit_password_reset_path

    patch update_password_reset_path, params: {
      password: "new-password-456",
      password_confirmation: "new-password-456"
    }

    assert_redirected_to new_session_path
    assert @user.reload.authenticate("new-password-456")
    assert_nil User.find_by_password_reset_token(token)
    get edit_password_reset_path
    assert_redirected_to new_password_path
  end

  test "password reset POST logs and responses do not contain the token" do
    token = request_reset_token
    log_buffer = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(log_buffer))

    post verify_password_reset_path, params: { token: token }

    assert_response :redirect
    assert(!log_buffer.string.include?(token), "reset token was written to Rails logs")
    assert_token_absent(response.body, token)
  ensure
    Rails.logger = original_logger
  end

  test "SMTP failure keeps the response generic and does not report delivery success" do
    original_method = PasswordsMailer.delivery_method
    PasswordsMailer.delivery_method = :van_quote_failing

    post passwords_path, params: { email_address: @user.email_address }

    assert_redirected_to new_session_path
    assert_equal I18n.t("passwords.notices.reset_instructions"), flash[:notice]
    assert_nil flash[:alert]
  ensure
    PasswordsMailer.delivery_method = original_method
  end

  test "misconfigured limiter fails closed without sending mail" do
    original_key = ENV["PASSWORD_RESET_RATE_LIMIT_SECRET"]
    ENV["PASSWORD_RESET_RATE_LIMIT_SECRET"] = "invalid"
    post passwords_path, params: { email_address: @user.email_address }

    assert_redirected_to new_session_path
    assert_equal I18n.t("passwords.notices.reset_instructions"), flash[:notice]
    assert_empty ActionMailer::Base.deliveries
  ensure
    ENV["PASSWORD_RESET_RATE_LIMIT_SECRET"] = original_key
  end

  private

  def request_reset_token
    post passwords_path, params: { email_address: @user.email_address }
    assert_redirected_to new_session_path
    reset_uri_from(ActionMailer::Base.deliveries.last).fragment
  end

  def reset_uri_from(mail)
    url = mail.text_part.body.decoded.match(%r{https?://\S+}).to_s
    URI.parse(url)
  end

  def assert_token_absent(value, token)
    assert(!value.to_s.include?(token), "reset token appeared in a response or URL")
  end
end
