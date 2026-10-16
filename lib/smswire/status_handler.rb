module Smswire
  # Applies a parsed provider status update to its delivery and notifies
  # observers. Shared by the webhook endpoints.
  module StatusHandler
    module_function

    def call(update, provider:, delivery_id: nil)
      payload = {provider:, provider_id: update.provider_id, status: update.status, error_code: update.error_code}
      ActiveSupport::Notifications.instrument("status_update.smswire", payload) do
        delivery = Delivery.apply_status_update(update, provider:, delivery_id:)
        payload[:delivery_id] = delivery&.id
        payload[:delivery_status] = delivery&.status
        notify_observers(delivery, update) if delivery
        delivery
      end
    end

    def notify_observers(delivery, update)
      Smswire.config.observers.each do |observer|
        observer = observer.is_a?(String) ? observer.constantize : observer
        observer.sms_status_updated(delivery, update) if observer.respond_to?(:sms_status_updated)
      end
    end
  end
end
