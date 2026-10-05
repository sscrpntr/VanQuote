require "test_helper"

class QuotesControllerTest < ActionDispatch::IntegrationTest
  test "creates a quote" do
    assert_difference("Quote.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 620,
          estimated_duration_minutes: 360,
          fuel_cost: 80,
          toll_cost: 35,
          vehicle_cost: 120,
          driver_cost: 150,
          loading_cost: 20,
          waiting_cost: 30,
          other_cost: 10,
          margin: 25
        }
      }
    end

    quote = Quote.last

    assert_redirected_to quote_path(quote)
    assert_equal 445.to_d, quote.total_cost
    assert_equal 556.25.to_d, quote.recommended_price
  end
  test "shows the three price options" do
    quote = quotes(:one)

    get quote_path(quote)

    assert_response :success
      assert_includes response.body, "€489.50"
      assert_includes response.body, "€556.25"
      assert_includes response.body, "€623.00"
  end
  test "does not create an invalid quote" do
    assert_no_difference("Quote.count") do
      post quotes_path, params: {
        quote: {
          origin: "",
          destination: "",
          distance_km: 0,
          estimated_duration_minutes: 0,
          fuel_cost: -10,
          margin: -5
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
