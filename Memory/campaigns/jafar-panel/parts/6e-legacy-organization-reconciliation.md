# Part 6E: Legacy Organization Reconciliation

## Approved behavior

- New paid organizations never use `pending_setup`; only rows that predate the versioned onboarding
  flow do. This is a one-time review queue, not an ongoing state.
- Each legacy row is deliberately converted to `active` or `suspended` with a reconciliation reason.
  No bulk assumption is allowed and no automatic transition exists.
- Resolving to `active` requires, all at once: a published package version assigned, paid-through
  eligibility or an active free-access grant, an owner or admin membership, and that
  administrator having completed login setup (a usable password, not just an unconsumed setup
  link). Each missing condition is reported with a specific, actionable error.
- Resolving to `suspended` needs only a valid suspension category (the same five categories as
  normal lifecycle suspension) and a reason — no eligibility checks, since suspending is always the
  safe direction for an unreviewed row.
- Activating requires Platform Owner password step-up (first-time commercial activation is at least
  as high-impact as reactivation, which already requires it). Suspending does not require step-up.
- The directory and organization-detail screens surface `pending_setup` as "Needs review" rather
  than exposing the raw lifecycle string, with a dedicated KPI count on the directory.
- The command is idempotent per organization and idempotency key, and writes one owner-private
  event (`pending_setup_resolved`) plus one contractor-safe event (`account_suspended` /
  `account_reactivated`, reusing the existing safe kinds), atomically with the lifecycle change.

## Dependencies

Parts 6B (payments and paid-through control), 6C (versioned package changes and exceptions), and 6D
(free access and categorized lifecycle control) — all complete. 6E reuses their commercial event
seam, free-access eligibility query pattern, and suspension categories; it does not redesign them.

## Implementation sequence

1. Migration: `organization_legacy_readiness(target_organization_id)` — read-only checklist
   (`package_assigned`, `administrator_exists`, `administrator_login_ready`,
   `paid_through_eligible`, `free_access_active`) backing both the review screen and the mutation's
   own guard.
2. Migration: `apply_organization_pending_setup_reconciliation(...)` — refuses any organization not
   currently `pending_setup` (this is what keeps it distinct from `apply_organization_lifecycle_change`,
   which already explicitly refuses `pending_setup` organizations). Calls the readiness function
   before allowing activation; suspension skips the readiness call entirely. Writes
   `pending_setup_resolved` to the existing `organization_commercial_events` / `organization_safe_events`
   seam from 6A, following the same per-org row-lock and idempotency-dedup pattern as
   `apply_organization_lifecycle_change`.
3. Corrective migration: the 6A `organization_commercial_events_suspension_check` constraint only
   tolerated a `suspension_category` on `event_kind = 'organization_suspended'`. Broadened to a
   `case` expression so `pending_setup_resolved` may carry a category (suspend outcome) or none
   (activate outcome), while every other event kind still forbids one. Found live via pgTAP against
   the remote database before it reached the API layer.
4. New Zod schema `organizationLegacyReconciliationSchema` in `owner.schema.ts`, mirroring
   `organizationLifecycleSchema`'s discriminated union on `status`.
5. New route `api/jafar/organizations/[organizationId]/legacy-review/+server.ts`: `GET` returns the
   organization plus the readiness checklist; `PATCH` calls the reconciliation RPC, gating step-up
   only on `status: 'active'`.
6. New component `LegacyReconcileActions.svelte`: fetches readiness, renders the four-item checklist
   with Ready/Needs review badges, disables Activate until every item passes, and always allows
   Suspend. Reuses `OwnerReconfirmDialog` for the activate step-up round trip.
7. Wired into the organization detail page: when `lifecycle_status === 'pending_setup'`, the
   lifecycle card renders `LegacyReconcileActions` instead of `LifecycleActions`, with matching
   copy changes in the "Next safe action" card and the header badge.
8. Directory page: `LifecycleStatus` extended to include `pending_setup`, a fourth "Needs review" KPI
   card added, and the lifecycle filter/badge/tone helpers extended (`warning` tone, "Needs review"
   label).
9. History label added (`commercial.pending_setup_resolved` → "Legacy organization reviewed").
10. pgTAP coverage (31 assertions) for both functions: privileges, every readiness signal individually,
    every activation-blocked error message, the suspend happy path (including safe-event redaction
    and category/reason validation), the activate happy path, the double-reconciliation guard, the
    already-active guard, idempotency, and general input validation.
11. Vitest route coverage (12 tests) for the new endpoint: auth/validation boundaries, step-up gating
    (required for activate, not for suspend), correct RPC argument passing for both directions, and
    conflict-code mapping.
