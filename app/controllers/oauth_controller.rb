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
    user = Identity.authenticate!(auth)
    start_new_session_for(user)
    redirect_to after_authentication_url(default_url: dashboard_url)
  rescue Identity::AuthenticationError => error
    Rails.logger.info("OAuth authentication rejected: #{error.message}")
    redirect_to new_session_path, alert: oauth_error("authentication_failed")
  rescue ActiveRecord::RecordInvalid => error
    Rails.logger.warn("OAuth account could not be saved: #{error.record.errors.full_messages.join(', ')}")
    redirect_to new_registration_path, alert: oauth_error("account_creation_failed")
  end

  def failure
    redirect_to new_session_path, alert: oauth_error("authentication_failed")
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
