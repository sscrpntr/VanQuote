class AnonymousQuoteCounter < ApplicationRecord
  MAX_REQUESTS = 3

  def self.consume!(request)
    fingerprint = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Rails.application.secret_key_base,
      [ request.remote_ip, request.user_agent.to_s.first(500) ].join("\0")
    )

    allowed = transaction do
      counter = find_or_create_by!(fingerprint: fingerprint) do |record|
        record.window_started_at = Time.current
      end
      counter.with_lock do
        next false if counter.requests_count >= MAX_REQUESTS

        counter.increment!(:requests_count)
        true
      end
    end
    allowed
  end
end
