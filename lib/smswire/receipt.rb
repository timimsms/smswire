module Smswire
  # What a provider returns after accepting a message.
  #
  # +status+ uses the normalized vocabulary: :queued, :accepted, :sent,
  # :delivered, :undelivered, :failed, :read.
  Receipt = Data.define(:provider, :provider_id, :status, :segments, :price_amount, :price_currency, :raw) do
    def initialize(provider:, provider_id: nil, status: :accepted, segments: nil, price_amount: nil, price_currency: nil, raw: nil)
      super
    end
  end
end
