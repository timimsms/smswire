module Smswire
  # Receives inbound messages at POST <mount>/inbound/:provider, records
  # them once per provider message id, and handles compliance keywords.
  # Apps can build two-way messaging with an observer that implements
  # +sms_received(inbound_message)+.
  class InboundMessagesController < ActionController::Base
    skip_forgery_protection

    def create
      provider = Providers.resolve(params[:provider])
      return head(:not_found) unless provider.capabilities.include?(:inbound)

      if Smswire.config.verify_callback_signatures
        provider.verify_signature!(request, url: Callbacks.request_url(request))
      end

      inbound = provider.parse_inbound(request)
      payload = {provider: provider.name, provider_id: inbound.provider_id, from: inbound.from}
      ActiveSupport::Notifications.instrument("inbound.smswire", payload) do
        record = InboundMessage.receive(inbound, provider: provider.name)
        payload[:duplicate] = record.nil?
        if record
          payload[:keyword] = Keywords.handle(record, inbound, provider: provider.name) if Smswire.config.enforce_consent
          notify_observers(record)
        end
      end

      body, content_type = provider.inbound_response
      body ? render(plain: body, content_type:) : head(:no_content)
    rescue ConfigurationError
      head :not_found
    rescue SignatureError
      head :forbidden
    end

    private

    def notify_observers(record)
      Smswire.config.observers.each do |observer|
        observer = observer.is_a?(String) ? observer.constantize : observer
        observer.sms_received(record) if observer.respond_to?(:sms_received)
      end
    end
  end
end
