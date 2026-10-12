# Part 5 Corrections — part note

**Plan:** `docs/time-clock-behavior-contract.md` § Timesheets page (Add, Edit or delete, Edit history,
Manager actions), § Forgotten timers. **Roadmap:** line 5.

## Technical approach (chosen 2026-10-12)

- **History:** new table `time_entry_history` (append-only by having no writer but definer functions), one
  row per started / stopped / added / changed / deleted, keyed by the entry's id. Values hold person, kind,
  Job, visit, start, minutes and notes — never money (Job costing keeps `job_costing_events` for that).
  Existing Job entries are back-filled from `job_costing_events`; existing General entries get an "added" row.
- **One id from start to finish:** `running_timers.id` becomes the stopped entry's id, so a running timer's
  start-time edits and its later corrections read as one history. `running_timers.notes` added; carried on stop.
- **One writer:** private `change_time_entry` / `remove_time_entry` used by both Timesheets and the Job's Labor
  section (`update_job_time_entry`, `delete_job_time_entry` become wrappers). A Job ↔ General change moves the
  row between tables keeping its id. A person change re-prices at the new person's current rate (cost follows
  who did the work); same person keeps the recorded rate.
- **Local times:** Timesheets sends day + start + end (HH:MM) in the business's time zone; the database turns
  them into instants. End at or before start means the next morning. 24 hours is the most one entry holds.
- **Manager actions:** `clock_in_member`; `stop_timer_at` (now or a chosen end, team or own-with-track_own);
  stopping at a chosen time ends the day — nothing resumes.

## Next action

Write migration `20261208090000_timesheet_corrections.sql`, then API routes, then the Timesheets UI.
