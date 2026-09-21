# Migration baseline — roadmap

**Goal:** The repo's migration files can rebuild the live database exactly, and the remote ledger agrees with them, so
the self-hosted rehearsal and `supabase db push` / `supabase test db` work. Industry method: squash to a baseline taken
from the live database, then prove it by rebuilding and diffing.

**Evidence (2026-09-21):** 351 of 690 ledger rows differ; a throwaway rebuild from the repo fails at duplicate version
`20260916110000`; `supabase db dump --linked` works (Docker available). Details: `Memory/deferred/two-migration-ledger-rows-do-not-match-the-repo.md`.

## Part 1 — Inventory what a structure dump omits (read-only)
- **Outcome:** a checklist of everything the live database holds that `supabase db dump` will not capture: seed/reference rows,
  `pg_cron` schedules, `auth`/`storage`/`realtime` objects made by migrations, extensions, and any repo file never applied remotely.
- **State:** Done 2026-09-21 — results in `parts/part-2-baseline.md`.
- **Gate:** met; no database change.

## Part 2 — Build the baseline in the repo
- **Outcome:** one baseline migration (structure + reference rows + cron schedules + omitted objects); the 500 old files leave
  `supabase/migrations/` (git keeps them); no repo file is unaccounted for.
- **State:** Done 2026-09-21 — four baseline files committed; old files in `supabase/migrations-archive/pre-baseline-2026-09-21/`.
- **Depends on:** Part 1. **Gate:** files only; nothing applied to the live database.

## Part 3 — Prove it
- **State:** Next — packet `parts/part-3-prove.md`.
- **Outcome:** a fresh rebuild from the baseline, in a throwaway container, gives an empty `supabase db diff --linked`, and the
  pgTAP files (`tenant_isolation`, `quote_proposal_draft_commands`, `automation_6d2`) pass on it.
- **Depends on:** Part 2. **Gate:** diff shows only the accepted noise list (packet) and passing tests, recorded.

## Part 4 — Repair the remote ledger (approval gate)
- **Outcome:** ledger backed up, then `supabase migration repair` so remote history reads as the baseline; `supabase migration list --linked`
  shows no mismatches; deferred notes and `CLAUDE.md` test guidance updated.
- **Depends on:** Part 3 and Jafar's explicit go-ahead. **Gate:** clean list, app still works, rollback path (ledger backup) confirmed.
