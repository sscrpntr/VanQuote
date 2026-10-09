class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @reset_url = new_password_reset_url(anchor: user.password_reset_token)
    mail subject: "Reset your password", to: user.email_address
  end
end
