# Permanent customer delete — technical design

**Part 3 of** `docs/data-privacy-deletion-behavior-contract.md` (approved 2026-10-24). This file is the
implementation plan for the hidden engine behind "Delete permanently now", the day-30 delete and Jafar's
"Delete for them". It changes no promised behaviour; where a technical choice touches what users see, the
plan section it serves is named.

## Patterns followed

- **Tombstone plus anonymise** for records the law makes us keep: the customer row stays as an empty
  "Deleted client" shell so kept invoices and payments still have something to point at. Stripe does the
  same with a deleted customer (the object remains with `deleted: true`, its charges keep referencing it).
  GDPR Art. 17(3)(b),(e) lets legally required records survive an erasure request (research §6).
- **Our own proven deletes:** `delete_property` (one plan function drives the preview and the delete; locks,
  then re-reads the plan; a transaction-local flag lets history guards step aside),
  `apply_organization_purge` + `organization-closure-cron.ts` (a receipt row with pending external
  cleanup anchors, retried until done, with an owner alert on failure), and `merge_clients` (the full list
  of tables that point at a customer, including the type-and-id links with no foreign key).
- **Twilio message delete:** `DELETE /2010-04-01/Accounts/{AccountSid}/Messages/{Sid}.json` returns 204 and
  also deletes the message's media; bodies may stay up to 30 days in Twilio's backups (Twilio Message
  resource docs, read 2026-10-24). Resolves the plan's "Unverified" Twilio assumption.

## What happens to each kind of record

| Kind | Result |
| --- | --- |
| Customer row | Tombstone: `display_name` "Deleted client", names, company, billing address, lead fields cleared; `deleted_at` kept or set; new `purged_at` set. Never hard-deleted. |
| Contacts, phones, emails, preferences, consent rows | Deleted, after "don't contact me" fingerprints are written (below). |
| Properties | Deleted, except one a kept quote shell still needs, which is scrubbed to "Deleted" with no notes or map pin. |
| Requests, assessments, jobs, visits, checklists, reports, signatures, time, expenses, costing | Deleted. `invoice_sources` rows for those jobs are removed first (the invoice keeps its own frozen lines, totals, customer and address snapshots). |
| Quotes | Deleted, except a quote that took a deposit or has a card checkout: it stays as an anonymous shell (number, status, currency, amounts) because the deposit report and the invoice's payment list read the deposit through it. Its versions lose the customer name, service address and messages; lines, attachments, recipients, links, decisions and signatures go. |
| Issued invoices, lines, history, payments, refunds, allocations, deposits, opening balances, card checkouts and refunds | Kept unchanged (§ Money records). Invoice and receipt links keep working; the stored recipient name and email on those links are cleared. |
| Draft invoices | Deleted with their history rows. |
| Messages on every channel | Deleted: send records and their events, inbound messages and attachments, forwards, reply aliases, Messenger identities, website chat, read marks, assignees, followers, and the raw provider callback rows behind them. |
| The business's text and email usage and charges | Kept: SMS credit reservations, email usage events and capacity reservations lose their link to the deleted message instead of being deleted with it (foreign keys become `ON DELETE SET NULL`), so the business's bill and allowance counts never change. |
| Marketing campaign send records | Kept as anonymous rows (no email, name "Deleted client") so campaign totals do not change, as HubSpot keeps anonymous totals. |
| Pipeline cards, tasks, call logs, review requests and feedback, shared-file links, campaign attribution | Deleted. |
| Notes, tags, files, activity, bell notifications, automation enrollments and events, form submissions, import rows, merge snapshots | Deleted when they belong to the customer or a deleted record. A note or file also linked to a record that stays keeps living there. File objects are queued for storage deletion. |

## "Don't contact me" fingerprints (§ "Don't contact me" survives deletion)

