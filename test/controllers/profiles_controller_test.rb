require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", password: "password123", admin: true)
    @user = User.create!(email_address: "user@example.com", password: "password123")
  end

  test "authenticated user can access profile" do
    sign_in(@user)

    get profile_path

    assert_response :success
    assert_includes response.body, "Mi perfil"
    assert_includes response.body, "Mis presupuestos"
    assert_select "nav.site-navigation a", text: "Mi perfil"
  end

  test "unauthenticated user is redirected from profile to login" do
    get profile_path

    assert_redirected_to new_session_path
  end

  test "admin sees the back-office link in profile" do
    sign_in(@admin)

    get profile_path

    assert_response :success
    assert_select "a[href=?]", admin_path, text: "Back-office"
  end

  test "regular user does not see the back-office link in profile" do
    sign_in(@user)

    get profile_path

    assert_response :success
    assert_select "a[href=?]", admin_path, count: 0
  end

  private

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
