module Smswire
  # A message received from a provider webhook. Webhook retries for the
  # same provider message id are recorded once.
  class InboundMessage < ApplicationRecord
    KEYWORDS = %w[stop start help].freeze

    scope :recent, -> { order(created_at: :desc) }

    # Returns the new record, or nil when this provider message id was
    # already received.
    def self.receive(inbound, provider:)
      create!(
        provider: provider.to_s,
        provider_id: inbound.provider_id,
        from_number: PhoneNumber.normalize(inbound.from) || inbound.from,
        to_number: inbound.to,
        messaging_service: inbound.messaging_service,
        body: inbound.body,
        raw: inbound.raw
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