12. `database.types.ts` regenerated against remote; `get_advisors` run (no new findings — everything
    surfaced pre-existed and is unrelated to this part's tables/functions).

## Acceptance checks

- [x] A `pending_setup` organization cannot be changed through the ordinary suspend/reactivate
      action (`apply_organization_lifecycle_change` still refuses it) — only through this dedicated
      command.
- [x] Activation is blocked, with a specific error, when the package version is unassigned, when
      there is no owner/admin, when the administrator has not completed login setup, or when there
      is neither a paid-through date nor active free access.
- [x] Suspension applies with only a category and reason, regardless of readiness — verified live in
      browser against the real admin-less `xdasd` organization (zero team members).
- [x] Activation applies once every readiness signal is true — verified live in browser against a
      seeded fully-eligible legacy organization (`Riverside Legacy Demo`), through the point where
      the password step-up dialog correctly appears. Completing that dialog requires Jafar's actual
      password, which the agent does not enter per policy; Jafar can finish that single click himself
      if he wants the full round trip witnessed, matching how 6D's step-up was personally verified.
- [x] Retrying the same idempotency key does not create a second event or change state twice.
- [x] The contractor-safe event carries only `access_status` — no private reason, category, or actor
      email.
- [x] The directory KPI and filter, and the organization-detail badge/checklist, all reflect
      `pending_setup` correctly (confirmed live: KPI moved 2 → 1 needs-review after the suspend
      action; `xdasd` correctly showed "Suspended" and handed off to the normal `LifecycleActions`
      component afterward).
- [x] `svelte-check` 0 errors, `vitest` 345/345, pgTAP 31/31 for this part, `get_advisors` clean of
      new findings.

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Commercial control decisions` (the `Legacy
  pending_setup review` paragraph).
- `docs/jafar-organization-management-mission.md`, heading `Legacy pending setup`.
- `supabase/migrations/20260814110000_organization_legacy_pending_setup_reconciliation.sql`.
- `supabase/migrations/20260814120000_fix_pending_setup_resolved_suspension_category_check.sql`
  (corrective).
- `supabase/migrations/20260814034522_organization_free_access_scheduling_and_lifecycle_control.sql`
  (`apply_organization_lifecycle_change` — the pattern this part's mutation mirrors, and the function
  that still refuses `pending_setup`).
- `supabase/tests/database/organization_legacy_pending_setup_reconciliation.sql`.
- `src/routes/api/jafar/organizations/[organizationId]/legacy-review/+server.ts` and its spec.
- `src/lib/components/jafar/LegacyReconcileActions.svelte`.
- `src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte`.
- `src/routes/jafar/(protected)/organizations/+page.svelte`.
- `src/lib/server/validation/owner.schema.ts`.

## Non-discoverable risks

- The 6A `organization_commercial_events_suspension_check` constraint was written assuming only
  `organization_suspended` would ever carry a `suspension_category`. Any future event kind that
  needs a category on only *some* outcomes will hit the same wall — extend the `case` expression
  added by the corrective migration rather than re-deriving the check from scratch.
- `organization_legacy_readiness` is called both standalone (for the GET checklist) and from inside
  `apply_organization_pending_setup_reconciliation` (for the activation guard) so the two can never
  drift — do not duplicate its eligibility logic inline in the mutation.
- "Administrator login setup complete" is read directly from `auth.users.encrypted_password is not
  null`, not from the new provisioning flow's setup-link tracking — legacy organizations predate that
  table entirely, so checking setup-link state would silently and permanently block every legacy row.
- Legacy reconciliation reuses the *existing* safe-event kinds (`account_suspended`,
  `account_reactivated`) rather than inventing new ones — the contractor-visible outcome is
  identical to a normal lifecycle change, so no new allowlisted safe payload shape was needed.
- The remote Supabase project is authoritative; Docker/local CLI remain unavailable. Migrations were
  applied and pgTAP was run directly against remote via Supabase MCP tools (results captured through
  a temporary results table, since the MCP `execute_sql` tool only returns the last statement's
  result set for a multi-statement script).

## Current checkpoint

Closed 2026-08-14. All acceptance checks pass. `svelte-check` 0 errors, `vitest` 345/345 (12 new for
this part), pgTAP 31/31 for this part, `get_advisors` clean of new findings. Browser-verified live:
suspended the real admin-less `xdasd` organization end to end (no step-up needed, correct handoff to
normal lifecycle controls afterward); confirmed the activate path's full readiness checklist and
step-up gate on a seeded fully-eligible legacy organization, stopping at the password prompt per the
credential-entry policy.

`xdasd` is now permanently `suspended` (real data, real action, not a rollback-only test). `Riverside
Legacy Demo` (`7e37a58f-60e4-40ee-bb4a-cf13966a7a3d`) remains `pending_setup` and fully
activation-eligible — a seeded demo org, safe to leave as is or for Jafar to click through the
step-up himself later. Both are demo data per the project's current stage.
