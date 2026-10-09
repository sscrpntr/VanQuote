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
    profile = Identity.profile_from(request.env["omniauth.auth"])
    identity = Identity.find_by(provider: profile.fetch("provider"), uid: profile.fetch("uid"))
    user = identity&.user || User.find_by(email_address: profile.fetch("email_address"))

    if user&.terms_accepted?
      user.identities.find_or_create_by!(provider: profile.fetch("provider"), uid: profile.fetch("uid")) unless identity
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
end
