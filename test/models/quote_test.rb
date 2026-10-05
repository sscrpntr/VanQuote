require "test_helper"

class QuoteTest < ActiveSupport::TestCase
  test "valid quote" do
    quote = Quote.new(
      origin: "Barcelona",
      destination: "Madrid",
      distance_km: 620,
      estimated_duration_minutes: 360,
      fuel_cost: 80,
      toll_cost: 35,
      vehicle_cost: 120,
      driver_cost: 150,
      loading_cost: 30,
      waiting_cost: 20,
      other_cost: 10,
      margin: 25
    )

    assert quote.valid?
  end

  test "requires origin" do
    quote = quotes(:one)
    quote.origin = nil

    assert_not quote.valid?
  end

  test "requires destination" do
    quote = quotes(:one)
    quote.destination = nil

    assert_not quote.valid?
  end

  test "does not allow negative costs" do
    quote = quotes(:one)
    quote.fuel_cost = -10

    assert_not quote.valid?
  end

  test "does not allow negative margin" do
    quote = quotes(:one)
    quote.margin = -5

    assert_not quote.valid?
  end
end
