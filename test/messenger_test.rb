require "test_helper"

class MessengerTest < Smswire::TestCase
  setup do
    @user = User.new(name: "Ada", phone_number: "(415) 555-2671")
  end

  test "renders the template with i18n, url helpers, and whitespace cleanup" do
    message = OrderMessenger.with(order_number: "R100").shipped(@user).message

    assert_equal "Hi Ada!\nOrder R100 has shipped.\n\nTrack it: http://shop.example/orders/R100", message.body
    assert_equal "OrderMessenger", message.messenger
    assert_equal "shipped", message.action
    assert_equal :gsm7, message.encoding
  end

  test "applies a layout" do
    message = NoticeMessenger.reminder("+14155552671").message
    assert_equal "Your appointment is tomorrow.\n\nReply STOP to opt out.", message.body
  end

  test "squish and preserve whitespace modes" do
    with_config(body_whitespace: :squish) do
      assert_equal "a b c", OrderMessenger.literal("+14155552671", "  a\n\n b   c ").body
    end
    with_config(body_whitespace: :preserve) do
      assert_equal "  a\n", OrderMessenger.literal("+14155552671", "  a\n").body
    end
  end

  test "resolves named senders and class defaults" do
    shipped = OrderMessenger.with(order_number: "R1").shipped(@user).message
    assert_equal "+15005550006", shipped.from
    assert_equal :transactional, shipped.category

    promo = OrderMessenger.promo("+14155552671").message
    assert_nil promo.from
    assert_equal "MG00000000000000000000000000000000", promo.messaging_service
    assert_equal :twilio, promo.provider
    assert_equal :marketing, promo.category
  end

  test "deliver_now normalizes, sends through the default provider, and returns a result" do
    result = OrderMessenger.with(order_number: "R1").shipped(@user).deliver_now

    assert result.accepted?
    assert_match(/\ASMtest/, result.provider_id)
    assert_equal ["+14155552671"], sms_deliveries.map(&:to)
    assert_equal "(415) 555-2671", sms_deliveries.first.raw_to
    assert_equal @user, sms_deliveries.first.recipient.record
  end

  test "keyword arguments and params reach the action" do
    message = OrderMessenger.with(order_number: "R7").delivery_window("+14155552671", window: "9-11am").message
    assert_equal "Order R7 arrives 9-11am", message.body
  end

  test "an action that does not call text is skipped" do
    delivery = OrderMessenger.maybe("+14155552671", send: false)
    assert_nil delivery.message
    assert delivery.deliver_now.skipped?
    assert_empty sms_deliveries
  end

  test "invalid numbers and empty bodies are rejected without calling the provider" do
    assert_equal :rejected_invalid_number, OrderMessenger.literal("555-1234", "hi").deliver_now.status
    assert_equal :rejected_empty_body, OrderMessenger.literal("+14155552671", "   ").deliver_now.status
    assert_empty sms_deliveries
  end

  test "unresolvable recipients and unknown senders raise while building" do
    assert_raises(Smswire::UnresolvableRecipient) { OrderMessenger.literal(nil, "hi").message }
    assert_raises(Smswire::UnresolvableRecipient) { OrderMessenger.literal(Object.new, "hi").message }

    with_config(senders: {}) do
      assert_raises(Smswire::ConfigurationError) { OrderMessenger.literal("+14155552671", "hi").message }
    end
  end

  test "custom recipient resolver" do
    contact = Struct.new(:mobile).new("+14155552671")
    with_config(recipient_resolver: ->(record) { record.mobile }) do
      assert_equal "+14155552671", OrderMessenger.literal(contact, "hi").to
    end
  end

  test "rejects unknown text options and defaults" do
    messenger = Class.new(ApplicationMessenger) do
      def self.name = "BadMessenger"

      def bad(phone) = text(to: phone, body: "x", colour: :red)
    end
    assert_raises(ArgumentError) { messenger.bad("+14155552671").message }
    assert_raises(ArgumentError) { messenger.default(colour: :red) }
  end

  test "action methods are exposed on the class and parameterized proxy" do
    assert_respond_to OrderMessenger, :shipped
    assert_respond_to OrderMessenger.with(order_number: "R1"), :shipped
    refute_respond_to OrderMessenger, :text
    assert_raises(NoMethodError) { OrderMessenger.nonexistent }
  end

  test "idempotency key is stable for identical messages" do
    first = OrderMessenger.literal("+14155552671", "hi").message
    second = OrderMessenger.literal("+14155552671", "hi").message
    third = OrderMessenger.literal("+14155552671", "bye").message

    assert_equal first.idempotency_key, second.idempotency_key
    refute_equal first.idempotency_key, third.idempotency_key
  end

  test "inspect and log hash never include the body" do
    message = OrderMessenger.literal("+14155552671", "secret code 1234").message
    refute_includes message.inspect, "1234"
    refute message.to_log_h.values.any? { |value| value.to_s.include?("1234") }
  end
end
