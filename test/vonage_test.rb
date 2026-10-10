require "test_helper"

class VonageTest < Smswire::IntegrationTest
  OPTIONS = {api_key: "key", api_secret: "secret", signature_secret: "sigsecret", signature_method: "sha256"}.freeze

  def with_vonage(**options, &)
    with_config(providers: Smswire.config.providers.merge(vonage: OPTIONS.merge(options)), &)
  end

  def provider(**options) = Smswire::Providers::Vonage.new(OPTIONS.merge(options), name: :vonage)

  def signed(params, method: "sha256")
    params = params.merge("timestamp" => Time.now.to_i.to_s)
    params.merge("sig" => Smswire::Providers::Vonage.signature(params, secret: "sigsecret", method:))
  end

  test "signatures match the Vonage SDK algorithm" do
    params = {"api_key" => "abc123", "to" => "447900000000", "from" => "447900000001", "text" => "Hello & =World", "timestamp" => "1385047698"}
    data = "&api_key=abc123&from=447900000001&text=Hello _ _World&timestamp=1385047698&to=447900000000"
    assert_equal OpenSSL::HMAC.hexdigest("sha256", "s", data).upcase, Smswire::Providers::Vonage.signature(params, secret: "s", method: "sha256")
    assert_equal Digest::MD5.hexdigest("#{data}s"), Smswire::Providers::Vonage.signature(params, secret: "s", method: "md5hash")
  end

  test "sends unicode, sender, ttl, and callback parameters" do
    message = Smswire::Message.new(to: "+14155552671", from: "AcmeCo", body: "Café ☕", validity_period: 600)
    message.status_callback_url = "https://app.example/smswire/status/vonage?delivery_id=1"
    params = provider.form_for(message).to_h
    assert_equal ["14155552671", "AcmeCo", "unicode", "600000", "1"], params.values_at("to", "from", "type", "ttl", "status-report-req")
    assert_equal "https://app.example/smswire/status/vonage?delivery_id=1", params["callback"]
  end

  test "multipart sends keep the first id and total the price" do
    stub_request(:post, Smswire::Providers::Vonage::API_URL).to_return(status: 200, body: {
      "message-count" => "2",
      "messages" => [{"message-id" => "part-1", "status" => "0", "message-price" => "0.0333"},
        {"message-id" => "part-2", "status" => "0", "message-price" => "0.0333"}]
    }.to_json)
    receipt = provider.deliver(Smswire::Message.new(to: "+14155552671", from: "+15005550006", body: "x" * 200))
    assert_equal ["part-1", 2, BigDecimal("0.0666")], [receipt.provider_id, receipt.segments, receipt.price_amount]
    assert_nil receipt.price_currency
  end

  test "number barred is unroutable, not an opt-out" do
    stub_request(:post, Smswire::Providers::Vonage::API_URL).to_return(status: 200, body: {"messages" => [{"status" => "7"}]}.to_json)
    error = assert_raises(Smswire::PermanentError) { provider.deliver(Smswire::Message.new(to: "+14155552671", from: "+15005550006", body: "x")) }
    assert_equal [:unroutable, "7"], [error.reason, error.provider_code]
    refute error.opted_out?
  end

  test "delivery receipts and inbound replies arrive through the webhooks" do
    stub_request(:post, Smswire::Providers::Vonage::API_URL).to_return(status: 200,
      body: {"messages" => [{"message-id" => "vg-1", "status" => "0"}]}.to_json)
    result = with_vonage do
      with_config(default_provider: :vonage) { OrderMessenger.literal("+14155552671", "Shipped").deliver_now }
    end
    assert_equal "accepted", result.delivery.status

    with_vonage do
      post "/smswire/status/vonage", params: signed({"messageId" => "vg-1", "msisdn" => "14155552671", "status" => "delivered", "err-code" => "0"})
      assert_response :no_content
      assert_equal "delivered", result.delivery.reload.status

      post "/smswire/inbound/vonage", params: signed({"messageId" => "vg-in", "msisdn" => "14155552671", "to" => "15005550006", "text" => "STOP"})
      assert_response :no_content
    end
    assert_equal "opted_out", Smswire::Consent.status_for("+14155552671")
    assert_equal "+15005550006", Smswire::InboundMessage.sole.to_number
  end

  test "stale timestamps, bad signatures, and a missing secret are refused" do
    with_vonage do
      stale = {"messageId" => "x", "status" => "delivered", "timestamp" => (Time.now.to_i - 3600).to_s}
      post "/smswire/status/vonage", params: stale.merge("sig" => Smswire::Providers::Vonage.signature(stale, secret: "sigsecret", method: "sha256"))
      assert_response :forbidden
      post "/smswire/status/vonage", params: {"messageId" => "x", "status" => "delivered", "sig" => "bad"}
      assert_response :forbidden
    end
    with_vonage(signature_secret: nil) do
      post "/smswire/status/vonage", params: signed({"messageId" => "x", "status" => "delivered"})
      assert_response :forbidden
    end
  end

  test "md5hash signatures are accepted" do
    with_vonage(signature_method: "md5hash") do
      post "/smswire/inbound/vonage", params: signed({"messageId" => "vg-md5", "msisdn" => "14155552671", "to" => "15005550006", "text" => "hi"}, method: "md5hash")
    end
    assert_response :no_content
    assert_equal 1, Smswire::InboundMessage.count
  end
end
