require "openssl"

class PasswordResetRateLimiter
  IP_LIMIT = 10
  IP_WINDOW = 3.minutes
  ACCOUNT_LIMIT = 5
  ACCOUNT_WINDOW = 15.minutes
  CLEANUP_BATCH_SIZE = 100

  class ConfigurationError < StandardError; end

  def self.allow?(ip:, email:, now: Time.current, environment: Rails.env,
    configured_key: ENV["PASSWORD_RESET_RATE_LIMIT_SECRET"])
    key = secret_key(environment: environment, configured_key: configured_key)
    ip_digest = key_digest(key, "ip", ip.to_s)
    account_digest = key_digest(key, "account", email.to_s.strip.downcase)

    counts = PasswordResetRateLimit.transaction do
      cleanup_expired!(now)
      [
        increment_bucket!("ip", ip_digest, IP_WINDOW, now),
        increment_bucket!("account", account_digest, ACCOUNT_WINDOW, now)
      ]
    end

    counts[0] <= IP_LIMIT && counts[1] <= ACCOUNT_LIMIT
  end

  def self.secret_key(environment:, configured_key:)
    return configured_key if configured_key.is_a?(String) && configured_key.match?(/\A[0-9a-f]{64}\z/i)

    if configured_key.present? || environment.production?
      raise ConfigurationError, "PASSWORD_RESET_RATE_LIMIT_SECRET must be 64 hexadecimal characters"
    end

    Rails.application.secret_key_base
  end
  private_class_method :secret_key

  def self.key_digest(secret, scope, value)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "password-reset-rate-limit\0#{scope}\0#{value}")
  end
  private_class_method :key_digest

  def self.increment_bucket!(scope, digest, window, now)
    connection = PasswordResetRateLimit.connection
    quoted_now = connection.quote(now)
    quoted_expiry = connection.quote(now + window)
    quoted_scope = connection.quote(scope)
    quoted_digest = connection.quote(digest)

    sql = <<~SQL
      INSERT INTO password_reset_rate_limits
        (scope, key_digest, request_count, window_started_at, expires_at, created_at, updated_at)
      VALUES (#{quoted_scope}, #{quoted_digest}, 1, #{quoted_now}, #{quoted_expiry}, #{quoted_now}, #{quoted_now})
      ON CONFLICT (scope, key_digest) DO UPDATE SET
        request_count = CASE
          WHEN password_reset_rate_limits.expires_at <= EXCLUDED.window_started_at THEN 1
          ELSE password_reset_rate_limits.request_count + 1
        END,
        window_started_at = CASE
          WHEN password_reset_rate_limits.expires_at <= EXCLUDED.window_started_at THEN EXCLUDED.window_started_at
          ELSE password_reset_rate_limits.window_started_at
        END,
        expires_at = CASE
          WHEN password_reset_rate_limits.expires_at <= EXCLUDED.window_started_at THEN EXCLUDED.expires_at
          ELSE password_reset_rate_limits.expires_at
        END,
        updated_at = EXCLUDED.updated_at
      RETURNING request_count
    SQL

    connection.select_value(sql).to_i
  end
  private_class_method :increment_bucket!

  def self.cleanup_expired!(now)
    connection = PasswordResetRateLimit.connection
    quoted_now = connection.quote(now)
    connection.execute(<<~SQL)
      WITH expired AS (
        SELECT id
        FROM password_reset_rate_limits
        WHERE expires_at <= #{quoted_now}
        ORDER BY expires_at
        LIMIT #{CLEANUP_BATCH_SIZE}
        FOR UPDATE SKIP LOCKED
      )
      DELETE FROM password_reset_rate_limits
      USING expired
      WHERE password_reset_rate_limits.id = expired.id
    SQL
  end
  private_class_method :cleanup_expired!
end
