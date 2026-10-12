# Time clock Part 8 — Assessment timers proof (2026-10-12)

Branch dev app on port 5180, remote dev database, business Raad LTD, the Field member (`Field Tester`,
Login.md) who is assigned to both test Assessments. Script: `journey.mjs` in this folder.

## Checks

- `npm run check` — 0 errors (the earlier run ran out of memory; rerun with a larger heap, plus `.env` copied
  into the worktree). `npx prettier --check` on every changed file passes.
- `npx vitest run src/lib/time-clock src/routes/api/time-clock src/lib/components/jobs` — 10 files, 140 tests
  pass.

## Database (rolled back, before the migration was applied)

`database-proof.sql` → `database-proof-output.txt`: only today's, assigned, incomplete Assessments can be
started; one timer at a time; the day clock pauses and resumes; 40 minutes recorded once against the Request
with no Job entry; completing the Assessment stops its timer; corrections keep or clear the Request.

## Live app (Field member, 1440px and 390px, 5/5 checks each)

- Tomorrow's Assessment ("Live check tomorrow"): the Request page offers no Start timer.
- Today's Assessment ("Live check today"): Start timer on the Request page → toast "Timer started", the
  header shows a green running time and "Assessment" with Stop, and the card shows Stop timer.
- Stop after more than a minute → Start timer returns; Timesheets Day shows "Assessment · Live check today"
  with "Timer" as its source.
- Database after both runs: two entries on that Request (15 min, 1 min), each recorded once, `source = timer`,
  and no Job time entry for the crew member in that period.

Not run live (covered by the database proof): ticking "Assessment complete" while a timer runs; Start from the
Schedule preview (same `WorkTimerControl` as the Request page).

## Screen check (Classic)

Screenshots: `field-today-request-running-{390,1440}.png`, `field-today-request-before-*`,
`field-tomorrow-request-*`, `field-timesheets-*`. Header timer, Request card and Timesheets rows are readable
and unclipped at both widths.

Test data left in Raad LTD: Requests "Live check today" and "Live check tomorrow".
