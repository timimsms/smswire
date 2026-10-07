# Smswire

> The production SMS layer for Rails that Noticed and twilio-ruby both leave to you.

Smswire gives Rails applications Action Mailer-style messenger classes and
templates for SMS, a provider-agnostic message object, persisted deliveries
with provider status callbacks, consent and keyword handling (STOP / HELP /
START), quiet hours, retries with a transient-vs-permanent error taxonomy,
development sandboxing, previews, and test helpers.

It complements [Noticed](https://github.com/excid3/noticed) by shipping a
`Noticed::DeliveryMethods::Smswire` adapter, and it works standalone for apps
that do not need a notification inbox.

**Status:** specification stage. Nothing is published yet.

- [Scoped specification](docs/SPEC.md)

## License

MIT.
