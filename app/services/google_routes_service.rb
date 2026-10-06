require "net/http"
require "json"

class GoogleRoutesService
  API_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"

  def initialize(origin:, destination:, http_factory: nil)
    @origin = origin
    @destination = destination
    @http_factory = http_factory || ->(uri) { Net::HTTP.new(uri.host, uri.port) }
  end

  def call
    response = perform_request

    unless response.code.to_i.between?(200, 299)
      raise "Google Routes API error: HTTP #{response.code} - #{response.body}"
    end

    route = JSON.parse(response.body).fetch("routes").first

    {
      distance_km: route.fetch("distanceMeters").to_f / 1000,
      duration_minutes: route.fetch("duration").delete_suffix("s").to_f / 60
    }
  end

  private

  def perform_request
    uri = URI(API_URL)
    http = @http_factory.call(uri)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Goog-Api-Key"] =
      Rails.application.credentials.google_maps_api_key
    request["X-Goog-FieldMask"] =
      "routes.distanceMeters,routes.duration"

    request.body = {
      origin: { address: @origin },
      destination: { address: @destination },
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE"
    }.to_json

    http.request(request)
  end
end
