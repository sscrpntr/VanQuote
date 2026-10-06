class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :quotes, dependent: :nullify
  has_many :identities, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address,
            presence: true,
            uniqueness: true
end
