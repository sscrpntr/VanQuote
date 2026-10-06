require "test_helper"

class GoogleRoutesServiceTest < ActiveSupport::TestCase
  class FakeResponse
    attr_reader :code, :body

    def initialize(code:, body:)
      @code = code
      @body = body
    end
  end

  class FakeHttp
    attr_reader :request

    def initialize(response)
      @response = response
    end

    def use_ssl=(_value)
    end

    def request(request = nil)
      if request
        @request = request
        @response
      else
        @request
      end
    end
  end

  test "returns road distance and duration from Google Routes API" do
    response_body = {
      routes: [
        {
          distanceMeters: 103_765,
          duration: "4840s"
        }
      ]
    }.to_json

    response = FakeResponse.new(
      code: "200",
      body: response_body
    )

    http = FakeHttp.new(response)

    result = GoogleRoutesService.new(
      origin: "Barcelona, Spain",
      destination: "Girona, Spain",
      http_factory: ->(_uri) { http }
    ).call

    assert_in_delta 103.765, result[:distance_km], 0.001
    assert_in_delta 80.6667, result[:duration_minutes], 0.001

    assert_equal "POST", http.request.method
    assert_equal(
      "routes.distanceMeters,routes.duration",
      http.request["X-Goog-FieldMask"]
    )
  end

  test "raises an error when Google Routes API returns an error" do
    response = FakeResponse.new(
      code: "400",
      body: '{"error":"bad request"}'
    )

    http = FakeHttp.new(response)

    error = assert_raises(RuntimeError) do
      GoogleRoutesService.new(
        origin: "Barcelona, Spain",
        destination: "Girona, Spain",
        http_factory: ->(_uri) { http }
      ).call
    end

    assert_includes error.message, "Google Routes API error: HTTP 400"
  end
end
