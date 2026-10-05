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

  validates :email,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :consent_given,
            inclusion: { in: [ true ] }

  validates :consent_at,
            presence: true

  validates :status,
            inclusion: { in: STATUSES }

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
