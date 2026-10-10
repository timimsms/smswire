# Loaded by Smswire::Engine when Noticed is present.
module Noticed
  module DeliveryMethods
    # Sends a Noticed notification through a Smswire messenger, so
    # templates, consent, quiet hours, deduplication, persistence, retries,
    # and status tracking all apply.
    #
    #   class OrderShippedNotifier < Noticed::Event
    #     deliver_by :smswire do |config|
    #       config.messenger = "OrderMessenger"
    #       config.action = :shipped
    #       # Optional:
    #       # config.args   = -> { [recipient] }                # default
    #       # config.kwargs = -> { {} }
    #       # config.params = -> { {order: record} }            # default: the event params
    #       # config.wait, config.queue, config.priority        # for Smswire::DeliveryJob
    #     end
    #   end
    #
    # The messenger receives the event params plus +notification+, +record+,
    # and +recipient+. Each Smswire::Delivery records the Noticed
    # notification and event ids in its metadata.
    class Smswire < DeliveryMethod
      required_options :messenger, :action

      def deliver
        messenger = fetch_constant(:messenger)
        action = evaluate_option(:action).to_sym
        args = evaluate_option(:args) || [recipient]
        kwargs = evaluate_option(:kwargs) || {}

        ::Smswire::MessageDelivery.new(messenger, action, args: Array(args), kwargs:, params: messenger_params)
          .deliver_later(**job_options)
      end

      private

      def messenger_params
        base = evaluate_option(:params) || event.params || {}
        base.to_h.symbolize_keys.merge(
          notification:, record: event.record, recipient:,
          smswire_metadata: {"noticed_notification_id" => notification.id, "noticed_event_id" => event.id}
        )
      end

      def job_options
        {wait: evaluate_option(:wait), wait_until: evaluate_option(:wait_until),
         queue: evaluate_option(:queue), priority: evaluate_option(:priority)}.compact
      end
    end
  end
end
