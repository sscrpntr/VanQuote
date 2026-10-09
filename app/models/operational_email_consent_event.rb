class OperationalEmailConsentEvent < ApplicationRecord
  belongs_to :user

  ACTIONS = %w[granted withdrawn].freeze

  validates :action, inclusion: { in: ACTIONS }
  validates :purpose, presence: true
  validates :occurred_at, presence: true
  validates :text_version, :consent_text, presence: true, if: -> { action == "granted" }
end
