# Getting started

This guide takes a Rails app from no SMS to a tested, previewable message
with delivery tracking. It assumes Rails 7.1 or newer and Ruby 3.2 or newer.

## Install

```ruby
# Gemfile
gem "smswire"
```

```
bundle install
bin/rails generate smswire:install
bin/rails db:migrate
```

The install generator:

- copies three tables: `smswire_deliveries`, `smswire_consents`, and
  `smswire_inbound_messages`;
- writes `config/initializers/smswire.rb` and `app/messengers/application_messenger.rb`;
- mounts the engine at `/smswire` in `config/routes.rb`.

Out of the box, development uses the `:log` provider, which writes each
message to the log, and tests use the `:test` provider, which records
messages in memory. Nothing is sent until you configure a real provider.

## Configure a sender and a provider

```ruby
# config/initializers/smswire.rb
Smswire.configure do |config|
  config.default_provider = :twilio if Rails.env.production?
  config.providers = {
    twilio: {
      account_sid: Rails.application.credentials.dig(:twilio, :account_sid),
      auth_token: Rails.application.credentials.dig(:twilio, :auth_token)
    }
  }
  config.senders = {
    transactional: {number: "+15555550100"}
  }
  config.callbacks_url = "https://app.example.com/smswire"
  config.program_name = "Acme"
  config.support_contact = "help@acme.example"
end
```

Twilio credentials default to `Rails.application.credentials.twilio`, so the
`providers` entry can be omitted when the credentials file has `account_sid`
and `auth_token` under `twilio:`. Telnyx and Vonage work the same way under
`telnyx:` and `vonage:`.

`callbacks_url` is the public URL of the engine mount. With it set, every
message asks the provider to post delivery status back, and each
`Smswire::Delivery` row moves from `pending` to `delivered` or `failed`.

## Write a messenger

```
bin/rails generate smswire:messenger Order shipped
```

```ruby
# app/messengers/order_messenger.rb
class OrderMessenger < ApplicationMessenger
  def shipped(user)
    @order = params[:order]
    text to: user
  end
end
```

```erb
<%# app/views/order_messenger/shipped.text.erb %>
Order <%= @order.number %> has shipped. Track it: <%= order_url(@order) %>
```

`text to:` accepts an E.164 string or any object with `phone_number`. Use
`config.recipient_resolver` if your column is named differently. URL helpers
use `Rails.application.routes.default_url_options`, so set a host there.

Send it:

```ruby
OrderMessenger.with(order:).shipped(user).deliver_later
```

`deliver_later` is the right default. `deliver_now` runs the pipeline inline
and returns a `Smswire::Result`:

```ruby
result = OrderMessenger.with(order:).shipped(user).deliver_now
result.status        # :accepted, :failed, :duplicate, :rejected_opted_out, ...
result.delivery      # the Smswire::Delivery row
```

## Preview it

Open `http://localhost:3000/smswire/previews`. The generator wrote a preview
in `test/messengers/previews/order_messenger_preview.rb`; point it at real
records:

```ruby
class OrderMessengerPreview < Smswire::Preview
  def shipped
    OrderMessenger.with(order: Order.last).shipped(User.first)
  end
end
```

Each preview shows the message in a phone frame with its encoding, segment
count, and remaining characters, and names any character that forces UCS-2,
which cuts a segment from 160 characters to 70. The inbox at
`/smswire/inbox` shows what development sent and lets you simulate a reply
such as STOP.

## Test it

```ruby
class OrderTest < ActiveSupport::TestCase
  include Smswire::TestHelper

  test "shipping texts the customer" do
    assert_sms_delivered(to: users(:ada).phone_number, messenger: OrderMessenger, body: /has shipped/) do
      orders(:one).ship!
    end
  end
end
```

Inside the block, `deliver_later` jobs are performed. RSpec users can
`require "smswire/rspec"` for `deliver_sms` and `have_enqueued_sms`.

## Point the provider at the webhooks

| Webhook | URL |
|---|---|
| Delivery status | sent automatically per message when `callbacks_url` is set |
| Incoming messages | `https://app.example.com/smswire/inbound/<provider>` |

Incoming messages are needed for STOP, START, and HELP handling. Read the
[compliance primer](compliance.md) before sending marketing messages.

## Before production

- Set `config.default_provider` and real credentials.
- Run `Smswire.verify_credentials!` from a boot check or health endpoint.
- In staging, register `Smswire::Interceptors::Allowlist` so only your team's
  numbers receive messages.
- Register your sender with the carriers: 10DLC brand and campaign
  registration for US long codes, or toll-free verification.
