# Part 6D: Free Access and Categorized Lifecycle Control

## Approved behavior

- Free access supports a durable business `starts_at` date, separate from the audit `occurred_at`
  timestamp. Grants may be scheduled to start in the future.
- An organization may have at most one currently active free-access grant and at most one
  non-overlapping future (scheduled) grant. A future grant's start must be after the active grant's
  effective end; if the active grant is forever, no future grant is permitted.
- Free-access actions (`grant`, `extend`, `convert_to_forever`, `end`) are immutable, reasoned,
  actor-attributed events. `extend`/`convert_to_forever`/`end` reference the root `grant` event they
  modify. Permanent (forever) grants require Platform Owner step-up reconfirmation (unchanged from
  today).
- An active (not future) free-access grant makes the organization's effective billing state
  non-overdue regardless of `paid_through_date` — free access is a real commercial arrangement, not
  a display-only badge.
- Suspension requires an explicit category (`nonpayment`, `payment_dispute`, `security`, `support`,
  `other`) and a private reason. Suspension always requires step-up reconfirmation (unchanged).
- Reactivation eligibility depends on the organization's most recent suspension category:
  - `nonpayment` / `payment_dispute`: requires restored commercial eligibility — paid-through date
    not overdue (or still within the seven-day grace window), OR an active (not future) free-access
    grant covering today in the commercial timezone.
  - `security` / `support` / `other`: requires a resolution reason only; must never invent payment
    or renewal history.
- Every lifecycle and free-access command is idempotent per organization and idempotency key, and
  concurrent commands for one organization serialize safely (reuse the existing per-org row lock on
  `organization_commercial_state`).
- Every command writes one owner-private event to the existing `organization_commercial_events`
  stream and one contractor-safe event to the existing `organization_safe_events` stream, atomically
  with its domain projection. Private reasons, categories, and owner identity never reach the safe
  stream.

## Dependencies

Part 6A (commercial-control foundation), 6B (payments and paid-through control) — both complete.
6A's foundation migration already allowlists the `free_access_*` and `organization_suspended` /
`organization_reactivated` event kinds, the `suspension_category` column, and the
`account_suspended` / `account_reactivated` / `free_access_updated` safe-event kinds — this part
wires up what 6A deliberately left ready, it does not redesign the shared history seam.

## Implementation sequence

1. Migration: add `starts_at date not null` and `target_grant_id uuid references
   organization_free_access_events(id)` to `organization_free_access_events`. Keep the table
   append-only (existing immutability trigger stays).
2. Migration: `apply_organization_free_access_change` RPC — per-org lock, idempotency dedup, folds
   events per root grant to compute active/future state, enforces the one-active/one-future
   non-overlap rule, writes the free-access event plus the shared owner/safe events atomically.
3. Migration: `apply_organization_lifecycle_change` RPC — per-org lock, idempotency dedup, validates
   category+reason on suspend and the eligibility/resolution-reason branch on reactivate (reading the
   most recent `organization_suspended` event for category), updates `organizations.lifecycle_status`,
   writes the shared owner/safe events atomically. No new lifecycle projection table — current state
   stays `organizations.lifecycle_status`; "why suspended" reads the latest matching event.
4. pgTAP coverage for both RPCs: overlap/non-overlap enforcement, idempotency, concurrent
   serialization, category validation, both reactivation-eligibility branches, contractor-safe
   redaction.
5. Extend `effective.ts`: an active-today free-access grant overrides `is_overdue`/`is_in_grace` to
   false; expose free-access state on `EffectiveOrganizationAccess`. Extend `effective.spec.ts`.
6. Replace `lifecycle/+server.ts` PATCH and `free-access/+server.ts` POST to call the new RPCs.
   Extend `organizationLifecycleSchema` (category, reason, optional resolution reason) and
   `freeAccessChangeSchema` (`starts_at`, future-grant fields) in `owner.schema.ts`. Route-level
   vitest for both.
7. UI: suspend flow adds a category select; reactivate flow shows restored-eligibility state or asks
   for a resolution reason when noncommercial. Free-access UI adds a start-date field, shows active
   vs. scheduled-future grants separately, and surfaces a clear inline error on a conflicting second
   future grant.
8. Regenerate `database.types.ts` against remote, run `get_advisors`, run focused vitest + pgTAP, and
   browser-verify on a real organization (Jafar LTD or Raad).

## Acceptance checks

- [x] A free-access grant requires a published/assigned package version, reason, and `starts_at`;
      forever grants require step-up.
- [x] At most one active and one non-overlapping future free-access grant can exist per organization;
      a conflicting grant attempt is rejected with a clear error and creates no event.
- [x] `extend`/`convert_to_forever`/`end` only apply to a still-effective grant the caller identifies
      by its root event; acting on an already-ended or nonexistent grant is rejected.
