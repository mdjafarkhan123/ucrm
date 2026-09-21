# Migration baseline — now

**Goal:** Repo migrations rebuild the live database exactly; remote ledger agrees. See `ROADMAP.md` (read only to change scope).

**Active part:** Part 3 — prove it. Parts 1 and 2 closed 2026-09-21 (baseline committed; nothing applied to the live database or ledger).

**Exact next action:** In a fresh session, read `parts/part-3-prove.md`, stand up the throwaway proof stack it describes, run all 162 pgTAP files on
the rebuild, fix stale tests (first: `package_access.sql`), fix any real baseline gap and re-prove, and record the pass counts. Files and the
throwaway stack only — apply nothing to the live database.

**Blockers:** none. Part 4 (live ledger repair) needs Jafar's separate go-ahead.

**Pointers:** `parts/part-3-prove.md`; `Memory/deferred/two-migration-ledger-rows-do-not-match-the-repo.md` (deleted when Part 4 closes). Until Part 4,
new migrations still go through `mcp__supabase__apply_migration` with the local file renamed to the version the ledger records.

**After this campaign (default):** return to the deferred-cleanup work — start at `Memory/deferred/INDEX.md`. Already triaged and left for a
decision or another campaign: R2 line-photo cleanup (Files and Media), unindexed foreign keys, functions executable by everyone, four more
composite foreign keys, and the screen items. Ask Jafar before starting any of those.

**Resume command:** `read memory and continue migration-baseline`
