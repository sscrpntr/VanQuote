require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      first_name: "Sergi",
      last_name: "User",
      phone: "+34600000000",
      email_address: "sergi@example.com",
      password: "password123"
    )
  end

  test "authenticated user sees personalized dashboard actions without account header navigation" do
    sign_in

    get dashboard_path

    assert_response :success
    assert_select "h1", "Hola Sergi, ¿qué quieres hacer hoy?"
    assert_select "a[href=?]", quotes_path, text: "Ir a mis presupuestos"
    assert_select "a[href=?]", new_quote_path, text: "Nuevo presupuesto"
    assert_select "a[href=?]", profile_path, text: "Ir a mi perfil"
    assert_select "form[action=?]", session_path do
      assert_select "input[name=_method][value=delete]"
      assert_select "button[type=submit]", text: "Cerrar sesión"
    end
    assert_select "header.site-header nav.site-navigation", count: 0
    assert_select "header.site-header nav.language-selector", count: 1
    assert_select 'meta[property^="og:"]', count: 0
    assert_select 'meta[name^="twitter:"]', count: 0
  end

  test "unauthenticated user is redirected to sign in" do
    get dashboard_path

    assert_redirected_to new_session_path
  end

  test "uses a translated fallback when first name is blank" do
    @user.update_column(:first_name, "")
    sign_in

    get dashboard_path

    assert_response :success
    assert_select "h1", "Hola de nuevo, ¿qué quieres hacer hoy?"
  end

  test "dashboard greeting and actions use the selected locale" do
    {
      "ca" => [ "Hola Sergi, què vols fer avui?", "Anar als meus pressupostos", "Nou pressupost" ],
      "en" => [ "Hello Sergi, what would you like to do today?", "Go to my quotes", "New quote" ]
    }.each do |locale, (greeting, quotes_label, new_quote_label)|
      sign_in
      post locale_path, params: { locale: locale, return_to: dashboard_path }
      get dashboard_path

      assert_response :success
      assert_select "h1", greeting
      assert_select "a[href=?]", quotes_path, text: quotes_label
      assert_select "a[href=?]", new_quote_path, text: new_quote_label
    end
  end

  private

  def sign_in
    post session_path, params: {
      email_address: @user.email_address,
      password: "password123"
    }
  end
end
