require "test_helper"
require "base64"

# Phase 5 acceptance: the same dummy-app messenger passes the provider
# contract against every bundled adapter.
module DummyContractMessage
  def contract_message
    customer = Struct.new(:name, :phone_number).new("Ada", "+14155552671")
    OrderMessenger.with(order_number: "R100").shipped(customer).message.tap { |message| message.to = "+14155552671" }
  end

  def expected_body = "Hi Ada!\nOrder R100 has shipped.\n\nTrack it: http://shop.example/orders/R100"
end

class TwilioContractTest < Smswire::TestCase
  include Smswire::ProviderContract
  include DummyContractMessage

  URL = "https://api.twilio.com/2010-04-01/Accounts/ACtest/Messages.json"

  def contract_provider_name = :twilio

  def contract_provider_options = {account_sid: "ACtest", auth_token: "secret"}

  def stub_contract_send(outcome, message)
    stub = stub_request(:post, URL)
    case outcome
    when :success
      stub.with(body: hash_including("To" => message.to, "Body" => expected_body))
        .to_return(status: 201, body: {sid: "SMcontract", status: "queued", num_segments: "1"}.to_json)
    when :invalid_number then stub.to_return(status: 400, body: {code: 21211}.to_json)
    when :opted_out then stub.to_return(status: 400, body: {code: 21610}.to_json)
    when :authentication then stub.to_return(status: 401, body: {code: 20003}.to_json)
    when :throttled then stub.to_return(status: 429, body: {code: 20429}.to_json)
    when :server_error then stub.to_return(status: 503)
    when :timeout then stub.to_timeout
    end
  end

  def twilio_request(params, signed:)
    url = "https://app.example/smswire/callbacks"
    data = url + params.sort.map { |key, value| "#{key}#{value}" }.join
    signature = signed ? Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "secret", data)) : "forged"
    contract_request(url, params:, headers: {"X-Twilio-Signature" => signature})
  end

  def contract_status_request(provider_id:, status:, signed: true)
    twilio_request({"MessageSid" => provider_id, "MessageStatus" => status.to_s}, signed:)
  end

  def contract_inbound_request(from:, to:, body:, signed: true)
    twilio_request({"MessageSid" => "SMinbound", "From" => from, "To" => to, "Body" => body, "SmsStatus" => "received"}, signed:)
  end
end

class TelnyxContractTest < Smswire::TestCase
  include Smswire::ProviderContract
  include DummyContractMessage

  KEY = OpenSSL::PKey.generate_key("ED25519")
  PUBLIC_KEY = Base64.strict_encode64(KEY.public_to_der[-32..])

  def contract_provider_name = :telnyx

  def contract_provider_options = {api_key: "KEYtest", public_key: PUBLIC_KEY}

  def stub_contract_send(outcome, message)
    stub = stub_request(:post, Smswire::Providers::Telnyx::API_URL)
    error = ->(status, code) { stub.to_return(status:, body: {errors: [{code:, title: "error"}]}.to_json) }
    case outcome
    when :success
      stub.with(headers: {"Authorization" => "Bearer KEYtest"},
        body: hash_including("to" => message.to, "from" => "+15005550006", "text" => expected_body))
        .to_return(status: 200, body: {data: {id: "tx-contract", to: [{phone_number: message.to, status: "queued"}],
                                              parts: 1, cost: {amount: "0.0040", currency: "USD"}}}.to_json)
    when :invalid_number then error.call(422, "40310")
    when :opted_out then error.call(422, "40300")
    when :authentication then error.call(401, "10009")
    when :throttled then error.call(429, "10011")
    when :server_error then error.call(503, "10007")
    when :timeout then stub.to_timeout
    end
  end

  def telnyx_request(data, signed:)
    body = {data:}.to_json
    timestamp = Time.now.to_i.to_s
    signature = Base64.strict_encode64(KEY.sign(nil, "#{timestamp}|#{signed ? body : "#{body} "}"))
    contract_request("https://app.example/smswire/inbound/telnyx", body:,
      headers: {"telnyx-signature-ed25519" => signature, "telnyx-timestamp" => timestamp})
  end

  def contract_status_request(provider_id:, status:, signed: true)
    native = {delivered: "delivered", undelivered: "delivery_failed"}.fetch(status)
    telnyx_request({event_type: "message.finalized", payload: {id: provider_id, to: [{phone_number: "+14155552671", status: native}]}}, signed:)
  end

  def contract_inbound_request(from:, to:, body:, signed: true)
    telnyx_request({event_type: "message.received", payload: {id: "tx-inbound", from: {phone_number: from},
                                                              to: [{phone_number: to}], text: body}}, signed:)
  end
end

class VonageContractTest < Smswire::TestCase
  include Smswire::ProviderContract
  include DummyContractMessage

  def contract_provider_name = :vonage

  def contract_provider_options = {api_key: "key", api_secret: "secret", signature_secret: "sigsecret", signature_method: "sha256"}

  def stub_contract_send(outcome, message)
    stub = stub_request(:post, Smswire::Providers::Vonage::API_URL)
    part = ->(status) { stub.to_return(status: 200, body: {"message-count" => "1", "messages" => [{"status" => status, "error-text" => "error"}]}.to_json) }
    case outcome
    when :success
      stub.with(body: hash_including("to" => message.to.delete_prefix("+"), "text" => expected_body, "type" => "text"))
        .to_return(status: 200, body: {"message-count" => "1", "messages" => [{"to" => "14155552671", "message-id" => "vg-contract",
                                                                               "status" => "0", "message-price" => "0.0333"}]}.to_json)
    when :invalid_number then part.call("6")
    when :authentication then part.call("4")
    when :throttled then part.call("1")
    when :server_error then stub.to_return(status: 500)
    when :timeout then stub.to_timeout
    end
  end

  # Vonage's "number barred" code also covers blocks other than opt-outs.
  def contract_reports_opt_outs? = false

  def vonage_request(params, signed:)
    params = params.merge("timestamp" => Time.now.to_i.to_s)
    sig = Smswire::Providers::Vonage.signature(params, secret: "sigsecret", method: "sha256")
    contract_request("https://app.example/smswire/inbound/vonage", params: params.merge("sig" => signed ? sig : "0" * 64))
  end

  def contract_status_request(provider_id:, status:, signed: true)
    native = {delivered: "delivered", undelivered: "failed"}.fetch(status)
    vonage_request({"messageId" => provider_id, "msisdn" => "14155552671", "to" => "15005550006", "status" => native,
                    "err-code" => (status == :delivered) ? "0" : "2"}, signed:)
  end

  def contract_inbound_request(from:, to:, body:, signed: true)
    vonage_request({"messageId" => "vg-inbound", "msisdn" => from.delete_prefix("+"), "to" => to.delete_prefix("+"),
                    "text" => body, "type" => "text"}, signed:)
  end
end
