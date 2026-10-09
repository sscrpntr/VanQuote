class Identity < ApplicationRecord
  belongs_to :user

  PROVIDERS = %w[google apple].freeze

  validates :provider,
            presence: true,
            inclusion: { in: PROVIDERS }

  validates :uid,
            presence: true,
            uniqueness: { scope: :provider }

  class AuthenticationError < StandardError; end

  def self.profile_from(auth)
    raise AuthenticationError, "missing provider response" unless auth.respond_to?(:[])

    provider = auth["provider"].to_s
    provider = "google" if provider == "google_oauth2"
    uid = auth["uid"].to_s
    raise AuthenticationError, "unsupported provider" unless PROVIDERS.include?(provider)
    raise AuthenticationError, "missing provider uid" if uid.blank?

    info = auth["info"] || {}
    email = info["email"].to_s.strip.downcase
    raise AuthenticationError, "missing email" if email.blank?
    raise AuthenticationError, "unverified email" unless verified_email?(auth)

    name = info["name"].to_s.strip.split(/\s+/, 2)
    {
      "provider" => provider,
      "uid" => uid,
      "email_address" => email,
      "first_name" => info["first_name"].presence || name.first.presence || I18n.t("oauth.default_name"),
      "last_name" => info["last_name"].presence || name.second.presence || I18n.t("oauth.default_last_name")
    }
  end

  def self.authenticate!(auth)
    profile = profile_from(auth)
    identity = find_by(provider: profile.fetch("provider"), uid: profile.fetch("uid"))
    raise AuthenticationError, "in-app registration required" unless identity

    identity.user
  end

  def self.verified_email?(auth)
    extra = auth["extra"] || {}
    claims = (extra["raw_info"] || {}).to_h.merge((extra["id_info"] || {}).to_h)
    claims["email_verified"].to_s == "true"
  end
  private_class_method :verified_email?

  def self.create_user!(provider, info, email)
    name = info["name"].to_s.strip.split(/\s+/, 2)
    first_name = info["first_name"].presence || name.first.presence || I18n.t("oauth.default_name")
    last_name = info["last_name"].presence || name.second.presence || I18n.t("oauth.default_last_name")

    User.create!(
      first_name: first_name,
      last_name: last_name,
      email_address: email,
      password: SecureRandom.urlsafe_base64(32)
    )
  end
  private_class_method :create_user!
end
