# Part 5 Corrections — part note

**Plan:** `docs/time-clock-behavior-contract.md` § Timesheets page (Add, Edit or delete, Edit history,
Manager actions), § Forgotten timers. **Roadmap:** line 5. **Stage:** Building — database and API done,
screens half-wired.

## Technical approach (chosen 2026-10-12)

- **History:** table `time_entry_history` (no grants; written only by definer functions), one row per
  stopped / added / changed / deleted, keyed by the entry's id; values hold person, kind, Job, visit, start,
  minutes, notes — never money. Back-filled from `job_costing_events`.
- **One id start to finish:** `running_timers.id` becomes the stopped entry's id; `running_timers.notes`
  carried on stop.
- **One writer:** `private.change_time_entry` / `private.remove_time_entry` serve Timesheets and the Job's
  Labor section. Job ↔ General moves the row under the same id. A person change re-prices at the new
  person's current rate (our adaptation; tell Jafar in the report).
- **Local times:** day + HH:MM on the business clock; end at or before start = next morning; 24 h max.
- **Manager actions:** `clock_in_member`; `stop_timer_at` (now or chosen end; team, or own with
  track_own); a chosen end ends the day — nothing resumes (our adaptation).

## Done

- Migration `20261208090000_timesheet_corrections.sql` applied 2026-10-12; types regenerated. Rolled-back
  proof incl. the overnight success check: `docs/research/time-clock-corrections-2026-10-12/`.
- Routes under `src/routes/api/time-clock/timesheets/` (entries POST, `entries/[entryId]` PATCH/DELETE,
  `…/history` GET, `running/[userId]` PATCH, `…/stop`, `…/clock-in`); spec `corrections.spec.ts` passes.
- Client module `src/lib/time-clock/corrections.ts`; types in `timesheets.ts` extended.
- New, not yet wired or autofixed: `work/JobPicker.svelte`, `time-clock/TimesheetEntryDialog.svelte`,
  `TimeEntryHistoryDialog.svelte`, `StopTimerDialog.svelte`. `TimesheetEntryList.svelte` now takes
  `userId` and `actions` (menu: Edit / Stop… / History / Delete; "Edited" mark).

## Next action

1. `TimesheetPersonRow.svelte`: pass `userId={person.user_id}` and `actions` to `TimesheetEntryList`; add a
   manager person menu (Add entry for them, Clock in, Clock out / Set end time via `StopTimerDialog`).
2. `src/routes/(app)/timesheets/+page.svelte`: "Add entry" in `PageHeader` actions when `summary.can_add`;
   hold one `TimesheetEntryDialog`, `TimeEntryHistoryDialog`, `StopTimerDialog` and a `ConfirmDialog` for
   Delete (`deleteTimesheetEntry` then `refreshAfterCorrection`); `warm` prefetches `entryHistoryKey`.
3. Run the Svelte autofixer on every new/changed component; `npx vitest run src/lib/time-clock
   src/routes/api/time-clock`; add unit tests for `historyLines`, `spanMinutes`, `businessClock`;
   `npm run check` once; prettier/eslint.
4. Live proof (owner + field logins, `Login.md`): add, edit, delete, history, manager stop at a set time;
   design screen check at 1440 and 390. Then mark Part 5 done in `ROADMAP.md`.
