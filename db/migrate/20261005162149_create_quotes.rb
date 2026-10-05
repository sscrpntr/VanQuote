class CreateQuotes < ActiveRecord::Migration[8.1]
  def change
    create_table :quotes do |t|
      t.string :origin
      t.string :destination
      t.decimal :distance_km
      t.integer :estimated_duration_minutes
      t.decimal :fuel_cost
      t.decimal :toll_cost
      t.decimal :vehicle_cost
      t.decimal :driver_cost
      t.decimal :loading_cost
      t.decimal :waiting_cost
      t.decimal :other_cost
      t.decimal :total_cost
      t.decimal :margin
      t.decimal :recommended_price

      t.timestamps
    end
  end
end
