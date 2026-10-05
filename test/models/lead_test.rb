require "test_helper"

class LeadTest < ActiveSupport::TestCase
  test "is valid with valid attributes" do
    lead = Lead.new(
      quote: quotes(:one),
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    assert lead.valid?
  end

  test "requires an email" do
    lead = Lead.new(
      quote: quotes(:one),
      email: "",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    assert_not lead.valid?
    assert_includes lead.errors[:email], "can't be blank"
  end

  test "requires a valid email format" do
    lead = Lead.new(
      quote: quotes(:one),
      email: "not-an-email",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    assert_not lead.valid?
    assert lead.errors[:email].any?
  end

  test "requires consent" do
    lead = Lead.new(
      quote: quotes(:one),
      email: "customer@example.com",
      consent_given: false,
      consent_at: Time.current,
      status: "NEW"
    )

    assert_not lead.valid?
    assert lead.errors[:consent_given].any?
  end

  test "requires consent timestamp" do
    lead = Lead.new(
      quote: quotes(:one),
      email: "customer@example.com",
      consent_given: true,
      consent_at: nil,
      status: "NEW"
    )

    assert_not lead.valid?
    assert_includes lead.errors[:consent_at], "can't be blank"
  end

  test "requires a valid status" do
    lead = Lead.new(
      quote: quotes(:one),
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "INVALID"
    )

    assert_not lead.valid?
    assert lead.errors[:status].any?
  end

  test "belongs to a quote" do
    lead = Lead.new(
      email: "customer@example.com",
      consent_given: true,
      consent_at: Time.current,
      status: "NEW"
    )

    assert_not lead.valid?
    assert lead.errors[:quote].any?
  end
end
