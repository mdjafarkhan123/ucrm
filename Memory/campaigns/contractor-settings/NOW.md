# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Part 3F (member availability) is closed. All 5 browser-verification steps pass on Raad LTD. Two real bugs
were found and fixed this session (uncommitted):

1. `src/routes/(app)/settings/team/[userId]/+page.svelte` — a non-admin member 403'd loading their OWN
   team-member page, hiding the Availability box. Fixed by rendering just the Availability section when
   `viewingOwnRecordWithoutAdminAccess` is true.
2. Not a code bug: the step-4 "not working that day" warning looked broken, but the wrong visit had been
   fixture-assigned (Job #18 had no assignee; Job #19 "5c-5 Partial Lock Check" was the one really assigned
   to Field Tester). Retested against Job #19 — the warning fires correctly, and clearing the day-off
   (step 5) correctly removes it. No product code changed for this one.

`member-detail.spec.ts` was also fixed this session (added `email: null` to its fixture after uncommitted 3E
work added an `email` field to `/api/team/members/[userId]`). All schedule/availability unit tests pass;
`npx prettier --check` is clean on the touched files.

Part 3 overall stays partially closed: "Activity-log reader" is still unscoped.

## Blockers

None for 3F. Commit 3E + 3F together once Jafar approves (not yet asked/committed).

## Exact next action

Ask Jafar: (a) OK to commit the uncommitted 3E + 3F work now, and (b) what's next for Part 3 — scope the
Activity-log reader, or move to a different part.

## Test fixtures left on Raad LTD

- Team member `7d450c50-b3e5-4f97-8ee9-50e08c1f70bb`, display name **"Field Tester"**. Working week:
  every day 08:00-17:00. One remaining exception: `2026-09-10` (past, harmless). The `2026-09-12` day-off
  exception was deliberately deleted during step-5 verification — safe to leave cleared.
- Job #19 "5c-5 Partial Lock Check" is assigned to Field Tester. Job #18 "5c-5 Stage Billing Rig" is
  unassigned (contrary to an earlier, incorrect note that said #18 was the assigned one).
- Logins: Owner `info.socialmediauser1@gmail.com` / `11223344`; Field `dev.jafarkhan@gmail.com` /
  `11223344` (role: field, this IS Field Tester); Office `dev.jafarkhan+office@gmail.com` / `PaidLaunch16!`.

## Essential pointers

- `docs/contractor-settings-blueprint.md` § Confirmed Part 3 behavior (the two availability bullets)
- `supabase/tests/database/team_member_availability.sql` — rerun via the linked-remote fallback in
  `docs/testing/database.md`; local Supabase CLI is not installed on this machine
- `Memory/deferred/background-jobs-have-no-production-scheduler-decision.md`

Resume command: `continue contractor settings`.
