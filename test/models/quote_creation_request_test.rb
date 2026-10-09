require "test_helper"

class QuoteCreationRequestTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent claims for one key produce one reservation and one quote" do
    user = User.create!(
      first_name: "Concurrent",
      last_name: "Requester",
      email_address: "concurrent-requester@example.com",
      password: "password123",
      email_verified_at: Time.current
    )
    key = QuoteCreationRequest.generate_key
    digest = QuoteCreationRequest.request_digest(
      origin: "Barcelona",
      destination: "Madrid",
      contact_email: user.email_address
    )
    start = Queue.new
    outcomes = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          begin
            outcomes << QuoteCreationRequest.claim!(
              key: key,
              request_digest: digest,
              user: user,
              session_binding: nil,
              http_request: nil
            )
          rescue QuoteCreationRequest::RequestInProgress => error
            outcomes << error
          end
        end
      end
    end
    2.times { start << true }
    threads.each(&:value)

    results = 2.times.map { outcomes.pop }
    process_claims = results.grep(Hash).select { |result| result[:status] == :process }
    assert_equal 1, process_claims.length
    assert_equal 1, results.grep(QuoteCreationRequest::RequestInProgress).length

    claim = process_claims.fetch(0)
    operation = claim.fetch(:operation)
    quote = operation.complete!(claim.fetch(:claim_token)) do
      Quote.create!(
        user: user,
        origin: "Barcelona",
        destination: "Madrid",
        contact_email: user.email_address,
        distance_km: 620,
        estimated_duration_minutes: 360,
        fuel_cost: 74.4,
        toll_cost: 0,
        vehicle_cost: 62,
        driver_cost: 150,
        loading_cost: 20,
        waiting_cost: 0,
        other_cost: 10,
        total_cost: 316.4,
        margin: 25,
        recommended_price: 395.5
      )
    end

    replay = QuoteCreationRequest.claim!(
      key: key,
      request_digest: digest,
      user: user,
      session_binding: nil,
      http_request: nil
    )
    assert_equal :completed, replay[:status]
    assert_equal quote.id, replay[:quote].id
    assert_equal 1, QuoteCreationRequest.where(key_digest: operation.key_digest).count
    assert_equal 1, Quote.where(user_id: user.id, origin: "Barcelona", destination: "Madrid").count
  ensure
    operation&.destroy!
    quote&.destroy!
    user&.destroy!
  end
end
