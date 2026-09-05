# Invoice Part 2 — approved foundation design

**Part 2 complete: corrected research/design redline approved by Jafar.**
This includes D1–D5 and the seven corrections below. Implementation remains unstarted; Jafar requested
a documentation-only handoff and stop. Resume implementation only when Jafar directs it.
The [Invoice contract](invoice-behavior-contract.md) is authoritative. This proposal adds no display status,
processor infrastructure, general ledger, chart of accounts, new queue, or accounting framework.

## Existing seams checked

- `clients` already has `client_type = person/company`. `properties.is_billing_address` already has a
  one-per-Client unique index. Source: `20260816103906_client_property_data_model.sql`.
- Invoice repository, service and validation files are zero-byte placeholders; no customer Invoice/payment
  tables were found in active migrations. Organization subscription/onboarding payments are unrelated.
- `quote_deposit_events` already retains received/reversed events, restricted to cash/check/other and a
  published Quote version. Reuse its receipts rather than copying money into a second receipt table.
  Source: `20260821104331_quote_deposit_configuration_and_recording.sql`.
- `job_invoice_reminders` already has pending/resolved state and `invoiced` resolution. Visit completion
  locks Job then Visit and creates the per-visit reminder. Sources: `20260901105659_jobs_invoice_reminders_and_requires_invoicing.sql`,
  `20260903120000_jobs_visit_completion_and_lifecycle.sql`.
- Job installment/per-Visit quantity work is still a dependency, not an existing table to pretend to reuse.
  `20260901101459_jobs_pricing_and_billing_commands.sql` explicitly leaves it to Jobs 11c.
- Quote commands already validate `/api` requests and call protected database commands; money projections
  withhold price/cost columns. Shared notes/activity/attachments and Communications already exist.
  Reuse their mechanisms, not empty Invoice scaffold behavior.

## Proven mechanism and alternatives

