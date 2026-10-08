require "test_helper"

class TestHelperTest < Smswire::TestCase
  test "assert_sms_delivered filters by recipient, messenger, action, and body" do
    OrderMessenger.literal("415-555-2671", "Your code is 1234").deliver_now

    assert_sms_delivered(to: "+14155552671", messenger: OrderMessenger, action: :literal, body: /code is \d+/)
    assert_sms_delivered(to: "(415) 555-2671")
    assert_sms_delivered(1)
    assert_raises(Minitest::Assertion) { assert_sms_delivered(to: "+12125550100") }
    assert_raises(Minitest::Assertion) { assert_sms_delivered(2) }
  end

  test "assert_sms_delivered with a block performs deliver_later jobs" do
    assert_sms_delivered(1, body: "later") do
      OrderMessenger.literal("+14155552671", "later").deliver_later
    end
  end

  test "assert_no_sms_delivered" do
    assert_no_sms_delivered { OrderMessenger.maybe("+14155552671", send: false).deliver_now }
    assert_raises(Minitest::Assertion) do
      assert_no_sms_delivered { OrderMessenger.literal("+14155552671", "x").deliver_now }
    end
  end

  test "assert_enqueued_sms matches messenger, action, params, args, and kwargs" do
    assert_enqueued_sms(OrderMessenger, :delivery_window, params: {order_number: "R2"},
      args: ["+14155552671"], kwargs: {window: "noon"}) do
      OrderMessenger.with(order_number: "R2").delivery_window("+14155552671", window: "noon").deliver_later
    end
    assert_enqueued_sms(count: 1)
    assert_raises(Minitest::Assertion) { assert_enqueued_sms(OrderMessenger, :shipped) }
  end

  test "assert_no_enqueued_sms" do
    assert_no_enqueued_sms { OrderMessenger.literal("+14155552671", "now").deliver_now }
    assert_raises(Minitest::Assertion) do
      assert_no_enqueued_sms { OrderMessenger.literal("+14155552671", "later").deliver_later }
    end
  end

  test "unknown filters raise" do
    assert_raises(ArgumentError) { assert_sms_delivered(colour: :red) }
  end

  test "deliveries are cleared before each test" do
    assert_empty sms_deliveries
  end
end
