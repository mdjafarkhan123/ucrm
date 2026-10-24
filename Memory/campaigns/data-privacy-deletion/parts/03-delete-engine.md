# Part 3 — Permanent-delete engine

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Money records, § "Don't contact me", § Delete
permanently now. **Design (read first):** `docs/data-privacy-deletion-engine.md` — record-by-record result,
fingerprints, transaction order, performance verdict (Ready).
**Branch:** `claude/data-privacy-part3`, folder `.worktrees/data-privacy-part3` (branched from the planning
branch), reservation `22a159eee4c9`.

## Slices

- **3a Database engine** — migration: `clients.purged_at`, `contact_opt_out_fingerprints` + Vault key +
  re-entry trigger, `client_deletion_receipts`, usage/charge foreign keys to `SET NULL`, step-aside flag
  `app.client_purge_in_progress` in history/alert triggers, `private.client_deletion_plan`,
  `private.apply_client_purge`. pgTAP suite `supabase/tests/database/client_permanent_delete.sql`.
- **3b Provider cleanup** — `src/lib/server/privacy/` worker: storage objects and Twilio messages from the
  receipt anchors, retry, owner alert; vitest spec.

## Done when

pgTAP on a seeded test business: nothing personal left for the customer (every table in the design), money
totals and financial summaries unchanged, a STOP / unsubscribe / suppression carried to a re-imported
contact, a second run is a no-op, open money refuses. Performance EXPLAIN recorded in the design file.

## Next action

Write the 3a migration `supabase/migrations/20270108090000_client_permanent_delete_engine.sql`.
