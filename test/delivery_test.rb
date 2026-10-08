require "test_helper"

class DeliveryTest < Smswire::TestCase
  def send_literal(body = "hi", to: "+14155552671")
    OrderMessenger.literal(to, body).deliver_now
  end

  test "an accepted send is recorded with its receipt" do
    result = send_literal("Your order shipped")
    delivery = result.delivery

    assert delivery.persisted?
    assert_equal "accepted", delivery.status
    assert_equal result.provider_id, delivery.provider_id
    assert_equal ["OrderMessenger", "literal"], [delivery.messenger, delivery.action]
    assert_equal ["+14155552671", "+15005550006"], [delivery.to_number, delivery.from_number]
    assert_equal "Your order shipped", delivery.body
    assert_equal [1, "gsm7", "transactional", "test"], [delivery.segments, delivery.encoding, delivery.category, delivery.provider]
    assert_equal 1, delivery.attempts
    assert_nil delivery.claimed_at
    assert delivery.sent_at
  end

  test "identical messages inside the dedupe window are refused" do
    assert send_literal.accepted?
    duplicate = send_literal
    assert duplicate.duplicate?
    assert_nil duplicate.delivery
    assert_equal 1, Smswire::Delivery.count
    assert_equal 1, sms_deliveries.size

    assert send_literal("different").accepted?
    assert send_literal(to: "+12125550123").accepted?
  end

  test "an explicit idempotency key dedupes across different bodies" do
    messenger = Class.new(ApplicationMessenger) do
      def self.name = "OtpMessenger"

      def code(phone, code) = text(to: phone, body: "Code #{code}", idempotency_key: "otp:#{phone}")
    end
    assert messenger.code("+14155552671", "1111").deliver_now.accepted?
    assert messenger.code("+14155552671", "2222").deliver_now.duplicate?
  end

  test "the same message is allowed again after the window" do
    travel_to Time.utc(2026, 1, 1, 12) do
      send_literal
    end
    travel_to Time.utc(2026, 1, 1, 12, 11) do
      assert send_literal.accepted?
    end
    assert_equal 2, Smswire::Delivery.count
    assert_equal 1, Smswire::Delivery.where.not(idempotency_key: nil).count
  end

  test "dedupe can be disabled" do
    with_config(dedupe_window: nil) do
      2.times { assert send_literal.accepted? }
    end
    assert_equal 2, Smswire::Delivery.count
  end

  test "a transient failure releases the claim and the retry reuses the row" do
    Smswire::Providers::Test.fail_next(Smswire::TransientError.new("timeout", provider_code: "T1"))
    assert_raises(Smswire::TransientError) { send_literal }

    delivery = Smswire::Delivery.sole
    assert_equal "pending", delivery.status
    assert_nil delivery.claimed_at
    assert_equal "timeout", delivery.error_message

    result = send_literal
    assert result.accepted?
    assert_equal delivery.id, result.delivery.id
    assert_equal 2, result.delivery.attempts
    assert_nil result.delivery.error_message
    assert_equal 1, Smswire::Delivery.count
  end

  test "a row claimed by another worker is not sent twice until the claim expires" do
    travel_to Time.utc(2026, 1, 1, 12) do
      Smswire::Providers::Test.fail_next(Smswire::TransientError.new("timeout"))
      assert_raises(Smswire::TransientError) { send_literal }
      Smswire::Delivery.sole.update!(claimed_at: Time.current) # another worker picked it up
      assert send_literal.duplicate?
    end
    travel_to Time.utc(2026, 1, 1, 12, 3) do
      assert send_literal.accepted?
    end
    assert_equal 1, sms_deliveries.size
  end

  test "a permanent failure is recorded and may be retried" do
    Smswire::Providers::Test.fail_next(Smswire::PermanentError.new("blocked", reason: :opted_out, provider_code: "21610"))
    failed = send_literal
    assert failed.failed?
    assert_equal ["failed", "21610", "blocked"], [failed.delivery.status, failed.delivery.error_code, failed.delivery.error_message]
    assert failed.delivery.failed_at

    retried = send_literal
    assert retried.accepted?
    assert_equal failed.delivery.id, retried.delivery.id
  end

  test "suppressed messages are recorded" do
    blocker = Object.new
    def blocker.delivering_sms(message) = message.cancel!
    Smswire.register_interceptor(blocker)
    result = send_literal
    assert_equal "suppressed", result.delivery.status
  ensure
    Smswire.unregister_interceptor(blocker)
  end

  test "the stored message reflects interceptor changes" do
    rewriter = Object.new
    def rewriter.delivering_sms(message) = message.body = "[staging] #{message.body}"
    Smswire.register_interceptor(rewriter)
    assert_equal "[staging] hi", send_literal.delivery.body
  ensure
    Smswire.unregister_interceptor(rewriter)
  end

  test "bodies are not stored for the otp category or when disabled" do
    messenger = Class.new(ApplicationMessenger) do
      def self.name = "CodeMessenger"

      def code(phone) = text(to: phone, body: "Code 4321", category: :otp)
    end
    assert_nil messenger.code("+14155552671").deliver_now.delivery.body

    with_config(store_bodies: false) do
      assert_nil send_literal("not kept").delivery.body
    end
  end

  test "rejections are not persisted" do
    send_literal(to: "nope")
    assert_equal 0, Smswire::Delivery.count
  end

  test "persistence can be disabled" do
    with_config(persist_deliveries: false) do
      result = send_literal
      assert result.accepted?
      assert_nil result.delivery
    end
    assert_equal 0, Smswire::Delivery.count
  end

  test "status only moves forward" do
    delivery = send_literal.delivery
    delivery.advance!(:delivered)
    delivery.advance!(:sent)
    assert_equal "delivered", delivery.reload.status
    assert delivery.delivered_at

    delivery.advance!(:read)
    assert_equal "read", delivery.reload.status
  end

  test "engine provides the install migrations task" do
    Rails.application.load_tasks
    assert Rake::Task.task_defined?("smswire:install:migrations")
  end
end
