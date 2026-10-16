require "rack/mock"
require "action_dispatch"

module Smswire
  # Minitest contract every provider adapter must pass. Include it in a
  # test case that also has Smswire::TestHelper and WebMock, and define the
  # hooks below. Tests for optional capabilities run only when the adapter
  # declares them.
  #
  #   class AcmeProviderContractTest < ActiveSupport::TestCase
  #     include Smswire::TestHelper
  #     include Smswire::ProviderContract
  #
  #     def contract_provider_name = :acme
  #     def contract_provider_options = {api_key: "test"}
  #     def stub_contract_send(outcome, message) = ...       # WebMock stub; see OUTCOMES
  #     def contract_status_request(provider_id:, status:, signed: true) = ...   # with :status_callbacks
  #     def contract_inbound_request(from:, to:, body:, signed: true) = ...      # with :inbound
  #   end
  #
  # +stub_contract_send+ must stub the provider API for +outcome+ and return
  # the WebMock stub. For :success it should also match the message's
  # recipient and body. +status+ is :delivered or :undelivered. Define
  # +contract_reports_opt_outs?+ as false when the provider cannot report an
  # opt-out when sending. Request
  # hooks return an ActionDispatch::Request, built with +contract_request+.
  module ProviderContract
    OUTCOMES = %i[success invalid_number opted_out authentication throttled server_error timeout].freeze
    STATUSES = %i[queued accepted sent delivered undelivered failed read].freeze
    CAPABILITIES = %i[mms status_callbacks inbound messaging_services scheduling].freeze

    # Return false when the provider has no send-time error that
    # specifically means the recipient opted out. The suite then skips the
    # :opted_out outcome rather than accept a guess.
    def contract_reports_opt_outs? = true

    # The message the suite sends. Override to use one of your messengers.
    def contract_message
      Message.new(to: "+14155552671", from: "+15005550006", body: "Smswire contract check", messenger: "ContractMessenger",
        action: "check")
    end

    def contract_provider
      Providers.lookup(contract_provider_name).new(contract_provider_options, name: contract_provider_name)
    end

    def contract_request(url, body: nil, params: nil, headers: {})
      env = Rack::MockRequest.env_for(url, :method => "POST", :input => body || Rack::Utils.build_query(params || {}),
        "CONTENT_TYPE" => body ? "application/json" : "application/x-www-form-urlencoded")
      headers.each { |key, value| env["HTTP_#{key.upcase.tr("-", "_")}"] = value }
      ActionDispatch::Request.new(env)
    end

    def test_contract_declares_known_capabilities
      assert_empty contract_provider.capabilities.to_a - CAPABILITIES
    end

    def test_contract_delivers_and_returns_a_receipt
      message = contract_message
      stub = stub_contract_send(:success, message)
      receipt = contract_provider.deliver(message)

      assert_requested stub
      assert_equal contract_provider_name, receipt.provider
      assert receipt.provider_id.present?, "receipt needs the provider message id"
      assert_includes STATUSES, receipt.status
      assert(receipt.segments.nil? || receipt.segments.positive?)
    end

    def test_contract_delivers_through_the_pipeline
      message = contract_message
      stub_contract_send(:success, message)
      providers = Smswire.config.providers.merge(contract_provider_name => contract_provider_options)
      result = contract_with_config(default_provider: contract_provider_name, providers:) do
        message.provider = contract_provider_name
        Pipeline.call(message)
      end

      assert result.accepted?, "expected accepted, got #{result.status} #{result.error&.message}"
      if Smswire.config.persist_deliveries
        assert_equal result.provider_id, result.delivery.reload.provider_id
        assert_equal contract_provider_name.to_s, result.delivery.provider
      end
    end

    def test_contract_maps_permanent_errors_to_reasons
      expected = {invalid_number: :invalid_number, opted_out: :opted_out, authentication: :authentication}
      expected.delete(:opted_out) unless contract_reports_opt_outs?
      expected.each do |outcome, reason|
        message = contract_message
        stub_contract_send(outcome, message)
        error = assert_raises(PermanentError, "#{outcome} should be permanent") { contract_provider.deliver(message) }
        assert_equal reason, error.reason, "#{outcome} should map to #{reason}"
        assert_equal contract_provider_name, error.provider
        WebMock.reset!
      end
    end

    def test_contract_raises_retryable_errors
      {throttled: ThrottledError, server_error: TransientError, timeout: TransientError}.each do |outcome, klass|
        message = contract_message
        stub_contract_send(outcome, message)
        assert_raises(klass, "#{outcome} should raise #{klass}") { contract_provider.deliver(message) }
        WebMock.reset!
      end
    end

    def test_contract_parses_and_verifies_status_callbacks
      skip "no :status_callbacks capability" unless contract_provider.capabilities.include?(:status_callbacks)

      %i[delivered undelivered].each do |status|
        request = contract_status_request(provider_id: "contract-#{status}", status:)
        contract_provider.verify_signature!(request, url: request.original_url)
        update = contract_provider.parse_status_callback(request)
        assert_equal "contract-#{status}", update.provider_id
        assert_equal status, update.status
      end

      forged = contract_status_request(provider_id: "contract-forged", status: :delivered, signed: false)
      assert_raises(SignatureError) { contract_provider.verify_signature!(forged, url: forged.original_url) }
    end

    def test_contract_parses_and_verifies_inbound_messages
      skip "no :inbound capability" unless contract_provider.capabilities.include?(:inbound)

      request = contract_inbound_request(from: "+14155552671", to: "+15005550006", body: "STOP")
      contract_provider.verify_signature!(request, url: request.original_url)
      inbound = contract_provider.parse_inbound(request)
      assert inbound.provider_id.present?
      assert_equal ["+14155552671", "+15005550006", "STOP"], [inbound.from, inbound.to, inbound.body]
      if contract_provider.capabilities.include?(:status_callbacks)
        assert_nil contract_provider.parse_status_callback(request), "inbound messages must not parse as status updates"
      end

      forged = contract_inbound_request(from: "+14155552671", to: "+15005550006", body: "STOP", signed: false)
      assert_raises(SignatureError) { contract_provider.verify_signature!(forged, url: forged.original_url) }
    end

    def test_contract_status_callbacks_are_not_inbound_messages
      capabilities = contract_provider.capabilities
      skip "needs both :status_callbacks and :inbound" unless capabilities.superset?(Set[:status_callbacks, :inbound])

      request = contract_status_request(provider_id: "contract-status", status: :delivered)
      assert_nil contract_provider.parse_inbound(request)
    end

    private

    def contract_with_config(**overrides)
      config = Smswire.config
      previous = overrides.keys.to_h { |key| [key, config.public_send(key)] }
      overrides.each { |key, value| config.public_send(:"#{key}=", value) }
      yield
    ensure
      previous&.each { |key, value| config.public_send(:"#{key}=", value) }
    end
  end
end
