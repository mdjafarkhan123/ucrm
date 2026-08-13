# Jafar Panel: Current Checkpoint

## Goal

Finish the approved Platform Owner journey from public contractor application through commercial
control, support recovery, closure, and dependency-linked provider controls.

## Active part

Part 6B: payments and paid-through control. Not planned yet.

## Exact next action

Plan Part 6B against the commercial seam delivered in 6A, then create its part packet after Jafar
approves the plan. 6B builds owner routes and UI for initial payment, renewal, correction, refund,
reversal, and optional late-renewal reactivation. Every write goes through
`public.apply_organization_commercial_command`; nothing else may write commercial history or the
projection. Confirm before any further remote schema change.

## Current truth

- Parts 0 through 6A are complete.
- The commercial seam lives in `supabase/migrations/20260813200000_organization_commercial_control_foundation.sql`
  and is applied to the linked remote project: `organization_commercial_settings`,
  `organization_commercial_events`, `organization_commercial_state`, `organization_safe_events`, and
  the single command function.
- Existing operational timezones were imported once as commercial baselines and existing
  `organization_billing_accounts` paid-through values were imported into the projection.
- `src/lib/server/access/effective.ts` still computes grace from UTC and fixed 24-hour periods. It
  must move onto `organization_commercial_state.grace_ends_at` during 6B so only one grace truth
  survives.
- `organization_billing_accounts` remains the legacy mutable projection. 6B decides when reads move
  across and when writes to it stop.

## Blockers

None. Docker is unavailable, so local Supabase cannot run. Database work uses the linked remote
project, and every remote execution needs Jafar's approval at execution time.

## Protected work

- Preserve all unrelated dirty work in the repository.
- In particular, do not absorb or commit the existing `LocationPicker`, `TimezonePicker`,
  `country-state-city` dependency, design-skill, or unrelated application changes as campaign work.

## Required pointers

- `docs/jafar-completion-contract.md`, heading `Organization and commercial control`, including the
  promoted `Commercial control decisions`.
- `docs/jafar-organization-management-mission.md` headings `Commercial rules` and `Lifecycle`.
- `docs/adr/0001-paid-prospect-provisioning-and-versioned-packages.md`.
- `docs/testing/database.md` for the remote test path.
- `supabase/tests/database/organization_commercial_control.sql` for the 6A acceptance coverage.
- `Memory/campaigns/jafar-panel/ROADMAP.md`.

## Active-part completion gate

Stop when Jafar approves the Part 6B plan and its packet exists. Do not write 6B routes or UI before
that approval.
