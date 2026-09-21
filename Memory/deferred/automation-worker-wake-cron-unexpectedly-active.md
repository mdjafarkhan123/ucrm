# The automation worker's one-minute wake sweep is active on the shared remote database

- **Priority:** P2
- **Found:** 2026-09-21, incidentally, while verifying an unrelated pgTAP fix in
  `automation_6d2_claims_and_recovery.sql`.
- **Reason postponed:** Not this task's scope, and flipping a live cron job needs Jafar's judgment call, not
  a unilateral fix.
- **What was found:** `supabase/migrations/20260831022758_automation_worker_wake.sql` schedules the
  `automation-worker-wake-one-minute` Cron job and immediately deactivates it
  (`cron.alter_job(job_id, active := false)`), intending it to stay off "until deployment configuration is in
  place." On the live remote database right now, `cron.job` shows it `active = true`. No migration in the repo
  re-enables it, so something toggled it live (manually, via the dashboard, or via another session's work) —
  not tracked in any migration file.
- **Why it matters:** If unintentional, this means the automation worker sweep may be firing for real tenants
  every minute already, ahead of the deployment readiness this was gated on. If intentional (e.g. automation
  went live as part of other recent work), the stale test and this note are the only record of the change.
- **Reactivation trigger:** Jafar confirms whether this is intentional. If yes, update
  `supabase/tests/database/automation_6d2_claims_and_recovery.sql`'s last assertion to expect `true` and note
  why in a comment. If no, turn it back off with `select cron.alter_job(job_id, active := false)` and find out
  what turned it on.
- **Pointer:** `supabase/migrations/20260831022758_automation_worker_wake.sql`.
