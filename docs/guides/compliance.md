# Compliance primer

This primer explains what Smswire does for SMS compliance, what it leaves to
you, and which settings matter. It summarizes US rules and industry
guidance as of 2026 and is not legal advice. Have counsel review your
messaging program.

## The rules in brief

- **TCPA and FCC rules** govern automated texts in the US. Marketing texts
  need prior express written consent. Consumers may revoke consent by any
  reasonable means, and since April 11, 2025 a revocation must be honored
  within 10 days. One confirmation text is allowed after an opt-out; it must
  not contain marketing and may ask the person to clarify what they want to
  stop.
- **The FCC "revoke all" provision**, which makes an opt-out from one kind of
  message apply to all of a sender's unrelated messages, is delayed to
  January 31, 2027.
- **Quiet hours.** Federal rules restrict telemarketing outside 8am to 9pm in
  the recipient's local time. Several states are stricter.
- **CTIA Messaging Principles and Best Practices** are what carriers enforce.
  They expect opt-out keywords to work regardless of case or punctuation; one
  confirmation after an opt-out and then silence; HELP replies that name the
  brand and give a support contact; and consent specific to the program it
  was collected for.
- **Carrier registration.** US long codes need 10DLC brand and campaign
  registration. Toll-free numbers need verification. Unregistered traffic is
  filtered or blocked.

## What Smswire does

| Requirement | Smswire |
|---|---|
| Honor STOP-type replies | STOP, STOPALL, UNSUBSCRIBE, CANCEL, END, QUIT, OPTOUT (or "opt out"), and REVOKE opt the number out immediately |
| One confirmation, no marketing | one opt-out reply through the `compliance` category; deduplication blocks repeats inside 10 minutes |
| HELP reply with brand and contact | HELP and INFO reply with `program_name` and `support_contact` |
| Re-subscribe | START, YES, and UNSTOP opt back in |
| Refuse sends to opted-out numbers | every category except `compliance` checks consent first |
| Marketing needs opt-in | `marketing` requires `opted_in` consent |
| Quiet hours | `marketing` waits outside 9pm to 8am, recipient time |
| Carrier opt-outs | a provider "recipient opted out" error records an opt-out |
| Evidence | consent rows keep source, timestamps, last keyword, and your metadata |

## What you must do

1. **Collect and record opt-in** before marketing. Store the evidence:

   ```ruby
   Smswire::Consent.opt_in!(user.phone, source: :web_form,
     metadata: {ip: request.remote_ip, form: "checkout", copy: SMS_TERMS, at: Time.current.iso8601})
   ```

2. **Set your program name and support contact.**

   ```ruby
   config.program_name = "Acme Alerts"
   config.support_contact = "help@acme.example"
   ```

   Without a contact, HELP replies omit it and Smswire logs a warning.

3. **Route incoming messages to Smswire** at `/smswire/inbound/<provider>`.
   Without this, STOP replies never reach your app. If your provider handles
   opt-outs itself, such as Twilio Advanced Opt-Out, Smswire still records
   them and skips its own reply.

4. **Watch for free-text opt-outs.** Smswire matches keywords only when they
   are the whole message. "Please stop texting me" is stored but not acted
   on, yet it is a reasonable revocation. Review unmatched messages:

   ```ruby
   class OptOutReview
     def self.sms_received(message)
       return if message.keyword
       SupportTicket.create!(phone: message.from_number, body: message.body) if message.body.match?(/\b(stop|unsubscribe|remove me)\b/i)
     end
   end
   Smswire.register_observer(OptOutReview)
   ```

5. **Honor opt-outs from other channels.** When a customer opts out by email
   or phone, call `Smswire::Consent.opt_out!(phone, source: :support)`.

6. **Choose consent scopes deliberately.** By default STOP applies to the
   `consent_scope` of the number that received it, so two programs on two
   numbers keep separate consent. To make every STOP apply everywhere, as the
   FCC revoke-all provision will require across a sender's messages, set:

   ```ruby
   config.opt_out_all_scopes = true
   ```

7. **Check your categories.** Anything promotional must use
   `category: :marketing`. Transactional messages skip the opt-in
   requirement, so mislabeling a promotion as transactional defeats the
   checks.

8. **Set time zones.** Quiet hours use `recipient.time_zone` when the
   recipient object has one, and `config.default_time_zone` otherwise.

9. **Register with the carriers** and keep your messages consistent with the
   registered campaign: brand name in messages, opt-out instructions at least
   periodically, and content matching the sample messages.

## Settings reference

| Setting | Default | Notes |
|---|---|---|
| `enforce_consent` | `true` | turn off only if another system owns consent |
| `categories` | see README | merged per key over the shipped rules |
| `keywords` | the lists above | add synonyms, such as `ARRET` |
| `keyword_replies` | CTIA-style replies | `%{program}` and `%{contact}` are replaced; `nil` sends no reply |
| `program_name` | the app name | |
| `support_contact` | none | phone, email, or URL |
| `opt_out_all_scopes` | `false` | STOP applies to every scope |
| `default_time_zone` | `Time.zone` | for quiet hours |

## Sources

- [FCC consent revocation order, FCC 24-24](https://docs.fcc.gov/public/attachments/FCC-24-24A1.pdf)
- [FCC revocation rule effective April 11, 2025 (JD Supra)](https://www.jdsupra.com/legalnews/fcc-s-tcpa-consent-revocation-rule-8022288/)
- [Revoke-all provision delayed to January 31, 2027 (Wiley)](https://www.wiley.law/alert-FCC-Extends-Limited-Waiver-for-Part-of-the-TCPA-Consent-Revocation-Rule)
- [CTIA Messaging Principles summary (Bird)](https://bird.com/explained/compliance/what-are-the-ctia-messaging-principles)
- [Vonage 10DLC traffic compliance](https://api.support.vonage.com/hc/en-us/articles/8443130026140-10DLC-Traffic-compliance)
