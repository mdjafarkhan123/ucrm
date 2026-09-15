# Stage 5 — Signed inbound & status webhooks

Spec: `docs/communications-a2-implementation-plan.md` §5. Everything stays dark (cron inactive, no traffic)
until Stage 5 + the country launch gate pass.

## Split (each independently verifiable)

- **5A — Status callbacks (outbound delivery outcomes). DONE (this session, verified).** Signed status
  webhook, token-overlap validation, durable dedupe, delivery-outcome projection with terminal protection +
  conflicting-terminal → needs-checking. Files: `twilio-webhook.ts`, `api/webhooks/twilio/status/+server.ts`,
  its two specs, and pgTAP `communications_sms_signed_status_webhook.sql`. Migration `20260919160000` applied.
- **5B — Inbound messages.** Signed inbound route; STOP/START/HELP before identity; normalized-number
  identity resolution (one match / no match → Lead+Unassigned / multiple → Needs identification); inbound
  persistence. Reuses 5A's validation helper. Depends on SMS conversation/inbound tables (shared with email
  model — verify before building 5B).

## Approved engineering decisions

- **Signature check uses the official `twilio` library** (`validateRequest`), Jafar approved 2026-09-15 ("do
  what mature industries do"). Used ONLY for signature validation; every other Twilio call stays hand-rolled.
- Routes are single-URL (org NOT in path): `/api/webhooks/twilio/status` and `/api/webhooks/twilio/inbound`
  (the exact paths our provisioning registers — see `twilio-provisioning.spec.ts` PROVISION_INPUT).
- **AccountSid-lookup-then-validate:** read `AccountSid` from the *unvalidated* form only as a key to load
  that subaccount's Auth Token(s), then validate the signature. A forged AccountSid loads the wrong token →
  validation fails → 403. Safe and standard.
- **Token overlap:** validate against current, then staged (during rotation), then prior Auth Token while
  `retire_after` is in the future. Tokens come from `communication_twilio_credentials` (purpose `auth_token`,
  lifecycle current/staged/prior), decrypted via `decryptTwilioCredential`.

## Non-discoverable schema facts (CORRECTED against the live dev DB — the schema moved past older notes)

- `communication_provider_callback_events` has a NOT NULL `channel` column (default 'email') with
  `provider_channel_check`: email↔brevo, sms↔twilio. Inserting a twilio row REQUIRES `channel: 'sms'`
  (the route sets it). Dedupe is `unique(provider, provider_event_key)` (key = MessageSid:MessageStatus).
- The email drain `process_communication_provider_callbacks` is ALREADY scoped to `channel='email'` and does
  far more than older notes said (quote automation events, unsubscribe suppression, reputation, per-row
  quarantine). DO NOT CREATE OR REPLACE it — that regresses live email. 5A added a separate
  `process_communication_sms_provider_callbacks` scoped to `channel='sms'` (rides the sms partial index).
- A `delivery_outcome` change fires `private.communication_delivery_outcome_history`, which writes a
  `communication_message_events` row whose `event_kind` = the outcome verbatim. `event_kind`,
  `delivery_outcome`, and callback `normalized_kind` checks were ALL widened for sms_* in `20260919160000`.
- Match a status callback to its intent by `provider_message_id = MessageSid` scoped to org + `channel='sms'`.
  `getAccountBySubaccountSid` now exists on `TwilioProvisioningStore`.
- `client_contact_methods.normalized_value` is a GENERATED column — never insert it (matters for 5B tests).

## 5A acceptance (plan §5 gate, status-callback subset)

Fixture/DB tests: invalid signature → 403; forged AccountSid → 403; valid but unknown MessageSid → 204
recorded unresolved; duplicate/out-of-order events idempotent; delivered projects delivery_outcome;
undelivered/failed terminal cannot be regressed by a later 'sent'/'delivered'; conflicting terminal
(delivered vs failed) → needs_checking; rotation: signature signed with staged token validates; retired
prior token past retire_after → 403. Never log bodies or credentials.