- New table `contact_opt_out_fingerprints (organization_id, channel, fingerprint, kind, opted_out_at)`.
  `fingerprint` = HMAC-SHA256 of the normalised phone or email under a key held in Supabase Vault, so a
  table dump alone cannot be reversed by trying every phone number.
- Written at purge for: an SMS number whose latest consent event is an opt-out; an email whose marketing
  state is unsubscribed; an organisation email suppression (bounce, complaint, unsubscribe) for an address
  no remaining customer uses (the plain suppression row is then removed); a stricter contact policy
  (`no_marketing`, `do_not_disturb`) on the customer.
- **Re-entry, not new gates:** a trigger on `client_contact_methods` insert or value change looks the new
  value up and, on a match, writes the ordinary record the existing send checks already read — an SMS
  opt-out consent event, a marketing unsubscribe event, a suppression row, or the contact policy. Every
  sending path (manual, automation, campaigns, imports) is covered without touching the send gates. A later
  START or opt-in is newer than the carried event, so it wins, as the plan promises.

## Order inside one transaction (`private.apply_client_purge`)

1. Lock the client row; refuse if already purged or if `private.client_deletion_plan` finds open money
   (unpaid balance, card payment settling, unused credit or deposit, refund pending) or a message mid-send
   at the provider. Lock the work rows and re-read the plan, as `delete_property` does.
2. Turn on `app.client_purge_in_progress`. History guards (published quote content, costing, signatures,
   protected file links, draft-invoice history) step aside for it, and the schedule-alert and
   schedule-change triggers stay quiet, so no crew alert or customer notice names a deleted person.
3. Collect provider work into the receipt: storage object keys (files, signatures, message attachments,
   form photos) and Twilio message ids with their subaccount.
4. Write fingerprints. Delete in dependency order (automation, notifications and type-and-id links; messages;
   jobs; quotes; requests; properties; contacts). Scrub the shells. Tombstone the client.
5. Insert `client_deletion_receipts`: who, when, trigger (`delete_now`, `scheduled`, `platform_owner`), item
   counts, what was kept and why, and pending provider anchors. No names, addresses or message content.

## Provider cleanup (server, `src/lib/server/privacy/`)

After commit, a worker deletes each queued storage object and Twilio message, marks the receipt's
components done, and retries on the next run. "Already gone" counts as success. A component still failing
raises a Jafar owner alert, as the organisation purge does.

## Performance design

```text
Performance Design – permanent customer delete
Growth path       : rows owned by one customer (messages and their events, jobs and visits, files);
                    day-30 batches of many customers after a bulk delete
Workload contract : assume a heavy customer has ≤ 5,000 messages, ≤ 300 jobs, ≤ 3,000 visits,
                    ≤ 1,000 files (≈ 50,000 rows with cascades); organisations up to ~1M message rows.
                    Background work, no user waiting; delete-now shows progress until the receipt.
Chosen shape      : one transaction per customer through one plan function; set-based deletes keyed by
                    the customer's id arrays; provider calls after commit from receipt anchors.
                    Scheduled purges claim customers with FOR UPDATE SKIP LOCKED, a few per run.
Complexity cost   : one fingerprint table + index, one receipt table, one Vault secret; no new indexes
                    until the verification plans below show a referential check scanning an organisation.
Rejected options  : a queue service (pg_cron + receipt anchors already retry); per-row loops (set-based
                    deletes are bounded by the arrays); deleting money anchors (would change reports).
Failure behavior  : any SQL error rolls the whole delete back; provider failures leave anchors for retry
                    and an owner alert; a second run on a purged customer is a no-op.
Verification plan : EXPLAIN (ANALYZE, BUFFERS) of the purge on a seeded heavy test customer inside a rolled-
                    back transaction; check each cascaded child delete uses an index (no seq scan on the
                    big communication tables, job_visit_assignments, visit_checklist_answers, consent
                    events); record total time; confirm financial summaries are byte-identical before and
                    after.
Open decisions    : none.
Overall           : Ready
```
