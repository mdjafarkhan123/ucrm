# Contractor Settings: Current Checkpoint

## Goal

Give a non-technical contractor one understandable, permission-aware control room for business identity,
shared defaults, personal preferences, and the real settings owned by each CRM feature.

## Status

Part 3A, 3B, 3C, and 3D are closed. Part 3C's last open item — the durable "Delivery failed" indicator for
Pending invitations — shipped 2026-08-24: resend, cancel, and replace-email were already implemented from
earlier uncommitted work, so this session added the badge (directory + member-detail rail, reading the
existing `invitation.delivery_failed` field) and browser-verified the full Pending-invitation flow end to end
with a real invitation (invite, resend, delivery-failed rendering, change-email dialog, cancel). Cancel
correctly leaves the member `pending` until the 5-minute pg_cron worker reconciles it — confirmed working
against the live Vault-configured worker URL, not a bug. See `parts/03c-...md` for detail. Jafar waived the
390px mobile pass for this slice on 2026-08-24 (desktop verification stands as sufficient); Part 3C is fully
closed.

Part 1's mobile/390px pass closed 2026-08-24: Jafar checked the four settings pages himself at 390px
(automation still can't resize the viewport) and confirmed they're fine. Part 1 now stays open only for its
pre-existing Quotes-owned blocker — the frozen-branding acceptance test needs Quotes to snapshot logo/brand
color onto a published quote and render it on `/q/[token]`, neither of which exists yet. Confirmed still
unbuilt 2026-08-24; Jafar explicitly chose to leave it for the Quotes campaign rather than build it here. Two
real bugs found during Part 1's earlier 2026-08-24 verification were fixed (currency-lock dead end,
save-then-immediate-edit false conflict). See `parts/01-...md` Layer 4 and "Blocking integrations owned
elsewhere".

**Part 2 is closed (2026-08-24).** Taxes (2A), Price Book (2B), and Quote Settings (2C) are all fully closed;
detail in `parts/02a-taxes.md`, `parts/02b-price-book-management.md`, `parts/02c-quote-settings.md`. 2C's
final session browser-verified the two checks that had blocked it: permission denial for the `field` role
(Settings home hides the destination card; direct navigation confirms a real 403 with no data leak) and
target-margin redaction for a `settings.quotes.manage` role without `quotes.view_cost` (via a temporary,
since-reverted override on the Admin test member — the Target Margin card and its `basis_points` field are
both absent from the response). One out-of-scope UX gap found along the way — Settings pages hang on a blank
loading state on a 403 instead of showing an error — is logged as
`Memory/deferred/settings-quotes-and-taxes-pages-never-resolve-a-403-into-an-error-state.md` (P3), not
blocking.

While closing 2B, a critical app-wide bug was found and fixed (2026-08-24): PostgREST reads SQLSTATE `40001`
(`serialization_failure`) as "safe to retry the whole transaction" and does so forever, but a stale-revision
or expired-lease conflict is permanent, not transient — one stale save produced 75,000+ retries against the
DB in under 90s with the browser tab hung indefinitely. Fixed in
`supabase/migrations/20260902110000_stale_revision_conflicts_are_not_retryable.sql` (21 functions moved to
`P0409`, the same non-retried code Quotes and Team-member profile saves already used) plus 13 API error
mappers and 4 test fixtures. Also resolved 2 of the "8 pre-existing test failures" flagged earlier
(`role.spec.ts`/`permissions.spec.ts`; the remaining 6 are `quote.spec.ts`, unrelated — see
`Memory/deferred/eight-vitest-failures-in-the-quotes-and-team-specs.md`). Full suite: 1100/1107 (7
pre-existing, unrelated). Performance-reviewed: pure errcode swap, no SQL/lock/query-shape changes.

## Exact next action

Part 2 is fully closed (2026-08-24) — Taxes, Price Book, and Quote Settings all shipped and browser-verified,
including the previously-blocked permission-denial and target-margin-redaction checks (see `parts/02c-
quote-settings.md` for full detail on all layers and the five real bugs found and fixed across the slice).

