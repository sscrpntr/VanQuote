require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(first_name: "Admin", last_name: "User", phone: "+34600000001",
      email_address: "admin@example.com", password: "password123", admin: true)
    @user = User.create!(first_name: "Test", last_name: "User", phone: "+34600000000",
      email_address: "user@example.com", password: "password123")
  end

  test "authenticated user can access profile" do
    sign_in(@user)

    get profile_path

    assert_response :success
    assert_includes response.body, "Mi perfil"
    assert_includes response.body, "Mis presupuestos"
    assert_select "nav.site-navigation a", text: "Mi perfil"
  end

  test "authenticated user can update profile" do
    sign_in(@user)

    patch profile_path, params: {
      user: {
        first_name: "Updated",
        last_name: "Name",
        email_address: "updated@example.com",
        phone: "+34600000999"
      }
    }

    assert_redirected_to profile_path

    @user.reload
    assert_equal "Updated", @user.first_name
    assert_equal "Name", @user.last_name
    assert_equal "updated@example.com", @user.email_address
    assert_equal "+34600000999", @user.phone
  end

  test "authenticated user sees validation errors when profile update is invalid" do
    sign_in(@user)

    patch profile_path, params: {
      user: {
        first_name: "",
        last_name: "",
        email_address: "",
        phone: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "No se ha podido actualizar el perfil"
  end

  test "unauthenticated user cannot update profile" do
    patch profile_path, params: {
      user: {
        first_name: "Hacker",
        last_name: "User",
        email_address: "hacker@example.com",
        phone: "+34699999999"
      }
    }

    assert_redirected_to new_session_path
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
