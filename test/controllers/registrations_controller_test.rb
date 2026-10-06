require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "shows registration form" do
    get new_registration_path

    assert_response :success
    assert_select "h1", "Crea tu cuenta"
    assert_select "form"
  end

  test "creates a user and starts a session" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
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
end
