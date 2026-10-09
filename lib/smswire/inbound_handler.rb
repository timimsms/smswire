module Smswire
  # Records an inbound message once, handles compliance keywords, and
  # notifies observers. Shared by the webhook endpoint and the development
  # inbox.
  module InboundHandler
    module_function

    # Returns the new Smswire::InboundMessage, or nil for a repeated webhook.
    def call(inbound, provider:)
      payload = {provider:, provider_id: inbound.provider_id, from: inbound.from}
      ActiveSupport::Notifications.instrument("inbound.smswire", payload) do
        record = InboundMessage.receive(inbound, provider:)
        payload[:duplicate] = record.nil?
        if record
          payload[:keyword] = Keywords.handle(record, inbound, provider:) if Smswire.config.enforce_consent
          notify_observers(record)
        end
        record
      end
    end

    def notify_observers(record)
      Smswire.config.observers.each do |observer|
        observer = observer.is_a?(String) ? observer.constantize : observer
        observer.sms_received(record) if observer.respond_to?(:sms_received)
      end
    end
  end
end
