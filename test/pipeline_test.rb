require "test_helper"

class PipelineTest < Smswire::TestCase
  class Rewriter
    def self.delivering_sms(message)
      message.body = "[staging] #{message.body}"
    end
  end

  class Blocker
    def self.delivering_sms(message)
      message.cancel!
    end
  end

  class Recorder
    def self.results = (@results ||= [])

    def self.delivered_sms(result) = results << result
  end

  teardown do
    [Rewriter, Blocker, "PipelineTest::Blocker"].each { Smswire.unregister_interceptor(_1) }
    Smswire.unregister_observer(Recorder)
    Recorder.results.clear
  end

  test "interceptors can rewrite messages" do
    Smswire.register_interceptor(Rewriter)
    OrderMessenger.literal("+14155552671", "hello").deliver_now
    assert_equal "[staging] hello", sms_deliveries.first.body
  end

  test "interceptors can cancel delivery, including by class name" do
    Smswire.register_interceptor("PipelineTest::Blocker")
    result = OrderMessenger.literal("+14155552671", "hello").deliver_now
    assert result.suppressed?
    assert_empty sms_deliveries
  end

  test "interceptors see normalized numbers" do
    seen = nil
    interceptor = Object.new
    interceptor.define_singleton_method(:delivering_sms) { |message| seen = message.to }
    Smswire.register_interceptor(interceptor)
    OrderMessenger.literal("415-555-2671", "hello").deliver_now
    assert_equal "+14155552671", seen
  ensure
    Smswire.unregister_interceptor(interceptor)
  end

  test "observers receive every outcome" do
    Smswire.register_observer(Recorder)
    OrderMessenger.literal("+14155552671", "hello").deliver_now
    OrderMessenger.literal("bogus", "hello").deliver_now
    assert_equal %i[accepted rejected_invalid_number], Recorder.results.map(&:status)
  end

  test "permanent errors become failed results" do
    Smswire::Providers::Test.fail_next(Smswire::PermanentError.new("blocked", reason: :opted_out))
    result = OrderMessenger.literal("+14155552671", "hello").deliver_now
    assert result.failed?
    assert result.error.opted_out?
  end

  test "transient errors propagate" do
    Smswire::Providers::Test.fail_next(Smswire::TransientError.new("timeout"))
    assert_raises(Smswire::TransientError) { OrderMessenger.literal("+14155552671", "hello").deliver_now }
  end

  test "missing provider configuration raises" do
    with_config(default_provider: nil) do
      assert_raises(Smswire::ConfigurationError) { OrderMessenger.literal("+14155552671", "hi").deliver_now }
    end
  end

  test "instruments deliveries and rejections without the body" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/\.smswire\z/) { |event| events << event }
    OrderMessenger.literal("+14155552671", "secret 9876").deliver_now
    OrderMessenger.literal("bogus", "secret 9876").deliver_now

    assert_equal %w[deliver.smswire reject.smswire], events.map(&:name)
    assert_equal :accepted, events.first.payload[:status]
    assert_equal :test, events.first.payload[:provider]
    assert_equal :rejected_invalid_number, events.last.payload[:reason]
    refute events.any? { |event| event.payload.values.any? { |v| v.to_s.include?("9876") } }
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "custom providers can be registered" do
    provider = Class.new(Smswire::Providers::Base) do
      def deliver(message) = receipt(provider_id: "custom-1", status: :sent)
    end
    Smswire::Providers.register(:custom, provider)
    with_config(default_provider: :custom) do
      result = OrderMessenger.literal("+14155552671", "hi").deliver_now
      assert_equal "custom-1", result.provider_id
      assert_equal :custom, result.receipt.provider
    end
  end

  test "log provider writes the body to the logger" do
    output = StringIO.new
    with_config(default_provider: :log, logger: Logger.new(output)) do
      assert OrderMessenger.literal("+14155552671", "hello log").deliver_now.accepted?
    end
    assert_includes output.string, "SMS to +14155552671"
    assert_includes output.string, "1 segment(s), GSM-7"
    assert_includes output.string, "hello log"
  end

  test "null provider accepts and discards" do
    with_config(default_provider: :null) do
      assert OrderMessenger.literal("+14155552671", "hi").deliver_now.accepted?
    end
    assert_empty sms_deliveries
  end
end
