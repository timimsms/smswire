require "test_helper"
require "base64"

class InboundTest < Smswire::IntegrationTest
  PHONE = "+14155552671"
  OUR_NUMBER = "+15005550006"

  setup do
    stub_request(:post, twilio_url).to_return { twilio_success(sid: "SM#{SecureRandom.hex(6)}") }
  end

  def receive(body, sid: "SMin#{SecureRandom.hex(4)}", signature: :valid, **extra)
    params = {"MessageSid" => sid, "From" => PHONE, "To" => OUR_NUMBER, "Body" => body}.merge(extra.transform_keys(&:to_s))
    url = "http://www.example.com/smswire/inbound/twilio"
    if signature == :valid
      data = url + params.sort.map { |key, value| "#{key}#{value}" }.join
      signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "secret", data))
    end
    post "/smswire/inbound/twilio", params:, headers: {"X-Twilio-Signature" => signature.to_s}
  end

  test "acceptance: STOP flips consent and sends a confirmation" do
    receive(" stop ")

    assert_response :ok
    assert_equal "text/xml", response.media_type
    assert_includes response.body, "<Response></Response>"

    consent = Smswire::Consent.sole
    assert_equal ["opted_out", "keyword", "STOP"], [consent.status, consent.source, consent.last_keyword]
    inbound = Smswire::InboundMessage.sole
    assert_equal ["stop", PHONE, OUR_NUMBER], [inbound.keyword, inbound.from_number, inbound.to_number]
    assert inbound.handled_at

    assert_enqueued_sms(Smswire::KeywordMessenger, :reply, args: [PHONE, "opt_out"])
    perform_enqueued_jobs
    reply = Smswire::Delivery.sole
    assert_equal ["compliance", OUR_NUMBER, "twilio", "queued"], [reply.category, reply.from_number, reply.provider, reply.status]
    assert_equal "Dummy: You are unsubscribed and will no longer receive any further messages. Reply START to resubscribe.",
      reply.body

    assert_equal :rejected_opted_out, OrderMessenger.literal(PHONE, "Your order shipped").deliver_now.status
  end

  test "START opts back in and HELP replies without changing consent" do
    receive("STOP")
    receive("Start!")
    assert_equal "opted_in", Smswire::Consent.status_for(PHONE)

    receive("help")
    assert_equal %w[stop start help], Smswire::InboundMessage.order(:created_at).pluck(:keyword)
    assert_equal %w[opt_out opt_in help], Smswire::Testing.enqueued(enqueued_jobs).map { |job| job[:args].last }
  end

  test "STOPALL opts out of every scope" do
    senders = Smswire.config.senders.merge(brand_b: {number: "+15005550001", consent_scope: "brand_b"})
    with_config(senders:) { receive("STOPALL") }
    assert_equal %w[brand_b default], Smswire::Consent.where(status: "opted_out").pluck(:scope).sort
  end

  test "STOP to a scoped sender only opts out of that scope" do
    senders = Smswire.config.senders.merge(transactional: {number: OUR_NUMBER, consent_scope: "orders"})
    with_config(senders:) { receive("STOP") }
    assert_equal [["orders", "opted_out"]], Smswire::Consent.pluck(:scope, :status)
  end

  test "keywords ignore spaces and hyphens" do
    receive("Opt out.")
    receive("stop all")
    assert_equal %w[stop stop], Smswire::InboundMessage.pluck(:keyword)
  end

  test "HELP includes the support contact, and warns when none is set" do
    with_config(support_contact: "help@acme.example") do
      receive("HELP")
      perform_enqueued_jobs
    end
    assert_equal "Dummy: For help, contact help@acme.example. Reply STOP to unsubscribe. Msg & data rates may apply.",
      Smswire::Delivery.sole.body

    output = StringIO.new
    with_config(logger: Logger.new(output)) do
      receive("INFO")
      perform_enqueued_jobs
    end
    assert_includes output.string, "Set config.support_contact"
    assert_equal "Dummy: Reply STOP to unsubscribe. Msg & data rates may apply.", Smswire::Delivery.order(:created_at).last.body
  end

  test "STOP can opt out of every scope" do
    senders = Smswire.config.senders.merge(brand_b: {number: "+15005550001", consent_scope: "brand_b"})
    with_config(senders:, opt_out_all_scopes: true) { receive("STOP") }
    assert_equal %w[brand_b default], Smswire::Consent.where(status: "opted_out").pluck(:scope).sort
  end

  test "keywords must be the whole message" do
    receive("please stop texting me")
    assert_nil Smswire::InboundMessage.sole.keyword
    assert_equal 0, Smswire::Consent.count
    assert_no_enqueued_sms
  end

  test "webhook retries are processed once" do
    2.times { receive("STOP", sid: "SMsame") }
    assert_response :ok
    assert_equal 1, Smswire::InboundMessage.count
    assert_enqueued_sms(count: 1)
  end

  test "a provider-handled opt-out is recorded without a second reply" do
    receive("STOP", OptOutType: "STOP")
    assert_equal "opted_out", Smswire::Consent.status_for(PHONE)
    assert_no_enqueued_sms
  end

  test "replies can be turned off per keyword" do
    with_config(keyword_replies: {opt_out: nil, opt_in: nil, help: nil}) do
      receive("STOP")
      perform_enqueued_jobs
    end
    assert_equal "opted_out", Smswire::Consent.status_for(PHONE)
    assert_equal 0, Smswire::Delivery.count
  end

  test "custom program name and keywords" do
    keywords = Smswire.config.keywords.merge(opt_out: %w[STOP ARRET])
    with_config(program_name: "Acme Alerts", keywords:) do
      receive("arrêt".tr("ê", "e"))
      perform_enqueued_jobs
    end
    assert_includes Smswire::Delivery.sole.body, "Acme Alerts"
  end

  test "observers receive inbound messages" do
    received = []
    observer = Object.new
    observer.define_singleton_method(:delivered_sms) { |_result| }
    observer.define_singleton_method(:sms_received) { |message| received << message.body }
    Smswire.register_observer(observer)
    receive("Is my order ready?")
    assert_equal ["Is my order ready?"], received
  ensure
    Smswire.unregister_observer(observer)
  end

  test "invalid signatures and unsupported providers are refused" do
    receive("STOP", signature: "forged")
    assert_response :forbidden
    assert_equal 0, Smswire::InboundMessage.count

    post "/smswire/inbound/test", params: {"Body" => "STOP"}
    assert_response :not_found
  end
end
