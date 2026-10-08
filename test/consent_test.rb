require "test_helper"

class ConsentTest < Smswire::TestCase
  PHONE = "+14155552671"

  def brand_messenger
    Class.new(ApplicationMessenger) do
      def self.name = "BrandMessenger"

      def note(phone) = text(to: phone, from: :brand_b, body: "Brand B note")
    end
  end

  def brand_senders
    Smswire.config.senders.merge(brand_b: {number: "+15005550001", consent_scope: "brand_b"})
  end

  test "opt in and out with evidence" do
    Smswire::Consent.opt_in!("(415) 555-2671", source: :web_form, metadata: {ip: "203.0.113.9", form: "checkout"})
    consent = Smswire::Consent.sole
    assert_equal [PHONE, "default", "opted_in", "web_form"], [consent.phone, consent.scope, consent.status, consent.source]
    assert consent.opted_in_at
    assert_equal "opted_in", Smswire::Consent.status_for(PHONE)

    Smswire::Consent.opt_out!(PHONE, source: :api, metadata: {reason: "support ticket"})
    assert_equal({"ip" => "203.0.113.9", "form" => "checkout", "reason" => "support ticket"}, consent.reload.metadata)
    assert_equal "opted_out", consent.status
    assert_equal "unknown", Smswire::Consent.status_for("+12125550123")
    assert_raises(ArgumentError) { Smswire::Consent.opt_in!("nope", source: :api) }
  end

  test "opted-out numbers are refused for every category" do
    Smswire::Consent.opt_out!(PHONE, source: :api)
    assert_equal :rejected_opted_out, OrderMessenger.literal(PHONE, "hi").deliver_now.status
    assert_equal :rejected_opted_out, OrderMessenger.deal(PHONE, "sale").deliver_now.status
    assert_empty sms_deliveries
    assert_equal 0, Smswire::Delivery.count
  end

  test "marketing requires opt-in" do
    travel_to Time.utc(2026, 1, 15, 17) do
      assert_equal :rejected_no_consent, OrderMessenger.deal(PHONE, "sale").deliver_now.status
      Smswire::Consent.opt_in!(PHONE, source: :web_form)
      assert OrderMessenger.deal(PHONE, "sale").deliver_now.accepted?
    end
  end

  test "consent is kept per sender scope" do
    with_config(senders: brand_senders) do
      Smswire::Consent.opt_out!(PHONE, source: :api)
      assert brand_messenger.note(PHONE).deliver_now.accepted?

      Smswire::Consent.opt_out!(PHONE, scope: "brand_b", source: :api)
      assert_equal :rejected_opted_out, brand_messenger.note(PHONE).deliver_now.status
    end
  end

  test "opt_out_everywhere covers every configured scope" do
    with_config(senders: brand_senders) do
      Smswire::Consent.opt_out_everywhere!(PHONE, source: :keyword, keyword: "STOPALL")
      assert_equal %w[brand_b default], Smswire::Consent.where(status: "opted_out").pluck(:scope).sort
    end
  end

  test "a carrier opt-out error records the opt-out" do
    Smswire::Providers::Test.fail_next(Smswire::PermanentError.new("unsubscribed", reason: :opted_out, provider_code: "21610"))
    assert OrderMessenger.literal(PHONE, "hi").deliver_now.failed?

    consent = Smswire::Consent.sole
    assert_equal ["opted_out", "carrier"], [consent.status, consent.source]
    assert_equal :rejected_opted_out, OrderMessenger.literal(PHONE, "again").deliver_now.status
  end

  test "enforcement can be turned off" do
    Smswire::Consent.opt_out!(PHONE, source: :api)
    with_config(enforce_consent: false) do
      assert OrderMessenger.literal(PHONE, "hi").deliver_now.accepted?
    end
  end

  test "category overrides merge over the defaults" do
    with_config(categories: {marketing: {quiet_hours: nil}}) do
      assert_nil Smswire.config.category_options(:marketing)[:quiet_hours]
      assert_equal :require_opted_in, Smswire.config.category_options(:marketing)[:consent]
      assert_equal false, Smswire.config.category_options(:otp)[:store_body]
      assert_equal :allow_unless_opted_out, Smswire.config.category_options(:custom)[:consent]
    end
    with_config(categories: {marketing: {consent: :maybe}}) do
      assert_raises(Smswire::ConfigurationError) { Smswire.config.category_options(:marketing) }
    end
  end
end
