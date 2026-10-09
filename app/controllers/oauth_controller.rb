class OauthController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection only: :callback

  def unavailable
    provider = oauth_provider
    return redirect_to new_registration_path, alert: oauth_error("invalid_provider") unless provider

    redirect_to new_registration_path,
                alert: oauth_error("not_configured", provider: provider_label(provider))
  end

  def callback
    auth = request.env["omniauth.auth"]
    log_google_auth_hash_structure(auth) if Rails.env.development?
    profile = Identity.profile_from(auth)
    identity = Identity.find_by(provider: profile.fetch("provider"), uid: profile.fetch("uid"))
    user = identity&.user
    user&.verify_email! if identity

    if !identity && User.exists?(email_address: profile.fetch("email_address"))
      session[:pending_oauth_link] = profile
      redirect_to new_session_path, alert: I18n.t("oauth.errors.sign_in_to_link")
      return
    end

    if user&.terms_accepted?
      raise Identity::AuthenticationError, "unverified account" unless user.email_verified?

      session.delete(:pending_oauth_signup)
      start_new_session_for(user)
      redirect_to after_authentication_url(default_url: dashboard_url)
    else
      profile["user_id"] = user.id if user
      session[:pending_oauth_signup] = profile
      redirect_to new_registration_path
    end
  rescue Identity::AuthenticationError => error
    Rails.logger.info("OAuth authentication rejected: #{error.message}")
    redirect_to new_session_path, alert: oauth_error("authentication_failed")
  rescue ActiveRecord::RecordInvalid => error
    Rails.logger.warn("OAuth account could not be saved: #{error.record.errors.attribute_names.join(', ')}")
    redirect_to new_registration_path, alert: oauth_error("account_creation_failed")
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_registration_path, alert: oauth_error("account_creation_failed")
  end

  def failure
    session.delete(:pending_oauth_signup)
    redirect_to new_session_path, alert: oauth_error("authentication_failed")
  end

  def cancel
    session.delete(:pending_oauth_signup)
    token = session[:quote_token_after_authenticating]
    quote = Quote.find_signed(token, purpose: :public_view) if token.present?
    redirect_to(quote ? public_quotes_path(token: token) : root_path)
  end

  private

  def oauth_provider
    params[:provider].presence_in(%w[google_oauth2 apple])
  end

  def provider_label(provider)
    I18n.t("oauth.providers.#{provider}")
  end

  def oauth_error(key, **options)
    I18n.t("oauth.errors.#{key}", **options)
  end

  def log_google_auth_hash_structure(auth)
    auth_keys = auth.respond_to?(:keys) ? auth.keys.map(&:to_s).sort : []
    credentials = auth.respond_to?(:[]) ? (auth["credentials"] || auth[:credentials]) : nil
    extra = auth.respond_to?(:[]) ? (auth["extra"] || auth[:extra]) : nil
    credentials_keys = credentials.respond_to?(:keys) ? credentials.keys.map(&:to_s).sort : []
    extra_keys = extra.respond_to?(:keys) ? extra.keys.map(&:to_s).sort : []
    id_token_present = extra.respond_to?(:[]) && (extra["id_token"] || extra[:id_token]).present?

    Rails.logger.info(
      "Google OAuth callback hash structure: auth_keys=#{auth_keys.inspect} " \
      "credentials_keys=#{credentials_keys.inspect} extra_keys=#{extra_keys.inspect} " \
      "id_token_present_in_extra=#{id_token_present}"
    )
  end
end
