require "application_system_test_case"

class PasswordResetFlowTest < ApplicationSystemTestCase
  test "fragment token is removed before the password form is shown" do
    user = User.create!(
      first_name: "Reset",
      last_name: "Browser",
      email_address: "reset-browser@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
    mail = PasswordsMailer.reset(user).deliver_now
    reset_url = mail.text_part.body.decoded.match(%r{https?://\S+}).to_s
    uri = URI.parse(reset_url)

    visit "#{uri.path}##{uri.fragment}"

    assert_current_path edit_password_reset_path
    assert page.current_url.end_with?(edit_password_reset_path), "reset token remained in the browser URL"
    assert_selector "form[action='#{update_password_reset_path}']"

    find("input[name='password']").set("browser-reset-456")
    find("input[name='password_confirmation']").set("browser-reset-456")
    find("form[action='#{update_password_reset_path}'] input[type='submit']").click

    assert_current_path new_session_path
    assert user.reload.authenticate("browser-reset-456")
  end
end
