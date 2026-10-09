class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_password_reset_security_headers
  before_action :set_reset_authorized_user, only: %i[edit_reset update_reset]

  def new
  end

  def create
    email = params[:email_address].to_s.strip
    allowed = PasswordResetRateLimiter.allow?(ip: request.remote_ip, email: email)
    if allowed
      user = User.find_by(email_address: email)
      send_reset_email(user) if user
    end

    redirect_to new_session_path, notice: I18n.t("passwords.notices.reset_instructions")
  rescue PasswordResetRateLimiter::ConfigurationError
    Rails.logger.error("Password reset throttling unavailable: configure PASSWORD_RESET_RATE_LIMIT_SECRET with at least 32 bytes")
    redirect_to new_session_path, notice: I18n.t("passwords.notices.reset_instructions")
  rescue StandardError => error
    Rails.logger.error("Password reset request failed (#{error.class})")
    redirect_to new_session_path, notice: I18n.t("passwords.notices.reset_instructions")
  end

  def reset_link
  end

  def verify_reset
    user = User.consume_password_reset_token(params[:token].to_s)
    unless user
      return redirect_to new_password_path,
        alert: I18n.t("passwords.alerts.invalid_or_expired_link")
    end

    reset_session
    session[:password_reset_authorization] = {
      user_id: user.id,
      expires_at: 15.minutes.from_now.to_i
    }
    redirect_to edit_password_reset_path
  rescue StandardError => error
    Rails.logger.error("Password reset token verification failed (#{error.class})")
    redirect_to new_password_path,
      alert: I18n.t("passwords.alerts.invalid_or_expired_link")
  end

  def edit_reset
    render :edit
  end

  def update_reset
    if @reset_user.update(params.permit(:password, :password_confirmation))
      @reset_user.sessions.destroy_all
      session.delete(:password_reset_authorization)

      redirect_to new_session_path,
        notice: I18n.t("passwords.notices.reset_success")
    else
      flash.now[:alert] = I18n.t("passwords.alerts.passwords_did_not_match")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def send_reset_email(user)
    PasswordsMailer.reset(user).deliver_now
  rescue StandardError => error
    Rails.logger.error("Password reset email failed (#{error.class})")
  end

  def set_reset_authorized_user
    authorization = session[:password_reset_authorization]
    if authorization.is_a?(Hash)
      expires_at = authorization["expires_at"] || authorization[:expires_at]
      user_id = authorization["user_id"] || authorization[:user_id]
      @reset_user = User.find_by(id: user_id) if expires_at.present? && expires_at.to_i > Time.current.to_i
    end

    return if @reset_user

    session.delete(:password_reset_authorization)
    redirect_to new_password_path,
      alert: I18n.t("passwords.alerts.invalid_or_expired_link")
  end

  def set_password_reset_security_headers
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
  end
end
