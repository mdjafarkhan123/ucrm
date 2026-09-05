# Invoice behavior contract

Status: **Approved by Jafar on 2026-09-05** — follow verified Jobber behavior without speculative additions.
Owner: Invoice campaign

The research redline and both traceability departures are explicitly approved by Jafar in the current
session. This approval authorizes neither schema design nor implementation. D1–D5 are now approved concrete UCRM behavior; see the decisions below. Part 2 design is authorized
for review only; implementation remains unapproved.

## Purpose and authority

An Invoice is the customer's bill for completed work. Jobber is the product-behavior baseline. We preserve every
required capability and financial consequence, but may simplify a complex Jobber interaction by reducing steps,
grouping related choices, using plain language, or previewing consequences—provided nothing becomes ambiguous,
automatic, or less safe. Each material departure from Jobber's interaction is named before implementation.
Existing Quote and Job contracts remain authoritative for proposal history, Job scope, Visits, pricing inputs, and
deposits before allocation. This contract owns the frozen bill, delivery state, balance, and manual payment allocation.

## Boundaries

- Quotes propose and approve work. Jobs own agreed and changing work. Invoices snapshot what is billed.
- A Quote never converts directly to an Invoice. Its deposit or payment schedule reaches Invoice through its Job.
- Creating an Invoice never closes a Job. Closing a Job never sends an Invoice or collects money.
- Communications delivers email and later SMS. Invoice owns recipients, document links, issue state, and events.
- Online card/ACH processing, saved methods, automatic charging, settlement, disputes, and payouts are a later
  provider slice. The first campaign records money received outside the platform honestly.

## Identity, customer, and source

- Each Invoice belongs to one organization and one Client and receives a non-reused organization Invoice number.
- A direct Invoice has no Job. A Job-generated Invoice links the selected Job(s), Visits, reminder, or installment.
- Multiple Jobs may share one Invoice only when they belong to the same Client, matching Jobber. Batch creation makes
  draft Invoices grouping compatible selected work per Client; differing property tax rates split Invoices.
- The Client has one effective billing address, matching a designated Property or using a custom Client billing
  address. A Job-generated Invoice also snapshots each included service property.
  Issued customer, billing, property, line, tax, and terms snapshots never drift with later source edits.
- One source unit cannot be billed twice: the command locks and claims each selected reminder, Visit, or installment.
  Retrying the same command returns the original Invoice rather than creating another.

## Creation paths

Following Jobber, staff may create an Invoice directly, from a Client, from a Job, from an invoice reminder, from a
payment-schedule installment, or through batch invoicing. A Job handoff copies eligible service dates and Job-owned
lines into an editable draft. Per-visit billing selects uninvoiced Visits; progress invoicing fixes the installment's
amount and does not allow its line amounts to be edited independently of the Job schedule.

Saving creates a Draft. Save and Send combines two explicit commands without pretending they are one database write.
Batch creation produces Drafts for review; batch delivery is a separate action. Drafts accept manual payment,
including Save-and-Collect; full settlement makes Paid. Partial-Draft behavior follows approved D1 below. Jobber can batch-invoice selected incomplete Visits and marks them complete;
the UCRM Job consequences follow approved D5 below.

## Status and lifecycle

The displayed statuses follow the reconciled Jobber vocabulary:

| Status           | Meaning                                                                      |
| ---------------- | ---------------------------------------------------------------------------- |
| Draft            | Saved but not sent or marked sent; contractor-only                           |
| Awaiting Payment | Issued, due date not passed, and still has a balance                         |
| Past Due         | Due date passed and a balance remains                                        |
| Paid             | Accepted allocations cover the balance, or it was explicitly marked received |
| Bad Debt         | Valid completed work whose remaining balance was written off                 |
| Voided           | Invalid/cancelled bill retained immutably with a reason                      |

“Sent but not due” is an overview grouping, not a separate detail status. List-filter groupings may split
Awaiting payment into past due / not yet due / all. Partial payment is not a status. Delivery, delivery failure, customer view, and partial payment are independent facts.
Voiding is allowed only for an unpaid eligible Invoice, records an internal reason (Duplicate / Created in error / Client request / Other), releases
attached deposits to Client credit, notifies through Communications, and is irreversible. Bad debt is for valid work
that will not be collected and may be reversed through Jobber's reopen/unmark behavior. It removes the unpaid
remainder from Client debt and hides the Invoice in Client Hub; it does not imply cancellation messaging.
Void excludes progress invoices; ordinary payment allocations must be resolved before Void, per D2. Void notifications use email
initially, with SMS deferred. Missing channels and failed-delivery consequences remain unverified.

Close without recording payment changes status to Paid but does not settle Invoice or Client debt.
Payment, write-off, and status-only closure have distinct financial consequences.

## Editing and deletion

- Drafts are editable and may be deleted after confirmation.
- **Approved departure from Jobber:** issued Invoices are retained through Void instead of Delete to preserve
  the original bill and its correction trail. Jobber permits issued deletion. Progress-invoice correction
  uses the approved correction/replacement chain in D3; progress invoices remain excluded from ordinary Void.
- Sent Invoices remain editable as Jobber permits; saving and re-sending are separate explicit choices and every edit
  is recorded in history. Source Job changes never rewrite an issued Invoice.
- Progress Invoice amounts stay controlled by the Job payment schedule; already issued installments are locked there.
- Voided Invoices are immutable and cannot be sent or paid. Financial history is never silently deleted.

## Document and money

