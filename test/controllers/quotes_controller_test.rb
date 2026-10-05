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
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    quote = Quote.last

    assert_redirected_to quote_path(quote)
    assert_equal 316.4.to_d, quote.total_cost
    assert_equal 395.5.to_d, quote.recommended_price
  end

  test "creates a lead when creating a quote" do
    assert_difference("Lead.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 620,
          estimated_duration_minutes: 360
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    lead = Lead.last

    assert_equal "customer@example.com", lead.email
    assert_equal true, lead.consent_given
    assert_not_nil lead.consent_at
    assert_equal "NEW", lead.status
    assert_equal Quote.last.id, lead.quote_id
  end

  test "ignores internal costs submitted by the customer" do
    assert_difference("Quote.count", 1) do
      post quotes_path, params: {
        quote: {
          origin: "Barcelona",
          destination: "Madrid",
          distance_km: 620,
          estimated_duration_minutes: 360,
          fuel_cost: 9999,
          toll_cost: 9999,
          vehicle_cost: 9999,
          driver_cost: 9999,
          loading_cost: 9999,
          waiting_cost: 9999,
          other_cost: 9999,
          margin: 999
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    quote = Quote.last

    assert_equal 74.4.to_d, quote.fuel_cost
    assert_equal 0.to_d, quote.toll_cost
    assert_equal 62.to_d, quote.vehicle_cost
    assert_equal 150.to_d, quote.driver_cost
    assert_equal 20.to_d, quote.loading_cost
    assert_equal 0.to_d, quote.waiting_cost
    assert_equal 10.to_d, quote.other_cost
    assert_equal 25.to_d, quote.margin
    assert_equal 395.5.to_d, quote.recommended_price
  end

  test "shows the three price options" do
    quote = quotes(:one)

    get quote_path(quote)

    assert_response :success
    assert_includes response.body, "€489.50"
    assert_includes response.body, "€556.25"
    assert_includes response.body, "€623.00"
    assert_not_includes response.body, "Coste real"
    assert_not_includes response.body, "Margen"
  end

  test "does not create a lead without consent" do
    assert_no_difference("Quote.count") do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Barcelona",
            destination: "Madrid",
            distance_km: 620,
            estimated_duration_minutes: 360
          },
          email: "customer@example.com",
          consent_given: "0"
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "does not create a lead with an invalid email" do
    assert_no_difference("Quote.count") do
      assert_no_difference("Lead.count") do
        post quotes_path, params: {
          quote: {
            origin: "Barcelona",
            destination: "Madrid",
            distance_km: 620,
            estimated_duration_minutes: 360
          },
          email: "not-an-email",
          consent_given: "1"
        }
      end
    end

    assert_response :unprocessable_entity
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
        },
        email: "customer@example.com",
        consent_given: "1"
      }
    end

    assert_response :unprocessable_entity
  end

  test "strips whitespace from lead email" do
  assert_difference("Lead.count", 1) do
    post quotes_path, params: {
      quote: {
        origin: "Barcelona",
        destination: "Madrid",
        distance_km: 620,
        estimated_duration_minutes: 360
      },
      email: "  customer@example.com  ",
      consent_given: "1"
    }
  end

  lead = Lead.last

  assert_equal "customer@example.com", lead.email
end
end
