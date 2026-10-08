module Smswire
  # Receives provider delivery status callbacks at
  # POST <mount>/status/:provider. Always answers 2xx for well-formed,
  # signed requests so providers do not retry, even when the delivery is
  # unknown.
  class StatusCallbacksController < ActionController::Base
    skip_forgery_protection

    def create
      provider = Providers.resolve(params[:provider])
      return head(:not_found) unless provider.capabilities.include?(:status_callbacks)

      if Smswire.config.verify_callback_signatures
        provider.verify_signature!(request, url: Callbacks.request_url(request))
      end

      update = provider.parse_status_callback(request)
      payload = {provider: provider.name, provider_id: update.provider_id, status: update.status,
                 error_code: update.error_code}
      ActiveSupport::Notifications.instrument("status_update.smswire", payload) do
        delivery = Delivery.apply_status_update(update, provider: provider.name, delivery_id: params[:delivery_id])
        payload[:delivery_id] = delivery&.id
        payload[:delivery_status] = delivery&.status
        notify_observers(delivery, update) if delivery
      end

      head :no_content
    rescue ConfigurationError
      head :not_found
    rescue SignatureError
      head :forbidden
    end

    private

    def notify_observers(delivery, update)
      Smswire.config.observers.each do |observer|
        observer = observer.is_a?(String) ? observer.constantize : observer
        observer.sms_status_updated(delivery, update) if observer.respond_to?(:sms_status_updated)
      end
    end
  end
end
