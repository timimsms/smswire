# Smswire: Scoped Specification

> The production SMS layer that Noticed and twilio-ruby both leave to you.

Status: draft for review. Sequencing is expressed as ordered phases with
acceptance criteria. No calendar estimates are included by design.

---

## 1. Purpose and positioning

Rails has no first-party SMS framework. In practice, Rails apps in 2026 send
SMS one of two ways:

1. **Directly through a provider SDK** (twilio-ruby at ~136M downloads), with
   phone normalization, consent, retries, status tracking, and dev safety
   hand-rolled per app.
2. **Through Noticed** (~7M downloads), where SMS is one of a dozen delivery
   channels and is implemented as a ~45-line HTTP post with a message string.

Everything that makes SMS hard in production sits between those two layers and
is owned by nobody:

| Concern | twilio-ruby | Noticed | Smswire |
|---|---|---|---|
| Mailer-style classes and templates | no | no (inline lambda / params) | yes |
| Preview UI with segment and encoding display | no | no | yes |
| E.164 normalization and validation | no | no | yes |
| Provider-agnostic message object | no | no (per-provider payloads) | yes |
| Persisted delivery record with provider ID and status | no | requested since 2021, not built | yes |
| Status-callback endpoint and signature verification | SDK helpers only | no | yes |
| Consent store, STOP/HELP/START keyword handling | no | no | yes |
| Quiet hours and per-recipient rate limits | no | no | yes |
| Retries with transient vs. permanent error taxonomy | no | unanswered request | yes |
| Dev/staging interceptor (sandbox, allowlist, local inbox) | no | no | yes |
| Test helpers and assertions | no | requested, not built | yes |
| Notification inbox, fan-out, multi-channel | no | **yes** | no (delegates to Noticed) |

Smswire is a **complement** to Noticed, not a competitor. It ships a Noticed
delivery method so Noticed users get all of the above by changing one line.
It is also useful standalone for apps that do not need an inbox.

## 2. Goals

- Make sending a compliant, observable SMS from Rails as ergonomic as sending
  an email with Action Mailer.
- Own the full outbound lifecycle: compose, normalize, authorize (consent),
  deliver, track, retry, report.
- Own the minimum inbound surface needed for compliance: delivery status
  callbacks and opt-out / help / opt-in keywords.
- Be provider-agnostic with a small adapter contract and zero provider SDK
  dependencies in the core gem.
- Be safe by default in non-production environments.
- Be testable without network access.

## 3. Non-goals

- A notification inbox, read/unread tracking, or multi-channel fan-out. That
  is Noticed.
- Email, push, chat, or voice delivery.
- Two-way conversational messaging, chat UIs, or inbound message routing beyond
  compliance keywords. (The inbound adapter contract will allow an app to build
  this on top, but Smswire does not ship it.)
- Marketing campaign management, audience segmentation, or scheduling UIs.
- Carrier registration workflows (10DLC brand/campaign registration, toll-free
  verification). Smswire exposes the fields these require but does not
  automate the registrations.
- Replacing provider SDKs for non-messaging APIs (voice, verify, lookup).

## 4. Prior art

| Project | State | What to borrow | What to avoid |
|---|---|---|---|
| Action Mailer (Rails) | core | Class-per-concern, `with(params)`, `deliver_now`/`deliver_later`, interceptors and observers, previews, `deliveries` test array | Nothing; this is the ergonomic target |
| Noticed 3.x | active, 0 open issues | Zero-dependency HTTP client, `error_handler` lambda, Rails credentials defaults, WebMock-based tests | Per-provider payload shapes, always-async-only delivery |
| Textris | dead since 2019 | Phony-based E.164 handling, ActiveJob delivery, email proxy for inspection | Provider SDK dependencies, unmaintained |
| action_smser | alive, tiny | Delivery reports table, gateway status-callback endpoints, resend from report | 2012-era config style, DelayedJob coupling |
| short_message (2026) | alive, single provider | Delivery status callbacks, metadata persistence as a Rails engine | Hard-wired to one provider |
| sms_safe | dead | The interceptor idea: redirect or block in non-prod | Nothing else to borrow |
| Twilio Messaging API | n/a | `StatusCallback`, `MessagingServiceSid`, error code taxonomy, signature verification scheme | Nothing |

