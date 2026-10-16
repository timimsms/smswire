require "test_helper"
require "base64"

class StatusCallbacksTest < ActionDispatch::IntegrationTest
  include Smswire::TestHelper
  include ConfigHelpers

  setup { Smswire::Delivery.delete_all }

  def sign(url, params, token: "secret")
    data = url + params.sort.map { |key, value| "#{key}#{value}" }.join
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", token, data))
  end

  def callback(path, params, signature: :valid, base: "http://www.example.com")
    signature = sign(base + path, params) if signature == :valid
    post path, params:, headers: {"X-Twilio-Signature" => signature.to_s}
  end

  def send_via_twilio(sid: "SMabc")
    stub_request(:post, twilio_url).to_return(twilio_success(sid:, status: "queued"))
    with_config(default_provider: :twilio) { OrderMessenger.literal("+14155552671", "Your order shipped").deliver_now }
  end

  test "acceptance: a delivery moves pending to queued to sent to delivered from replayed callbacks" do
    result = nil
    with_config(callbacks_url: "https://app.example/smswire") do
      stub = stub_request(:post, twilio_url).with { |request|
        URI.decode_www_form(request.body).include?(["StatusCallback", "https://app.example/smswire/status/twilio?delivery_id=#{Smswire::Delivery.last&.id}"])
      }.to_return(twilio_success(sid: "SMabc", status: "queued"))
      result = with_config(default_provider: :twilio) { OrderMessenger.literal("+14155552671", "Your order shipped").deliver_now }
      assert_requested stub
    end
    delivery = result.delivery
    assert_equal "queued", delivery.reload.status

    path = "/smswire/status/twilio?delivery_id=#{delivery.id}"
    with_config(callbacks_url: "https://app.example/smswire") do
      callback(path, {"MessageSid" => "SMabc", "MessageStatus" => "sent"}, base: "https://app.example")
      assert_response :no_content
      assert_equal "sent", delivery.reload.status

      callback(path, {"MessageSid" => "SMabc", "MessageStatus" => "delivered"}, base: "https://app.example")
      assert_equal "delivered", delivery.reload.status
      assert delivery.delivered_at

      callback(path, {"MessageSid" => "SMabc", "MessageStatus" => "sent"}, base: "https://app.example")
      assert_equal "delivered", delivery.reload.status, "late callbacks never move status backwards"
    end
  end

  test "callbacks without a delivery id are matched by provider message id" do
    delivery = send_via_twilio(sid: "SMxyz").delivery
    callback("/smswire/status/twilio", {"MessageSid" => "SMxyz", "MessageStatus" => "undelivered",
                                        "ErrorCode" => "30003", "ErrorMessage" => "Unreachable"})
    assert_response :no_content
    delivery.reload
    assert_equal ["undelivered", "30003", "Unreachable"], [delivery.status, delivery.error_code, delivery.error_message]
    assert delivery.failed_at
  end

  test "a mismatched delivery id falls back to the provider message id" do
    first = send_via_twilio(sid: "SM1").delivery
    second = with_config(default_provider: :twilio) do
      stub_request(:post, twilio_url).to_return(twilio_success(sid: "SM2"))
      OrderMessenger.literal("+14155552671", "another").deliver_now.delivery
    end
    callback("/smswire/status/twilio?delivery_id=#{first.id}", {"MessageSid" => "SM2", "MessageStatus" => "delivered"})
    assert_equal "queued", first.reload.status
    assert_equal "delivered", second.reload.status
  end

  test "invalid signatures are refused" do
    delivery = send_via_twilio.delivery
    callback("/smswire/status/twilio", {"MessageSid" => "SMabc", "MessageStatus" => "delivered"}, signature: "forged")
    assert_response :forbidden
    callback("/smswire/status/twilio", {"MessageSid" => "SMabc", "MessageStatus" => "delivered"}, signature: nil)
    assert_response :forbidden
    assert_equal "queued", delivery.reload.status
  end

  test "signature checks can be disabled" do
    delivery = send_via_twilio.delivery
    with_config(verify_callback_signatures: false) do
      callback("/smswire/status/twilio", {"MessageSid" => "SMabc", "MessageStatus" => "delivered"}, signature: "x")
    end
    assert_response :no_content
    assert_equal "delivered", delivery.reload.status
  end

  test "unknown deliveries are acknowledged" do
    callback("/smswire/status/twilio", {"MessageSid" => "SMnope", "MessageStatus" => "delivered"})
    assert_response :no_content
  end

  test "unknown providers and providers without callbacks are not found" do
    post "/smswire/status/carrier-pigeon", params: {"MessageSid" => "x"}
    assert_response :not_found
    post "/smswire/status/test", params: {"MessageSid" => "x"}
    assert_response :not_found
  end

  test "observers are told about status updates" do
    delivery = send_via_twilio.delivery
    seen = []
    observer = Object.new
    observer.define_singleton_method(:delivered_sms) { |_result| }
    observer.define_singleton_method(:sms_status_updated) { |record, update| seen << [record.id, update.status] }
    Smswire.register_observer(observer)
    callback("/smswire/status/twilio", {"MessageSid" => "SMabc", "MessageStatus" => "delivered"})
    assert_equal [[delivery.id, :delivered]], seen
  ensure
    Smswire.unregister_observer(observer)
  end
end
