# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Guides: getting started, migrating from twilio-ruby, migrating from
  Noticed's Twilio method, compliance primer, and writing a provider.
- `Smswire.verify_credentials!` with checks for Twilio, Telnyx, and Vonage.
- `support_contact` for HELP replies and `opt_out_all_scopes`.
- Release workflow publishing to RubyGems with trusted publishing.

### Changed

- Keyword replies follow CTIA guidance: the opt-out confirmation says no
  further messages will be sent, and HELP names a support contact.
- Keywords ignore internal spaces and hyphens, so "opt out" and "stop all" match.
- Noticed adapter job options are `sms_queue` and `sms_priority`, so Noticed's
  own `wait` no longer delays a message twice.

- Telnyx adapter (Messaging API v2) with Ed25519 webhook verification.
- Vonage adapter (SMS API) with signed webhook verification for `md5hash` and
  HMAC methods.
- `Smswire::ProviderContract`, a shipped Minitest suite every adapter passes;
  the provider generator now writes a test that runs it.
- `Noticed::DeliveryMethods::Smswire` for `deliver_by :smswire`, loaded when
  Noticed is present.
- Webhook endpoints accept both status and inbound events, for providers that
  post everything to one URL.

- Messenger previews at `<mount>/previews` with a phone frame, encoding,
  segment count, remaining characters, and the characters that force UCS-2.
- Development inbox at `<mount>/inbox` listing deliveries and inbound
  messages, with a form that simulates replies through keyword handling.
- Generators: `smswire:install`, `smswire:messenger`, and `smswire:provider`.
- `Smswire::Interceptors::Allowlist` for staging, suppressing or redirecting
  messages to unlisted numbers.

- `Smswire::Consent` with per-sender consent scopes, evidence metadata, and
  `opt_in!`, `opt_out!`, `opt_out_everywhere!`, and `status_for`.
- Inbound webhook endpoint storing `Smswire::InboundMessage` once per
  provider message id, with STOP / START / HELP keyword handling,
  configurable auto-replies, and an `sms_received` observer hook.
- Category rules for consent, quiet hours, and rate limits, merged over
  shipped defaults. New outcomes `:rejected_opted_out`,
  `:rejected_no_consent`, `:rejected_rate_limited`, `:deferred_quiet_hours`,
  and `:deferred_rate_limited`; deferred messages re-enqueue themselves.
- Carrier opt-out errors record an opt-out with source `carrier`.

- `Smswire::Engine` with `smswire:install:migrations` and the
  `smswire_deliveries` table, following the app's primary key type.
- `Smswire::Delivery` records for every send, with atomic send claims,
  forward-only status, and retries that reuse their row.
- Deduplication of identical messages inside `dedupe_window`, returning
  `:duplicate`, with optional explicit `idempotency_key`.
- Status callback endpoint with Twilio signature verification and
  `sms_status_updated` observer hook. `callbacks_url` builds callback URLs.
- Per-category body storage, with `otp` bodies not stored by default.
- `Smswire::LogSubscriber` logging deliveries, rejections, and status
  updates with masked numbers and no bodies.

- `Smswire::Base` messenger classes with `default`, `with(params)`, `.text.erb`
  templates, layouts, I18n lazy lookup, and URL helpers.
- `Smswire::Message` with GSM-7 / UCS-2 encoding detection and segment counting.
- Delivery pipeline: E.164 normalization, empty-body rejection, interceptors,
  provider delivery, observers, and `ActiveSupport::Notifications` events.
- Providers: `twilio`, `log`, `test`, `null`, plus a registry for custom adapters.
- `deliver_now` returning `Smswire::Result`, and `deliver_later` through
  `Smswire::DeliveryJob` with transient retries and Retry-After handling.
- Named senders, recipient resolution, and optional `phonelib` support.
- `Smswire::TestHelper` for Minitest and RSpec matchers in `smswire/rspec`.
- CI matrix over Ruby 3.2 to 3.4 and Rails 7.1 to 8.1.

## [0.0.1.pre]

- Reserve the gem name. No functionality yet; see `docs/SPEC.md`.
