require "test_helper"

class SchedulingTest < Smswire::TestCase
  PHONE = "+14155552671"

  setup { Smswire::Consent.opt_in!(PHONE, source: :web_form) }

  test "acceptance: a marketing send in quiet hours is re-enqueued for the next window" do
    with_config(default_time_zone: "America/New_York") do
      travel_to Time.utc(2026, 1, 15, 3) do # 22:00 in New York
        result = OrderMessenger.deal(PHONE, "Sale today").deliver_now
        assert_equal :deferred_quiet_hours, result.status
        assert_equal Time.utc(2026, 1, 15, 13), result.resume_at # 08:00 in New York
        assert_empty sms_deliveries
        assert_enqueued_sms(OrderMessenger, :deal, args: [PHONE, "Sale today"])
        assert_equal Time.utc(2026, 1, 15, 13).to_f, enqueued_jobs.last[:at]
      end

      travel_to Time.utc(2026, 1, 15, 13) do
        perform_enqueued_jobs
        assert_equal ["Sale today"], sms_deliveries.map(&:body)
      end
    end
  end

  test "a deferred background job re-enqueues itself" do
    with_config(default_time_zone: "America/New_York") do
      travel_to Time.utc(2026, 1, 15, 3) do
        OrderMessenger.deal(PHONE, "Later").deliver_later
        perform_enqueued_jobs(only: Smswire::DeliveryJob)
        assert_empty sms_deliveries
        assert_equal Time.utc(2026, 1, 15, 13).to_f, enqueued_jobs.last[:at]
      end
    end
  end

  test "transactional messages ignore marketing quiet hours" do
    with_config(default_time_zone: "America/New_York") do
      travel_to(Time.utc(2026, 1, 15, 3)) { assert OrderMessenger.literal(PHONE, "Shipped").deliver_now.accepted? }
    end
  end

  test "quiet hours use the recipient's time zone" do
    recipient = Struct.new(:phone_number, :time_zone).new(PHONE, "America/Los_Angeles")
    with_config(default_time_zone: "America/New_York") do
      travel_to Time.utc(2026, 1, 15, 3) do # 19:00 in Los Angeles
        message = OrderMessenger.deal(recipient, "Sale").message
        assert Smswire::Pipeline.call(message).accepted?
      end
      travel_to Time.utc(2026, 1, 15, 6) do # 22:00 in Los Angeles
        message = OrderMessenger.deal(recipient, "Sale 2").message
        result = Smswire::Pipeline.call(message)
        assert_equal Time.utc(2026, 1, 15, 16), result.resume_at # 08:00 in Los Angeles
      end
    end
  end

  test "rate limits defer once the window is full" do
    with_config(categories: {transactional: {rate_limit: {max: 2, per: 1.day}}}) do
      travel_to(Time.utc(2026, 1, 15, 9)) { OrderMessenger.literal(PHONE, "one").deliver_now }
      travel_to(Time.utc(2026, 1, 15, 10)) { OrderMessenger.literal(PHONE, "two").deliver_now }
      travel_to Time.utc(2026, 1, 15, 11) do
        result = OrderMessenger.literal(PHONE, "three").deliver_now
        assert_equal :deferred_rate_limited, result.status
        assert_equal Time.utc(2026, 1, 16, 9), result.resume_at
        assert OrderMessenger.literal("+12125550123", "other person").deliver_now.accepted?
      end
      travel_to(Time.utc(2026, 1, 16, 9)) { assert OrderMessenger.literal(PHONE, "three").deliver_now.accepted? }
    end
  end

  test "failed sends do not count toward the rate limit" do
    with_config(categories: {transactional: {rate_limit: {max: 1, per: 1.hour}}}) do
      Smswire::Providers::Test.fail_next(Smswire::PermanentError.new("filtered"))
      assert OrderMessenger.literal(PHONE, "one").deliver_now.failed?
      assert OrderMessenger.literal(PHONE, "two").deliver_now.accepted?
    end
  end

  test "rate limits can reject instead of deferring" do
    with_config(categories: {transactional: {rate_limit: {max: 1, per: 1.hour, exceed: :reject}}}) do
      OrderMessenger.literal(PHONE, "one").deliver_now
      assert_equal :rejected_rate_limited, OrderMessenger.literal(PHONE, "two").deliver_now.status
      assert_no_enqueued_sms
    end
  end

  test "rate limits require persistence" do
    with_config(persist_deliveries: false, categories: {transactional: {rate_limit: {max: 1, per: 1.hour}}}) do
      assert_raises(Smswire::ConfigurationError) { OrderMessenger.literal(PHONE, "one").deliver_now }
    end
  end
end