- [x] An active (not future) free-access grant makes `effective.ts` billing report `is_overdue:
      false` regardless of `paid_through_date`.
- [x] Suspension requires a category and reason; retrying the same idempotency key does not create a
      second event or state change.
- [x] Reactivation after `nonpayment`/`payment_dispute` is blocked until eligibility (paid-through,
      grace, or active free access) is restored; reactivation after `security`/`support`/`other`
      succeeds with a resolution reason and never fabricates payment history.
- [x] Concurrent commands for one organization serialize (no lost update, no double event) — structural
      guarantee via the unchanged per-org row lock (6A/6B/6C pattern), not independently retested.
- [x] Contractor-safe events contain only allowlisted fields — no private reason, category, or owner
      email.
- [x] RLS, grants, and independent owner authorization prevent contractor or anonymous mutation of
      any new table or function.
- [x] Existing 6A/6B/6C pgTAP and route suites remain green.

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Organization and commercial control`.
- `docs/jafar-organization-management-mission.md`, headings `Lifecycle`, `Commercial rules` ->
  `Free access`, `History, transparency, and recovery`.
- `supabase/migrations/20260813200000_organization_commercial_control_foundation.sql` (shared event
  seam, already-allowlisted event/safe kinds and `suspension_category` column).
- `supabase/migrations/20260814090000_organization_commercial_control_package_exceptions.sql` (RPC
  pattern to mirror: `apply_organization_package_change`).
- `supabase/migrations/20260810064732_organization_free_access_history.sql` (table being extended).
- `supabase/migrations/20260808233459_organization_lifecycle.sql` (`lifecycle_status` column and
  `private.is_organization_member`, both unchanged by this part).
- `src/lib/server/access/effective.ts`.
- `src/routes/api/jafar/organizations/[organizationId]/lifecycle/+server.ts`.
- `src/routes/api/jafar/organizations/[organizationId]/free-access/+server.ts`.
- `src/lib/server/validation/owner.schema.ts`.
- `src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte`.

## Non-discoverable risks

- The free-access "current state" is folded from an append-only event log grouped by root grant, not
  read from a single row — get the root-grouping (`coalesce(target_grant_id, id)`) and terminal `end`
  handling right or active/future classification silently breaks.
- `private.validate_organization_free_access_event()` currently rejects any `occurred_at > now()`.
  That check is about the audit timestamp, not `starts_at` — do not loosen it to allow future audit
  timestamps; only `starts_at` is allowed to be future-dated.
- The remote Supabase project is authoritative; Docker/local CLI remain unavailable. Never use
  `db push` blindly — apply through Supabase MCP tools and verify via `list_migrations`.
- Preserve unrelated dirty work already in the tree (layout, pickers, `country-state-city`,
  design-skill changes) — do not absorb it into this part's commits.

## Current checkpoint

Closed 2026-08-14. All acceptance checks pass. Full regression green: `svelte-check` 0 errors,
`vitest` 333/333, pgTAP 6A/6B/6C/6D all passing (46/46 for 6D), `get_advisors` clean.
Browser-verified end to end on Jafar LTD, including Jafar personally completing the password
step-up round-trip for suspend/reactivate and convert-to-forever.

Two real database bugs fixed during implementation, each its own corrective migration mirroring
the 6C convention (versions match Supabase's recorded history via `list_migrations`) — worth
remembering for future RPC work:
- PL/pgSQL cannot reference a field on a `record` variable in the same boolean expression as its
  `is not null` guard (planning fails: indeterminate tuple structure).
- A `record` variable's `is [not] null` is an unreliable "did I find a matching row" sentinel across
  branches in this engine — confirmed by direct reproduction (silently misclassified an existing
  future grant as absent). Use explicit boolean flags plus plain scalar fields instead.

One UI bug found during browser verification, fixed the same session: the history feed was
double-showing every free-access action (once with a friendly label from
`organization_free_access_events`, once as a raw unlabeled key from the new shared
`commercial.free_access_*` ledger write) — `history/+server.ts` now filters those four kinds out of
the commercial stream since the dedicated stream already represents them.

One pgTAP test-authoring gotcha, not a production bug: `now()` is frozen for the whole test
transaction, so back-to-back RPC calls to the same org in one script need explicit
strictly-increasing `occurred_at` or the RPC's latest-event fold ties-break on a random UUID. Real
callers each use a separate transaction, so this can't happen outside a test script.

Raad (`abb23ea5-12e8-4f9a-b164-d041366e3fa6`) is still suspended (`nonpayment`) from earlier
database-layer smoke testing, deliberately not fixed automatically (reactivating it honestly needs
a real paid-through/renewal record or free access, and it has no versioned package assignment yet).
Carried forward as a known item, not a 6D gap.
