# Migration baseline — now

**Goal:** Repo migrations rebuild the live database exactly; remote ledger agrees. See `ROADMAP.md` (read only to change scope).

**Active part:** Part 4 — repair the remote ledger. Parts 1–3 closed 2026-09-21 (baseline committed; rebuild proven identical to live in structure
and permissions; nothing applied to the live database or ledger).

**Exact next action:** Ask Jafar for the go-ahead on Part 4. On yes: back up the ledger, `supabase migration repair` so remote history reads as
the four baseline files, confirm `supabase migration list --linked` is clean, then update `CLAUDE.md` test guidance and delete
`Memory/deferred/two-migration-ledger-rows-do-not-match-the-repo.md`. Uncommitted from Part 3: test fixes under `supabase/tests/database/`,
a comment fix in `...0100_baseline_platform_hooks.sql`, `major_version = 17` in `supabase/config.toml` — commit these first.

**Blockers:** Jafar's explicit approval for Part 4 (it changes the live ledger).

**Pointers:** `Memory/deferred/stale-database-tests-found-by-the-baseline-proof.md`; `Memory/deferred/revising-a-sent-quote-drops-tax-source-and-deposit.md`
(real live bug, Jafar to decide). Until Part 4, new migrations still go through `mcp__supabase__apply_migration` with the local file renamed to the
version the ledger records. A rebuilt database needs real Vault URLs/secrets before email-send paths work (see the hooks file comment).

**After this campaign (default):** return to the deferred-cleanup work — start at `Memory/deferred/INDEX.md`. Already triaged and left for a
decision or another campaign: R2 line-photo cleanup (Files and Media), unindexed foreign keys, functions executable by everyone, four more
composite foreign keys, and the screen items. Ask Jafar before starting any of those.

**Resume command:** `read memory and continue migration-baseline`
