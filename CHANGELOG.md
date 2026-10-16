# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Before 1.0, minor versions may
include breaking changes, which are called out here.

## [Unreleased]

## [0.1.0] - 2026-10-15

First functional release. Requires Ruby 3.2+ and Rails 7.1 to 8.1.

### Messengers and delivery

- `Smswire::Base` messenger classes with `default`, `with(params)`, `.text.erb`
  templates, layouts, I18n lazy lookup, URL helpers, and named senders.
- `Smswire::Message` with GSM-7 / UCS-2 detection and segment counting.
- A delivery pipeline with E.164 normalization, consent checks, quiet hours,
  rate limits, deduplication, interceptors, and observers, returning a
  `Smswire::Result` with a typed status.
- `deliver_later` through `Smswire::DeliveryJob`, retrying transient errors
  with backoff and honoring `Retry-After`.

### Providers

- Twilio, Telnyx, and Vonage adapters over REST with no provider SDK, plus
  `log`, `test`, and `null` providers and a registry for custom adapters.
- Webhook signature verification for each provider: Twilio HMAC-SHA1, Telnyx
  Ed25519, and Vonage `md5hash` or HMAC.
- `Smswire::ProviderContract`, a Minitest suite every adapter passes.
- `Smswire.verify_credentials!` for boot checks and health endpoints.

### Persistence and tracking

- `Smswire::Engine` with `smswire:install:migrations` and tables for
  deliveries, consents, and inbound messages, following the app's primary
  key type.
- A `Smswire::Delivery` row for every send, with atomic send claims, retries
  that reuse their row, and forward-only status from provider callbacks.

### Consent and compliance

- `Smswire::Consent` with per-sender scopes and evidence metadata.
- STOP / START / HELP keyword handling with replies following CTIA guidance,
  including a `support_contact` in HELP replies.
- Category rules: `marketing` requires opt-in and observes 9pm to 8am quiet
  hours in the recipient's time zone. Carrier opt-out errors record opt-outs.

### Developer experience

- Previews at `<mount>/previews` and a development inbox at `<mount>/inbox`.
- Generators: `smswire:install`, `smswire:messenger`, and `smswire:provider`.
- `Smswire::TestHelper` for Minitest and RSpec matchers in `smswire/rspec`.
- `Smswire::Interceptors::Allowlist` for staging.
- `Noticed::DeliveryMethods::Smswire` for `deliver_by :smswire`.
- Guides in `docs/guides`.

### Known limitations

- Free-text opt-outs such as "please stop texting me" are stored but not
  acted on; the compliance guide shows how to review them.
- Concurrent sends can briefly exceed a rate limit.
- Vonage receipts for the second and later parts of a long message are not
  matched to the delivery, and Vonage has no MMS.
- Telnyx ignores `validity_period`.

## [0.0.1.pre] - 2026-10-08

- Reserve the gem name. No functionality.

[Unreleased]: https://github.com/timimsms/smswire/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/timimsms/smswire/compare/v0.0.1.pre...v0.1.0
[0.0.1.pre]: https://github.com/timimsms/smswire/releases/tag/v0.0.1.pre
