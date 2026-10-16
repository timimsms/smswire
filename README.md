# Smswire

> The production SMS layer for Rails that Noticed and twilio-ruby both leave to you.

Smswire gives Rails applications Action Mailer-style messenger classes and
templates for SMS, a provider-agnostic message object, a delivery pipeline
with typed outcomes, retries with a transient-versus-permanent error
taxonomy, and test helpers. Persisted deliveries with status callbacks,
consent and STOP / HELP / START handling, quiet hours, previews, and a
[Noticed](https://github.com/excid3/noticed) delivery method are included.
See the [specification](docs/SPEC.md) for the full design.

**Status:** pre-release. All six phases of the spec are implemented; the
published `0.0.1.pre` gem only reserves the name. See
[RELEASING.md](RELEASING.md) for the release steps.

## Guides

- [Getting started](docs/guides/getting-started.md)
- [Migrating from direct twilio-ruby calls](docs/guides/migrating-from-twilio-ruby.md)
- [Migrating from Noticed's Twilio delivery method](docs/guides/migrating-from-noticed-twilio.md)
- [Compliance primer](docs/guides/compliance.md)
- [Writing a provider adapter](docs/guides/writing-a-provider.md)

## Requirements

Ruby 3.2+ and Rails 7.1 through 8.1.

## Installation

```ruby
# Gemfile
gem "smswire"
```

```
bin/rails generate smswire:install
bin/rails db:migrate
bin/rails generate smswire:messenger Order shipped
```

The install generator copies the migrations, writes
`config/initializers/smswire.rb` and `ApplicationMessenger`, and mounts the
engine at `/smswire`. The messenger generator writes the class, a template per
action, a preview, and a test.

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

### Development tools

In development, open `/smswire/previews` to see every preview rendered in a
phone frame with its encoding, segment count, and remaining characters, and
which characters force UCS-2. Open `/smswire/inbox` to see what was sent and
received, and to simulate a reply such as STOP.

```ruby
# test/messengers/previews/order_messenger_preview.rb
class OrderMessengerPreview < Smswire::Preview
  def shipped
    OrderMessenger.with(order: Order.first).shipped(User.first)
  end
end
```

For staging, only let messages through to known numbers:

```ruby
Smswire.register_interceptor(
  Smswire::Interceptors::Allowlist.new(numbers: ENV.fetch("SMS_ALLOWLIST", "").split(","))
  # or redirect_to: "+15555550100" to reroute everything else to one phone
)
```

### Providers

| Name | Use |
|---|---|
| `:twilio` | Twilio Programmable Messaging over REST, no SDK |
| `:telnyx` | Telnyx Messaging API v2; `api_key`, `public_key` for webhooks |
| `:vonage` | Vonage SMS API; `api_key`, `api_secret`, `signature_secret` |
| `:log` | Writes messages to the logger; development default |
| `:test` | Records messages in memory; test default |
| `:null` | Accepts and discards |

Each adapter passes `Smswire::ProviderContract`, a test suite shipped in the
gem. Generate your own with `bin/rails generate smswire:provider Acme`, which
writes an adapter and a test that runs the contract against it, or
subclass `Smswire::Providers::Base` and call
`Smswire::Providers.register(:acme, "AcmeProvider")`.

### Noticed

```ruby
class OrderShippedNotifier < Noticed::Event
  deliver_by :smswire do |config|
    config.messenger = "OrderMessenger"
    config.action = :shipped        # called with the recipient by default
  end
end
```

The messenger gets the event params plus `notification`, `record`, and
`recipient`, so consent, quiet hours, deduplication, retries, and status
tracking all apply. Each delivery stores the Noticed notification and event
ids in its metadata.

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