## 5. Naming and distribution

### Why not keep `actionmessenger`

- `action_messenger` (underscore) is already a published gem by another author
  (Slack-style delivery, 2019, ~16k downloads). The constant `ActionMessenger`
  and `require "action_messenger"` would collide in any app that has both, and
  rubygems search would surface both side by side.
- Four unrelated GitHub repos already use the name, including one for XMPP.
- The `Action*` prefix implies Rails core. Third-party use is tolerated but
  invites confusion with Action Mailbox and Action Text.
- The existing repo has no users, no stars of note, and a dead lockfile. There
  is nothing to preserve beyond the MIT license.

### Shortlist (checked on this date against rubygems.org, GitHub, and DNS)

| Name | Gem | GitHub org/handle | Repos with exact name | `.dev` | `.io` | `.com` |
|---|---|---|---|---|---|---|
| **smswire** | available | available | none | unresolved | unresolved | parked for sale |
| textable | available | available | none | unresolved | not checked | in use |
| smsable | available | available | none | unresolved | not checked | not checked |
| actionmessenger | available (but `action_messenger` taken) | available | 4 | unresolved | not checked | in use |
| textkit / smskit | available | **taken** | several, active | n/a | n/a | n/a |

**Recommendation: `smswire`.** It says exactly what it is, has zero collisions
on gem, org, or repo, and the `.dev` and `.io` domains do not resolve. Module
name `Smswire`, Noticed adapter `Noticed::DeliveryMethods::Smswire`.

"Unresolved" in DNS is a signal, not proof of availability. Confirm with a
registrar before buying.

### Registration checklist

Perform in this order, since the first two are free and instant:

1. Create the repo `timimsms/smswire` (done; an org can be created or the repo moved later).
2. Push a `0.0.1.pre` gem to rubygems.org to reserve the name, with MFA
   enabled on the account and the `allowed_push_host` metadata set.
3. Register `smswire.dev` (and `smswire.io` if desired).
4. Archive `timimsms/actionmessenger` with a README pointer to the new project.

## 6. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ App code                                                             │
│   OrderMessenger.with(order:).shipped(user).deliver_later            │
│   Noticed: deliver_by :smswire, messenger: "OrderMessenger", ...     │
└───────────────┬──────────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────┐   ┌────────────────────────────────────┐
│ Smswire::Base (Messenger)    │   │ Smswire::Preview (dev route)       │
│  - default from:, sender:    │   │  - renders body, segments, encoding│
│  - text(to:, body:|template) │   │  - phone-frame + raw view          │
│  - renders app/views/...erb  │   └────────────────────────────────────┘
└───────────────┬──────────────┘
                │ returns
┌───────────────▼──────────────────────────────────────────────────────┐
│ Smswire::Message (value object, serializable)                        │
│  to, from, body, media_urls, messenger, action, params, metadata,    │
│  idempotency_key, scheduled_at, segments, encoding                   │
│  #deliver_now  #deliver_later(wait:, queue:, priority:)              │
└───────────────┬──────────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────────────┐
│ Delivery pipeline (Smswire::Pipeline)                                │
│  1. normalize    recipient -> E.164 (or reject)                      │
│  2. authorize    consent check, quiet hours, rate limit, allowlist   │
│  3. persist      Smswire::Delivery row (status: pending)             │
│  4. intercept    interceptors may mutate/cancel (dev sandbox lives   │
│                  here)                                               │
│  5. send         Provider#deliver(message) -> Receipt                │
│  6. record       provider_id, status: accepted|failed, error_code    │
│  7. observe      observers + ActiveSupport::Notifications             │
└───────────────┬──────────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────┐   ┌────────────────────────────────────┐
│ Providers (adapters)         │   │ Smswire::Engine (mounted routes)   │
│  twilio  telnyx  vonage      │◄──┤  POST /smswire/status/:provider    │
│  test    log     null        │   │  POST /smswire/inbound/:provider   │
│  (later: sinch bandwidth sns)│   │  GET  /smswire/previews (dev only) │
└──────────────────────────────┘   │  GET  /smswire/inbox    (dev only) │
                                   └────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────────┐
