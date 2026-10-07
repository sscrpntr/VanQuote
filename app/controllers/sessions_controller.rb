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
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for(user)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path,
                  alert: I18n.t("sessions.alerts.invalid_credentials")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

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
