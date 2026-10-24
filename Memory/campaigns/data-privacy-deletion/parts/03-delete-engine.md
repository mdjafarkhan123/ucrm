# Part 3 — Permanent-delete engine

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Money records, § "Don't contact me", § Delete
permanently now. **Design (read first):** `docs/data-privacy-deletion-engine.md` — record-by-record result,
fingerprints, transaction order, performance verdict (Ready).
**Branch:** `claude/data-privacy-part3`, folder `.worktrees/data-privacy-part3` (branched from the planning
branch), reservation `22a159eee4c9`.

## Slices

- **3a Database engine** — migration **drafted, NOT applied, NOT tested**:
  `supabase/migrations/20270108090000_client_permanent_delete_engine.sql` (purged_at, step-aside flag in 11
  guard/alert triggers, usage/charge FKs → SET NULL, Vault key + fingerprint table + re-entry trigger,
  receipts, `private.client_deletion_plan`, `private.apply_client_purge`, `public.run_client_purge`).
- **3b Provider cleanup** — `src/lib/server/privacy/` worker: storage objects and Twilio messages from the
  receipt's pending arrays (subaccount from `communication_twilio_accounts` by organization), retry, owner
  alert, vitest spec. Model on `src/lib/server/jafar/organization-closure-cron.ts`.

## Next action

1. Re-read the migration against the design; then write pgTAP `supabase/tests/database/client_permanent_delete.sql`
   (pattern: `organization_purge.sql`, `begin … rollback`). Seed one customer with every record kind (work,
   invoiced job, deposit quote, messages + attachments, notes, files, STOP, unsubscribe, suppression).
2. Apply the migration with the CLAUDE.md `psql` command, run the suite with `psql -f`, fix until green.
3. Regenerate `src/lib/database.types.ts`; the three usage tables' `delivery_intent_id` become nullable —
   grep TS users.
4. Performance EXPLAIN on a heavy seeded customer; record in the design file. Then 3b.

## Found while mapping (for later parts)

- **Part 6:** `client_contact_methods_org_value_unique_idx` (one phone/email per business) blocks a new
  contact with the same phone while a soft-deleted client still holds it. The tombstone row still accepts new
  inserts, so every send and creation path must check `deleted_at`.
- **Check in 3b:** inbound messages never matched to the client, original import files in storage, and any
  stored raw inbound email are not covered yet.
