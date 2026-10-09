require "test_helper"
require "openssl"

class PasswordResetRateLimiterTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @key_pairs = []
    @base_time = Time.current.change(usec: 0)
  end

  teardown do
    @key_pairs.each do |scope, digest|
      PasswordResetRateLimit.where(scope: scope, key_digest: digest).delete_all
    end
  end

  test "atomic counters are shared across separate database connections" do
    email = "reset-#{SecureRandom.hex(8)}@example.com"
    ip = "198.51.100.27"
    track_keys(ip, email)
    start = Queue.new
    results = Queue.new

    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          results << PasswordResetRateLimiter.allow?(ip: ip, email: email, now: @base_time)
        end
      end
    end
    2.times { start << true }
    workers.each(&:value)

    assert_equal 2, 2.times.map { results.pop }.count(true)
    assert_equal 2, bucket("ip", ip).request_count
    assert_equal 2, bucket("account", email).request_count
  end

  test "account limit is bounded by a fixed window and expires" do
    email = "account-#{SecureRandom.hex(8)}@example.com"
    ips = 6.times.map { |index| "198.51.100.#{index + 50}" }
    ips.each { |ip| track_keys(ip, email) }

    5.times do |index|
      assert PasswordResetRateLimiter.allow?(ip: ips[index], email: email, now: @base_time)
    end
    assert_not PasswordResetRateLimiter.allow?(ip: ips.last, email: email, now: @base_time + 1.minute)

    expiry = bucket("account", email).expires_at
    assert_equal @base_time + PasswordResetRateLimiter::ACCOUNT_WINDOW, expiry
    assert PasswordResetRateLimiter.allow?(
      ip: ips.last,
      email: email,
      now: expiry + 1.second
    )
  end

  test "IP limit is independent from account limits and expires" do
    ip = "203.0.113.#{SecureRandom.random_number(100) + 1}"
    emails = 11.times.map { |index| "ip-limit-#{SecureRandom.hex(4)}-#{index}@example.com" }
    emails.each { |email| track_keys(ip, email) }

    10.times do |index|
      assert PasswordResetRateLimiter.allow?(ip: ip, email: emails[index], now: @base_time)
    end
    assert_not PasswordResetRateLimiter.allow?(ip: ip, email: emails.last, now: @base_time + 1.minute)
    assert PasswordResetRateLimiter.allow?(
      ip: ip,
      email: emails.last,
      now: @base_time + PasswordResetRateLimiter::IP_WINDOW + 1.second
    )
  end

  test "limiter rows contain only HMAC digests rather than raw email or IP" do
    email = "private-#{SecureRandom.hex(8)}@example.com"
    ip = "192.0.2.#{SecureRandom.random_number(100) + 1}"
    track_keys(ip, email)

    assert PasswordResetRateLimiter.allow?(ip: ip, email: email, now: @base_time)
    ip_row = bucket("ip", ip)
    account_row = bucket("account", email)

    [ [ ip_row, ip ], [ account_row, email ] ].each do |row, raw_value|
      assert_equal 64, row.key_digest.length
      assert_match(/\A[0-9a-f]{64}\z/, row.key_digest)
      assert(!row.attributes.values.compact.any? { |value| value.to_s.include?(raw_value) },
        "limiter row contained a raw identifier")
    end
  end

  test "production fails closed when the shared HMAC key is absent or malformed" do
    production_environment = Class.new do
      def production? = true
    end.new

    assert_raises(PasswordResetRateLimiter::ConfigurationError) do
      PasswordResetRateLimiter.send(:secret_key, environment: production_environment, configured_key: nil)
    end
    assert_raises(PasswordResetRateLimiter::ConfigurationError) do
      PasswordResetRateLimiter.send(:secret_key, environment: production_environment, configured_key: "short")
    end
  end

  private

  def bucket(scope, value)
    digest = digest_for(scope, value)
    PasswordResetRateLimit.find_by!(scope: scope, key_digest: digest)
  end

  def track_keys(ip, email)
    @key_pairs << [ "ip", digest_for("ip", ip) ]
    @key_pairs << [ "account", digest_for("account", email.strip.downcase) ]
  end

  def digest_for(scope, value)
    secret = PasswordResetRateLimiter.send(
      :secret_key,
      environment: Rails.env,
      configured_key: ENV["PASSWORD_RESET_RATE_LIMIT_SECRET"]
    )
    OpenSSL::HMAC.hexdigest("SHA256", secret, "password-reset-rate-limit\0#{scope}\0#{value}")
  end
end
