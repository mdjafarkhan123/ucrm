# Part 3: Operational Outbound Email

## Outcome

Authorized staff and CRM workflows can create safe operational-email delivery intents. Each intent is
rebuilt from current UCRM authority at send time, previewed when a human is sending it, and delivered only
after the already-built atomic worker claim accepts it. A resend is a visible, linked new attempt.

## Approved scope

- Add a narrow server-side command and Zod-validated `/api/*` boundary for manual and system-originated
  operational email. It accepts a purpose and immutable source reference, never a caller-provided sender,
  recipient email, allowance class, HTML, or secure URL.
- Resolve the permitted source record, recipient, assigned/current sender authority, purpose, and rendered
  content on the server. Commit the delivery intent and outbox event in one database command with a stable
  idempotency key.
- Create a read-only preview model for the manual-send surface. The screen is deliberately not designed in
  this first backend slice; before a `.svelte` screen is built, obtain the separate short UI-plan approval
  required by `docs/unified-inbox-behavior-contract.md`.
- Make manual and system intent states understandable: created, queued, deferred, held for review,
  cancelled, submitted, failed, and resent. A resend uses fresh current state and a new idempotency key
  linked to the original intent.
- Activate the worker only when an active subscription allowance period exists and all Part 3 tests pass.
  Until then the route remains `503` and no contractor email is sent.

## Explicit exclusions

- Inbound replies, reply aliases, attachments, templates/snippets, automations, Conversations UI,
  general inbox email, marketing email, SMS, and provider/reputation controls.
- Caller-controlled sender, recipient, raw HTML, capacity class, or portal URL; these would bypass stored
  CRM and Communications authority.

## First slice checklist

1. Inspect the existing email-intent/outbox schema, worker claim, CRM record access seams, and existing
   rate-limit conventions. Decide the exact allowed source types and access rule before any migration.
2. Add the smallest private/database command and indexes needed to atomically create a guarded delivery
   intent from a server-resolved payload. Privileges remain service-only; browser code never writes the
   Communications records directly.
3. Add the server command, Zod input schema, rate-limited API route, and focused tests for authorization,
   tenant isolation, idempotency, stale work state, and no direct recipient/sender override.
4. Run database plans/advisors plus API performance review. Keep delivery disabled unless the full Part 3
   activation checks are demonstrably met.

## Acceptance checks

- A user without `conversations.send` cannot create an intent, and one organization cannot reference
  another organization's client or work record.
- A caller cannot substitute a recipient, sender, allowance class, content, or secure document link.
- Replaying the same logical action produces no duplicate intent or outbox event; resending creates one
  linked, separately authorized logical action.
- Changed/invalid recipient, sender, permission, work state, suppression, allowance, or link authority
  prevents provider submission at claim time.
- Worker activation remains fail-closed without an active allowance period and browser-verifiable sender.

## Source pointers

- `docs/contractor-email-contract.md` §§ Domain provisioning, package allowances, templates, work-item
  behavior, queueing/retries/history
- `docs/unified-inbox-behavior-contract.md` §§ Composer and message behavior; required workflow before UI
  design
- `Memory/campaigns/communications/parts/1-email-delivery-foundation.md`
- `Memory/campaigns/communications/parts/2b-minimum-email-allowance-authority.md`
- `src/lib/server/communications/email-worker.ts`
- `supabase/migrations/20260823080419_communications_email_delivery_foundation.sql`