│ Persistence                                                          │
│  smswire_deliveries   smswire_consents   smswire_inbound_messages    │
└──────────────────────────────────────────────────────────────────────┘
```

### 6.1 Messenger classes

Mirror Action Mailer closely so the mental model transfers:

```ruby
# app/messengers/order_messenger.rb
class OrderMessenger < Smswire::Base
  default from: :transactional          # named sender, see 7.3
  default category: :transactional      # drives consent rules

  def shipped(user)
    @order = params[:order]
    text to: user, body: nil            # renders app/views/order_messenger/shipped.text.erb
  end

  def verification_code(phone, code)
    @code = code
    text to: phone, category: :otp, idempotency_key: "otp:#{phone}:#{code}"
  end
end
```

- `to:` accepts an E.164 string, any object responding to `phone_number`, or
  a `Smswire::Recipient`. Resolution is configurable (see 7.2).
- `text` returns a `Smswire::Message`. Nothing is sent until `deliver_now` or
  `deliver_later` is called, exactly like `mail`.
- Templates live at `app/views/<messenger_name>/<action>.text.erb`. I18n via
  `t(".key")` scoped the same way Action Mailer scopes it.
- Body whitespace is cleaned with `body_whitespace = :strip` by default:
  trailing spaces on each line are removed, three or more newlines collapse to
  two, and the ends are stripped. `:squish` and `:preserve` are the
  alternatives. Layouts are supported, which suits a shared opt-out footer.
  Rendering computes `segments` and `encoding` (GSM-7 vs. UCS-2) on the
  message so previews, logs, and callbacks can report them.
- `default` supports `from`, `category`, `provider`, `messaging_service`,
  `metadata`, `validity_period`. A named sender is given as `from: :name`.
  Quiet hours and rate limits are set per category, not per messenger.

### 6.2 Message object

`Smswire::Message` is a plain Ruby value object, serializable through
ActiveJob (GlobalID for the recipient object, primitives for the rest). It
exposes:

- `deliver_now` runs the pipeline inline and returns a `Smswire::Result`
  (status, message, receipt, error). From Phase 2 the result also carries the
  persisted `Smswire::Delivery`.
- `deliver_later(wait:, wait_until:, queue:, priority:)` enqueues
  `Smswire::DeliveryJob` with the messenger name, action, params, and
  arguments, like Action Mailer. Arguments must be ActiveJob-serializable.
  The job re-runs the action and the pipeline, so consent and quiet
  hours are evaluated at send time, not enqueue time.
- `segments`, `encoding`, `length` computed at render.
- `idempotency_key` defaults to a digest of messenger, action, recipient, and
  body. The pipeline refuses a duplicate key inside the configured dedupe
  window.

### 6.3 Delivery pipeline

Each step is a small object with a single `call(message, context)`. Steps can
halt with a typed outcome so callers and observers can distinguish:

- `:rejected_invalid_number`
- `:rejected_no_consent`
- `:rejected_opted_out`
- `:deferred_quiet_hours` (re-enqueued for the next allowed window)
- `:deferred_rate_limited`
- `:suppressed_by_interceptor` (dev sandbox, allowlist)
- `:rejected_empty_body` (no body and no media)
- `:skipped` (the action returned without calling `text`)
- `:duplicate`
- `:accepted` / `:failed`

Interceptors and observers use the Action Mailer contract:

```ruby
Smswire.register_interceptor(MyInterceptor)  # #delivering_sms(message) may mutate or cancel
Smswire.register_observer(MyObserver)        # #delivered_sms(delivery)
```

### 6.4 Provider adapter contract

```ruby
module Smswire::Providers
  class Base
    def initialize(config)                       # from Smswire.config.providers[:name]
    def deliver(message) -> Receipt              # Receipt(provider_id:, status:, raw:, segments:, price:)
    def parse_status_callback(request) -> StatusUpdate   # StatusUpdate(provider_id:, status:, error_code:, raw:)
    def parse_inbound(request) -> InboundMessage         # InboundMessage(from:, to:, body:, provider_id:, raw:)
    def verify_signature!(request)               # raises Smswire::SignatureError
    def capabilities -> Set[:mms, :status_callbacks, :inbound, :scheduling, :messaging_services]
  end