No Part 3, 4, 5, or 6 work is dependency-ready without a scoping conversation first:
- **Part 1** is done from contractor-settings' side; only the Quotes-owned frozen-branding acceptance test
  remains, gated on the Quotes campaign resuming (Jafar declined to build it inside contractor-settings on
  2026-08-24).
- **Part 3E** (team member delete/removal) is scoped but deliberately not started — see below.
- **Parts 4–6** are `Pending`, not yet scoped as campaigns.

The next contractor-settings session needs Jafar to say which of these to pick up, or to scope Part 3E's
reassignment dependency (see below — the framing changed on 2026-08-24).

**Separately, Jafar asked (2026-08-24) for the ability to delete/remove a team member.** That is Part 3E in
the roadmap (still "pending" — no packet exists yet). The database commands for deactivation and permanent
removal already shipped in 3A (`parts/03a-access-and-data-foundation.md`, item 6 — "the seven member
commands"); only the Settings UI is missing. The blueprint requires deactivation to show unfinished assigned
work and force reassignment or an explicit leave-unassigned choice.

**Correction, 2026-08-24:** the earlier framing ("Clients owner-assignment workflow" unblocks this) was
wrong and has been reversed. Confirmed against Jobber and our own 2026-08-16 design comment: Jobber has no
persistent client owner — the Field role's "assigned work only" scope was always meant to key off Visit/Job
assignment, which is gated on Scheduling (not yet built), not on a client-level owner. `clients.owner_user_id`
was speculative and has been removed (`supabase/migrations/20260902140000_remove_client_owner_no_jobber_precedent.sql`);
see `parts/03a-access-and-data-foundation.md` item 1. That means Part 3E's reassignment step still has
nothing real to reassign from the *assigned-scope* side — that stays blocked on Scheduling, full stop, not
on anything buildable in contractor-settings. A smaller, real alternative was surfaced but not yet approved
as a plan: a departing member's open **Opportunities** already have a real owner (`opportunities.owner_user_id`,
shipped in Pipeline) and could be what 3E's reassignment step actually reassigns, instead of waiting on
Clients or Scheduling. Scoping whether Part 3E uses Opportunity-reassignment (or something else, or stays
blocked) is the next product conversation before any Part 3E work starts.

## Blockers and dependency gates

- Part 3E's reassignment step needs a scoping decision (see "Correction, 2026-08-24" above) before it can
  start; the Field role's assigned-scope visibility itself stays genuinely gated on Scheduling.
- Supabase has no supported admin call to end another user's sessions; never write to `auth.sessions`.
- Availability (3F) remains gated on real Scheduling support.
- Keep the active Inbox/Communications agent's files and campaign Memory untouched.

## Protected work

- Preserve shipped Clients/Properties, Requests/Assessments, Pipeline, Quotes, collaboration, and completed
  Settings behavior.
- Team-member writes have exactly one road: the existing SECURITY DEFINER commands through validated APIs.
- Keep contractor Settings separate from `/jafar` Platform Owner controls and entitlements.
- Do not alter the existing test members without Jafar's explicit approval.

## Required pointers

- `parts/01-settings-foundation-and-business-profile.md` → Layer 4, for Part 1's remaining blocker/mobile gap
- `parts/03c-team-directory-and-member-details.md`
- `parts/03b-invitation-lifecycle.md`
- `parts/03-team-and-access.md`
- `docs/contractor-settings-blueprint.md` → Confirmed Part 3 behavior
- `parts/02a-taxes.md` → closed; keep for the shipped Taxes shape Part 2B builds beside
- `parts/02c-quote-settings.md` → closed; full detail on all layers, five bugs fixed, and final verification
- `docs/contractor-settings-blueprint.md` → Taxes and Quote settings behavior

## Active completion gate

Part 2 (2A, 2B, 2C) is fully closed — its completion gate is met. No part is currently active; see
"Exact next action" for what needs a scoping decision before the next part starts.
