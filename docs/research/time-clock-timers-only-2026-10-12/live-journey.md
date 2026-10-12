# Time clock Part 6 — timers-only proof (2026-10-12)

The Field member (`dev.jafarkhan@gmail.com`, Login.md) now holds only **Start and stop their own timers**
(`time.timers_own`), through the Field role. Branch dev server on port 5174, remote dev database.

## Database (rolled back, before applying `20261209090000_timers_only_permission`)

`database-proof.sql`, acting as the Field member:

| Check | Result |
| --- | --- |
| `can_run_own_timer` / `can_see_own_time` / `can_write_general_time` (own) | true / true / false |
| `timesheet_summary` | `can_add` false, own row only |
| `job_labor` on Job #20 | 3 own entries, `can_add` false, no entry editable |
| `job_time_entries` through RLS | 3 own rows |
| `time_entry_history` on own entry | readable |
| `clock_in`, then `clock_out` | both succeed |
| `add_time_entry`, `update_running_timer`, `stop_timer_at`, `delete_time_entry` | each refused: insufficient_privilege |

## Live app (`journey.mjs`, `team-access.mjs`)

- 390px with `--timer`: Start timer on the Job #20 visit → header shows the running timer → Stop timer after
  62 s → "1m added to this job's hours" (`timer-running-390.png`, `timer-stopped-390.png`); the entry landed
  once as `source = timer`, 1 minute.
- 390px and 1440px: Job Labor has no Add hours; Timesheets has no Add entry; the own row opens with 7 entries
  whose menu offers History only (`3-timesheets-entry-menu-*.png`). 7/7 checks at each width.
- `/api` as the Field member: POST and DELETE on Timesheets entries → 403 "Ask a manager to change your
  hours."; POST Job Labor hours → 404 (the Labor commands answer a refusal as not-found on purpose).
- Owner's Team access for the Field member: "Start and stop their own timers" ticked, "Record and change
  their own hours" and "anyone's hours" unticked (`team-access-*.png`).
