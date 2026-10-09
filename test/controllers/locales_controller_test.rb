require "test_helper"

class LocalesControllerTest < ActionDispatch::IntegrationTest
  %w[ca es en].each do |locale|
    test "anonymous user can select #{locale} and return to the home page" do
      post locale_path, params: { locale: locale, return_to: root_path }

      assert_redirected_to root_path
      assert_equal locale, session[:locale]
    end
  end

  test "authenticated user can change locale" do
    user = User.create!(first_name: "Locale", last_name: "User", phone: "+34600000004",
      email_address: "locale-user@example.com", password: "password123",
                        password_confirmation: "password123")
    post session_path, params: { email_address: user.email_address, password: "password123" }

    post locale_path, params: { locale: "ca", return_to: root_path }

    assert_redirected_to root_path
    assert_equal "ca", session[:locale]
  end

  test "registration draft survives a locale change without retaining passwords" do
    draft = {
      form_key: "registration",
      values: {
        "user[first_name]" => "Ada",
        "user[last_name]" => "Lovelace",
        "user[email_address]" => "ada@example.com",
        "user[accept_terms]" => true,
        "user[accept_operational_email]" => false,
        "user[password]" => "must-not-be-saved"
      }
    }.to_json

    post locale_path, params: {
      locale: "en",
      return_to: new_registration_path,
      locale_form_draft: draft
    }

    assert_redirected_to new_registration_path
    assert_equal %w[user[accept_operational_email] user[accept_terms] user[email_address] user[first_name] user[last_name]].sort,
      session[:locale_form_draft].fetch("values").keys.sort

    get new_registration_path

    assert_response :success
    assert_select "input[name='user[first_name]'][value='Ada']"
    assert_select "input[name='user[last_name]'][value='Lovelace']"
    assert_select "input[name='user[email_address]'][value='ada@example.com']"
    assert_select "input[name='user[accept_terms]'][checked]"
    assert_select "input[name='user[accept_operational_email]']:not([checked])"
    assert_select "input[name='user[password]']:not([value])"
    assert_nil session[:locale_form_draft]
  end

  test "login preserves email but never restores the password field" do
    post locale_path, params: {
      locale: "ca",
      return_to: new_session_path,
      locale_form_draft: { form_key: "session", values: { "email_address" => "login@example.com", "password" => "secret" } }.to_json
    }
    get new_session_path

    assert_response :success
    assert_select "input[name='email_address'][value='login@example.com']"
    assert_select "input[name='password']:not([value])"
    assert_not_includes response.body, "secret"
  end

  test "profile draft fields survive a locale change for the authenticated account" do
    user = User.create!(first_name: "Original", last_name: "User", email_address: "profile@example.com", password: "password123")
    post session_path, params: { email_address: user.email_address, password: "password123" }
    post locale_path, params: {
      locale: "ca",
      return_to: profile_path,
      locale_form_draft: {
        form_key: "profile",
        values: {
          "user[first_name]" => "Ada",
          "user[last_name]" => "Byron",
          "user[email_address]" => "ada@example.com",
          "user[phone]" => "+41790000000"
        }
      }.to_json
    }
    get profile_path

    assert_response :success
    assert_select "input[name='user[first_name]'][value='Ada']"
    assert_select "input[name='user[last_name]'][value='Byron']"
    assert_select "input[name='user[email_address]'][value='ada@example.com']"
    assert_select "input[name='user[phone]'][value='+41790000000']"
  end

  test "quote draft values are escaped and restored after a locale change" do
    draft = {
      form_key: "quote",
      values: { "quote[origin]" => "<script>alert(1)</script>", "quote[destination]" => "Geneva", "email" => "quote@example.com" }
    }.to_json
    post locale_path, params: { locale: "en", return_to: new_quote_path, locale_form_draft: draft }
    get new_quote_path

    assert_response :success
    assert_select "input[name='quote[origin]'][value=?]", "<script>alert(1)</script>"
    assert_select "input[name='quote[destination]'][value='Geneva']"
    assert_select "input[name='email'][value='quote@example.com']"
    assert_not_includes response.body, "<script>alert(1)</script>"
  end

  test "changing locale from a public quote preserves its signed token" do
    quote = quotes(:one)
    token = quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    public_path = public_quotes_path(token: token)

    { "es" => %w[ca en], "ca" => %w[es], "en" => %w[es] }.each do |from, targets|
      post locale_path, params: { locale: from, return_to: root_path }
      get public_path

      assert_response :success
      assert_includes response.body, "556.25 €"

      return_to = css_select("form.language-selector-form input[name='return_to']")
        .first["value"]
      assert_equal public_path, return_to

      targets.each do |to|
        post locale_path, params: { locale: to, return_to: return_to }

        assert_redirected_to public_path
        assert_equal token, Rack::Utils.parse_query(URI(response.location).query)["token"]

        follow_redirect!
        assert_response :success
        assert_includes response.body, "556.25 €"
        assert_equal quote, Quote.find_signed!(token, purpose: :public_view)
      end
    end
  end

  test "external return_to is rejected" do
    post locale_path, params: { locale: "ca", return_to: "https://evil.example.com" }

    assert_redirected_to root_path
  end

  test "protocol relative return_to is rejected" do
    post locale_path, params: { locale: "ca", return_to: "//evil.example.com" }

    assert_redirected_to root_path
  end

  test "invalid locale does not change the session locale" do
    post locale_path, params: { locale: "fr", return_to: root_path }

    assert_redirected_to root_path
    assert_nil session[:locale]
  end
end