end
```

Normalized status vocabulary across providers:
`queued`, `accepted`, `sent`, `delivered`, `undelivered`, `failed`, `read`
(where supported). Each adapter maps provider-specific codes to this vocabulary
and preserves the raw code.

Error taxonomy raised by `deliver`:

- `Smswire::TransientError` (5xx, timeouts, provider rate limits) → retried
- `Smswire::PermanentError` (invalid number, blocked, unsubscribed at carrier,
  bad credentials) → not retried, delivery marked failed, optional consent
  update (e.g. carrier opt-out → mark opted out)
- `Smswire::ThrottledError` (subclass of Transient with `retry_after`)

Initial adapters: `twilio`, `telnyx`, `vonage`, plus `test`, `log`, `null`.
Later: `sinch`, `bandwidth`, `aws_sns`, `plivo`, `messagebird`.

All adapters use Net::HTTP (or a tiny shared client as in Noticed). No
provider SDKs are runtime dependencies. Bodies are never logged.

Adapter notes:

- **Twilio** signs webhooks with HMAC-SHA1 over the URL and sorted POST
  parameters. Messaging services map to `MessagingServiceSid`.
- **Telnyx** signs webhooks with Ed25519 over `<timestamp>|<raw body>`,
  verified against the account public key, with a five-minute timestamp
  tolerance. Messaging services map to `messaging_profile_id`. A messaging
  profile can post every event to one URL, so both webhook endpoints accept
  both event kinds. Telnyx takes no validity period here, so it is ignored.
- **Vonage** (SMS API) signs webhooks with sorted `&key=value` pairs using the
  configured `signature_secret` and `signature_method` (`md5hash`, Vonage's
  default, or an HMAC). Its send error 7, "number barred," also covers blocks
  other than opt-outs, so it maps to `:unroutable` and never records an
  opt-out. Long messages are billed as several parts with separate ids; the
  receipt keeps the first, so receipts for later parts are acknowledged but
  not matched. The API does not name a price currency.

**Contract suite.** `Smswire::ProviderContract` is a Minitest module shipped
in the gem. An adapter's test includes it and defines hooks that stub the
provider for each outcome (`success`, `invalid_number`, `opted_out`,
`authentication`, `throttled`, `server_error`, `timeout`) and build signed
status and inbound requests. The suite checks receipts, the normalized status
vocabulary, the error taxonomy and reasons, a full pipeline send, and, for
declared capabilities, callback parsing and signature rejection. An adapter
whose provider cannot report opt-outs at send time says so with
`contract_reports_opt_outs?` rather than guessing.

### 6.5 Persistence

Three tables, installed by `rails g smswire:install`.

**smswire_deliveries**

| column | type | notes |
|---|---|---|
| id | app default | follows the app's generator `primary_key_type`, like Active Storage |
| messenger, action | string | e.g. `OrderMessenger`, `shipped` |
| to_number, from_number | string | E.164; named to avoid the reserved words `to` and `from` |
| messaging_service | string | |
| recipient_type, recipient_id | string, app key type | polymorphic, optional; set only for persisted Active Record recipients |
| category | string | `transactional`, `otp`, `marketing`, custom |
| body | text | nullable; `store_bodies` config defaults to true, with a per-category override so OTP bodies can be excluded |
| segments, encoding | integer, string | |
| provider | string | |
| provider_id | string | indexed, unique with provider |
| status | string | `pending`, `suppressed`, then the normalized vocabulary; only moves forward |
| error_code, error_message | string, text | provider raw code + normalized message |
| idempotency_key | string | unique index; cleared on the old row when the dedupe window expires |
| price_amount, price_currency | decimal, string | if the provider reports it |
| metadata | json | app-supplied |
| scheduled_at, sent_at, delivered_at, failed_at | datetime | |
| attempts | integer | |
| claimed_at | datetime | send claim; released on transient errors, expires after two minutes |
| status_updated_at | datetime | |
| created_at, updated_at | datetime | |

**smswire_consents**

| column | type | notes |
|---|---|---|
| phone | string | E.164, unique with `scope` |
| scope | string | default `"default"`; allows per-category or per-sender consent |
| status | string | `opted_in`, `opted_out`, `pending`, `unknown` |
| source | string | `keyword`, `web_form`, `import`, `api`, `carrier` |
| opted_in_at, opted_out_at | datetime | |
| last_keyword, last_keyword_at | string, datetime | |
| metadata | json | consent evidence (IP, form id, copy shown) for audit |

**smswire_inbound_messages**

| column | type | notes |
|---|---|---|
| provider, provider_id | string | unique together |
| from, to | string | E.164 |
| body | text | |
| keyword | string | normalized: `stop`, `help`, `start`, or null |
| handled_at | datetime | |
| raw | json | |

Models are plain ActiveRecord, namespaced, and extendable via
`Smswire.config.delivery_class` etc. for apps that need custom columns.

### 6.6 Consent and compliance primitives

Smswire provides the mechanisms; the app remains responsible for policy and
legal compliance. Defaults follow CTIA messaging principles so an app that does
nothing is at least not wrong:

- **Keyword handling** on inbound: opt-out set (`STOP`, `STOPALL`,
  `UNSUBSCRIBE`, `CANCEL`, `END`, `QUIT`, `OPTOUT`, `REVOKE`), help set
  (`HELP`, `INFO`), opt-in set (`START`, `YES`, `UNSTOP`). A keyword matches
  only as the whole message, ignoring case, whitespace, and surrounding
  punctuation. Configurable. `STOPALL` opts out of every consent scope.
- **Consent scopes**: consent is stored per phone number and scope. A
  sender's `consent_scope` (default `"default"`) decides the scope for both
  outbound checks and inbound keywords to that sender's number.
- **Auto-replies** for each keyword are templated and configurable; the
  opt-out confirmation is sent even if consent is already `opted_out`,
  through the built-in `compliance` category, which skips consent checks.
  When the provider already replied, as Twilio Advanced Opt-Out signals with
  `OptOutType`, consent is recorded and no second reply is sent.
- **Consent gating** by category: `otp` and `transactional` default to
  `allow_unless_opted_out`; `marketing` defaults to `require_opted_in`.
  Apps can define categories and rules.
- **Quiet hours** per category, evaluated in the recipient's time zone when
  resolvable (recipient object responds to `time_zone`), otherwise in a
  configured default. Deferred messages re-enqueue for the next window,
  from both `deliver_now` and `deliver_later`. The marketing default is the
  US federal TCPA window, 9pm to 8am; some states are stricter.
- **Rate limits** per recipient per category over a sliding window, counted
  from `smswire_deliveries` so they survive restarts and are shared across
  processes. Failed and suppressed deliveries do not count. Concurrent sends
  can exceed the limit briefly.
- **Carrier opt-out sync**: a permanent error with an unsubscribed/blocked
  code updates the consent row to `opted_out` with `source: carrier`.

### 6.7 Development and test safety

Environment defaults:

| env | provider | interceptor |
|---|---|---|
| development | `log` | local inbox UI at `/smswire/inbox` |
| test | `test` | none; `Smswire::Testing.deliveries` array |
| staging | real | `Smswire::Interceptors::Allowlist` (configured numbers only) |
| production | real | none |

`Smswire::TestHelper` for Minitest and matchers for RSpec:

```ruby
assert_sms_delivered to: "+15551234567", messenger: OrderMessenger, action: :shipped
assert_enqueued_sms(OrderMessenger, :shipped) { Order.ship!(order) }
assert_no_sms_delivered
```

Previews mirror Action Mailer previews, at `test/messengers/previews/` or
`spec/messengers/previews/`, served at `/smswire/previews` in development.
Each preview renders the body in a phone frame, shows segment count, encoding,
character budget remaining, and the resolved sender, and names any characters
that force UCS-2. Previews build the message without running interceptors or
sending.

The development inbox at `/smswire/inbox` lists recent deliveries and inbound
messages, and has a form that simulates a reply such as STOP through the same
handling as the inbound webhook.

Both tools are enabled with `config.smswire.show_previews` and
`config.smswire.show_inbox` in `config/application.rb` or an environment
file, and default to true in development only. Preview paths are registered
for autoloading before initializers run, as Action Mailer does, so they cannot
be set from `config/initializers`.

The allowlist interceptor either suppresses messages to unlisted numbers or,
with `redirect_to:`, reroutes them to one number with the original recipient
prefixed to the body.

### 6.8 Observability

`ActiveSupport::Notifications` events, all with the delivery id and never the
body:

- `deliver.smswire` (duration, provider, status, segments)
- `reject.smswire` (reason)
- `status_update.smswire`
- `inbound.smswire` (keyword)
- `retry.smswire`

A `Smswire::LogSubscriber` is attached by default. A Rails health check for
provider credentials is exposed as `Smswire.verify_credentials!`.

### 6.9 Noticed integration

Shipped inside the gem, loaded only when `Noticed` is defined:

```ruby
class OrderShippedNotifier < Noticed::Event
  deliver_by :smswire do |config|
    config.messenger = "OrderMessenger"
    config.action    = :shipped
    config.params    = -> { {order: record} }
    # Optional: config.args, config.kwargs, config.params, config.sms_queue;
    # Noticed options such as config.wait and config.if apply to its own job
  end
