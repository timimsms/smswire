# Smswire

> The production SMS layer for Rails that Noticed and twilio-ruby both leave to you.

Smswire gives Rails applications Action Mailer-style messenger classes and
templates for SMS, a provider-agnostic message object, a delivery pipeline
with typed outcomes, retries with a transient-versus-permanent error
taxonomy, and test helpers. Persisted deliveries with status callbacks,
consent and STOP / HELP / START handling, quiet hours, previews, and a
[Noticed](https://github.com/excid3/noticed) delivery adapter follow in later
phases of the [specification](docs/SPEC.md).

**Status:** pre-release. Phase 1 of the spec is implemented on `main`; the
published `0.0.1.pre` gem only reserves the name.

## Requirements

Ruby 3.2+ and Rails 7.1 through 8.1.

## Usage

```ruby
# config/initializers/smswire.rb
Smswire.configure do |config|
  config.default_provider = :twilio   # :log in development and :test in test by default
  config.providers = {twilio: {account_sid: "AC...", auth_token: "..."}}  # or credentials.twilio
  config.senders = {transactional: {number: "+15005550006"}}
end
```

```ruby
# app/messengers/order_messenger.rb
class OrderMessenger < Smswire::Base
  default from: :transactional

  def shipped(user)
    @order = params[:order]
    text to: user   # any object with #phone_number, or an E.164 string
  end
end
```

```erb
<%# app/views/order_messenger/shipped.text.erb %>
<%= t(".greeting", name: @order.customer_name) %> Order <%= @order.number %> has shipped.
Track it: <%= order_url(@order) %>
```

```ruby
OrderMessenger.with(order:).shipped(user).deliver_later
result = OrderMessenger.with(order:).shipped(user).deliver_now
result.status       # => :accepted, :failed, :rejected_invalid_number, ...
result.provider_id  # => "SM..."
```

Every message is normalized to E.164, checked for an empty body, passed
through interceptors, sent, and reported to observers and
`ActiveSupport::Notifications` (`deliver.smswire`, `reject.smswire`). Bodies
are never instrumented or logged by provider adapters.

### Providers

| Name | Use |
|---|---|
| `:twilio` | Twilio Programmable Messaging over REST, no SDK |
| `:log` | Writes messages to the logger; development default |
| `:test` | Records messages in memory; test default |
| `:null` | Accepts and discards |

Register your own with `Smswire::Providers.register(:acme, AcmeProvider)`,
subclassing `Smswire::Providers::Base`.

### Testing

```ruby
class OrderTest < ActiveSupport::TestCase
  include Smswire::TestHelper

  test "ships" do
    assert_sms_delivered(to: "+15551234567", messenger: OrderMessenger, body: /shipped/) do
      order.ship!   # deliver_later jobs inside the block are performed
    end
    assert_enqueued_sms(OrderMessenger, :shipped) { order.ship! }
  end
end
```

RSpec: `require "smswire/rspec"` for `deliver_sms(...)` and
`have_enqueued_sms(OrderMessenger, :shipped)`.

## Development

```
bin/setup
bundle exec rake            # tests and Standard
RAILS_VERSION=7.1 bundle exec rake test
```

## License

MIT.
