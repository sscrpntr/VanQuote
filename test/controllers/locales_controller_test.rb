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
