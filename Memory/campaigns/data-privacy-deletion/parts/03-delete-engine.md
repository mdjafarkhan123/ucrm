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

## Follow-ups done 2026-10-24 (Jafar: "solve those others following top industries")

Branch `claude/data-privacy-part3-followups`, reservation `e4949b98c6b7`.
- Org purge fixture fixed: pgTAP `organization_purge.sql` 42/42 on the checked-in file.
- Unlinked messages from the customer's email/phone go with them (`20270109094000`); pgTAP 66/66.
- Marketing SES event bodies emptied 30 days after processing, nightly (`20270109095000`); pgTAP 6/6.
- Import spreadsheets filed in Files › Imports, origin "Import", everyone with Files sees them, kept until the
  business trashes them (Jafar's answers); `20270109096000`, pgTAP 8/8, import vitest 102/102. Six earlier dev
  imports filed by a one-off run. On dev they stay "pending" because no virus scanner runs there.

## Provider checks (Jafar and Claude in his consoles, 2026-10-24)

- AWS: the inbound-email bucket lives in member account `UCRM Production Workloads` (881776924275; sign in through the
  access portal as `jafar.admin`, AdministratorAccess). Lifecycle rule `expire-raw-reply-mime-30d` already expires
  every object on day 30, whole bucket, enabled. Part 15's wording can say raw inbound email is kept 30 days.
- Twilio: account created 2026-04-30; Twilio enables automatic deletion of closed subaccounts' data 30 days after
  closure by default for accounts created after 2018-07-05, and the One Console has no switch for it. Nothing to do.
- Possible later: the same 30-day body rule for `communication_provider_callback_events` (the inbound attachment
  worker reads SES callback bodies, so check it first). Not raised with Jafar yet.

## Found while mapping (for later parts)

- **Part 6:** `client_contact_methods_org_value_unique_idx` blocks a new contact with the same phone while a
  soft-deleted client still holds it. Every send and creation path must check `deleted_at`.
- **Delete-now API (Part 7) and day-30 delete (Part 6):** call `run_client_purge` from the server (60 s limit;
  heavy customer 1.2–10 s), then `cleanUpClientDeletion(receipt_id)` after the response is sent. Preview
  (`client_deletion_plan`) 27–133 ms.
- Dev database cleanup 2026-10-24: 1018 → 124 MB; nightly `cron-run-history-trim-nightly` (`20270109090000`).

## Next action

Part 3 and its follow-ups are done. Next: Pencil design parts 4, 5, 8, 11, 13.
