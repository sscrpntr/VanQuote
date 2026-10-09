require "jwt"
require "net/http"

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
    claims = provider == "google" ? verified_google_claims(auth) : provider_claims(auth)
    raise AuthenticationError, "unverified email" unless claims["email_verified"].to_s == "true"
    raise AuthenticationError, "provider subject mismatch" unless claims["sub"].to_s == uid
    raise AuthenticationError, "provider email mismatch" unless claims["email"].to_s.casecmp?(email)

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

  def self.provider_claims(auth)
    extra = auth["extra"] || {}
    (extra["raw_info"] || {}).to_h.merge((extra["id_info"] || {}).to_h).stringify_keys
  end

  def self.verified_google_claims(auth)
    extra = auth["extra"] || auth[:extra] || {}
    token = extra["id_token"] || extra[:id_token]
    raise AuthenticationError, "missing Google ID token" if token.blank?
    client_id = Rails.application.config.x.oauth.google_client_id.presence
    client_id ||= "test-google-client-id" if Rails.env.test?
    raise AuthenticationError, "Google OAuth is not configured" if client_id.blank?

    jwks_loader = lambda do |options|
      if Rails.env.test? && Rails.application.config.x.oauth.google_jwks.present?
        next Rails.application.config.x.oauth.google_jwks
      end

      Rails.cache.delete("google_oauth_jwks") if options[:invalidate]
      Rails.cache.fetch("google_oauth_jwks", expires_in: 1.hour) do
        uri = URI("https://www.googleapis.com/oauth2/v3/certs")
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) do |http|
          http.get(uri.request_uri)
        end
        raise AuthenticationError, "Google signing keys unavailable" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
    claims, = JWT.decode(token, nil, true,
      algorithms: [ "RS256" ], jwks: jwks_loader,
      iss: %w[accounts.google.com https://accounts.google.com], verify_iss: true,
      aud: client_id, verify_aud: true, verify_exp: true)
    claims.stringify_keys
  rescue JWT::DecodeError, JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError => error
    raise AuthenticationError, "Google ID token validation failed (#{error.class})"
  end
  private_class_method :provider_claims, :verified_google_claims

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
