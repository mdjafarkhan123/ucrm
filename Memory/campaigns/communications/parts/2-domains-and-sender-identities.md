# Part 2: Domains and Sender Identities — Closed 2026-08-24

## Outcome

Give UCRM stored, tenant-safe authority for outbound sending domains, separate inbound receiving domains,
their provider/DNS health, and eligible sender identities. Jafar can safely provision, verify, warm,
replace, restrict, and remove them. Organization administrators can manage senders only after the outbound
domain is ready. The live worker remains disabled until Part 2B also supplies allowance authority.

## Approved behavior

- One platform-owned Brevo account remains behind server-only adapters; no credential or raw provider
  response enters contractor-visible data.
- Sending and receiving domains are distinct globally claimed names. The normal shape is
  `mail.contractor.com` and `reply.contractor.com`, but Jafar may choose other prefixes.
- UCRM records Brevo ownership, DKIM, and reported DMARC evidence. SPF is checked and stored separately as
  UCRM DNS health because Brevo does not expose ordinary SPF through its domain-authentication records.
- A sender is eligible only when it is enabled, allowed for the intended use, belongs to an active member
  when staff-assigned, and uses the organization's active verified healthy outbound domain.
- Manual sender priority and automated/default fallbacks follow `docs/contractor-email-contract.md`.
- Replacement verifies the new outbound domain before switching. Old inbound routing remains available for
  30 days by default. Queued manual mail is held for review instead of silently changing sender.
- Removal requires an impact preview. Provider deletion is never reported complete until UCRM confirms it;
  unsupported Brevo cascade behavior must not be assumed.

## Implementation slices

### A. Database authority — Closed 2026-08-24

- Add organization-scoped domain claim records with separate `sending` and `receiving` purpose, globally
  normalized domain uniqueness, lifecycle/health state, provider identity, DNS evidence, verification and
  check timestamps, replacement linkage, transition deadline, and immutable audit events.
- Add organization-scoped sender identities linked to sending domains, including normalized address,
  provider sender identity, enabled/restricted state, staff assignment, organization-default role, allowed
  manual/automated use, and audit timestamps.
- Use RLS and least privilege. Contractors receive only the reads/writes required by approved permissions;
  provider synchronization and Jafar commands remain server-only.

Implemented in `20260824005223_communications_domain_sender_authority.sql`. Remote transactional checks cover
domain claims, sender/domain alignment, default identity uniqueness, tenant visibility, direct-write denial,
and privileges. Every new foreign key is indexed; advisors report no new security warning or missing-index
warning. Empty new tables naturally report their purpose-built indexes as unused until runtime traffic.

### B. Provider and command layer — Closed 2026-08-24

- Add narrow Brevo operations for create/list/get/authenticate/delete domain and create/manage sender.
- Add Zod-validated `/api/*` commands for Jafar provisioning/recheck/replacement/removal and authorized
  contractor sender management.
- Persist provider attempts and safe failure states idempotently. Never hold a database transaction across a
  Brevo or DNS request.

Closed 2026-08-24: the server-only adapter now covers those narrow Brevo domain and sender operations.
The Jafar provisioning, recheck, replacement, and removal commands are validated, rate-limited, audited, and
idempotent. Provisioning persists the local claim before Brevo and reconciles provider state before create.
Recheck authenticates then reads Brevo, preserves separate SPF authority, persists refreshed safe DNS state,
and marks a verified-domain regression unhealthy. Replacement persists the linked new-domain claim before
provider I/O, leaves the verified current domain untouched, and records the manual-email review policy. Removal
requires a current impact preview and exact-domain confirmation, atomically starts cleanup, keeps ambiguous
Brevo deletion retryable, and atomically commits confirmed cleanup with its immutable receipt. All 23 focused
adapter/domain-command tests and the database/API performance gates pass. Contractor sender create/update/disable
commands persist their claim before provider I/O, reconcile by exact address, recheck domain/member authority at
the final write, switch the organization default atomically, and expose no provider-only state. Their remote
11-check database proof and 16 focused adapter/service/API tests pass.

