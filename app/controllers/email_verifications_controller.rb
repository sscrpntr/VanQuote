class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = User.find_signed!(params[:token], purpose: :email_verification)
    user.verify_email!
    start_new_session_for(user)
    redirect_to after_authentication_url(default_url: dashboard_url), notice: I18n.t("registrations.new.email_verified")
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to new_session_path, alert: I18n.t("registrations.new.email_verification_expired")
  end
end
