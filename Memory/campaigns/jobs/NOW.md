# Jobs: Current Checkpoint

- Goal: Research Jobber Jobs deeply, then build simpler contractor workflows without losing useful features.
- Contract: `docs/jobs-behavior-contract.md`, approved 2026-09-01, amended the same day for 10b's reduced scope.
- Parts 6-10a CLOSED. Part 10b CLOSED 2026-09-01 — browser pass done, all checks green, ready to commit.
- All Jobs work is still UNCOMMITTED (whole `src/**/jobs/**`, migrations, tests untracked on `main`).

## Exact next action (resume here)
Commit the whole Jobs campaign (git add + commit). Nothing else is outstanding.

## Browser pass result (2026-09-01, verified, do not redo)
- Created a real recurring job in dev and drove it end to end: "Edit all visits" opened `EditAllVisitsDialog`,
  showed the "26 visits removed / created" preview, saved, and toasted "Schedule updated — 26 visits
  scheduled, 26 old ones cleared", rebuilding the visit list.
- Editing one visit showed the "affects this visit only" note; "Save and update future visits" saved the
  visit (toast "Visit saved"), then opened `ApplyToFutureDialog` ("23 visits after it"); Apply committed.
- Job history correctly recorded all four events with the right labels (`schedule_replaced`,
  `visits_updated_forward`, two `visit updated` entries).
- Confirmed on a one-off job's visit: no "affects this visit only" note, no "Save and update future visits"
  button — only "Save visit". No "Edit all visits" button on a one-off job at all.
- Found and FIXED a pre-existing bug (unrelated to 10b, blocked all recurring-job creation): `RecurrenceFields.svelte`'s
  `$effect` always wrote `end_date` from the end-date picker even in "Ends after" mode, leaving `""` instead
  of `null` and failing the server's ISO-date regex before the "only required for Ends on" rule ever ran.
  Fixed to only set `end_date` when `end_mode === 'on'`. Full unit suite still 1508/1508, `npm run check` 0
  errors, prettier clean.

## Part 10b: what is DONE and verified (do not redo)
- Migration `20260901085513_..._completed_visit_protection.sql`, APPLIED to remote dev; pgTAP 35/35 (re-run
  2026-09-01). RPCs `reschedule_job_visits`, `apply_visit_to_future`, `private.job_visits_protect_completed()`.
- Routes `POST /api/jobs/[id]/schedule` and `.../visits/[visitId]/apply-to-future`; client `rescheduleJobVisits`
  / `applyVisitToFuture`; `GET /api/jobs/[id]` returns `recurrence`. Route spec covers both (jobs.spec 66/66).
- WIRING (this session): `JobVisitsSection` takes `jobType/isAsNeeded/recurrence/jobRevision`, shows "Edit all
  visits" + mounts `EditAllVisitsDialog`; edits open `JobVisitDialog` with `isRecurring`+`onSaveFuture` →
  `ApplyToFutureDialog`. Page passes the four props. History labels/details added for `schedule_replaced` and
  `visits_updated_forward`. `npm run check` 0 errors, full unit suite 1508 pass, prettier clean.

## Non-obvious facts established for 10b (verified, do not re-derive)
- Regeneration removes ALL incomplete visits, past-dated included. Settled — do not reopen.
- In `reschedule_job_visits` the idempotency receipt is checked BEFORE the revision, so a plain retry is not
  rejected as "someone else changed this job".
- "Later" in `apply_visit_to_future` = incomplete, dated, `visit_date` strictly > source's date (source and
  completed excluded). The client `applyLaterCount` mirrors this exactly.
- `is_as_needed` / `job_type` are immutable; as-needed conversion is deferred, not an oversight.
- Deferred, Jafar said "later": (A) map duplicate job_number (23505) to a field error, not a 500; (B) make the
  New Job "Job #" field editable with a live duplicate warning.

Resume command: `read memory and continue` (Jobs campaign).
