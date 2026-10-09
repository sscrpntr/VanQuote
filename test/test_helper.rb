ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module QuoteCreationRequestTestSupport
  def post(path, **options)
    if path == "/quotes" || (respond_to?(:quotes_path) && path == quotes_path)
      params = (options[:params] || {}).to_h
      params[:idempotency_key] ||= QuoteCreationRequest.generate_key
      options[:params] = params
    end

    super(path, **options)
  end
end

ActionDispatch::IntegrationTest.prepend(QuoteCreationRequestTestSupport)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
