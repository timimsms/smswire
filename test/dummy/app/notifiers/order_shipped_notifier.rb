class OrderShippedNotifier < Noticed::Event
  required_params :order_number

  deliver_by :smswire do |config|
    config.messenger = "OrderMessenger"
    config.action = :notify_shipped
  end
end
