require "test_helper"

class LeadUniquenessTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "the database prevents concurrent leads for the same quote" do
    quote = Quote.create!(
      origin: "Barcelona",
      destination: "Girona",
      contact_email: "lead-uniqueness@example.com",
      distance_km: 100,
      estimated_duration_minutes: 60,
      fuel_cost: 12,
      toll_cost: 0,
      vehicle_cost: 10,
      driver_cost: 25,
      loading_cost: 20,
      waiting_cost: 0,
      other_cost: 10,
      total_cost: 77,
      margin: 25,
      recommended_price: 96.25
    )
    start = Queue.new
    outcomes = Queue.new

    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          begin
            outcomes << Lead.create!(
              quote_id: quote.id,
              email: "lead-uniqueness@example.com",
              consent_given: true,
              consent_at: Time.current,
              status: "NEW"
            )
          rescue ActiveRecord::RecordNotUnique
            outcomes << :duplicate_rejected
          end
        end
      end
    end
    2.times { start << true }
    workers.each(&:value)

    results = 2.times.map { outcomes.pop }
    assert_equal 1, results.count { |result| result.is_a?(Lead) }
    assert_equal 1, results.count(:duplicate_rejected)
    assert_equal 1, Lead.where(quote_id: quote.id).count
  ensure
    Lead.where(quote_id: quote&.id).delete_all
    quote&.destroy!
  end
end
