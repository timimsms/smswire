Smswire.configure do |config|
  config.senders = {
    transactional: {number: "+15005550006"},
    marketing: {messaging_service: "MG00000000000000000000000000000000", provider: :twilio}
  }
  config.providers = {twilio: {account_sid: "ACtest", auth_token: "secret"}}
end
