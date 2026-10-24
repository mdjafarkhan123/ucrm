# Part 3 — Permanent-delete engine

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Money records, § "Don't contact me", § Delete
permanently now. **Design (read first):** `docs/data-privacy-deletion-engine.md` — record-by-record result,
fingerprints, transaction order, performance design and its verification (2026-10-24, Supported).
**Branch:** `claude/data-privacy-part3`, folder `.worktrees/data-privacy-part3` (branched from the planning
branch), reservation `22a159eee4c9`. Pushed.

## Slices

- **3a Database engine — done** (migration `20270108090000`, applied to the dev database; later edits to its
  functions and indexes were re-applied by hand from the file, so file and database match).
  `supabase/tests/database/client_permanent_delete.sql`: 64/64. Organisation purge still passes 42/42 using a
  patched fixture copy (see Ask Jafar). A sent text still waiting for Twilio's price is now charged at its
  send-time price, not refunded. Types for the engine spliced into `src/lib/database.types.ts` (only its own
  tables, columns and `run_client_purge`; the remote has other branches' changes).
- **3b Provider cleanup — next, not started.** Storage only. Twilio follows HighLevel (Jafar, 2026-10-24):
  no per-message delete at Twilio, no key permission change, no key rotation. First remove the engine's
  Twilio id collection (`pending_twilio_message_sids` / `twilio_messages` component) from
  `20270108090000`'s functions, re-apply by hand, update its pgTAP checks. Then a `src/lib/server/privacy/`
  worker modelled on `src/lib/server/jafar/organization-closure-cron.ts` (`finishProviderCleanup`,
  `retryReceiptCleanup`, the sweep): read `client_deletion_receipts` with pending
  `pending_storage_object_keys`; delete with `deleteObject` (`src/lib/server/storage/r2.ts`); merge
  `component_results` (`storage_objects`), clear done anchors, `completed` / `failed_partial`, owner alert on
  failure; vitest spec; internal cron route like `/api/jafar/internal/closure-cron`.

## Ask Jafar (word for word, in plain English when asked)

1. Fixing the checked-in `organization_purge.sql` fixture (line ~89 needs `proposed_other = 'something_else'`)
   is an extra fix and waits for his yes.

## Found while mapping (for later parts)

- **3c Business closure closes Twilio — done 2026-10-24** (Jafar: follow the top products). Migration
  `20270109091000` parks `{kind: 'twilio_subaccount', provider_id: <SID>}` on the purge receipt;
  `closeTwilioSubaccount` (`twilio.ts`, master credential, closed/404 = done) runs from
  `organization-closure-cron.ts`, which now retries only the resources that failed. Tests: vitest 24/24
  (`twilio-subaccount-close.spec.ts`, closure cron spec), pgTAP `organization_purge_twilio.sql` 6/6, org purge
  42/42 (patched copy), client delete 64/64. Jafar to check the Twilio console setting that deletes closed
  subaccounts' data after 30 days.
- **Dev database cleanup 2026-10-24:** 1018 → 124 MB (index rebuild; cron log trimmed to 7 days). Migration
  `20270109090000` adds the nightly `cron-run-history-trim-nightly` job (Supabase's recommendation), applied.
- **Big test (Part 16, 1M-message business):** won't fit the 500 MB free dev database. Jafar chose the top-industry
  way: a separate local copy (Supabase local stack in Docker, the same stack production uses). Waiting on Jafar
  to install Docker (needs his password); then `npx supabase start` from this worktree.

- **Part 6:** `client_contact_methods_org_value_unique_idx` (one phone/email per business) blocks a new
  contact with the same phone while a soft-deleted client still holds it. Every send and creation path must
  check `deleted_at`.
- **Check in 3b:** inbound messages never matched to the client, original import files in storage, any stored
  raw inbound email.
- **Ask Jafar later:** stray marketing provider events (a test send with no recipient row) keep the email in
  `marketing_campaign_recipient_events.payload`. The proven fix is a retention sweep for raw provider events.
- **For the delete-now API part:** call `run_client_purge` from the server; it allows 60 s (heavy customer
  took 6–10 s on dev). The preview (`client_deletion_plan`) took 62–133 ms.

## Next action

Start 3b: remove Twilio id collection from the engine, then the storage worker. Once Docker is installed, set up
the local database for the big test.
