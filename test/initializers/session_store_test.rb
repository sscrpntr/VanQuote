require "test_helper"

class SessionStoreTest < ActiveSupport::TestCase
  test "session cookie security settings are explicit and preserve local HTTP development" do
    options = Rails.application.config.session_options

    assert_equal "_van_quote_session", options.fetch(:key)
    assert_equal Rails.env.production?, options.fetch(:secure)
    assert_equal true, options.fetch(:httponly)
    assert_equal :lax, options.fetch(:same_site)
  end
end
