require "test_helper"

class AllowlistTest < Smswire::TestCase
  def with_interceptor(interceptor)
    Smswire.register_interceptor(interceptor)
    yield
  ensure
    Smswire.unregister_interceptor(interceptor)
  end

  test "listed numbers are delivered and others are suppressed" do
    allowlist = Smswire::Interceptors::Allowlist.new(numbers: ["(415) 555-2671", " +12125550123 ", "bogus"])
    assert_equal Set["+14155552671", "+12125550123"], allowlist.numbers

    with_interceptor(allowlist) do
      assert OrderMessenger.literal("415-555-2671", "ok").deliver_now.accepted?
      result = OrderMessenger.literal("+13105550188", "blocked").deliver_now
      assert result.suppressed?
      assert_equal "suppressed", result.delivery.status
    end
    assert_equal ["+14155552671"], sms_deliveries.map(&:to)
  end

  test "redirect mode reroutes and labels the original recipient" do
    allowlist = Smswire::Interceptors::Allowlist.new(numbers: [], redirect_to: "+12125550123")
    with_interceptor(allowlist) do
      assert OrderMessenger.literal("+13105550188", "hello").deliver_now.accepted?
    end
    message = sms_deliveries.sole
    assert_equal "+12125550123", message.to
    assert_equal "[to +13105550188] hello", message.body
    assert_equal "+12125550123", Smswire::Delivery.sole.to_number
  end

  test "an invalid redirect number raises" do
    assert_raises(Smswire::ConfigurationError) { Smswire::Interceptors::Allowlist.new(numbers: [], redirect_to: "nope") }
  end
end
