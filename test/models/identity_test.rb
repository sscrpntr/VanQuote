require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "accepts google as a provider" do
    user = User.create!(
      first_name: "Test",
      last_name: "Identity",
      phone: "+34600000010",
      email_address: "google@example.com",
      password: "password123"
    )

    identity = Identity.new(
      user: user,
      provider: "google",
      uid: "google-user-123"
    )

    assert identity.valid?
  end

  test "accepts apple as a provider" do
    user = User.create!(
      first_name: "Test",
      last_name: "Identity",
      phone: "+34600000010",
      email_address: "apple@example.com",
      password: "password123"
    )

    identity = Identity.new(
      user: user,
      provider: "apple",
      uid: "apple-user-123"
    )

    assert identity.valid?
  end

  test "rejects unsupported providers" do
    user = User.create!(
      first_name: "Test",
      last_name: "Identity",
      phone: "+34600000010",
      email_address: "unsupported@example.com",
      password: "password123"
    )

    identity = Identity.new(
      user: user,
      provider: "facebook",
      uid: "facebook-user-123"
    )

    assert_not identity.valid?
    assert_includes identity.errors[:provider], "is not included in the list"
  end

  test "does not allow the same uid for the same provider twice" do
    user = User.create!(
      first_name: "Test",
      last_name: "Identity",
      phone: "+34600000010",
      email_address: "first@example.com",
      password: "password123"
    )

    other_user = User.create!(
      first_name: "Test",
      last_name: "Identity",
      phone: "+34600000010",
      email_address: "second@example.com",
      password: "password123"
    )

    Identity.create!(
      user: user,
      provider: "google",
      uid: "same-google-id"
    )

    duplicate = Identity.new(
      user: other_user,
      provider: "google",
      uid: "same-google-id"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:uid], "has already been taken"
  end
end
