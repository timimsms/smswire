# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