end
```

The adapter builds the message through the messenger, so templates, consent,
quiet hours, persistence, and status tracking all apply. It always uses
`deliver_later`, so Smswire's retry policy applies even though Noticed's own
delivery jobs do not retry. The messenger receives the event params plus
`notification`, `record`, and `recipient`, and the default action argument is
the recipient. Each `Smswire::Delivery` records `noticed_notification_id` and
`noticed_event_id` in its metadata, which joins the two records without a
schema dependency between the gems.

### 6.10 Generators

- `rails g smswire:install` — migrations, initializer with commented config,
  route mount, credentials scaffold hints.
- `rails g smswire:messenger Order shipped delivered` — class, templates,
  preview, test.
- `rails g smswire:provider Acme` — adapter skeleton in `app/sms_providers`,
  a test that runs `Smswire::ProviderContract` against it with WebMock stubs,
  and a registration line in the initializer. The generated pair passes the
  contract as generated.

## 7. Configuration surface

```ruby
# config/initializers/smswire.rb
Smswire.configure do |c|
  c.default_provider = :twilio
  c.providers = {
    twilio: { account_sid: Rails.application.credentials.dig(:twilio, :account_sid),
              auth_token:  Rails.application.credentials.dig(:twilio, :auth_token) },
    telnyx: { api_key: ... }
  }

  c.senders = {                       # 7.3 named senders
    transactional: { number: "+15550001111", provider: :twilio, messaging_service: "MG..." },
    marketing:     { number: "+15550002222", provider: :telnyx }
  }

  c.recipient_resolver = ->(obj) { obj.respond_to?(:mobile_phone) ? obj.mobile_phone : obj.phone_number }
  c.default_region = "US"             # for parsing national-format numbers
  c.phone_validator = :auto            # :phonelib, or :e164 (built-in, no extra dependency)

  # Merged per key over the shipped defaults:
  #   otp:           { consent: :allow_unless_opted_out, store_body: false }
  #   transactional: { consent: :allow_unless_opted_out }
  #   marketing:     { consent: :require_opted_in, quiet_hours: "21:00".."08:00" }
  #   compliance:    { consent: :none }   # keyword auto-replies
  c.categories = {
    marketing: { rate_limit: {max: 3, per: 1.day} }   # exceed: :defer (default) or :reject
  }
  c.default_time_zone = "America/New_York"   # quiet hours when the recipient has no time_zone
  c.program_name = "Acme Alerts"             # used in keyword auto-replies

  c.dedupe_window = 10.minutes
  c.retry_attempts = 5                # total attempts for transient errors; polynomial backoff
  c.store_bodies = true
  c.body_whitespace = :strip          # or :squish, :preserve
  c.deliver_later_queue = :default
  # Smswire.register_interceptor / register_observer, per environment
  c.callbacks_url = "https://app.example.com/smswire"  # engine mount URL; builds StatusCallback URLs
  c.persist_deliveries = true
  c.verify_callback_signatures = true
