# Part 2 — Visit timer

**Plan:** `docs/time-clock-behavior-contract.md` § Timers, § Hours on the Job. **Stage:** Building.
**Code:** branch `time-clock`, worktree `/home/jafar/Ucrm-wt-time-clock` (pushed; **Waiting to merge**).
The worktree has untracked `node_modules` and `.env` links to the main folder.

## Done (2026-10-11)

- Migration `supabase/migrations/20261205090000_visit_timers.sql` is **applied to the remote database and
  recorded** — check with `select version from supabase_migrations.schema_migrations where version =
  '20261205090000'` before ever re-running it. It adds `running_timers` (one row per person = one timer),
  `job_time_entries.source`, `private.record_job_time_entry` (now also used by `add_job_time_entry`),
  `private.stop_running_timer`, `start_visit_timer`, `stop_my_timer`, `my_running_timer`; completing a visit
  stops its timers; `job_labor` returns `running`, `source` and `server_now`.
- Database behaviour proven in rolled-back transactions as the Raad LTD field member on Job #20: repeat
  Start is idempotent, under a minute records nothing, 40 minutes records once, second Stop records nothing,
  completing the visit records 2 hours, completed visit refuses Start, over 24 hours refuses Stop, second
  timer refused, direct table read and private functions refused. Test scripts were in the session
  scratchpad only.
- `src/lib/database.types.ts` regenerated. API: `src/routes/api/time-clock/timer/+server.ts` (GET, POST
  start) and `timer/stop/+server.ts`. Client: `src/lib/time-clock/api.ts`. Components:
  `src/lib/components/time-clock/VisitTimerControl.svelte`, `TimerElapsed.svelte`. Schedule popover shows
  the control through a new `timer` snippet slot in `VisitPreview.svelte`; completing there refreshes timers.

## Technical decisions

- A deleted visit leaves its timer running against the Job (`visit_id` set null). A closed Job refuses Start,
  but Stop still records, flagged `after_close`. Completing a visit leaves a timer over 24 hours running.
- Running time is counted from the server clock (`server_now` offset), not the phone's.

## Next

1. `src/lib/components/jobs/JobVisitsSection.svelte`: add `VisitTimerControl` to each open visit row
   (was choosing between the `__meta` column and under `__body` for phone layout), and call
   `refreshAfterTimer(queryClient, jobId)` in `completeVisit`.
2. `src/lib/components/jobs/JobLaborSection.svelte`: show `labor.running` rows with `TimerElapsed` and a
   running-clock mark, outside the totals. Add `running`, `server_now` and entry `source` to the `JobLabor` and
   `JobTimeEntry` types in `src/lib/jobs/api.ts`.
3. Route tests for both timer routes, modelled on
   `src/routes/api/reports/financial/time-entries/time-entries.spec.ts`. Run the `VisitPreview` and
   `JobVisitsSection` specs; the latter now fetches `/api/time-clock/timer`, so mock it if noisy.
4. One `npm run check`, then lint and Prettier on the changed files.
5. Live proof: run the worktree dev server on a spare port, sign in as the field member (`Login.md`), and
   time Job #20's open visit on Schedule and the Job page at 390px and 1440px. Then do the design screen check.
6. Merge `time-clock` into `main`, push, mark Part 2 done in `ROADMAP.md`, and delete this note.
