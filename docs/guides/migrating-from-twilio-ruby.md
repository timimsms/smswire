# Migrating from direct twilio-ruby calls

Many apps send SMS by calling the Twilio SDK from models, jobs, or service
objects. This guide moves that code onto Smswire one message at a time.
Both can run side by side during the move.

## What changes

| Before | After |
|---|---|
| `client.messages.create(from:, to:, body:)` | a messenger action plus `deliver_later` |
| bodies built in Ruby strings | `.text.erb` templates with I18n and URL helpers |
| your own job and retry logic | `Smswire::DeliveryJob` with transient and permanent errors separated |
| `rescue Twilio::REST::RestError` | a `Smswire::Result` with a status and a reason |
| your own status callback controller | the engine's signed `/smswire/status/twilio` endpoint |
| stubbing the Twilio client in tests | `Smswire::TestHelper` and the `:test` provider |
| `twilio-ruby` in the Gemfile | no provider SDK |

Smswire calls Twilio's REST API directly. You can remove `twilio-ruby` once
nothing else uses it, such as Voice or Verify.

## 1. Install and keep your credentials

Run the [getting started](getting-started.md) install steps. Smswire reads
`Rails.application.credentials.twilio[:account_sid]` and `[:auth_token]`, the
same keys most apps already use. Move the sending number into a sender:

```ruby
config.senders = {
  transactional: {number: Rails.application.credentials.dig(:twilio, :phone_number)},
  # A Messaging Service maps to messaging_service:
  # marketing: {messaging_service: "MG...", consent_scope: "marketing"}
}
```

## 2. Replace one send

Before:

```ruby
class ShipmentNotifier
  def call(order)
    client = Twilio::REST::Client.new(sid, token)
    client.messages.create(
      from: ENV["TWILIO_NUMBER"],
      to: order.customer.phone,
      body: "Order #{order.number} has shipped",
      status_callback: twilio_status_url(order_id: order.id)
    )
  rescue Twilio::REST::RestError => error
    Rails.logger.error(error.message)
  end
end
```

After:

```ruby
class OrderMessenger < ApplicationMessenger
  def shipped(order)
    @order = order
    text to: order.customer.phone
  end
end

OrderMessenger.shipped(order).deliver_later
```

```erb
<%# app/views/order_messenger/shipped.text.erb %>
Order <%= @order.number %> has shipped
```

`text to:` takes a string here. Pass the customer instead if it has a
`phone_number` method, which also links the delivery row to the customer.

## 3. Map your error handling

Smswire turns Twilio errors into outcomes:

| Twilio | Smswire |
|---|---|
| 21211, 21214, 21217, 21614 invalid number | `:failed`, `error.reason == :invalid_number` |
| 21610 recipient replied STOP | `:failed`, reason `:opted_out`, and the number is opted out |
| 21408, 21606, 21612 cannot route | `:failed`, reason `:unroutable` |
| 401, 403, 20003 | `:failed`, reason `:authentication` |
| 429 | retried after `Retry-After` |
| 5xx, timeouts | retried with backoff, up to `retry_attempts` |
| other 4xx | `:failed`, reason `:rejected` |

Code that rescued `RestError` to log or alert becomes an observer:

```ruby
class SmsAlerts
  def self.delivered_sms(result)
    Sentry.capture_message("SMS failed: #{result.error.message}") if result.failed?
  end
end
Smswire.register_observer(SmsAlerts)
```

## 4. Retire your status controller

If you had a controller for Twilio status callbacks, set
`config.callbacks_url` and delete it. Every message then carries a
`StatusCallback` URL with its delivery id, the engine checks the
`X-Twilio-Signature`, and `Smswire::Delivery#status` only moves forward. Use
`sms_status_updated(delivery, update)` on an observer for anything you did
in that controller.

Behind a load balancer that terminates TLS, the signature still verifies
because Smswire rebuilds the URL from `callbacks_url`.

## 5. Point incoming messages at the engine

Set the number's or Messaging Service's incoming webhook to
`https://app.example.com/smswire/inbound/twilio`. If you use Twilio Advanced
Opt-Out, Smswire records the opt-out and skips its own reply, since Twilio
already sent one.

## 6. Update tests

Before:

```ruby
client = instance_double(Twilio::REST::Client)
expect(client).to receive_message_chain(:messages, :create)
```

After:

```ruby
assert_sms_delivered(to: "+15555550100", messenger: OrderMessenger) { order.ship! }
```

The test environment uses the `:test` provider automatically, so no request
leaves the process.

## Behaviour to expect

- **Duplicates.** The same messenger, action, recipient, and body inside 10
  minutes returns `:duplicate`. Pass `idempotency_key:` to `text`, or set
  `config.dedupe_window = nil`.
- **Opt-outs.** Opted-out numbers are refused for every category.
- **Marketing.** Messages with `category: :marketing` need an opt-in and wait
  for quiet hours to end.
