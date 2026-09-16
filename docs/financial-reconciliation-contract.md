# Financial reconciliation contract

Status: **Approved by Jafar on 2026-09-13** — CRM Launch Readiness Part 3 / Financial Reconciliation Part 1.

## Purpose and authority

This contract makes operational screens, financial reports, and accountant-ready exports describe the same facts.
It adds no general ledger and does not turn UCRM into accounting software. Invoice, Payment, Job, Visit, tax, and
Pipeline contracts remain authoritative for their own behavior; this contract defines how their facts are reported
and reconciled.

The implementation follows the mature subledger pattern: immutable source events, one calculation for each reported
number, explicit corrections, and stable IDs that let an accountant trace summaries back to source rows.

## Reporting truth

- **Billed sales:** an issued Invoice, or a Draft recognized by full payment, is the sale. Net sales are Invoice
  total less Invoice tax. Drafts that have not been recognized are excluded. Voided and superseded Invoices are
  excluded from current sales but remain in correction history. A write-off is reported separately and never erases
  the original sale.
- **Cash received:** immutable payment and deposit events are the source. Receipts increase cash on their payment
  date, refunds reduce it on their refund date, and a reversal removes a mistaken receipt from corrected totals while
  preserving the original and correction. Moving or unapplying money changes allocation, not cash received.
- **Receivables:** Invoice balance is total less current allocations. Client outstanding is the sum of effective
  Invoice balances; available credit is received money not refunded, reversed, or allocated; Client balance is
  outstanding less available credit. Creating new status-only Mark Received closures is retired: money received must
  be recorded as a Payment, and valid debt that will not be collected must use Bad Debt. Historical Mark Received
  records remain immutable and appear as unsettled reconciliation exceptions.
- **Tax:** each effective Invoice's frozen `tax_minor` is the sole tax source. Draft, voided, and superseded bills are
  excluded. Tax is reported separately from net sales and cash.
- **Job profitability:** operational revenue is Job total less Job tax. Cost is snapshotted item cost plus rated
  labor plus recorded expenses. Unrated labor is disclosed and excluded rather than valued at zero. Job profit is
  operational analysis; it is neither billed sales nor cash received.
- **Pipeline and work:** Pipeline value and Won outcomes are sales estimates, never financial revenue. Completed
  Visits and other eligible uninvoiced work are reported separately so they can be billed without being mistaken for
  revenue.

All calendar reporting uses the organization's timezone and an inclusive start date / exclusive end date. Stored
business dates such as issue, payment, refund, expense, and service dates remain dates and are not shifted by the
viewer timezone. Money stays in integer minor units internally; CSV presentation uses fixed two-decimal values and
always names the ISO currency. The first launch supports one locked organization currency and performs no currency
conversion.

## Opening balances

Assisted import accepts only two explicit opening facts: customer receivable and unused customer credit. Each has a
Client, positive amount, currency, as-of date, source note, and import identity. These records do not invent historic
Jobs, Invoices, or Payments. Retrying the same import is idempotent; correcting an opening fact appends a linked
correction rather than editing or deleting history.

Opening balances appear in their own export and in reconciled Client balances. They do not enter current-period sales,
cash, tax, Job profitability, or Pipeline results.

## Permission and export rules

- Invoice amounts, aging, balances, payment allocation, deposits, refunds, tax, and opening balances require the
  existing Invoice financial visibility permissions.
- Job prices require `jobs.view_price`; costs, profit, rated labor cost, and expenses require `jobs.view_cost`.
  Time-entry identity and duration follow the existing own/team scope; exports must not widen that scope.
- Pipeline outcomes require Pipeline access. Every read is explicitly tenant-scoped in addition to RLS.
- A report or CSV omits unauthorized columns or records; it never substitutes zero for hidden money.
- In the stock role matrix only Owner and Admin hold `invoices.view`, so today only they can start the accountant
  package at all; Office, Sales and Finance are refused. The per-ledger omissions above therefore arise from
  per-member permission overrides rather than from any stock role.

The accountant-ready package contains stable, documented CSVs for invoices/sales, payment events, allocations,
deposits/credits, refunds/reversals, tax, Job profitability, expenses, time entries, uninvoiced work, sales outcomes,
and opening balances. A manifest names schema version, generation time, currency, date basis, row counts, primary
keys, and relationships. A reconciliation summary names totals and exceptions, including status-only closures and
unrated labor.

## Acceptance scenarios

Seeded tests must trace each source record through its applicable report and CSV for: an unpaid and partially paid
Invoice; unused and applied deposit; refund; reversed mistaken receipt; moved allocation; void; correction/rebill
chain; write-off and restore; Mark Received; taxable and non-taxable discounted lines; rated and unrated labor;
expense; recurring work; completed uninvoiced Visit; Pipeline Won value; both opening-balance types; and a mixed batch
whose failed item is visible and safely retryable without duplicating successful work.

For every scenario, net sales, tax, cash, receivables, available credit, Client balance, Job profitability, and row
counts must reconcile where applicable. Cross-tenant access and cost/price permission tests are mandatory.

`supabase/tests/database/financial_accounting_package_acceptance.sql` holds this list as one seeded period, traced
through the same paged readers the package writes each CSV from, with all seventeen summary-versus-rows agreement
checks recomputed and the cost-visibility and cross-tenant refusals asserted. One scenario waits on the part that
introduces it: the mixed batch belongs to batch Invoice creation. Both opening-balance types are seeded and traced
from export schema version 2 onward.

## Scale boundary

Initial reports are bounded server-side reads with required date ranges, deterministic pagination, narrow projections,
and indexes justified by measured query plans. Exports stream or page records rather than loading an unbounded tenant
history into browser memory. No cache, data warehouse, maintained aggregate, materialized view, or background export
queue is introduced until representative measurements show the simpler path misses an agreed budget.

Capacity is not established by this contract. It must be demonstrated against a named workload after implementation.
