class PasswordsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_user_by_token, only: %i[edit update]

  rate_limit to: 10,
             within: 3.minutes,
             only: :create,
             with: -> {
               redirect_to new_password_path,
                           alert: I18n.t("passwords.alerts.try_again_later")
             }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path,
                notice: I18n.t("passwords.notices.reset_instructions")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all

      redirect_to new_session_path,
                  notice: I18n.t("passwords.notices.reset_success")
    else
      redirect_to edit_password_path(params[:token]),
                  alert: I18n.t("passwords.alerts.passwords_did_not_match")
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path,
                alert: I18n.t("passwords.alerts.invalid_or_expired_link")
  end
end
