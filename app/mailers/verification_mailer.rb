class VerificationMailer < ApplicationMailer
  def verify(user)
    @user = user
    @token = user.signed_id(purpose: :email_verification, expires_in: 24.hours)
    mail subject: "Verify your VanQuote email", to: user.email_address
  end
end
