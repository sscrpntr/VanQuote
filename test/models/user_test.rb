
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email address" do
    user = User.new(
      first_name: "Test",
      last_name: "User",
      phone: "+34600000000",
      email_address: "  TEST@Example.COM  ",
      password: "password123"
    )

    assert user.valid?
    assert_equal "test@example.com", user.email_address
  end

  test "requires an email address" do
    user = User.new(first_name: "Test", last_name: "User", phone: "+34600000000", password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:email_address], "can't be blank"
  end

  test "requires a unique email address" do
    User.create!(
      first_name: "Test",
      last_name: "User",
      phone: "+34600000000",
      email_address: "test@example.com",
      password: "password123"
    )

    duplicate = User.new(
      first_name: "Test",
      last_name: "User",
      phone: "+34600000000",
      email_address: "TEST@example.com",
      password: "password123"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email_address], "has already been taken"
  end

  test "requires a password when creating a user" do
    user = User.new(first_name: "Test", last_name: "User", phone: "+34600000000", email_address: "test@example.com")

    assert_not user.valid?
    assert_includes user.errors[:password], "can't be blank"
  end

  test "requires matching password confirmation" do
    user = User.new(
      email_address: "test@example.com",
      password: "password123",
      password_confirmation: "different-password"
    )

    assert_not user.valid?
    assert_includes user.errors[:password_confirmation], "doesn't match Password"
  end
end
