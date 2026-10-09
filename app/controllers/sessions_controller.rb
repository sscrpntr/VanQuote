class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  rate_limit to: 10,
             within: 3.minutes,
             only: :create,
             with: -> {
               redirect_to new_session_path,
                           alert: I18n.t("sessions.alerts.try_again_later")
             }

  def new
    remember_public_quote_context

    if authenticated? && params[:quote_token].present?
      redirect_to after_authentication_url(default_url: quotes_url)
    end
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      unless user.email_verified?
        begin
          VerificationMailer.verify(user).deliver_now
          return redirect_to new_session_path, alert: I18n.t("sessions.alerts.email_not_verified")
        rescue StandardError => error
          Rails.logger.error("Email verification delivery failed (#{error.class})")
          return redirect_to new_session_path, alert: I18n.t("sessions.alerts.verification_delivery_failed")
        end
      end

      if pending_oauth_link_for?(user) && !user.terms_accepted?
        profile = session.delete(:pending_oauth_link)
        profile["user_id"] = user.id
        session[:pending_oauth_signup] = profile
        return redirect_to new_registration_path
      end

      link_pending_oauth_identity!(user)
      start_new_session_for(user)
      redirect_to after_authentication_url(default_url: dashboard_url)
    else
      redirect_to new_session_path,
                  alert: I18n.t("sessions.alerts.invalid_credentials")
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end

  private

  def link_pending_oauth_identity!(user)
    profile = session[:pending_oauth_link]
    return unless profile.is_a?(Hash) && profile["email_address"] == user.email_address

    user.identities.find_or_create_by!(provider: profile.fetch("provider"), uid: profile.fetch("uid"))
    session.delete(:pending_oauth_link)
  end

  def pending_oauth_link_for?(user)
    profile = session[:pending_oauth_link]
    profile.is_a?(Hash) && profile["email_address"] == user.email_address
  end

  def remember_public_quote_context
    if params[:quote_token].present?
      session[:quote_token_after_authenticating] = params[:quote_token]
    end

    if params[:contact_preference].present?
      session[:contact_preference_after_authenticating] =
        params[:contact_preference]
    end
  end
end