### C. Eligibility integration — Closed 2026-08-24

- Change the atomic claim contract so the database resolves and returns the stored eligible sender; remove
  caller-supplied sender authority.
- Keep temporary domain/DNS failures unclaimed and deferred. Permanently invalid automated senders cancel;
  invalid manual senders are held for review.
- Keep the live route disabled until Part 2B supplies subscription-period allowance and reserve authority.

Closed in `20260824022346_communications_sender_eligible_outbox_claim.sql`. The claim now resolves sender
authority from stored UCRM rows, rechecks the recipient, sender, member, and domain under one short lease
transaction, and preserves the approved defer/cancel/review outcomes. The worker no longer accepts a sender
from its caller. The live route remains fail-closed. The 13-check database proof, query plan, service-only
privileges, advisors, generated types, 8 focused tests, formatting, and `npm run check` pass.

### D. Minimum surfaces — Closed 2026-08-24

- Add only the Jafar domain controls and contractor sender controls required by this part.
- Reuse the existing settings and Platform Owner patterns. UI design follows the approved blueprint and the
  required pre-UI Communications workflow.
- Closed for the isolated Jafar domain surface: the owner can open an on-demand DNS setup panel for each
  sending domain, copy the exact host/value, and see each record's latest verification state. The read is
  owner-scoped and returns only these setup fields; provider identifiers stay server-only.
- Closed for the contractor Email identity surface: Jafar browser-verified create, edit, default-switching
  (adding a second sender as default correctly moved default off the first), disable, re-enable, and
  required-field validation on 2026-08-24. Denial for a member without `conversations.manage_connections`
  is covered by the passing `senders.spec.ts` 403 test rather than a live second-account pass — Jafar
  accepted that in place of logging into the existing Field-role test member, matching the precedent set
  for Team & access in `Memory/campaigns/contractor-settings/parts/03c-team-directory-and-member-details.md`.

## Performance decisions before SQL

- Domain and sender lists are small organization-scoped configuration reads; they do not need pagination or
  a materialized view.
- Globally unique normalized domains need a unique index. Organization/purpose/current-state reads and
  sender eligibility reads need composite or partial indexes matching the atomic claim predicates.
- Every foreign key used for joins, replacement lookup, staff removal, or cascading cleanup needs a covering
  leading index.
- Provider calls remain outside transactions. State changes use short row locks and idempotent commands.

## Acceptance checks

- Two organizations cannot claim the same normalized sending or receiving domain.
- One organization cannot use the same domain for both purposes.
- A contractor cannot read or mutate another organization's domain or sender.
- An unauthorized member cannot manage connections or senders; an inactive member cannot remain eligible.
- A sender on an unverified, unhealthy, replacing, restricted, or removed domain cannot be claimed.
- A replacement cannot switch outbound identity before the new domain is ready, and inbound transition is
  preserved for the configured window.
- Replayed provider/API commands are idempotent; ambiguous deletion remains visible and retryable.
- Database tests, query plans, RLS/security checks, and the database performance review pass before API work.

## Out of scope

- Allowance periods and reserves (Part 2B), sending/composer behavior (Part 3), inbound parsing (Part 4),
  Conversations UI (Part 5), templates/preferences (Part 6), and full capacity/reputation controls (Part 7).
- Marketing email, general mailbox sync, Twilio, Meta, and web chat.

## Source pointers

- `docs/contractor-email-contract.md` §§ Domain provisioning, warm-up, queueing, suspension, closure
- `docs/research/brevo-domain-sender-current-facts.md`
- `Memory/campaigns/communications/parts/1-email-delivery-foundation.md`
- `src/lib/server/communications/email-worker.ts`
- `supabase/migrations/20260823080419_communications_email_delivery_foundation.sql`
