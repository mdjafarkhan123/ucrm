# Part 3 — Permanent-delete engine

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Money records, § "Don't contact me", § Delete
permanently now. **Design (read first):** `docs/data-privacy-deletion-engine.md` — record-by-record result,
fingerprints, transaction order, performance verdict (Ready).
**Branch:** `claude/data-privacy-part3`, folder `.worktrees/data-privacy-part3` (branched from the planning
branch), reservation `22a159eee4c9`.

## Slices

- **3a Database engine — applied to the dev database 2026-10-24** (version `20270108090000`).
  `supabase/tests/database/client_permanent_delete.sql`: 63 checks pass on the applied database. Two
  deliberate breakages (alert guard removed, carry-over trigger dropped) made the matching checks fail.
  Dry runs on 5 real test customers (rolled back) found nothing personal left, and money was byte-identical.
  The scratchpad scripts are gone; to rerun, wrap `run_client_purge` in `begin … rollback`.
  Fixed along the way (all in the migration): the note-file tidy-up trigger failed on every note link delete,
  so "delete note" in the app was broken; a deposit or payment on a draft invoice now refuses the delete
  (`draft_invoice_holds_money`, the same rule as `delete_invoice_draft`); a STOP still in force for any SMS
  subject is kept; library files sent in a message are linked by delivery intent id.
- **3b Provider cleanup** — not started. `src/lib/server/privacy/` worker: storage objects and Twilio messages
  from the receipt's pending arrays (subaccount from `communication_twilio_accounts` by organization), retry,
  owner alert, vitest spec. Model on `src/lib/server/jafar/organization-closure-cron.ts`.

## Next action

1. Check the organisation purge still works with this migration: `organization_purge.sql` already fails at
   its fixture (line 98, `platform_onboarding_applications_proposal_check`: the fixture needs
   `proposed_experience_key` + `proposed_definition_version`). Run a patched copy in the scratchpad only;
   fixing the checked-in test waits for Jafar's yes.
2. Regenerate `src/lib/database.types.ts`; the three usage tables' `delivery_intent_id` are now nullable —
   grep TS users.
3. Performance: EXPLAIN (ANALYZE, BUFFERS) on a heavy seeded customer; record it in the design file (a small
   real customer took 1.5 s).
4. Then 3b.

## Found while mapping (for later parts)

- **Part 6:** `client_contact_methods_org_value_unique_idx` (one phone/email per business) blocks a new
  contact with the same phone while a soft-deleted client still holds it. Every send and creation path must
  check `deleted_at`.
- **Check in 3b:** inbound messages never matched to the client, original import files in storage, any stored
  raw inbound email.
- **Ask Jafar later:** stray marketing provider events (a test send with no recipient row) keep the email in
  `marketing_campaign_recipient_events.payload`, reachable only by a whole-table scan. The proven fix is a
  retention sweep for raw provider events.
