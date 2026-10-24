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
- **3b Provider cleanup — next, not started.** `src/lib/server/privacy/` worker modelled on
  `src/lib/server/jafar/organization-closure-cron.ts` (`finishProviderCleanup`, `retryReceiptCleanup`, the
  sweep): read `client_deletion_receipts` with pending `pending_storage_object_keys` /
  `pending_twilio_message_sids`; delete storage with `deleteObject` (`src/lib/server/storage/r2.ts`); delete
  Twilio messages with `DELETE /2010-04-01/Accounts/{sub}/Messages/{sid}.json` (204; 404 = already gone);
  subaccount from `communication_twilio_accounts` by organisation; credentials like
  `defaultResolveSmsCredentials` (`sms-worker.ts`); merge `component_results`
  (`storage_objects`, `twilio_messages`), clear done anchors, `completed` / `failed_partial`, owner alert on
  failure; vitest spec; internal cron route like `/api/jafar/internal/closure-cron`.
  **Blocker for the Twilio leg:** the restricted key lacks delete (see Ask Jafar). Build the storage leg and
  the Twilio leg's code now; the Twilio leg stays failing until the key is updated.

## Ask Jafar (word for word, in plain English when asked)

1. "To delete a customer's text messages at Twilio, the app's Twilio key needs one more permission,
   `/twilio/messaging/messages/delete` (confirmed in Twilio's Messaging permissions PDF). New keys would get it
   automatically. The one existing business's key would need to be swapped for a new one once, using the app's
   built-in key rotation. Can I add the permission and rotate that key?" Code: add it to
   `RESTRICTED_KEY_MESSAGING_CAPABILITIES` in `src/lib/server/communications/twilio.ts`; rotate with
   `rotateRestrictedKey` (`twilio-provisioning.ts`). Rotation is outward — verify the new key's policy after.
2. Fixing the checked-in `organization_purge.sql` fixture (line ~89 needs `proposed_other = 'something_else'`)
   is an extra fix and waits for his yes.

## Found while mapping (for later parts)

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

Start 3b with the storage leg and the worker shape; ask Jafar question 1 at the start of the session.
