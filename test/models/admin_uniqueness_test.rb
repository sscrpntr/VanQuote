require "test_helper"

class AdminUniquenessTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "the database prevents concurrent promotion of different users" do
    users = 2.times.map do |index|
      User.create!(
        first_name: "Admin",
        last_name: "Candidate #{index}",
        email_address: "admin-candidate-#{SecureRandom.hex(6)}@example.com",
        password: "password123"
      )
    end
    start = Queue.new
    outcomes = Queue.new

    workers = users.map do |user|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          begin
            User.find(user.id).update!(admin: true)
            outcomes << :promoted
          rescue ActiveRecord::RecordNotUnique
            outcomes << :rejected
          end
        end
      end
    end
    2.times { start << true }
    workers.each(&:value)

    results = 2.times.map { outcomes.pop }
    assert_equal 1, results.count(:promoted)
    assert_equal 1, results.count(:rejected)
    assert_equal 1, User.where(admin: true).count
  ensure
    User.where(id: users&.map(&:id)).update_all(admin: false)
    User.where(id: users&.map(&:id)).destroy_all
  end
end
