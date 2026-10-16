require "test_helper"

class TwilioTest < Smswire::TestCase
  setup do
    @user = User.new(name: "Ada", phone_number: "415-555-2671")
  end

  def deliver(delivery)
    with_config(default_provider: :twilio) { delivery.deliver_now }
  end

  test "acceptance: a rendered messenger template is sent through Twilio" do
    stub = stub_request(:post, twilio_url)
      .with(
        basic_auth: %w[ACtest secret],
        headers: {"Content-Type" => "application/x-www-form-urlencoded"},
        body: {
          "To" => "+14155552671",
          "From" => "+15005550006",
          "Body" => "Hi Ada!\nOrder R100 has shipped.\n\nTrack it: http://shop.example/orders/R100"
        }
      )
      .to_return(twilio_success(sid: "SMabc", status: "queued", segments: "1"))

    result = deliver(OrderMessenger.with(order_number: "R100").shipped(@user))

    assert_requested stub
    assert result.accepted?
    assert_equal "SMabc", result.provider_id
    assert_equal :queued, result.receipt.status
    assert_equal 1, result.receipt.segments
  end

  test "uses the messaging service, media, validity period, and status callback" do
    body = nil
    stub_request(:post, twilio_url).to_return do |request|
      body = request.body
      twilio_success
    end

    messenger = Class.new(ApplicationMessenger) do
      def self.name = "MediaMessenger"

      def photo(phone)
        text to: phone, from: :marketing, body: "Look", media_urls: %w[https://a.example/1.png https://a.example/2.png],
          validity_period: 600
      end
    end

    config = Smswire.config.providers.merge(twilio: {account_sid: "ACtest", auth_token: "secret",
                                                     status_callback: "https://app.example/sms/status"})
    with_config(providers: config) { deliver(messenger.photo("+14155552671")) }

    params = URI.decode_www_form(body)
    assert_includes params, ["MessagingServiceSid", "MG00000000000000000000000000000000"]
    refute params.any? { |key, _| key == "From" }
    assert_equal %w[https://a.example/1.png https://a.example/2.png], params.filter_map { |key, value| value if key == "MediaUrl" }
    assert_includes params, ["ValidityPeriod", "600"]
    assert_includes params, ["StatusCallback", "https://app.example/sms/status"]
  end

  test "records price when Twilio reports it" do
    stub_request(:post, twilio_url).to_return(
      status: 201, body: {sid: "SM1", status: "sent", num_segments: "2", price: "-0.01580", price_unit: "USD"}.to_json
    )
    receipt = deliver(OrderMessenger.literal("+14155552671", "hi")).receipt
    assert_equal BigDecimal("0.0158"), receipt.price_amount
    assert_equal "USD", receipt.price_currency
    assert_equal :sent, receipt.status
  end

  test "maps permanent error codes to reasons" do
    {21211 => :invalid_number, 21610 => :opted_out, 21408 => :unroutable, 30001 => :rejected}.each do |code, reason|
      stub_request(:post, twilio_url).to_return(status: 400, body: {code:, message: "nope"}.to_json)
      result = deliver(OrderMessenger.literal("+14155552671", "hi"))
      assert result.failed?, "expected #{code} to fail"
      assert_equal reason, result.error.reason
      assert_equal code.to_s, result.error.provider_code
      assert_equal 400, result.error.http_status
      Smswire::Consent.delete_all
    end
  end

  test "authentication failures are permanent" do
    stub_request(:post, twilio_url).to_return(status: 401, body: {code: 20003, message: "Authenticate"}.to_json)
    assert_equal :authentication, deliver(OrderMessenger.literal("+14155552671", "hi")).error.reason
  end

  test "429 raises ThrottledError with retry_after" do
    stub_request(:post, twilio_url).to_return(status: 429, headers: {"Retry-After" => "30"}, body: {code: 20429}.to_json)
    error = assert_raises(Smswire::ThrottledError) { deliver(OrderMessenger.literal("+14155552671", "hi")) }
    assert_equal 30, error.retry_after
  end

  test "5xx responses and timeouts are transient" do
    stub_request(:post, twilio_url).to_return(status: 503, body: "unavailable")
    assert_raises(Smswire::TransientError) { deliver(OrderMessenger.literal("+14155552671", "hi")) }

    stub_request(:post, twilio_url).to_timeout
    error = assert_raises(Smswire::TransientError) { deliver(OrderMessenger.literal("+14155552671", "hi")) }
    assert_equal :twilio, error.provider
  end

  test "missing credentials raise a configuration error" do
    with_config(providers: {}) do
      assert_raises(Smswire::ConfigurationError) { deliver(OrderMessenger.literal("+14155552671", "hi")) }
    end
  end

  test "a sender is required" do
    with_config(senders: {transactional: {number: nil}}) do
      assert_raises(Smswire::ConfigurationError) { deliver(OrderMessenger.literal("+14155552671", "hi")) }
    end
  end
end
