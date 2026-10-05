class QuoteCalculator
  COST_FIELDS = %i[
    fuel_cost
    toll_cost
    vehicle_cost
    driver_cost
    loading_cost
    waiting_cost
    other_cost
  ].freeze

  def initialize(quote)
    @quote = quote
  end

  def total_cost
    COST_FIELDS.sum { |field| @quote.public_send(field).to_d }
  end

  def recommended_price
    total_cost * (1 + @quote.margin.to_d / 100)
  end
end
