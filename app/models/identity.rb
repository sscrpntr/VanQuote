class Identity < ApplicationRecord
  belongs_to :user

  PROVIDERS = %w[google apple].freeze

  validates :provider,
            presence: true,
            inclusion: { in: PROVIDERS }

  validates :uid,
            presence: true,
            uniqueness: { scope: :provider }
end
