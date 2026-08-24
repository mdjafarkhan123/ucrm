# Part 1: Email Delivery Foundation

## Outcome

Create the non-UI, operational-email foundation that can safely record one contractor outbound intent,
deliver it once through a server-side Brevo adapter, accept authenticated provider callbacks, and expose
retryable outcomes. It creates no contractor inbox screen, domain-management UI, template UI, or general
inbound mailbox.

## Proposed scope

- Dedicated organization-scoped Communications records for outbound intent, delivery attempts, provider IDs,
  callback events, and email usage events. They retain a channel/thread seam without claiming Meta, SMS, or
  web-chat behavior is implemented.
- An atomic database command that creates the intent and a pending outbox row together, with a stable logical
  idempotency key. A server-only worker claims, rechecks eligibility, calls Brevo, and records the outcome.
- An authenticated, raw-body-safe callback route that resolves the organization, deduplicates provider events,
  tolerates out-of-order delivery, and never exposes provider payloads or secrets to a browser.
- A separate operational-email allowance event/counter seam. It never reads or writes Communication Balance.
- Tests for RLS, cross-organization isolation, repeated submit/callback/worker attempts, provider failure,
  and retry without a second accepted send or counted recipient.

## Not in scope

- Contractor domains or sender identities (Part 2), manual or automated sending UI (Part 3), inbound replies
  and attachments (Part 4), inbox UI (Part 5), Meta, web chat, Twilio, templates, reputation, or Jafar controls.
- Any contractor-facing fallback sender. Existing system-email delivery remains separate.

## Required approvals

1. Approve a dedicated Communications model rather than extending generic attachments, notes, or the
   platform-only outbox.
2. Approve the initial permission set: view assigned/followed/mentioned, view team, send, manage assignment,
   permanent delete, and manage connections—defined now but not surfaced in UI yet.
3. Approve generic package capability/quantity keys and a separate email allowance counter/event model.
4. Approve a server-only encrypted integration-secret boundary and signed callback verification; no credential
   appears in organization tables, browser payloads, or logs.
5. Confirm Part 1 creates only non-visible records and automated verification; no live contractor email is sent.

## Performance and security decisions

- Cursor-only inbox/event reads; no offset pagination. Index each worker and callback lookup by organization,
  status/due time, and provider/idempotency identity before the migration is written.
- RLS is organization-scoped and role-aware. Service-role workers remain server-only; provider callbacks gain
  no customer read access. A Conversation context lookup always rechecks the linked CRM record permission.
- The migration extends the existing organization-purge receipt with Communications components and uses an
  explicit R2/provider cleanup retry anchor. No storage object is treated as deleted solely because its row
  cascaded.

## Completion checks

- A failed or concurrent worker never produces a duplicate accepted provider send, charge, or usage count.
- An invalid, replayed, cross-organization, or out-of-order callback cannot alter another message.
- Suspension, pause, sender/recipient changes, and allowance exhaustion are rechecked immediately before send.
- Database/RLS and server tests pass; the performance review runs after the migration and API/worker layer.

## Current implementation state

- Applied remotely: `20260823080419_communications_email_delivery_foundation` and its explicit anonymous-RPC
  privilege fix `20260823081308_communications_email_foundation_security_fix`.
- Added a server-only Brevo adapter, bearer-token callback endpoint, and an intentionally inert worker route.
  It returns unavailable until Part 2 supplies a verified sender identity; it never claims a row in that state.
- The queue claim query uses its partial index (verified with `EXPLAIN`). The remote security advisor no longer
  reports the new command as anonymously executable. Its no-RLS-policy notices are intentional: authenticated
  roles have no table grants and service-role workers are the only readers/writers.
- Remote read-only verification on 2026-08-23 confirmed the tables, claim function, partial claim index, and
  anon/service-role privilege boundary exist. The corresponding migration versions are missing from remote
  migration history, so do not reapply them; reconcile history only as its own approved maintenance task.
- Server-only worker and transactional-callback secrets are configured in the local dev-tunnel environment.
  Brevo callback `2148798` is bearer-protected and targets
  `/api/webhooks/brevo/transactional` for delivery and failure events. Live probes confirmed its `400` and
  `422` rejection paths and the intentionally inert worker's authenticated `503` response; no contractor
  email was sent.
- Applied remotely on 2026-08-24: lease-protected atomic submitted/retry/unknown completion, one-time usage
  counting, approved bounded retry timing, and bounded stale-claim quarantine. The two new database commands
  are executable only by `service_role`; their database tests pass.
- The server worker service classifies provider outcomes and performs one claim/send/finalize cycle only when
  explicitly given a verified sender. The live route remains fail-closed, so no contractor email was sent.
- Focused Communications checks pass 18 tests. `npm run check` has zero errors and only two existing dashboard
  CSS warnings. The claim query uses its partial index and advisors found no new migration warning.
- Part 1 still needs an approved pre-send eligibility boundary covering organization state, current recipient,
  allowance, and the verified sender supplied by Part 2 before the route may call the worker service.
- Approved 2026-08-24: eligibility and claiming are one atomic database decision backed by stored UCRM
  authority. It rechecks organization state and pauses, the current recipient, the applicable allowance, and
  an enabled sender on a verified healthy domain. Temporary failures defer without claiming; permanently
  stale recipients cancel safely; queued manual email with an ineligible sender is held for review and never
  silently reassigned. Part 2 and the allowance authority must supply those records before the live route is
  enabled.

## Source pointers

- `docs/contractor-email-contract.md` §§ Brevo, allowances, queueing, closure
- `docs/unified-inbox-behavior-contract.md` §§ Composer, email, reliability
- `Memory/campaigns/communications/parts/0-architecture-and-implementation-audit.md`
- `src/lib/server/events/{outbox,dispatcher}.ts`
- `src/lib/server/storage/r2.ts`
