# Migrating from Noticed's Twilio delivery method

Noticed is a good fit for notification inboxes and fan-out across channels.
Its `twilio_messaging` delivery method posts a message string to Twilio and
leaves templates, consent, retries, and delivery tracking to the app.
Smswire adds a `deliver_by :smswire` delivery method, so you keep Noticed
and move only the SMS channel.

## Before

```ruby
class OrderShippedNotifier < Noticed::Event
  deliver_by :twilio_messaging do |config|
    config.json = -> {
      {
        From: Rails.application.credentials.dig(:twilio, :phone_number),
        To: recipient.phone_number,
        Body: "Order #{params[:order].number} has shipped"
      }
    }
    config.error_handler = ->(response) { ... }
  end
end
```

## After

```ruby
class OrderShippedNotifier < Noticed::Event
  deliver_by :smswire do |config|
    config.messenger = "OrderMessenger"
    config.action = :shipped
  end
end
```

```ruby
class OrderMessenger < ApplicationMessenger
  # Called with the Noticed recipient. params holds the event params plus
  # notification, record, and recipient.
  def shipped(user)
    @order = params[:order]
    text to: user
  end
end
```

```erb
<%# app/views/order_messenger/shipped.text.erb %>
Order <%= @order.number %> has shipped
```

Install Smswire first with the [getting started](getting-started.md) steps.
The delivery method loads automatically when Noticed is in the bundle.

## Options

| Option | Default | Use |
|---|---|---|
| `messenger` | required | class or class name |
| `action` | required | messenger action |
| `args` | `[recipient]` | positional arguments for the action |
| `kwargs` | `{}` | keyword arguments |
| `params` | the event params | the messenger's `params`, merged with `notification`, `record`, `recipient` |
| `sms_queue`, `sms_priority` | Smswire's defaults | queue and priority for `Smswire::DeliveryJob` |

Noticed's own options, such as `if`, `unless`, `wait`, and `queue`, still
apply to the Noticed job. A `wait` delays the message once; Smswire does not
add a second delay.

## Credentials

Noticed reads `Rails.application.credentials.twilio`, and so does Smswire.
The `phone_number` key becomes a sender:

```ruby
config.senders = {transactional: {number: Rails.application.credentials.dig(:twilio, :phone_number)}}
```

## Error handling

`config.error_handler` received Twilio's 4xx response. With Smswire:

- permanent errors become a `:failed` delivery with a reason, such as
  `:invalid_number` or `:opted_out`;
- a 21610 opt-out also records the opt-out, so later sends are refused;
- 429 and 5xx errors are retried by `Smswire::DeliveryJob`.

Use an observer for alerting; see the
[twilio-ruby guide](migrating-from-twilio-ruby.md#3-map-your-error-handling).

## Joining notifications and deliveries

Each `Smswire::Delivery` stores `noticed_notification_id` and
`noticed_event_id` in `metadata`, and `recipient` points at the Noticed
recipient when it is an Active Record model.

## What you gain

- Templates, previews, and test helpers for the SMS body.
- Delivery status from Twilio callbacks on every send.
- STOP / START / HELP handling and consent checks before sending.
- Quiet hours and rate limits per category.
- Deduplication and retries.
- The same code works with Telnyx or Vonage by changing the provider.
