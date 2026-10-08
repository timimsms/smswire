module Smswire
  # A received message as parsed by a provider adapter.
  #
  # +provider_keyword+ is true when the provider already handled an opt-out
  # keyword and replied itself, as Twilio Advanced Opt-Out does.
  Inbound = Data.define(:provider_id, :from, :to, :body, :messaging_service, :provider_keyword, :raw) do
    def initialize(provider_id:, from:, to:, body:, messaging_service: nil, provider_keyword: false, raw: {})
      super
    end
  end
end
