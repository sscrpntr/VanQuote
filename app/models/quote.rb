class Quote < ApplicationRecord
  validates :origin, presence: true
  validates :destination, presence: true

  validates :distance_km,
            numericality: { greater_than: 0 }

  validates :estimated_duration_minutes,
            numericality: { greater_than: 0 }

  validates :fuel_cost,
            :toll_cost,
            :vehicle_cost,
            :driver_cost,
            :loading_cost,
            :waiting_cost,
            :other_cost,
            numericality: { greater_than_or_equal_to: 0 }

  validates :margin,
            numericality: { greater_than_or_equal_to: 0 }
end
