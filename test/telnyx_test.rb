require "test_helper"
require "base64"

class TelnyxTest < Smswire::IntegrationTest
  KEY = OpenSSL::PKey.generate_key("ED25519")
  OPTIONS = {api_key: "KEYtest", public_key: Base64.strict_encode64(KEY.public_to_der[-32..])}.freeze

  def with_telnyx(&)
    with_config(providers: Smswire.config.providers.merge(telnyx: OPTIONS), &)
  end

  def provider = Smswire::Providers::Telnyx.new(OPTIONS, name: :telnyx)

  def post_event(path, data, timestamp: Time.now.to_i)
    body = {data:}.to_json
    signature = Base64.strict_encode64(KEY.sign(nil, "#{timestamp}|#{body}"))
    post path, params: body, headers: {"Content-Type" => "application/json", "telnyx-signature-ed25519" => signature,
                                       "telnyx-timestamp" => timestamp.to_s}
  end

  test "sends the profile id, media, and per-message webhook url" do
    message = Smswire::Message.new(to: "+14155552671", body: "Look", messaging_service: "profile-1", media_urls: ["https://a.example/1.png"])
    message.status_callback_url = "https://app.example/smswire/status/telnyx?delivery_id=7"
    assert_equal({to: "+14155552671", messaging_profile_id: "profile-1", text: "Look", media_urls: ["https://a.example/1.png"],
                  webhook_url: "https://app.example/smswire/status/telnyx?delivery_id=7"}, provider.payload_for(message))
    assert_raises(Smswire::ConfigurationError) { provider.payload_for(Smswire::Message.new(to: "+14155552671", body: "x")) }
  end

  test "carrier throughput and temporary failures are retryable" do
    {"40011" => Smswire::ThrottledError, "40006" => Smswire::TransientError}.each do |code, klass|
      stub_request(:post, Smswire::Providers::Telnyx::API_URL).to_return(status: 422, body: {errors: [{code:}]}.to_json)
      assert_raises(klass) { provider.deliver(Smswire::Message.new(to: "+14155552671", from: "+15005550006", body: "x")) }
    end
  end

  test "a profile webhook pointed at one URL handles both inbound and status events" do
    stub_request(:post, Smswire::Providers::Telnyx::API_URL).to_return(status: 200,
      body: {data: {id: "tx-1", to: [{status: "queued"}], parts: 1}}.to_json)
    result = with_telnyx do
      with_config(default_provider: :telnyx) { OrderMessenger.literal("+14155552671", "Shipped").deliver_now }
    end
    assert_equal "queued", result.delivery.status

    with_telnyx do
      post_event "/smswire/inbound/telnyx", {event_type: "message.finalized", payload: {id: "tx-1", to: [{status: "delivered"}]}}
      assert_response :no_content
      assert_equal "delivered", result.delivery.reload.status

      post_event "/smswire/status/telnyx", {event_type: "message.received",
                                             payload: {id: "tx-in", from: {phone_number: "+14155552671"}, to: [{phone_number: "+15005550006"}], text: "HELP"}}
      assert_response :no_content
    end
    assert_equal "help", Smswire::InboundMessage.sole.keyword
  end

  test "unrelated events are acknowledged" do
    with_telnyx { post_event "/smswire/inbound/telnyx", {event_type: "number_order.complete", payload: {}} }
    assert_response :no_content
  end

  test "stale or tampered events are refused" do
    with_telnyx do
      post_event "/smswire/status/telnyx", {event_type: "message.finalized", payload: {id: "x"}}, timestamp: Time.now.to_i - 3600
      assert_response :forbidden
      post "/smswire/status/telnyx", params: {data: {}}.to_json,
        headers: {"Content-Type" => "application/json", "telnyx-signature-ed25519" => Base64.strict_encode64("x" * 64),
                  "telnyx-timestamp" => Time.now.to_i.to_s}
      assert_response :forbidden
    end
  end
end
