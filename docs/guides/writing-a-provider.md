# Writing a provider adapter

An adapter connects Smswire to one SMS API. It sends messages, classifies
errors, and optionally verifies and parses webhooks. Every adapter must pass
`Smswire::ProviderContract`, a Minitest suite shipped in the gem.

## Generate the skeleton

```
bin/rails generate smswire:provider Acme
```

This writes:

- `app/sms_providers/acme_provider.rb`, a working adapter for a fictional API;
- `test/sms_providers/acme_provider_test.rb`, which runs the contract against it;
- a `Smswire::Providers.register(:acme, "AcmeProvider")` line in the initializer.

The generated pair passes the contract as generated. Change the API calls,
error codes, and stubs together, running the test as you go.

## The adapter contract

```ruby
class AcmeProvider < Smswire::Providers::Base
  def deliver(message)          # => Smswire::Receipt, or raises
  def capabilities              # => Set of :mms, :status_callbacks, :inbound, :messaging_services, :scheduling
  def verify_credentials!       # => true, or raises; nil if unsupported

  # With :status_callbacks or :inbound:
  def verify_signature!(request, url:)   # raises Smswire::SignatureError
  def parse_status_callback(request)     # => Smswire::StatusUpdate, or nil if not a status event
  def parse_inbound(request)             # => Smswire::Inbound, or nil if not an inbound message
  def inbound_response                   # => [body, content_type], or nil for 204
end
```

`options` holds `Smswire.config.providers[:acme]` with symbol keys, and
`name` is the registered name.

### Sending

Read `message.to` (E.164), `from`, `messaging_service`, `body`,
`media_urls`, `validity_period`, and `status_callback_url`. Use
`Smswire::HTTP.post_form` or `post_json`; both turn network failures into
`TransientError` and never log bodies. Return `receipt(provider_id:, status:,
segments:, price_amount:, price_currency:, raw:)` with a status from the
normalized vocabulary: `:queued`, `:accepted`, `:sent`, `:delivered`,
`:undelivered`, `:failed`, `:read`.

### Errors

| Situation | Raise |
|---|---|
| network failure, timeout, 5xx | `Smswire::TransientError` (retried) |
| rate limit | `Smswire::ThrottledError.new(..., retry_after: seconds)` |
| retrying cannot help | `Smswire::PermanentError.new(..., reason:)` |
| missing credentials or settings | `Smswire::ConfigurationError` |

Pass `provider: name, provider_code:, http_status:, raw:` to error
constructors. Reasons are `:invalid_number`, `:opted_out`, `:unroutable`,
`:authentication`, and `:rejected`. Use `:opted_out` only for an error that
specifically means the recipient opted out, because Smswire records an
opt-out when it sees one. If the provider has no such error, define
`contract_reports_opt_outs?` as `false` in the test.

### Webhooks

Verify before parsing. Use constant-time comparison, such as
`ActiveSupport::SecurityUtils.secure_compare`, and reject stale timestamps
when the provider signs them. `url:` is the public URL the provider posted
to, rebuilt from `config.callbacks_url` when that is set.

Return `nil` from `parse_status_callback` for events that are not status
updates, and from `parse_inbound` for events that are not messages. The
engine tries both, so a provider that posts every event to one URL works.

## Contract hooks

```ruby
class AcmeProviderTest < ActiveSupport::TestCase
  include Smswire::TestHelper
  include Smswire::ProviderContract

  def contract_provider_name = :acme
  def contract_provider_options = {api_key: "test-key"}

  # Stub the API for :success, :invalid_number, :opted_out, :authentication,
  # :throttled, :server_error, and :timeout. Return the WebMock stub.
  def stub_contract_send(outcome, message) = ...

  # With :status_callbacks; status is :delivered or :undelivered.
  def contract_status_request(provider_id:, status:, signed: true) = ...

  # With :inbound.
  def contract_inbound_request(from:, to:, body:, signed: true) = ...
end
```

Build requests with `contract_request(url, params:)` for form posts or
`contract_request(url, body: json)` for JSON, plus `headers:`. Override
`contract_message` to run the contract with one of your own messengers.

The suite checks:

- the receipt, its provider id, and its status;
- a full pipeline send that records a delivery row;
- each permanent outcome's reason, and that throttling, server errors, and
  timeouts are retryable;
- for declared capabilities, that signed requests parse and verify and
  unsigned ones raise `SignatureError`, and that status and inbound events
  are not mistaken for each other.

The bundled Twilio, Telnyx, and Vonage adapters pass the same suite; their
tests in `test/provider_contract_test.rb` in the Smswire repository are
worked examples.

## Sharing an adapter

Publish it as a gem that depends on `smswire` and registers itself:

```ruby
# lib/smswire-acme.rb
require "smswire"
Smswire::Providers.register(:acme, "Smswire::Acme::Provider")
```
