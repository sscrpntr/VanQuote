require "test_helper"

class ApplicationMailersTest < ActionMailer::TestCase
  class FailingDelivery
    def deliver_now
      raise IOError, "SMTP delivery rejected"
    end
  end

  class FailingQuoteMailer
    def self.result(_quote)
      FailingDelivery.new
    end
  end

  class FailingLeadsMailer
    def self.new_lead(_lead)
      FailingDelivery.new
    end
  end

  test "password reset mail contains a signed reset URL and private recipient" do
    user = User.create!(first_name: "Mail", last_name: "User", email_address: "mail@example.com", password: "password123")
    email = PasswordsMailer.reset(user)

    assert_equal [ user.email_address ], email.to
    assert_equal [ "theoriginalvanquote@gmail.com" ], email.from
    assert_equal "Reset your password", email.subject
    reset_url = email.text_part.body.decoded.match(%r{https?://\S+}).to_s
    uri = URI.parse(reset_url)
    assert_equal "example.com", uri.host
    assert_equal "/passwords/reset", uri.path
    assert uri.fragment.present?
    assert_includes email.text_part.body.decoded, "This link will expire"
  end

  test "verification mail targets the new user and contains a verification link" do
    user = User.create!(first_name: "Verify", last_name: "User", email_address: "verify@example.com", password: "password123")
    email = VerificationMailer.verify(user)

    assert_equal [ user.email_address ], email.to
    assert_equal [ "theoriginalvanquote@gmail.com" ], email.from
    assert_includes email.body.to_s, "/email-verification?token="
  end

  test "quote result mail contains only the requested quote result" do
    quote = Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: "customer@example.com",
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 25, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 77, recommended_price: 96.25)
    email = QuoteMailer.result(quote)

    assert_equal [ quote.contact_email ], email.to
    assert_equal [ "theoriginalvanquote@gmail.com" ], email.from
    assert_includes email.body.to_s, "Barcelona"
    assert_includes email.body.to_s, "Girona"
  end

  test "quote result delivery is idempotent when retried" do
    quote = Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: "customer@example.com",
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 25, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 77, recommended_price: 96.25)
    ActionMailer::Base.deliveries.clear

    assert quote.deliver_result_email_once!
    assert_not quote.deliver_result_email_once!
    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  test "failed quote delivery does not mark the message as sent" do
    quote = Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: "customer@example.com",
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 25, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 77, recommended_price: 96.25)
    assert_raises(IOError) { quote.deliver_result_email_once!(mailer: FailingQuoteMailer) }

    assert_nil quote.reload.result_email_sent_at
  end

  test "lead notification goes only to the configured administrator address" do
    quote = Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: "customer@example.com",
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 25, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 77, recommended_price: 96.25)
    lead = quote.create_lead!(email: "customer@example.com", phone: "+34600000000",
      contact_preference: "PHONE", consent_given: true,
      consent_at: Time.current, status: "NEW")
    email = LeadsMailer.new_lead(lead)

    assert_equal [ "sergiescarpenter@gmail.com" ], email.to
    assert_equal [ "theoriginalvanquote@gmail.com" ], email.from
    assert_includes email.body.to_s, "customer@example.com"
    assert_includes email.body.to_s, "Barcelona"
    assert_not_includes email.body.to_s, "+34600000000"
  end

  test "lead notification delivery is idempotent when retried" do
    quote = Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: "customer@example.com",
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 25, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 77, recommended_price: 96.25)
    lead = quote.create_lead!(email: "customer@example.com", consent_given: true,
      consent_at: Time.current, status: "NEW")
    ActionMailer::Base.deliveries.clear

    assert lead.notify_admin_once!
    assert_not lead.notify_admin_once!
    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  test "failed lead notification does not mark it as notified" do
    quote = Quote.create!(origin: "Barcelona", destination: "Girona", contact_email: "customer@example.com",
      distance_km: 100, estimated_duration_minutes: 60, fuel_cost: 12, toll_cost: 0,
      vehicle_cost: 10, driver_cost: 25, loading_cost: 20, waiting_cost: 0,
      other_cost: 10, margin: 25, total_cost: 77, recommended_price: 96.25)
    lead = quote.create_lead!(email: "customer@example.com", consent_given: true,
      consent_at: Time.current, status: "NEW")
    assert_raises(IOError) { lead.notify_admin_once!(mailer: FailingLeadsMailer) }

    assert_nil lead.reload.admin_notification_sent_at
  end
end
