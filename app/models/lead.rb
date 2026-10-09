class Lead < ApplicationRecord
  belongs_to :quote

  STATUSES = %w[
    NEW
    CONTACTED
    QUOTED
    ACCEPTED
    REJECTED
    COMPLETED
  ].freeze

  CONTACT_PREFERENCES = %w[
    EMAIL_QUOTE
    PHONE
    EMAIL_CONTACT
  ].freeze

  scope :with_consent, -> {
    where(consent_given: true, consent_withdrawn_at: nil).where.not(consent_at: nil)
  }

  CONSENT_BASES = %w[account_operational_email].freeze

  validates :email,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :consent_given,
            inclusion: { in: [ true ] }

  validates :consent_at,
            presence: true

  validates :status,
            inclusion: { in: STATUSES }

  validates :contact_preference,
            inclusion: { in: CONTACT_PREFERENCES },
            allow_nil: true

  validates :consent_basis,
            inclusion: { in: CONSENT_BASES },
            allow_nil: true

  validates :phone,
            presence: true,
            if: -> { contact_preference == "PHONE" }

  def contact!
    update!(status: "CONTACTED")
  end

  def mark_quoted!
    update!(status: "QUOTED")
  end

  def accept!
    update!(status: "ACCEPTED")
  end

  def reject!
    update!(status: "REJECTED")
  end

  def complete!
    update!(status: "COMPLETED")
  end
end
