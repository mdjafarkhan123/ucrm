# Migration baseline — now

**Goal:** Repo migrations rebuild the live database exactly; remote ledger agrees. See `ROADMAP.md` (read only to change scope).

**Active part:** Part 2 — build the baseline in the repo. Part 1 (inventory) closed 2026-09-21.

**Exact next action:** In a fresh session, read `parts/part-2-baseline.md` and follow it: (1) regenerate the structure dump with
`npx supabase db dump --linked`; (2) run the unapplied-work replay-and-diff drift report and show Jafar anything in the repo but not live;
(3) write the baseline migration (structure + reviewed reference rows + cron jobs off by default + `auth.users` trigger + `realtime.messages`
policies + Vault placeholders); (4) move the old files out of `supabase/migrations/`. Files only — apply nothing to the live database.

**Blockers:** Part 2 needs Jafar's look at the drift report and at which owner-edited reference values to carry. Part 4 changes live ledger
rows and needs his explicit go-ahead.

**Pointers:** `parts/part-2-baseline.md`; `Memory/deferred/two-migration-ledger-rows-do-not-match-the-repo.md`. Docker works
(`supabase_db_ucrm` local stack is running on 54322 — leave it alone; diff/dump use throwaway containers).

**After this campaign (default):** return to the deferred-cleanup work this campaign came from — start at `Memory/deferred/INDEX.md`
(65 notes on 2026-09-21; the ledger note is deleted when Part 4 closes and the database-tests note is updated). Already triaged and left
for a decision or another campaign: R2 line-photo cleanup (Files and Media), unindexed foreign keys, functions executable by everyone,
four more composite foreign keys, and the screen items. Ask Jafar before starting any of those.

**Resume command:** `read memory and continue migration-baseline`
