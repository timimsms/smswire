require "test_helper"

class VerifyCredentialsTest < Smswire::TestCase
  test "built-in development providers always pass" do
    assert Smswire.verify_credentials!
    assert Smswire.verify_credentials!(:log)
  end

  test "twilio checks the account endpoint" do
    stub = stub_request(:get, "https://api.twilio.com/2010-04-01/Accounts/ACtest.json")
      .with(basic_auth: %w[ACtest secret]).to_return(status: 200, body: "{}")
    assert Smswire.verify_credentials!(:twilio)
    assert_requested stub

    stub_request(:get, "https://api.twilio.com/2010-04-01/Accounts/ACtest.json").to_return(status: 401)
    assert_raises(Smswire::ConfigurationError) { Smswire.verify_credentials!(:twilio) }
  end

  test "telnyx and vonage check their balance endpoints" do
    providers = Smswire.config.providers.merge(telnyx: {api_key: "KEY"}, vonage: {api_key: "k", api_secret: "s"})
    with_config(providers:) do
      stub_request(:get, "https://api.telnyx.com/v2/balance").with(headers: {"Authorization" => "Bearer KEY"}).to_return(status: 200)
      stub_request(:get, "https://rest.nexmo.com/account/get-balance?api_key=k&api_secret=s").to_return(status: 200, body: "{}")
      assert Smswire.verify_credentials!(:telnyx)
      assert Smswire.verify_credentials!(:vonage)

      stub_request(:get, "https://api.telnyx.com/v2/balance").to_return(status: 503)
      assert_raises(Smswire::TransientError) { Smswire.verify_credentials!(:telnyx) }
    end
  end

  test "custom adapters that cannot check return nil" do
    Smswire::Providers.register(:silent, Class.new(Smswire::Providers::Base))
    assert_nil Smswire.verify_credentials!(:silent)
  end
end
