# Part 3 — Permanent-delete engine

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Money records, § "Don't contact me", § Delete
permanently now. **Design (read first):** `docs/data-privacy-deletion-engine.md`.
**Branch:** `claude/data-privacy-part3`, folder `.worktrees/data-privacy-part3` (branched from the planning
branch), reservation `ee89c1c453ce`. Pushed.

## Slices

- **3a Database engine — done.** Migration `20270108090000` (applied to dev; later function edits re-applied by
  hand from the file, so file and database match). pgTAP `client_permanent_delete.sql` 64/64. Big test on a
  1M-text local copy done (index fix `20270109092000`).
- **3b Stored-file cleanup — done 2026-10-24.** Engine no longer collects Twilio ids (column dropped).
  `src/lib/server/privacy/client-deletion-cleanup.ts` (`cleanUpClientDeletion` right after a delete, daily
  sweep), `deleteObjects` in `r2.ts`, route `/api/internal/privacy/client-deletion-cleanup`, job
  `client-deletion-cleanup-daily` (migration `20270109093000`, applied; dev Vault URL and secret set;
  `CLIENT_DELETION_CRON_SECRET` added to main `.env`). Evidence: vitest 7/7; live R2 multi-delete; branch dev
  server: wrong secret 401, right secret deleted two real R2 files and completed a test receipt (removed after).
- **3c Business closure closes Twilio — done.** Migration `20270109091000`; vitest 24/24, pgTAP 6/6.

## Ask Jafar (in plain English; each is an extra fix that waits for his yes)

1. Fix the checked-in `organization_purge.sql` fixture (line ~89 needs `proposed_other = 'something_else'`).
2. Emails from the customer's address that never got linked to them stay after delete. Proposed: the engine also
   deletes the business's unlinked inbound messages whose sender is one of the customer's emails or phones.
3. Original import spreadsheets stay in storage after import, listing deleted customers. Proposed: delete the
   original once its import finishes (only the review step reads it); the error file follows the same rule.
4. Raw inbound emails sit in AWS S3 `ucrm-ses-inbound-mime`. The app's key cannot read the bucket's expiry rule;
   Jafar checks the AWS console for one (proposed 30 days). Its number also feeds Part 15's wording.
5. Stray marketing provider events with no recipient row keep an email in
   `marketing_campaign_recipient_events.payload`; proven fix is a retention sweep for raw provider events.
6. Twilio console: turn on deleting closed subaccounts' data after 30 days.

## Found while mapping (for later parts)

- **Part 6:** `client_contact_methods_org_value_unique_idx` blocks a new contact with the same phone while a
  soft-deleted client still holds it. Every send and creation path must check `deleted_at`.
- **Delete-now API (Part 7) and day-30 delete (Part 6):** call `run_client_purge` from the server (60 s limit;
  heavy customer 1.2–10 s), then `cleanUpClientDeletion(receipt_id)` after the response is sent. Preview
  (`client_deletion_plan`) 27–133 ms.
- Dev database cleanup 2026-10-24: 1018 → 124 MB; nightly `cron-run-history-trim-nightly` (`20270109090000`).

## Next action

Part 3 is built. Merge the planning branch and this branch to main, then wait for Jafar's answers above. Any yes
becomes a small follow-up slice on the engine.
