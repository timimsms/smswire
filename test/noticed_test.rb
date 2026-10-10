require "test_helper"

# Phase 5 acceptance: a Noticed notifier delivers through a Smswire messenger.
class NoticedTest < Smswire::TestCase
  setup do
    @customer = Customer.create!(name: "Ada", phone_number: "(415) 555-2671")
  end

  test "the delivery method is registered with Noticed" do
    assert_equal Noticed::DeliveryMethods::Smswire, OrderShippedNotifier.delivery_methods[:smswire].constant
    assert_equal %i[messenger action], Noticed::DeliveryMethods::Smswire.required_option_names
  end

  test "a notifier delivers through the messenger pipeline" do
    perform_enqueued_jobs do
      OrderShippedNotifier.with(order_number: "R5").deliver(@customer)
    end

    notification = Noticed::Notification.sole
    delivery = Smswire::Delivery.sole
    assert_equal "Hi Ada, order R5 has shipped.", delivery.body
    assert_equal ["+14155552671", "OrderMessenger", "notify_shipped", "accepted"],
      [delivery.to_number, delivery.messenger, delivery.action, delivery.status]
    assert_equal @customer, delivery.recipient
    assert_equal({"noticed_notification_id" => notification.id, "noticed_event_id" => notification.event_id}, delivery.metadata)
  end

  test "consent still applies to Noticed deliveries" do
    Smswire::Consent.opt_out!(@customer.phone_number, source: :api)
    perform_enqueued_jobs do
      OrderShippedNotifier.with(order_number: "R6").deliver(@customer)
    end
    assert_equal 1, Noticed::Notification.count
    assert_equal 0, Smswire::Delivery.count
    assert_empty sms_deliveries
  end

  test "custom args, params, and job options" do
    notifier = Class.new(Noticed::Event) do
      def self.name = "CustomShippedNotifier"

      deliver_by :smswire do |config|
        config.messenger = OrderMessenger
        config.action = :delivery_window
        config.args = -> { [recipient.phone_number] }
        config.kwargs = -> { {window: "9-11am"} }
        config.params = -> { {order_number: "R7"} }
        config.queue = :sms
      end
    end
    Object.const_set(:CustomShippedNotifier, notifier)

    perform_enqueued_jobs(only: [Noticed::EventJob, Noticed::DeliveryMethods::Smswire]) do
      notifier.with(order_number: "ignored").deliver(@customer)
    end
    assert_enqueued_sms(OrderMessenger, :delivery_window, args: ["(415) 555-2671"], kwargs: {window: "9-11am"})
    assert_equal "sms", enqueued_jobs.last[:queue]

    perform_enqueued_jobs
    assert_equal "Order R7 arrives 9-11am", Smswire::Delivery.sole.body
  ensure
    Object.send(:remove_const, :CustomShippedNotifier) if Object.const_defined?(:CustomShippedNotifier)
  end
end