Invoice lines reuse Quote/Job customer-price arithmetic: integer minor units, numeric quantity, proportional discount,
per-line taxability, and one database calculation. Invoice lines omit quote-only optional/recommended and internal
cost/markup concepts; they add service date, source Job line, and progress-invoice original amount where applicable.

The document shows subtotal, discount, tax, total, deposits applied, payments applied, Invoice balance, and optionally
the Client account balance. Tips remain outside the taxable total. Deposit application moves available Client/Quote
credit onto the Invoice exactly once and preserves the original deposit event.

## Manual payments and financial history

- A payment records amount, date, method, details, Client, actor, and allocation to one or more Invoices.
- Initial methods are only Other, Bank transfer, Cash, Check, Credit/debit card (external), and PayPal.
  These acknowledge money received elsewhere; none processes a payment.
- Partial allocations reduce balance without creating a new status. Full allocation makes the Invoice Paid.
- **Approved departure from Jobber:** financial corrections preserve the original entry and use explicit
  reversal/replacement records. This improves traceability over Jobber's manual edit/delete workflows;
  it does not assert Jobber's internal storage. Exact partial-refund consequences remain unresolved.
- Receipts are generated from accepted payment facts and may be delivered by available Communications channels.

## Terms, delivery, and reminders

Jobber payment terms are the baseline: Due upon receipt; Net 7/15/30/45/60; End of month; End of next month; or a
custom due date. Resolution is Invoice override → Client term → residential/commercial account default.
Company-name identity uses commercial; unspecified type uses residential. No separate unverified Client-type
selector is implied. Term management supports named terms and the protected receipt/month-end terms;
deleting a default term falls back to receipt. Updating Invoice terms may explicitly promote them to the
Client default; otherwise it changes only the Invoice.

Sending by email or later SMS issues the Invoice and creates recipient-specific secure access. Mark as Sent issues it
without transport. Customer views are recorded separately. Payment reminders chase Past Due balances and are owned by
Invoice plus Communications; Job invoice reminders remain internal prompts to create an Invoice. Automatic payment,
when built later, suppresses unnecessary reminders.

## Screens

- List: Jobber-shaped status overview, actionable balances, filters/search, table, New Invoice, and later batch actions.
- New: shared Quote form shell; Invoice subject, number, issued date, terms/due date, service dates, Invoice totals,
  optional message/images/attachments/disclaimer, Overview and Notes rail, Save and Save-and actions.
- Detail: shared work-record header and blocks. Main content holds customer/source work, lines, optional document
  sections, disclaimer, and financial history. Rail holds Overview, Discount, Tax, applicable deposit/payment summary,
  Client view, and Notes. History opens in the rail.
- One primary action follows state: Send for Draft; Collect Payment while money is owed; no forced action when closed.

## Permissions and safety

Invoice view/edit, price visibility, payment recording, sending, void/bad-debt, and deletion are separately enforced
in the database. Tenant-safe composite keys guard every Client, address, Job, Visit, source, and allocation. All writes
use validated `/api/*` routes, expected revisions where editing is allowed, and idempotency for lifecycle/money commands.

## Initial campaign boundary

The campaign includes Invoice truth, direct and Job/Visit/installment creation, shared list/new/detail screens, email
and secure preview, manual payments, balances/receipts, overdue/bad-debt/void behavior, and batch billing after the
single-Invoice path works. SMS waits for Communications activation. Provider processing and automatic payments remain
separately gated and no fake payment UI ships. No ACH-failure, dispute, payout, saved-card, auto-pay, financing,
or all-15-method infrastructure is introduced. Standard-mail batch PDFs/labels are documented Jobber features,
not automatically authorized additions to this initial email/manual-payment subset.

Snapshots, numbering guarantees, arithmetic, permission enforcement and command boundaries in this contract
are UCRM safeguards, not conclusions about Jobber's database. Approved D1–D5 below settle source-work eligibility and the named transitions; other research limits do not
authorize speculative workflows.

## Approved transition decisions D1–D5

Jafar explicitly approved these concrete behaviors in the current session. D1–D4 are intentional UCRM
choices where Jobber documentation is silent; D5 follows verified Jobber behavior with added safeguards.
These supersede earlier unresolved qualifications for these five transitions in this document.

1. **Partial Draft payment:** keep Draft; create no issue date, delivery record, or communication event.
   Show payment and remaining amount. Until issuance, received money is Client credit/prepayment because
   Draft is not a receivable. Issuance applies that credit to the new receivable. A fully paid Draft still
   becomes Paid, following the already-approved behavior.
2. **Partially paid Void:** refuse while any non-deposit payment remains allocated. The user must explicitly
   unapply to Client credit, move to another Invoice, or record a refund. Void implies none of these actions.
   After ordinary allocations are resolved, follow verified Void behavior, including deposit release.
3. **Issued progress corrections:** keep issued installment amounts locked on the Job. Use an Invoice-owned
   retained correction/replacement chain. Preserve the original; replacement is the active receivable.
   Payments remain allocated where they were until explicitly reallocated. Preview any schedule difference
   before applying; never silently rewrite later installments.
4. **After Void:** never automatically return source work to the billing queue. Explicit replacement/rebill
   preserves the voided Invoice relationship and prevents independent duplicate billing.
5. **Batch incomplete Visits:** exclude by default. Selection requires a completion preview and existing
   Visit-completion permission. Complete selected Visits atomically with creation of the Draft invoices.
   Never automatically close the Job.

Receipt correction history and explicit payment movement must remain visible. These decisions add no
Invoice statuses and authorize no generalized accounting or provider framework.
