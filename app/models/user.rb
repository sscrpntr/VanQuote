class User < ApplicationRecord
  has_secure_password

  generates_token_for :password_reset, expires_in: 15.minutes do
    [ password_salt&.last(10), password_reset_generation ]
  end

  has_many :sessions, dependent: :destroy
  has_many :quotes, dependent: :nullify
  has_many :identities, dependent: :destroy
  has_many :operational_email_consent_events, dependent: :restrict_with_exception

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address,
            presence: true,
            uniqueness: true

  validates :first_name, presence: true
  validates :last_name, presence: true

  OPERATIONAL_EMAIL_CONSENT_VERSION = "2026-10-v1".freeze
  OPERATIONAL_EMAIL_CONSENT_PURPOSE = "quote_result_and_transport_request_follow_up".freeze
  TERMS_VERSION = "2026-10-v1".freeze

  def terms_accepted?
    terms_accepted_at.present? && terms_version == TERMS_VERSION
  end

  def email_verified?
    email_verified_at.present?
  end

  def self.consume_password_reset_token(token)
    user = find_by_password_reset_token(token)
    return unless user

    user.with_lock do
      user.reload
      next unless find_by_password_reset_token(token)&.id == user.id

      user.update!(password_reset_generation: user.password_reset_generation + 1)
      user
    end
  end

  def verify_email!
    update_column(:email_verified_at, Time.current) unless email_verified?
  end

  def operational_email_consent_valid?
    operational_email_consent? && operational_email_consent_at.present? &&
      operational_email_consent_text_version == OPERATIONAL_EMAIL_CONSENT_VERSION &&
      operational_email_consent_purpose == OPERATIONAL_EMAIL_CONSENT_PURPOSE
  end

  def grant_operational_email_consent!(consent_text:)
    now = Time.current

    transaction do
      update!(
        operational_email_consent: true,
        operational_email_consent_at: now,
        operational_email_consent_text_version: OPERATIONAL_EMAIL_CONSENT_VERSION,
        operational_email_consent_purpose: OPERATIONAL_EMAIL_CONSENT_PURPOSE
      )
      operational_email_consent_events.create!(
        action: "granted",
        text_version: OPERATIONAL_EMAIL_CONSENT_VERSION,
        purpose: OPERATIONAL_EMAIL_CONSENT_PURPOSE,
        consent_text: consent_text,
        occurred_at: now
      )
    end
  end

  def withdraw_operational_email_consent!
    return unless operational_email_consent?

    now = Time.current

    transaction do
      operational_email_consent_events.create!(
        action: "withdrawn",
        purpose: OPERATIONAL_EMAIL_CONSENT_PURPOSE,
        occurred_at: now
      )
      update!(
        operational_email_consent: false,
        operational_email_consent_at: nil,
        operational_email_consent_text_version: nil,
        operational_email_consent_purpose: nil
      )
      Lead.joins(:quote)
        .where(quotes: { user_id: id }, consent_basis: "account_operational_email")
        .update_all(consent_withdrawn_at: now, updated_at: now)
    end
  end
end
