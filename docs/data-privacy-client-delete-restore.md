# Delete and restore a customer — technical design

**Part 6 of** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a customer (approved 2026-10-24). This
file is the implementation plan; it changes no promised behaviour. The permanent delete it hands over to on day
30 is `docs/data-privacy-deletion-engine.md`. Look: `concept.pen` `WEpOG` (pop-ups) and `Wf0tP` (Recently Deleted).

## Patterns followed

- **Salesforce Recycle Bin:** deleting a parent marks it and the children deleted with it (`IsDeleted`); ordinary
  queries never return marked rows, and undelete brings the parent and those children back together. Here the mark
  is `client_deleted_at` on each work row, and row-level security hides marked rows from every member read.
- **HubSpot restore:** 30 days, a list with who deleted and when, restore one or many, and a check for a newer
  record with the same email (we offer the existing Merge tool instead of refusing).
- **Our own:** `archive_client` / `restore_client` (checked commands with history rows), `delete_property` (one
  plan function for preview and action), `run_client_purge` + `cleanUpClientDeletion` (the day-30 delete).

## Data

- **`public.client_deletions`** — one row per delete: organisation, client, `deleted_at`, `deleted_by`,
  `purge_after` (deleted_at + 30 days), `counts` (the plan's counts at delete time, so the Recently Deleted page
  never recounts), `restored_at`/`restored_by`, `purged_at`/`receipt_id`, `failure`. Only one open row per client
  (partial unique index where restored and purged are null). Members read it through functions only.
- **`client_deleted_at timestamptz`** on the client's work: requests, assessments, quotes, jobs, job visits,
  properties, opportunities, tasks linked to the client, review requests, draft invoices, contact methods, and the
  conversation rows that carry `client_id`. Set to the client's `deleted_at` in the delete, cleared in restore.
  Issued invoices, payments and deposits are never marked: they stay in Invoices and reports, shown as
  "Deleted client" (§ Money records).
- `clients.deleted_at` already exists and is already filtered by client lists and search; the delete sets it.

## Hiding (§ During the 30 days)

1. **Member reads:** each marked table's SELECT policy gains `client_deleted_at is null`; `clients` gains
   `deleted_at is null`. A column on the row itself, so no join per row.
2. **Security-definer reads** (lists, boards, reports, schedule, inbox, search, customer links) bypass row
   security, so each reads `(select * from public.<table> where client_deleted_at is null)` instead of the table
   (`20270110091000`). Server code that reads with the service key (inbox, conversation search) adds
   `.is('client_deleted_at', null)`. **A new definer list or report over these tables must do the same.**
3. **Writes:** one trigger on each marked table refuses an insert or update for a deleted client, except inside
   the delete, restore and purge (transaction flag, as the engine does). Creating new work for a deleted client
   (direct API call, booking, import) fails the same way.
4. **Messages never reach them:** every send passes the outbox claim (`claim_communication_outbox_event`,
   `claim_communication_sms_outbox_event`) and marketing passes `marketing_recipient_blocked_reason`. Both skip a
   deleted client and mark the send cancelled, reason `client_deleted`. A send that fell due while deleted is
   therefore never sent late; one due after a restore goes as normal.
5. **They get in touch again:** `match_client_by_contact` and the inbound recorders ignore marked contact
   methods, so a message arrives as a new contact. The business-wide unique index on contact values becomes
   partial (`where client_deleted_at is null`), so that new contact can hold the same phone or email.

## Delete and restore commands

- `public.delete_clients(client_ids uuid[])` — needs `customers.delete`; at most 100; locks the clients in id
  order; runs `client_deletion_plan` for each; clients with blockers are left out and returned with their
  blockers (one client with blockers → nothing deleted, the pop-up shows the refusal). Marks, writes
  `client_deletions` and a history row per client. Returns deleted ids and left-out clients.
- `public.client_delete_preview(client_ids uuid[])` — counts and blockers for the pop-up (the plan, totals for
  many).
- `public.restore_client_deletions(deletion_ids uuid[], mode text)` — needs `customers.delete`; clears the marks.
  When a newer active client shares a phone or email, it reports the match instead of restoring, unless `mode` is
  `separate` (the restored client's clashing contact values are dropped, as the newer client keeps them) or
  `merge` (restores, then runs `merge_clients` into the newer client).
- `public.recently_deleted_clients(search, deleted_by, cursor)` — open rows, soonest `purge_after` first, 50 a page.

## Day 30

The existing client-deletion job (`client-deletion-hourly`, formerly daily) calls the same internal route with the
same secret, so no new Vault entry is needed. The route first runs `runScheduledClientDeletions`
(`src/lib/server/privacy/client-deletion-scheduled.ts`): it leases due rows for 30 minutes
(`claim_due_client_deletions`, skip-locked, five at a time, 40 s budget), calls `run_client_purge` with trigger
`scheduled`, and cleans up stored files straight away. The purge's trigger on `clients.purged_at` closes the delete
record. A refusal (new open money, a message mid-send) is kept on the row and retried next hour
(`record_client_deletion_purge_failure`); after a day of failures Jafar gets one alert. Then the Part 3 file-cleanup
sweep runs as before.

## Performance design

```text
Growth path       : per-customer work rows (delete/restore), deleted clients per business (page), every list read (filter)
Workload contract : heavy customer ≈ 1k jobs/visits, 10k messages (engine test business); ≤100 per bulk delete;
                    ≤ a few hundred deleted clients per business at once
Chosen shape      : one UPDATE per marked table per delete keyed by (organization_id, client_id); counts stored at
                    delete time; row-local filter in policies; partial index on client_deletions (organization_id, purge_after)
Complexity cost   : one column per marked table (no new index: marked rows are found by existing client_id indexes),
                    one table + one partial index, one hourly job
Rejected options  : policy join to clients per row (an extra lookup on every list row, and visits need job→client);
                    recounting on the page (27–133 ms per client)
Failure behavior  : delete is one transaction; bulk deletes lock in id order; day-30 retries hourly, skip-locked claims
Verification plan : delete + restore timing at the heavy test customer; EXPLAIN of clients, jobs, schedule and inbox
                    lists before and after; Recently Deleted page with 300 rows
Open decisions    : none
Overall           : Ready
```
