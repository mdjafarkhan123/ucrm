# Part 4 — Timesheets views

**Campaign:** time-clock · **Plan:** `docs/time-clock-behavior-contract.md` § Timesheets page
**Stage:** Building — **Waiting to merge** (paused 2026-10-12 at Jafar's request to keep sessions small)
**Code:** branch `time-clock-part-4` (pushed; commit `84fe5e16`), worktree `/tmp/ucrm-time-clock` (may be
gone after a reboot — recreate with `git worktree add /tmp/ucrm-time-clock time-clock-part-4`, then link
`node_modules` and `.env` from the main folder). Not yet in `main`.
**Done when:** own-only and manager logins see exactly the right rows and totals; performance review
measured on a 15-person week.
**Read next:** performance-review `references/verify.md`; svelte skill if touching components.

## Steps

- [x] Migration `20261207090000_timesheets_views` applied and recorded (on `main`); API routes, gate, Zod,
  client module `src/lib/time-clock/timesheets.ts`, `TimesheetEntryList.svelte` (on `main`).
- [x] Branch: `src/routes/(app)/timesheets/+page.svelte`, `TimesheetPersonRow.svelte`, sidebar item in
  `SharedAppShell.svelte`, compact `size="small"` on `CalendarPicker` and `FilterChipMulti`,
  `timesheetWarnings`/`personName` helpers, route spec `src/routes/api/time-clock/timesheets/timesheets.spec.ts`
  (passes). `svelte-check` 0 errors.
- [x] Design screen check (Classic), 3 rounds: owner and field logins, Week/Day, row open, 15-person mock with
  long names, running and 12-hour timers, overlaps, left/deactivated, filtered-empty, loading, error, dark,
  keyboard focus, 1440 and 390. Fixed: heavy today column, uneven toolbar heights, phone total alignment,
  phone day values colliding, "You" badge for own-only, duplicated error text.
- [ ] Unit spec `src/lib/time-clock/timesheets.spec.ts` for the helpers (filters ↔ URL, shift, range label,
  `entryPurpose`, `visiblePeople`, `dayTotals`, `timesheetWarnings`).
- [ ] Performance verification (below), then merge `time-clock-part-4` into `main`, push, remove the worktree
  and branch, mark Part 4 done.

## Next

Write the helper unit spec, run it. Then performance: in a rolled-back transaction, add 15 members' week
(~1,300 entries) and `EXPLAIN ANALYZE` `timesheet_summary` and `timesheet_entries` as the owner; record
API time and payload bytes; render the 15-person mock on a throttled phone profile
(`docs/research/time-clock-timesheets-2026-10-11/screenshot.mjs` + `make-mocks.mjs` mock the API with
`--mock=`/`--entries=`; run the dev server from the worktree on port 5181). Save results beside the
screenshots, then merge.

## Proof

- Rolled-back database proof (2026-10-11): `docs/research/time-clock-timesheets-2026-10-11/database-proof.sql`.
- Screenshots and screen-check scripts: same folder (branch).

## Notes

- Decisions: running timers stay out of totals; a Job the reader cannot open shows "Job #N" only; the roster is
  active members passing `can_run_own_timer` plus anyone with hours or a running timer (Part 6 changes the gate
  in one place). The week table follows Carbon's expandable data-table row: the name is the disclosure button,
  entries sit in a full-width row beneath. People chosen in the filter who are absent this week stay in the URL.
- Chrome extension was not connected; Playwright screenshots were used instead.