end
```

### 7.1 Dependency policy

Runtime: `actionpack` (for AbstractController and Action View rendering),
`activejob`, `activesupport`, `railties` (all `>= 7.1, < 9`), and `zeitwerk`.
`activerecord` joins in Phase 2 with the persistence tables. Optional: `phonelib` (soft dependency, detected at
load). No provider SDKs. No HTTP client gem.

### 7.2 Recipient resolution

Order: `Smswire::Recipient` instance → string → object responding to the
configured resolver → object responding to `phone_number`. Resolution failures
raise `Smswire::UnresolvableRecipient` at `text` time, not at delivery time,
so they surface in tests.

### 7.3 Named senders

A sender bundles a from-number or messaging service, a provider, and defaults.
Messengers reference senders by name so number rotation and provider migration
are a config change, not a code change.

## 8. Compatibility targets

- Ruby `>= 3.2`
- Rails `>= 7.1` (matches Noticed 3.x so the integration is always valid)
- Databases: PostgreSQL, MySQL, SQLite (CI matrix)
- ActiveJob adapters: any; test against `async`, `solid_queue`, `sidekiq`
- CI: GitHub Actions, matrix over Ruby × Rails × DB

## 9. Sequencing

Phases are ordered by dependency. Each has acceptance criteria that gate the
next. No phase includes a calendar estimate.

### Phase 0: Reservation and skeleton

- Register org, repo, gem name (pre-release push), domain.
- Gem skeleton with Zeitwerk, engine, dummy app, CI matrix, RuboCop,
  Standard or similar, `CHANGELOG.md`, MIT license.
- Accept: `bundle exec rake` green on all matrix cells; `0.0.1.pre` on
  rubygems.org.

### Phase 1: Core messenger and delivery

- `Smswire::Base`, `Message`, template rendering, segment/encoding calc.
- Pipeline with normalize, intercept, send, observe (no persistence yet).
- Providers: `test`, `log`, `null`, `twilio`.
- `deliver_now`, `deliver_later`, `DeliveryJob` with retry taxonomy.
- `TestHelper`, RSpec matchers, interceptors and observers.
- Accept: a dummy-app messenger renders a template, sends through Twilio
  against WebMock, and the full test-helper surface passes.
- Status: implemented. Built-in phone validation accepts E.164 input and
  North American national formats; other national formats need `phonelib`.

### Phase 2: Persistence and status tracking

- Migrations and models for deliveries.
- Engine route for status callbacks with signature verification (Twilio).
- Idempotency key and dedupe window.
- `ActiveSupport::Notifications` + log subscriber.
- Accept: a delivery row moves `pending → accepted → delivered` from a
  replayed Twilio callback fixture; duplicate sends inside the window are
  refused.
- Status: implemented. Rows are claimed atomically before sending, so a
  transient-error retry reuses its row and two workers never send the same
  claimed message. Callback URLs carry the delivery id to survive the race
  between the provider's response and its first callback. Rejected messages
  are not persisted; they are reported through `reject.smswire`.

### Phase 3: Consent and inbound keywords

- Consents and inbound tables, inbound route, keyword parser, auto-replies.
- Category rules, quiet hours with deferral, per-recipient rate limits.
- Carrier opt-out sync from permanent errors.
- Accept: `STOP` from a fixture request flips consent and triggers a
  confirmation; a `marketing` send to a non-opted-in number is rejected with
  `:rejected_no_consent`; a quiet-hours send is re-enqueued for the next
  window.
- Status: implemented. Inbound webhooks are recorded once per provider
  message id, so retries never double-process a keyword. Observers can
  implement `sms_received(inbound_message)` to build two-way messaging.

### Phase 4: Developer experience

- Previews route and UI, local inbox UI, generators, allowlist interceptor.
- Accept: `rails g smswire:messenger` output renders in previews with correct
  segment and encoding display; development deliveries appear in the inbox.
- Status: implemented.

### Phase 5: Breadth

- Providers: `telnyx`, `vonage`; contract test suite that every adapter must
  pass.
- `Noticed::DeliveryMethods::Smswire`.
- Accept: the same dummy-app messenger passes the contract suite against all
  three real adapters (WebMock) and delivers through a Noticed notifier.
- Status: implemented. Webhook endpoints share one controller, so a provider
  that sends every event to one URL is routed by event kind.

### Phase 6: Release

- Guides: getting started, migrating from direct twilio-ruby, migrating from
  Noticed `twilio_messaging`, compliance primer, provider authoring.
- `1.0.0` once the adapter contract and schema are considered stable.
- Status: guides written in `docs/guides`, with a test that every setting,
  constant, and generator they name exists. Compliance research changed the
  defaults: HELP replies include `support_contact`, the opt-out confirmation
  follows CTIA wording, keywords ignore spaces ("opt out"), and
  `opt_out_all_scopes` prepares for the FCC revoke-all provision.
  `Smswire.verify_credentials!` from section 6.8 is implemented. Release
  steps are in `RELEASING.md`; publishing 1.0 is left to the maintainer.

### Known limitations at 1.0

- Free-text opt-outs ("please stop texting me") are stored but not acted on;
  the compliance guide shows an observer for review.
- Rate limits can be exceeded briefly by concurrent sends.
- Vonage receipts for the second and later parts of a long message are
  acknowledged but not matched to the delivery.
- Vonage uses the SMS API, not the newer Messages API, and has no MMS.
- Telnyx ignores `validity_period`.

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| SMS volume for app notifications keeps shifting to push and WhatsApp | Adapter contract is channel-agnostic enough to add WhatsApp via Twilio/Meta later; Noticed integration keeps Smswire relevant as one channel among many |
| Compliance defaults implying legal guarantees | Documentation states primitives-not-policy clearly; defaults are conservative; consent evidence is stored for audit |
| Single maintainer, like Noticed | Small core, adapter contract with conformance tests so community adapters do not need core changes |
| Schema churn before 1.0 | Pre-1.0 migrations are versioned and documented; `store_bodies` and custom-column hooks reduce pressure to fork models |
| `phonelib` data size | Soft dependency with a regex fallback; documented trade-off |

## 11. Open decisions

Decisions 1 to 3 are settled. Decisions 4 to 6 are proposed as settled in
Phase 6, matching the implementation; confirm them before tagging 1.0.

1. **Name.** `smswire` is recommended; `textable` and `smsable` are the
   fallbacks. Decide before the pre-release push.
2. **Body storage default.** Settled in Phase 2: `store_bodies = true`, with
   `categories: { otp: { store_body: false } }` as the shipped default.
3. **UUID vs. bigint** primary keys. Settled in Phase 2: the migration follows
   the app's generator `primary_key_type`, so both work without a choice here.
4. **Phone validation.** Proposed: both. The built-in validator handles E.164
   input and North American national formats with no dependency; `phonelib`
   is used automatically when it is in the bundle, for other regions.
5. **`deliver_now` in production.** Proposed: allowed without a warning. It
   returns a `Result`, which is useful for interactive flows such as
   verification codes. Guides recommend `deliver_later`, and the Noticed
   adapter always uses it.
6. **MMS in 1.0.** Proposed: a capability, not a requirement. Twilio and
   Telnyx send `media_urls`; Vonage's SMS API does not and does not declare
   `:mms`. The contract does not require it.
