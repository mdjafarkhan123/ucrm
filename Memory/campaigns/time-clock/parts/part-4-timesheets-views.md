# Part 4 — Timesheets views

**Campaign:** time-clock · **Plan:** `docs/time-clock-behavior-contract.md` § Timesheets page
**Stage:** Building (paused 2026-10-11 at Jafar's request to keep sessions small)
**Code:** `main`
**Done when:** own-only and manager logins see exactly the right rows and totals; performance review
measured on a 15-person week.
**Read next:** design skill → Classic (`tables.md`, `accordion.md`); svelte skill; performance-review
`references/verify.md` when the page exists.

## Steps

- [x] Migration `20261207090000_timesheets_views` applied and recorded: `private.timesheet_rows` (both hour
  tables + running timers, overlap = shared minute or more), `timesheet_summary(org, anchor_date, span)`,
  `timesheet_entries(org, user, from, to)`, `private.organization_timezone`. Types regenerated.
- [x] API: `GET /api/time-clock/timesheets?span=&date=`, `GET /api/time-clock/timesheets/entries?user_id=&from=&to=`;
  gate `src/lib/server/time-clock/timesheets.ts`; Zod in `time-clock.schema.ts`.
- [x] Client `src/lib/time-clock/timesheets.ts` (types, keys, URL filters, labels). Timer moves and Job Labor
  writes invalidate `timesheetsKey`. Navigation flag `timesheets` + spec; `clock` icon registered.
- [x] `src/lib/components/time-clock/TimesheetEntryList.svelte` written, not yet autofixer-checked.
- [ ] `TimesheetPersonRow.svelte` and `src/routes/(app)/timesheets/+page.svelte`, then the sidebar item.
- [ ] Route specs for both endpoints; unit spec for `timesheets.ts` helpers.
- [ ] Performance verification, live proof with each role, design screen check.

## Next

Build `TimesheetPersonRow.svelte`: a disclosure row (button, `aria-expanded`) showing avatar, name, badges
(You / Left the team / Deactivated / overlap count / running `RunningClock` with `flagLong`), week day cells or
day status, and total; its entries query (`timesheetEntriesKey`) is enabled when open or hovered. Phone
(≤639px): days drop under the name. Then the page: `CalendarBar` (Day/Week, arrows, Today, range label from
the summary's `from`/`to`), `CalendarPicker` to jump to a date, `FilterChipMulti` people filter for team
readers (client-side via `visiblePeople`), a warnings `Banner`, and a week footer of `dayTotals`. URL state
uses `readTimesheetFilters` (`?view=day&date=&people=`). Own-only readers start with their row open. Then
add `{ label: 'Timesheets', href: '/timesheets', icon: 'clock', area: 'timesheets' }` after Schedule in
`SharedAppShell.svelte` (removed for this commit so no link points at a missing page). Not on the warm list.

## Proof

- Rolled-back database proof (2026-10-11): 8:00–12:00 day totals 240 min with no false overlap from
  minute rounding; real overlaps flagged; forgotten timer flagged long; field login refused a teammate;
  sales refused; anon cannot reach `private`. Script: `docs/research/time-clock-timesheets-2026-10-11/database-proof.sql` (rolls back).

## Notes

- Decisions: running timers stay out of totals (as Job costing); a Job the reader cannot open shows
  "Job #N" with no title, client or link; the roster is active members passing `can_run_own_timer` plus
  anyone with hours or a running timer (Part 6 changes the gate there, in one place).
- Performance design: summary is people × days, entries load per opened row; existing
  `(organization_id, started_at, id)` indexes, no new index or cache. Verify with ~1,300 entries for 15
  people (EXPLAIN ANALYZE both functions, API time, payload bytes, throttled phone render).