Use ordinary Postgres relationships, constraints and short transactions with explicit row locks, as used in
our Quote/Job commands. Supabase recommends combining table grants with tenant RLS; PostgreSQL documents
consistent lock ordering to avoid deadlocks. These mechanisms enforce the business invariants without a
new service. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Postgres locking](https://www.postgresql.org/docs/current/explicit-locking.html).

Keep receipt facts separate from where money is applied. This is required by D1/D2/D3, not an invitation to
build double-entry accounting. A single mutable payment total would lose correction history; copying the
entire Quote version/package model would add unrelated proposal machinery. Use explicit Invoice records,
line rows, source claims and retained financial entries instead.

## Proposed records

All new child records carry organization ownership. Monetary amounts use signed `bigint` minor units;
quantities use the existing `numeric(12,3)` convention. Date-only terms remain dates; action times are
`timestamptz`. Every cross-record reference must also enforce same Client where applicable.

| Record                             | Minimal responsibility and constraints                                                                                                                                                                                                                                                                                                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Existing `clients`                 | Add optional custom billing-address fields and payment-term override. Preserve existing `client_type`; no residential/commercial status.                                                                                                                                                                                                                                                   |
| Existing `properties`              | Keep designated billing flag. Custom Client address and designated Property are mutually exclusive via one guarded Client billing command. No silent primary-Property fallback.                                                                                                                                                                                                            |
| `invoice_payment_terms`            | Organization-owned named terms: day count or protected receipt/month-end rule. Client override and residential/commercial organization defaults reference these. Custom Invoice date stays on the Invoice, not a new term. Put defaults on existing organization settings.                                                                                                                 |
| `organization_invoice_counters`    | One counter per organization; non-reused number. Unique organization/number on Invoice. Reuse on failed transaction is safe because no Invoice committed; never reuse a committed/deleted number.                                                                                                                                                                                          |
| `invoices`                         | Client, number, revision, subject, customer/billing/terms snapshots, currency code snapshot, immutable service-property snapshot array, totals, due date, issue facts, receipt recognition, void/write-off/mark-received facts, and immediate predecessor/root references, correction/rebill link kind, and frozen predecessor display label for replacement chains. No processor columns. |
| `invoice_lines`                    | Ordered customer-price lines, service date and applicable source-line references; validated tax/discount inputs and calculated results. No Quote packages/options or cost/markup.                                                                                                                                                                                                          |
| `invoice_sources`                  | One canonical billing claim per source unit, attached permanently to a billing-chain root. Explicit Job/Visit/reminder/installment references with valid-shape checks; no unvalidated generic entity ID. Each source identifies its entry in the Invoice service-property snapshot array; retained claims never resolve historical addresses from live Jobs.                               |
| `client_payment_events`            | Immutable manual receipt, external refund, or reversing entry, with Client, amount, six-method value when relevant, transaction date, reference/details, actor, currency snapshot and original-receipt reference for refunds (manual or Quote deposit, exactly one). No imaginary processing success. A correction reverses/replaces records; it does not edit money history.              |
| `invoice_payment_allocations`      | Retained application/unapplication entries linking an Invoice to either a manual receipt or an existing Quote deposit receipt (exactly one). Reversing entries reference the original application. Supports partial amounts; commands reject over-application/refund or double reversal.                                                                                                   |
| `invoice_events`                   | Append-only Invoice-specific history: financial closure/correction facts, prior issued-document snapshot, actor, reason, revision and stable Invoice identity/number. Excludes request fingerprints and retry results. Retained after permitted Draft deletion; no cascading history deletion.                                                                                             |
| Private `invoice_command_receipts` | Organization/action/idempotency identity, authorized actor, input fingerprint and stable result IDs for successful commands. Supports Client-only and multi-Invoice commands without an Invoice parent. No normal history access; replay never resurrects deleted work.                                                                                                                    |

That is **nine new tables including payment terms**, with targeted changes to
existing Client/settings records. Table names are proposals. Part 2 does not create any of them.

No duplicate Client credit table: credit is calculated from existing Quote deposits and manual receipts,
refunds, and allocations. Quote receipt reversal/deletion commands must refuse changes that would invalidate
Invoice usage until that usage is explicitly resolved. Do not widen Quote payment methods as a side effect.
For notes/attachments, extend the existing Invoice entity branch when the screen part needs it. For secure
links/delivery, extend the proven Quote/Communications approach in Part 6; no second outbox in this foundation.

## Currency, dates and service snapshots

Store `invoices.currency_code` from `organization_settings.currency_code`. Manual receipts also retain their
currency; every allocation/refund must match the original receipt and Invoice currency. No conversion or
multi-currency account is introduced. Extend both `organization_currency_is_locked` and
`save_organization_business_profile`: retain the existing Quote lock, and also lock after any Invoice is
issued, recognized by full Draft payment, or any Client money is received (including a partial Draft payment).
Voiding, replacing, refunding or deleting an eligible Draft must not unlock currency: retained issue/recognition
and receipt facts continue to establish the lock. Settings updates and first issue/recognition/receipt commands
lock the same organization-settings row before their other locks to prevent a currency-change race.
An unpaid Draft whose snapshot no longer matches settings must be explicitly refreshed and previewed before
issue or payment; never silently relabel its amounts.

Use `organization_settings.timezone`, not platform subscription/commercial timezone or browser timezone.
Issue date and relative/month-end due dates use the organization's local calendar date; store the resulting
due date as a date. Past Due means the local current date is strictly after that date for an eligible unpaid
issued Invoice. Changing timezone does not rewrite stored issue/due dates. Keep action timestamps as instants.

The Invoice document snapshot contains an explicit `service_properties` array: source Property/Job identifiers
where applicable and the copied address fields for every included service property. `invoice_sources` points
to its corresponding snapshot entry. This supports multiple Jobs/properties on one Invoice without duplicating
source claims. Freeze the array on issuance or full-Draft recognition; any permitted issued edit retains the
prior complete snapshot in `invoice_events`. Replacements copy/explicitly revise their own snapshot and keep
the predecessor's snapshot. Historical rendering never fetches current Job/Property addresses.

## Status, receivables and money

Expose exactly Draft, Awaiting Payment, Past Due, Paid, Bad Debt, Voided. Awaiting/Past Due are derived from
issue/date/balance; no daily status-writing job. Store business facts needed to derive the labels, not a
second set of public workflow statuses. When a successor becomes effective, freeze the predecessor's then-current
six-status label and show “Replaced by Invoice #…” with its successor link. A correction link replaces an
issued bill; a rebill link succeeds an explicitly Voided bill. Store that link kind, not another displayed status.
A prepared successor Draft does not deactivate an issued predecessor until the replacement activation command.
Activation excludes the predecessor from receivables, reminders, collection actions, and current Client Hub
billing in the same transaction. Historical inspection remains available; its frozen label never ages into
Past Due or changes when an allocation is explicitly moved. Amount/allocation history remains visible.
Use the same effective-receivable predicate for balances, reminder selection, collection commands and Client Hub;
commands recheck it under lock, including queued reminders before dispatch. No successor branching.

Separate three quantities:

- **Invoice amount remaining:** its calculated total less net allocations, with closure/write-off effects shown.
- **Client account balance:** effective recognized bills, less write-offs and net money received (including
  available/prepaid money). Exclude voided/superseded receivables; never count a receipt twice.
- **Available credit:** money not refunded or already committed to another Invoice. A Draft payment is
  prepayment associated with that Draft, so it must not also be spent elsewhere without explicit unapplication.

Example: a Draft for 100 receives 30. It remains Draft, remaining 70, account credit/prepayment 30, and no
issue/delivery/communication facts. Its 30 is committed to that Draft. On issuance, recognize 100 and apply
that same 30: account debt 70, with no second receipt. If the Draft becomes fully paid, recognize the settled
bill for balance purposes and show Paid, without fabricating delivery. A separate recognition timestamp
allows full-paid-Draft behavior without misusing the issue date; this is a proposed representation of the
approved behavior, not another lifecycle status.

Status-only Mark Received never extinguishes debt. Bad Debt writes off only remaining debt. A receipt stays
real money after an Invoice correction: if an old 100 bill with 30 paid is replaced by 80, only 80 counts as
the active bill and account debt is 50, but the 30 still points to the original until explicitly reallocated.
The replacement must show that related payment context, not imply it has already received the allocation.

Receivable reductions from correction are attached to the retained predecessor/replacement link. They are
not new cash receipts or refunds. Past originals remain inspectable but cannot independently collect more.

## Source claims and D1–D5 commands

Choose canonical units from the Job's billing basis: whole one-off Job, per-Visit, fixed-period reminder,
or installment. A reminder selecting Visits consumes the Visit claims, not a competing second claim for
the same work. Validate reminder/Visit/Job association under locks. Fixed-period date boundaries belong to
the existing reminder; do not synthesize periods from a timestamp. Installment foreign keys wait for Jobs
11c. Source constraints and same-Client keys prevent a second independent chain claiming identical work.

Void retains the source claim; it neither reopens its reminder nor requeues its Visits. Explicit rebill
creates a successor in the same chain. Unique predecessor linkage prevents branching; conditional creation
requires the expected current leaf. Creating a replacement does not copy payment allocations. Issued-progress
replacement atomically deactivates the predecessor receivable and activates the replacement, preserves all
original amounts, and checks the previewed schedule difference. No writes to later installments.

Commands needed by later parts (one transaction each unless transport is involved):

- Create/edit/delete Draft; edit permitted issued document with a retained prior snapshot; issue/mark sent.
- Record receipt; apply/unapply/move payment; record actual external refund; reverse/replace erroneous record.
- Mark received/reopen; bad debt/unmark; Void; explicit rebill; issued-progress correction/replacement.
- Batch create: validate the complete selected set and permissions, lock Jobs then Visits, complete selected
  incomplete Visits through existing Job behavior, create grouped Drafts, resolve consumed reminders, and
  record one private command receipt plus relevant history on each affected Invoice. All selected changes commit or roll back together. No automatic Job closure.

Refuse Void while ordinary allocations remain; eligible Void unapplications of deposits happen in the same
transaction. Queue the cancellation notification through existing Communications after the state change is
secured, with retry identity. No provider call while holding locks. Receipt/refund messages are separate
explicit actions. Partial-Draft payment creates financial history only, not communication activity.

Refunds record an actual external refund against exactly one original receipt (manual or reused Quote deposit),
with matching Client, organization and currency. Lock that receipt and validate the cumulative unrefunded
amount, accounting for retained reversals. The refund cannot exceed either the unrefunded receipt amount or
its currently unapplied funds. Require explicit unapplication before refund; Void cannot imply ordinary-payment unapplication
(the approved deposit-release exception still applies). Concurrent
refunds and allocations serialize on the receipt. Erroneous refund corrections use retained reversal/replacement
entries, subject to the same conservation checks; do not delete the original refund.

A partially paid Draft is deletable only after its allocation is explicitly returned to Client credit.
Deletion must not automatically unapply, refund or move it. Keep the receipt and its application/unapplication
history. A fully paid Draft is recognized as Paid and is not eligible for Draft deletion.

Atomic batch is bounded, not secretly split into partial commits. The bounded atomic mechanism is approved. The initial 20 resulting
Invoices / 100 selected source units are **provisional measurement inputs, not approved fixed product limits**.
The 100-line detail workload remains the proposed per-Invoice bound. Reject before work if grouping exceeds
the configured bounds; select final batch numbers from latency/lock/rollback verification evidence. Preview includes the actual group count, Visits to complete, revisions, and schedule differences.
Stale previews conflict and require refresh. A retry with the same input returns the original result; reuse
of its key with changed input conflicts. Existing Visit-completion events/reminders are emitted once within
the transaction; reminders consumed by this batch resolve without leaving a duplicate prompt.

Retries use the private `invoice_command_receipts` table, keyed by organization, action and idempotency key.
Authorize the caller on every attempt, including replay; validate actor/scope and fingerprint before returning
only the command's permitted result. Changed input conflicts. Successful business changes and receipt insert
commit together; rollback leaves neither a success receipt nor partial changes. Client-level payment commands
need no artificial Invoice event, and a multi-Invoice batch has one receipt plus per-Invoice relevant history.
Keep fingerprints/results out of normal history projections, activity feeds and Client Hub. A stable result
identifies previously created work even if a Draft was later deleted; retry must not recreate it.

## Access and isolation

Proposed keys: `invoices.view`, `invoices.view_price`, `invoices.create`, `invoices.edit`, `invoices.send`,
`invoices.record_payment`, `invoices.correct_payment`, `invoices.void`, `invoices.bad_debt`, `invoices.delete`,
`settings.invoices.manage`. The settings permission follows existing `settings.quotes.manage`: owner/admin
manage Invoice terms/defaults and numbering settings. Client term overrides use the existing Client-edit
permission; Invoice overrides use `invoices.edit`, with price visibility where monetary data is involved.
Map these into the existing permission catalog and `core.invoices_payments` entitlement; role grants require
review, not automatic Finance/Sales expansion. Owner/admin receive these; other roles retain deny until an
explicit role matrix is reviewed. Batch with incomplete Visits additionally checks existing `jobs.complete`;
billing cannot grant it implicitly. All monetary commands additionally require price visibility. Header edits do not authorize payment corrections.

RLS on each exposed table; no `anon` access and no authenticated direct writes. Narrow RPC commands validate
membership, entitlement, permission, revision, same-tenant and same-Client ownership inside the database.
Use existing permission helpers with current membership, not user-editable JWT metadata. Harden privileged
command execution/search paths and revoke default PUBLIC execution. Price-sensitive snapshots/events/payment
rows require price visibility; do not leak them through the shared activity feed. Reads use permission-shaped
projections like Quote money reads. Foreign keys to Client/source work use restrict for retained history;
financial records never disappear through Draft deletion. Retained history uses stable document identity plus
snapshots without a cascading dependency on a deletable Draft; source claims retain their canonical root.

Put command receipts in the private schema with no normal-reader grants, exposed table API or history join.
Only narrowly authorized command functions can access them; privileged server callers still follow those
functions and cannot use a broad history-read endpoint to fetch fingerprints/results.

Enforce append-only `client_payment_events`, `invoice_payment_allocations` and `invoice_events` with revoked
UPDATE/DELETE/TRUNCATE privileges and database rejection triggers for UPDATE/DELETE and TRUNCATE, including
privileged application roles and SECURITY DEFINER command execution. RLS alone is insufficient for roles
that bypass it. No application-role exemption or history-maintenance escape hatch; corrections append records.
Apply equivalent protection to reused Quote receipt history where needed, and restrict parent deletion rather
than cascade. Application runtime roles cannot own/alter these tables, disable triggers, or assume migration
roles. A database administrator's ability to change DDL is outside the application privilege boundary.

## Read cost and verification gate

Growth variables are tenant Invoice count, Client payment history, selected source count, lines, and concurrent
writes. Initial assumptions for validation: 10k Invoices/tenant, a skewed 100k tenant, 10k receipts on one Client,
50-row list pages, 100-line detail, and the bounded batch above. These are test workloads, not capacity claims.

Use tenant-first keyset list ordering with unique ID tie-breaker, Client/Invoice indexes for balance and
history joins, and unique source/predecessor/idempotency lookups. Index child foreign keys not already covered
by those indexes. Sum the indexed Client subset for account balance; no global per-row nested totals.
No maintained aggregate or server cache until measured cost warrants one. TanStack Query owns client caching.

Concurrency: currency-sensitive commands first lock organization settings as described above; then use
the existing Job→Visit lock order, then shared source/Invoice/receipt locks in stable ID order;
standalone commands must follow the same order when they touch those rows. Counters held briefly. Explicit
lock/statement timeouts return a retriable refusal, not an uncertain success. Deadlocks require retry with the
same replay identity; no user-visible duplicate effects. Hot-Client serialization and tenant counters are
intentional small correctness costs to measure before introducing finer machinery.

| Gate before implementation can be declared verified | Required evidence                                                                                                                                       |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1                                                  | 100/30 Draft→issue and Draft→full settlement; issue/delivery fields unchanged during receipt; credit conserved                                          |
| D2                                                  | Partial payment blocks Void; explicit unapply/move/refund; deposit release exactly once                                                                 |
| D3                                                  | Only replacement receivable counted; old allocations unchanged; no later-installment rewrite; stale preview refusal                                     |
| D4                                                  | Retained claims after Void; explicit rebill succeeds once; independent duplicate and concurrent branch refused                                          |
| D5                                                  | Missing `jobs.complete` refused; failure after completion rolls back Visits/reminders/Invoices; replay emits once; Job stays open                       |
| Money/history                                       | Fractional quantity/discount/tax shared fixtures; over-allocation/refund prevention; reversal and Draft deletion retain receipts                        |
| Isolation                                           | Cross-tenant and cross-Client keys, anonymous/direct-write denial, price-hidden reads/events, revoked membership, each role/key                         |
| Replacement visibility                              | Frozen six-status label/banner; correction vs rebill; no predecessor debt, reminders, collection or current Hub billing; stale queued reminder refused  |
| Currency/dates/snapshots                            | Concurrent settings/first-receipt or issuance; permanent lock after refunds/Void; local midnight, DST and month-end; multiple frozen property addresses |
| Refund/deletion                                     | Original-receipt cap under concurrent refunds; unapplied-funds prerequisite; partial Draft deletion refused until explicit credit return                |
| Private retries/history                             | Client-only and batch replay; changed-input conflict; no fingerprint/result leaks; privileged UPDATE/DELETE/TRUNCATE rejected; no cascading erasure     |
| Growth                                              | EXPLAIN ANALYZE/BUFFERS for list/balance/history/source queries at stated skew; RPC latency, rows/bytes, lock waits and concurrent batches              |
| Delivery boundary                                   | No external work within transaction; idempotent enqueue and retry; payment-on-Draft creates no communication event                                      |

**Performance design verdict:** approved design with explicit bounded workload; implementation and capacity
remain unverified. If indexed Client balances or bounded atomic batches miss measured budgets, return with
that evidence before adding aggregates or changing atomicity. No infrastructure change is proposed.

## Approval boundary and sequencing

**Approved final research/design redline:**

1. Nine tables: Invoice history and private command receipts have separate responsibilities and access.
2. Correction/rebill links freeze the predecessor label and exclude it from all current billing/collection.
3. Snapshot currency; extend the permanent currency lock; use organization-local issue/due/Past Due dates.
4. Store all service-property addresses in the Invoice's frozen document snapshot, linked from sources.
5. Cap refunds against their original receipt and require unapplied funds; block allocated Draft deletion.
6. Add `settings.invoices.manage`; enforce append-only history even for privileged application access.
7. Retain approved bounded atomic batching while measuring the provisional 20-Invoice/100-source numbers.

Part 2 is complete. Stop at this documentation handoff; no migrations, SQL, tests, application code or database
changes are part of this closeout. When Jafar directs implementation, follow the existing campaign order:
direct Invoice/money foundation, screens, Job handoff
including Jobs 11c, delivery, closure, batch. Installment/source integration must be verified against the actual
Jobs 11c implementation before its migration; public-schema compatibility is not assumed from a design document.
All files inspected here are repository evidence; remote schema drift and deployment state remain unverified.
