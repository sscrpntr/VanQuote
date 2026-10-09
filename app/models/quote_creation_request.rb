require "openssl"

class QuoteCreationRequest < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :quote, optional: true

  KEY_PATTERN = /\A[A-Za-z0-9_-]{43}\z/
  LEASE_DURATION = 10.minutes
  STATUSES = %w[pending processing failed completed].freeze

  class KeyConflict < StandardError; end
  class RequestInProgress < StandardError; end
  class AnonymousLimitReached < StandardError; end
  class LostClaim < StandardError; end

  validates :key_digest, :request_digest, presence: true
  validates :status, inclusion: { in: STATUSES }

  def self.valid_key?(value)
    value.is_a?(String) && value.match?(KEY_PATTERN)
  end

  def self.generate_key
    SecureRandom.urlsafe_base64(32, false)
  end

  def self.request_digest(origin:, destination:, contact_email:)
    digest("quote-request", [ origin, destination, contact_email ].to_json)
  end

  def self.claim!(key:, request_digest:, user:, session_binding:, http_request:)
    raise KeyConflict unless valid_key?(key)

    key_hash = OpenSSL::Digest.hexdigest("SHA256", key)
    session_hash = digest("quote-session-binding", session_binding) if session_binding.present?

    transaction do
      operation = create_or_find_by!(key_digest: key_hash) do |record|
        record.request_digest = request_digest
        record.user = user
        record.anonymous_session_digest = user ? nil : session_hash
        record.status = "pending"
      end

      operation.with_lock do
        operation.reload
        verify_request!(operation, request_digest, user, session_hash)

        if operation.status == "completed"
          next { status: :completed, quote: operation.quote }
        end

        if operation.status == "processing" && operation.lease_expires_at.future?
          raise RequestInProgress
        end

        if operation.user_id.nil? && operation.anonymous_counted_at.nil?
          raise AnonymousLimitReached unless AnonymousQuoteCounter.consume!(http_request)

          operation.anonymous_counted_at = Time.current
        end

        claim_token = SecureRandom.hex(32)
        operation.update!(
          status: "processing",
          claim_token: claim_token,
          lease_expires_at: LEASE_DURATION.from_now,
          anonymous_counted_at: operation.anonymous_counted_at
        )
        { status: :process, operation: operation, claim_token: claim_token }
      end
    end
  end

  def complete!(claim_token)
    with_lock do
      reload
      raise LostClaim unless status == "processing" && self.claim_token == claim_token

      created_quote = yield
      update!(
        quote: created_quote,
        status: "completed",
        claim_token: nil,
        lease_expires_at: nil
      )
      created_quote
    end
  end

  def fail!(claim_token)
    with_lock do
      reload
      return false unless status == "processing" && self.claim_token == claim_token

      update!(status: "failed", claim_token: nil, lease_expires_at: nil)
      true
    end
  end

  def self.digest(purpose, value)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{purpose}\0#{value}")
  end
  private_class_method :digest

  def self.verify_request!(operation, request_digest, user, session_hash)
    raise KeyConflict unless ActiveSupport::SecurityUtils.secure_compare(operation.request_digest, request_digest)

    authorized = if operation.user_id.present?
      user&.id == operation.user_id
    else
      session_hash.present? &&
        ActiveSupport::SecurityUtils.secure_compare(operation.anonymous_session_digest, session_hash)
    end
    raise KeyConflict unless authorized
  end
  private_class_method :verify_request!
end
