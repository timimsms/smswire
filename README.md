# Smswire

> The production SMS layer for Rails that Noticed and twilio-ruby both leave to you.

Smswire gives Rails applications Action Mailer-style messenger classes and
templates for SMS, a provider-agnostic message object, a delivery pipeline
with typed outcomes, retries with a transient-versus-permanent error
taxonomy, and test helpers. Persisted deliveries with status callbacks,
consent and STOP / HELP / START handling, quiet hours, previews, and a
[Noticed](https://github.com/excid3/noticed) delivery adapter follow in later
phases of the [specification](docs/SPEC.md).

**Status:** pre-release. Phases 1 to 3 of the spec are implemented; the
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

### Deliveries and status callbacks

```
bin/rails smswire:install:migrations
bin/rails db:migrate
```

```ruby
# config/routes.rb
mount Smswire::Engine => "/smswire"

# config/initializers/smswire.rb
config.callbacks_url = "https://app.example.com/smswire"
```

Every send is recorded in `Smswire::Delivery` with the provider message id,
segments, price, and status. With `callbacks_url` set, Twilio posts status
updates to the engine, which verifies the signature and moves the row
forward: `pending`, `queued`, `sent`, `delivered` (or `undelivered` /
`failed`). Out-of-order callbacks never move a status backwards.

Identical messages to the same number inside `dedupe_window` (10 minutes by
default) are refused with status `:duplicate`. Pass `idempotency_key:` to
`text` to choose what counts as identical. Bodies are stored unless the
category opts out; `otp` does by default.

```ruby
result = OrderMessenger.with(order:).shipped(user).deliver_now
result.delivery.status          # => "accepted"
Smswire::Delivery.for_number("+15551234567").recent
```

### Consent, keywords, quiet hours, and rate limits

Point your Twilio number's incoming message webhook at
`https://app.example.com/smswire/inbound/twilio`. Replies of STOP, START,
and HELP (and their synonyms) update `Smswire::Consent` and send the
configured confirmation. Record opt-ins from your own forms with evidence:

```ruby
Smswire::Consent.opt_in!(user.phone, source: :web_form,
  metadata: {ip: request.remote_ip, form: "checkout", copy: terms_text})
```

Each message has a category. The shipped rules are:

| Category | Consent | Quiet hours |
|---|---|---|
| `transactional` (default) | send unless opted out | none |
| `otp` | send unless opted out; body not stored | none |
| `marketing` | requires opt-in | 9pm to 8am recipient time |
| `compliance` | not checked; keyword replies | none |

Override any key, and add rate limits, in `config.categories`. Messages in
quiet hours or over a rate limit are re-enqueued for when they may send and
return `:deferred_quiet_hours` or `:deferred_rate_limited`. A carrier
opt-out error from the provider records an opt-out automatically.

Smswire provides these mechanisms. Your app is still responsible for its
messaging program's legal compliance.

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
