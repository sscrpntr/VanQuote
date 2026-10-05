require "test_helper"

class QuoteCalculatorTest < ActiveSupport::TestCase
  test "calculates total cost" do
    quote = quotes(:one)

    calculator = QuoteCalculator.new(quote)

    assert_equal 445.to_d, calculator.total_cost
  end

  test "calculates recommended price using margin percentage" do
    quote = quotes(:one)

    calculator = QuoteCalculator.new(quote)

    assert_equal 556.25.to_d, calculator.recommended_price
  end

  test "calculates minimum price" do
    quote = quotes(:one)

    calculator = QuoteCalculator.new(quote)

    assert_equal 489.50.to_d, calculator.minimum_price
  end

  test "calculates premium price" do
    quote = quotes(:one)

    calculator = QuoteCalculator.new(quote)

    assert_equal 623.to_d, calculator.premium_price
  end
end
