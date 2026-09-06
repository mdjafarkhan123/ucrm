# Jobber Reference — Invoices & Payments

> Source: `JobberJson.md` (schema, authoritative for fields/enums) + Jobber Help Center (behavior, cited).
> Part of the Jobber competitor reference set — see `jobber-00-overview-lifecycle.md` for the index/lifecycle,
> `jobber-03-quotes.md` for the Quote (deposits start there), and `jobber-04-jobs-visits-scheduling.md` for the
> Job that feeds invoicing (**Requires Invoicing** → batch billing). Plain English; **(unverified)** marks
> anything not confirmed by schema or help center.

An **Invoice** is _"a request for payment which Service Providers send to their clients after the work is
done"_ (schema). A **PaymentRecord** is _"payment records applied to a quote or invoice"_ (schema) — money
in, whether a card charge through **Jobber Payments** or a manually-recorded cash/check. This file documents
the invoice object, its line items and amounts, the full status set, how invoices get created (one-off,
per-job, and **batch**), reminders, deposits, and progress invoicing. Provider API fields below are historical
reference, outside the current manual-payment campaign.

---

## Research authority and current scope

Current behavior reconciliation: [Invoice evidence matrix](../../../docs/invoice-jobber-evidence.md).
Consult it before using this reference for Invoice planning. API fields below are a historical public-schema
inventory, not newly verified API compatibility, screen labels, storage design, or an implementation mandate.
UI controls and GraphQL connections do not establish Jobber's internal tables or financial storage.

Initial UCRM manual methods, restricted by Jafar: **Other, Bank transfer, Cash, Check, Credit/debit card
(external), PayPal**. No processor, ACH failure, dispute, payout, saved-card, auto-pay, financing, or
all-15-method infrastructure belongs in this campaign. Provider fields remain reference material only.

## 1. Invoice (`Invoice`)

### 1.1 Fields (from schema)

| Field                            | Type                          | Meaning                                                                            |
| -------------------------------- | ----------------------------- | ---------------------------------------------------------------------------------- |
| `id`                             | `EncodedId!`                  | Opaque unique id.                                                                  |
| `invoiceNumber`                  | `String!`                     | The invoice number (**not** guaranteed unique — see `hasInvoiceNumberDuplicates`). |
| `subject`                        | `String!`                     | The subject / title of the invoice.                                                |
| `message`                        | `String`                      | Message to the client (cover note).                                                |
| `contractDisclaimer`             | `String`                      | Contract / disclaimer text on the invoice (T&C block).                             |
| `invoiceStatus`                  | `InvoiceStatusTypeEnum!`      | Current status (see §2).                                                           |
| `client`                         | `Client`                      | The client billed.                                                                 |
| `properties`                     | `PropertyConnection!`         | The properties this invoice covers (an invoice can span multiple).                 |
| `billingAddress`                 | `InvoiceBillingAddress`       | Billing address on the invoice (city, street1/2, province, postal, geo).           |
| `billingIsSameAsPropertyAddress` | `Boolean`                     | Whether billing = property address.                                                |
| `jobs`                           | `JobConnection!`              | The jobs this invoice bills for (one invoice can bill **multiple** jobs).          |
| `archivedJobs`                   | `JobConnection!`              | Archived jobs related to the invoice.                                              |
| `visits`                         | `VisitConnection!`            | The visits associated with the invoice.                                            |
| `lineItems`                      | `InvoiceLineItemConnection!`  | The invoice's line items (see §3).                                                 |
| `amounts`                        | `InvoiceAmounts`              | Money breakdown (see §1.2).                                                        |
| `taxDetails`                     | `TaxDetails`                  | Tax rate + amount detail.                                                          |
| `taxRate`                        | `TaxRate`                     | Tax rate info on the invoice.                                                      |
| `taxCalculationMethod`           | `String!`                     | How tax is calculated on the invoice.                                              |
| `customFields`                   | list                          | Invoice-level custom-field values.                                                 |
| `paymentRecords`                 | `PaymentRecordConnection!`    | Payments applied to the invoice (see §5).                                          |
| `issuedDate`                     | `ISO8601DateTime`             | Date the invoice was issued.                                                       |
| `dueDate`                        | `ISO8601DateTime`             | Date payment is due.                                                               |
| `invoiceNet`                     | `Int`                         | Whole days after issue date that payment is due (net terms, e.g. Net 30).          |
| `receivedDate`                   | `ISO8601DateTime`             | Date the invoice was received/marked received.                                     |
| `createdAt` / `updatedAt`        | `ISO8601DateTime!`            | Timestamps (`updatedAt` = last SP-meaningful change).                              |
| `clientHubUri`                   | `String`                      | Client-facing Client Hub URL of the invoice.                                       |
| `dateViewedInClientHub`          | `ISO8601DateTime`             | When the client last viewed it in Client Hub.                                      |
| `salesperson`                    | `User`                        | Assigned salesperson.                                                              |
| `notes` / `noteAttachments`      | connections                   | Internal notes + attached files.                                                   |
| `linkedCommunications`           | `MessageInterfaceConnection!` | All messages related to the invoice.                                               |
| `allowReviewRequest`             | `Boolean!`                    | Whether an SMS Google-review request may be sent for this invoice.                 |
| `nextDateToSendReviewSms`        | `ISO8601DateTime`             | Next allowed date to send a review-request SMS.                                    |
| `hasRefundableSurchargePayments` | `Boolean!`                    | Whether any payment has a refundable surcharge amount.                             |
| `waitingForFinancedPayment`      | `Boolean!`                    | Whether the invoice is waiting on a financed (Wisetack-style) payment.             |
| `hasInvoiceNumberDuplicates`     | `Boolean!`                    | Whether another invoice shares this invoice number.                                |
| `jobberWebUri`                   | `String!`                     | Deep link in Jobber web.                                                           |

### 1.2 `InvoiceAmounts` (money breakdown — all `Float!`)

| Field                  | Meaning                                                                    |
| ---------------------- | -------------------------------------------------------------------------- |
| `subtotal`             | Line-item costs, excluding tax.                                            |
| `discountAmount`       | Discount amount.                                                           |
| `legacyDiscountAmount` | Computed discount applied to the subtotal (legacy calc).                   |
| `nonTaxAmount`         | Portion exempt from tax (tax-exempt line items).                           |
| `taxAmount`            | Tax charged.                                                               |
| `total`                | Grand total (line items + tax).                                            |
| `depositAmount`        | Deposit amount tied to the invoice.                                        |
| `paymentsTotal`        | Total payments applied to the invoice.                                     |
| `tipsTotal`            | Sum of all tips paid on the invoice.                                       |
| `invoiceBalance`       | **Balance remaining after all payments** — the "what's still owed" number. |

> **Build note:** unlike the quote (which tracks _outstanding deposit_), the invoice tracks a live
> **`invoiceBalance`** = total − payments, plus `tipsTotal` as a separate bucket (tips are on top of the bill,
> not part of `total`). Copy this split: tips must not inflate the taxable/total figure.

---

## 2. Invoice status vocabulary (reconciled 2026-09-04)

The current [Invoice list documentation](https://help.getjobber.com/en/articles/invoices-list-page-and-key-metrics/)
lists **Draft, Awaiting Payment, Past Due, Paid, Bad Debt, Voided**. Awaiting Payment includes issued,
unpaid invoices whose due date has not passed; it is not restricted to invoices due today.

The live **overview** used `Past due`, `Sent but not due`, and `Draft`. Its **filters** grouped
`Awaiting payment: past due`, `Awaiting payment: not yet due`, and `Awaiting payment: all`, alongside
Draft, Paid, Bad Debt, and Voided. The future-due invoice's **detail badge** said `Awaiting payment`.

Historical API enum: `draft`, `awaiting_payment`, `paid`, `past_due`, `bad_debt`, `sent_not_due`.
`sent_not_due` is not evidence for a separate detail badge. That old sample's missing `voided` does not
invalidate current documented Voided behavior. Invoice Basics' introductory count of five statuses is
stale relative to its own Void section and the list article. Partial payment is not a separate listed status.

---

## 3. Invoice line items (`InvoiceLineItem`)

### 3.1 Fields (from schema)

| Field                     | Type                           | Meaning                                                                      |
| ------------------------- | ------------------------------ | ---------------------------------------------------------------------------- |
| `id`                      | `EncodedId!`                   | Unique id.                                                                   |
| `name`                    | `String!`                      | Line item name.                                                              |
| `description`             | `String!`                      | Description.                                                                 |
| `category`                | `ProductsAndServicesCategory!` | Product vs service category.                                                 |
| `quantity`                | `Float!`                       | Quantity.                                                                    |
| `unitPrice`               | `Float!`                       | Price per unit to the client.                                                |
| `totalPrice`              | `Float!`                       | Total price for the line.                                                    |
| `originalCost`            | `Float`                        | Original cost **before any progress-invoicing adjustments** (see §4.2).      |
| `taxable`                 | `Boolean!`                     | **Per-line taxable flag.**                                                   |
| `taxRate`                 | `TaxRate!`                     | The tax rate applied to the line.                                            |
| `date`                    | `ISO8601DateTime`              | Date of service for this line (billing what was done when).                  |
| `jobLineItem`             | `JobLineItem`                  | The **job** line item this was created from (snapshot link back to the job). |
| `linkedProductOrService`  | `ProductOrService`             | The price-book item this line came from.                                     |
| `createdAt` / `updatedAt` | `ISO8601DateTime!`             | Timestamps.                                                                  |

> **Note vs quote line items:** the invoice line item **drops `unitCost`, `markup`, `totalCost`,
> `optional`, `recommended`, `textOnly`, `sortOrder`** that quote lines carry, and **adds** `date`
> (date-of-service), `originalCost` (progress-invoicing baseline), and `jobLineItem` (the snapshot link
> back to the job's line item). Cost/markup/margin live on the _quote_ and _job_, not on the customer-facing
> invoice line. Tax is still **per line** (`taxable` + `taxRate`).

---

## 4. How invoices get created

### 4.1 One-off, per-job, and batch (help center)

Jobber creates invoices from several entry points:

- **From a job** — the standard path. A **one-off** job produces (typically) one final invoice; a
  **recurring** job can be invoiced many times on a **billing schedule** (per visit, monthly, etc. — see
  `jobber-04` §Billing). When an invoice **reminder** comes due, the job flips to **Requires Invoicing**
  status so it's easy to find. [[invoice reminders]]
- **One-off invoice** — created directly against a Client + Property with no job (schema `invoiceCreate`).
- **Batch invoicing (two-part workflow):** [[batch create invoices]] [[batch deliver invoices]]
  1. **Batch Create** — when jobs reach **Requires Invoicing**, generate invoices for many jobs at once
     instead of one-by-one.
  2. **Batch Deliver** — send the freshly-created invoices to clients in bulk.

### 4.1b Create-invoice-from-a-job, observed live 2026-09-05

Walked on a one-off job with two priced lines and one late visit. Read-only; nothing was saved.

- **Entry point is the job's `··· More` menu → "Create Invoice"** — *not* the green primary action, which
  stays on the lifecycle step (here "Show Late Visit"). Creating an invoice does not close the job.
- It navigates to the ordinary new-invoice route, seeded by query string:
  `/invoices/new?client_id=<client>&initial_work_order_id=<job>`. **No draft is written on the way in** — the
  originating job is only a pre-selection.
- The form opens behind a modal: **"Select jobs to invoice for <Client>"**, a table of *every* invoiceable
  job for that client, not just the one you came from. Columns: **Status** (job status pill), **Title**
  (`#N Title` as a link, with `Visit: <date>` underneath), **Address**, **Uninvoiced**, **Subtotal**. The
  originating job is checked; the rest are unchecked and multi-selectable. Actions: **Cancel** / **Continue**.
  This is the interaction behind "several jobs may share one invoice, same client only".
- After **Continue**, the form fills: **Subject** becomes the job's title (it was the "For Services Rendered"
  default beforehand), the job's line items copy in as fully editable rows, and **each line carries its own
  `Service date:` chip** (the visit date) with an `✕` to remove it. Billing address and property address show
  in the client card.
- Totals block on the create form reads: Subtotal, **Discount** (Add Discount), **Tax** (Add Tax), **Total**,
  **Deposits** (Add Deposit), then a shaded **Invoice balance** row.
- Bottom bar: **Cancel** and a split **Save Invoice** whose caret opens "Save and… → **Send as Email** /
  **Collect Payment**".

### 4.2 Progress invoicing / payment schedules (help center) — [[progress invoicing]]

For larger jobs, Jobber bills a job in stages instead of all at once:

- Set up on the **quote**: from the total section choose **"Add Deposit or Payment Schedule"**, then either
  **Deposit only** (one-time upfront on approval) or **Payment schedule** (split the total into multiple
  installments tied to milestones/stages). [[deposits on quotes]] [[progress invoicing]]
- Each **progress invoice bills only that stage's portion.** On the client-facing invoice, every line shows
  two columns: **Item Total** (full cost of that product/service) and **Due This Invoice** (the installment
  owed now). `originalCost` on the line item is the pre-adjustment baseline behind this.
- **Deposits stay attached to the job** and are **applied to the invoice** when you bill — you always see
  what's paid vs still owed. (Mirrors the quote's unallocated-deposit model from `jobber-03` §4.)

---

## 5. Payments (`PaymentRecord` / `PaymentRecordInterface`)

### 5.1 `PaymentRecordInterface` fields (from schema — the full-featured shape)

`PaymentRecord` (the base object) and `PaymentRecordInterface` overlap; the **interface** carries the
richer field set (branch on `__typename` for the concrete Jobber Payments subtypes in §5.4):

| Field                            | Type                                         | Meaning                                                                                                                                      |
| -------------------------------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                             | `EncodedId!`                                 | Unique id.                                                                                                                                   |
| `amount`                         | `Float!`                                     | Amount applied against the quote/invoice balance (**absolute value**).                                                                       |
| `rawAmount`                      | `Float!`                                     | Same amount **preserving sign** (negative for refunds/reversals).                                                                            |
| `adjustmentType`                 | `IncomeAdjustmentType!`                      | What kind of money movement this is (see §5.2).                                                                                              |
| `paymentType`                    | `PaymentType`                                | The method used — cash, check, Jobber Payments, etc. (see §5.3).                                                                             |
| `paymentOrigin`                  | `PaymentOrigin`                              | **Where** it originated (client online, swipe device, terminal, tap-to-pay, API, system-generated…).                                         |
| `allocations`                    | `PaymentRecordAllocationInterfaceConnection` | What the payment was applied to (invoice allocation(s), a single quote-deposit allocation, or empty — interpret empty via `adjustmentType`). |
| `client`                         | `Client`                                     | The client who paid.                                                                                                                         |
| `invoice`                        | `Invoice`                                    | The invoice paid (if any).                                                                                                                   |
| `quote`                          | `Quote`                                      | The quote paid against (for a deposit).                                                                                                      |
| `refunds`                        | `PaymentRecordRefundConnection`              | Refunds against this payment.                                                                                                                |
| `details`                        | `String`                                     | Free-text details (check number, memo…).                                                                                                     |
| `canEdit`                        | `Boolean!`                                   | Whether the payment can be edited.                                                                                                           |
| `entryDate`                      | `ISO8601DateTime!`                           | When the payment record was created.                                                                                                         |
| `sentAt`                         | `ISO8601DateTime`                            | If sent, when the receipt was sent to the client.                                                                                            |
| `jobberPaymentLast4`             | `String`                                     | Last 4 of the card/account (Jobber Payments).                                                                                                |
| `jobberPaymentPaymentMethod`     | `PaymentMethodSource`                        | `CREDIT_CARD` or `BANK_ACCOUNT` (Jobber Payments).                                                                                           |
| `jobberPaymentTransactionStatus` | `JobberPaymentTransactionStatus`             | Processor status (see §5.4); null for non-Jobber-Payments.                                                                                   |
| `tipAmount`                      | `Float`                                      | Tip attached to a Jobber payment.                                                                                                            |

### 5.2 `IncomeAdjustmentType` (what the money movement _is_) — from schema

`INVOICE`, `REFUND`, `CORRECTION`, `INITIAL_BALANCE`, `FAILED_ACH_PAYMENT`, `PAYMENT`, `DEPOSIT`,
`BAD_DEBT` (amount marked bad debt), `VOIDED` (reversal of a voided invoice). This is how you tell a real
payment from a deposit, a refund, a write-off, or a failed-ACH reversal on the same connection.

### 5.3 `PaymentType` (the method) — from schema (15 values)

`CASH`, `CHEQUE`, `CREDIT_CARD` (card **outside** Jobber), `BANK_TRANSFER`, `MONEY_ORDER`, `OTHER`,
`ZELLE`, `CASH_APP`, `PAYPAL`, `VENMO`, `E_TRANSFER`, `ACH_BANK_PAYMENT`, `JOBBER_PAYMENTS`,
`EPAYMENT` (a payment-integration provider), `CONSUMER_FINANCING` (i.e. Wisetack).

> Note the deliberate split: **`CREDIT_CARD`** = a card charged _outside_ Jobber (you recording it), vs
> **`JOBBER_PAYMENTS`** = a card/ACH charged _through_ Jobber's processor. Same for ACH: `ACH_BANK_PAYMENT`.

### 5.4 Jobber Payments processor detail (from schema)

- **`PaymentMethodSource`**: `CREDIT_CARD`, `BANK_ACCOUNT` (the two vaultable saved-method origins).
- **`JobberPaymentTransactionStatus`**: `PENDING`, `SUCCEEDED`, `FAILED`, `REFUNDED`, `PARTIALLY_REFUNDED`,
  `IN_DISPUTE`, `DISPUTED` — the live processor state of a Jobber Payments charge (chargebacks included).
- **`PaymentOrigin`**: `CLIENT_ONLINE_ORIGIN` (client paid via the emailed invoice), `EMPLOYEE_ONLINE_ORIGIN`,
  `TERMINAL_ORIGIN` (Stripe Terminal / physical reader, incl. Tap-on-Mobile), `TAP_TO_PAY`, `CARD_READER`,
  `SWIPE_ORIGIN` (e.g. Square), `EWALLET_ORIGIN` (Apple/Google Pay), `SYSTEM_GENERATED` (automatic payments),
  `API_ORIGIN` (Jobber's own mobile app / API), `MOBILE_ORIGIN` (deprecated), `UNKNOWN_ORIGIN` (default).
- **Concrete subtypes** (interface implementers): `JobberPaymentsCreditCardPaymentRecord`,
  `JobberPaymentsACHPaymentRecord`, `JobberPaymentsRefundPaymentRecord`.

### 5.5 Recording and correcting manual payments

See [verified financial evidence](../../../docs/invoice-payment-research.md) for draft collection,
Close Invoice, Bad Debt, Void, payment editing/deletion/refunds, and Client balance. The live six-method
list defines initial UCRM scope. `Credit/debit card` under `Create a payment record` records an external
payment; it does not charge a card. Full payment and status-only closure must remain distinguishable.

### 5.6 Provider features — outside this research boundary

Online processing, saved methods, automatic charging, ACH failures, disputes, payouts, fees, and financing
require separate current provider research and approval. Historical schema fields in §5.1–5.4 are not
requirements for the initial manual-payment campaign. Do not build placeholders from them.

---

## 6. Invoice reminders and payment follow-ups

[Invoice Reminders](https://help.getjobber.com/en/articles/invoice-reminders/) are internal creation prompts;
a due reminder puts a Job in Requires Invoicing. Creating the Invoice completes its reminder.
[Emails and Text Messages Settings](https://help.getjobber.com/en/articles/emails-and-text-messages-settings/)
places Invoice follow-up configuration in Automations. These chase overdue bills, not uncreated invoices.
The previous two-reminder/90-day claim was not reverified here; consult current Automation documentation
before relying on fixed limits. Auto-pay and review-request integrations remain outside initial scope.

---

## 7. Mutations & queries (from schema)

Public API exposes create/edit/close/reopen and note operations — but **no** payment-recording mutation
(recording money is a web-app/Client-Hub action, not in the sampled public schema):

| Action          | Mutation                                                                                      | Returns                                |
| --------------- | --------------------------------------------------------------------------------------------- | -------------------------------------- |
| Create invoice  | `invoiceCreate` (`InvoiceCreateInput`, `InvoiceCreationLineItemInput`, `InvoiceDueDetails`)   | `invoice`, `userErrors`                |
| Edit invoice    | `invoiceEdit` (`InvoiceEditInput`)                                                            | `invoice`, `userErrors`                |
| Mark as sent    | `invoiceMarkAsSent`                                                                           | `invoice`, `userErrors`                |
| Close invoice   | `invoiceClose` (`InvoiceCloseInput` + `InvoiceCloseOptionsType` = `MARK_RECEIVED`/`BAD_DEBT`) | `invoice`, `userErrors`                |
| Reopen invoice  | `invoiceReopen`                                                                               | `invoice`, `userErrors`                |
| Unmark bad debt | `invoiceUnmarkBadDebt`                                                                        | `invoice`, `userErrors`                |
| Add / edit note | `invoiceCreateNote` / `invoiceEditNote`                                                       | `invoice`, `invoiceNote`, `userErrors` |

_(Introspection does not expand `INPUT_OBJECT` fields, so exact create/edit arguments — line-item shape, due
details, client-view options via `InvoiceClientViewOptionsInput` — aren't enumerable from `JobberJson.md`.)_
**No public `PaymentRecordCreate` / refund / `InvoiceSend` mutation** appears in the sampled schema — payments,
refunds, and the actual _delivery_ of an invoice are done via the web app / Client Hub / Jobber Payments, not
the public API **(unverified whether such mutations exist under other names)**.

Read queries: `invoice(id)`, `invoices(filter, sort)` (`InvoiceFilterAttributes`, `InvoiceSortInput`),
`paymentRecord(id)`, `paymentRecords(filter)` (`PaymentRecordFilterAttributes`), plus the Jobber Payments
getters (capital loans, payouts, saved payment methods via `JobberPaymentsPaymentMethodFilterAttributes`).

---

## 8. How WE compare — decisions, not inferred Jobber internals

- Use the [evidence matrix](../../../docs/invoice-jobber-evidence.md) for current behavior and open limits.
- Match the six verified manual methods and distinguish recording an external card payment from processing it.
- **Approved by Jafar in the research-redline approval:** retain issued invoices through Void rather than Delete, and record
  financial corrections through reversal/replacement rather than erasing original history. These improve
  traceability over Jobber's deletion and manual-edit workflows. UCRM D1–D5 are now explicitly approved in the Invoice contract. See the [proposed redline](../../../docs/invoice-contract-proposed-redline.md).
- Historical API connections describe returned records only. They do not prove a single ledger table,
  append-only history, integer arithmetic, locks, idempotency, or an internal storage architecture.
- Batch creates drafts before separate delivery; different property tax rates split invoices for one Client.
  Selecting incomplete visits can complete them. See the evidence matrix before defining batch parity.
- Preserve the difference between Paid without payment and a settled Client account; see financial research.

## Live screen confirmation — 2026-09-04 (observed live)

- The New Invoice form reuses the Quote composer shape. Its Invoice-only primary fields are Subject,
  Invoice #, Issued date, and Payment terms. Terms offered were Custom date, Due upon receipt, Net 7/15/30/45/60,
  End of the month, and End of next month.
- Invoice lines use the shared product/service editor and add an optional Service Date. The totals editor adds
  Deposit, Invoice balance, and Account balance (including this draft).
- Draft detail uses the shared work-record skeleton. Header editing is in place with Cancel/Save; product/service
  editing is also in place with its own Cancel/Save.
- The Client view block exposes five toggles: Quantities, Unit prices, Line item totals, Account balance, and
  Late stamp (if overdue).
- Draft actions observed were Send Email; Mark as Sent; Create Similar Invoice; Collect Payment; Preview as
  Client; Collect Signature; Print or Save PDF; and Delete.

---

## Client-facing invoice view — 2026-09-05 (observed live)

Opened **More → Preview as Client** on issued invoice #1 (Client Hub `clienthub.getjobber.com/.../invoices/<id>?preview=true`).
This is the document the customer sees. Screenshot: `Design/invoices/jobber-client-invoice-view.jpg`. Structure,
top to bottom:

- **Branded top bar:** business name only ("JKA LTD"), left-aligned, on a thin brand-color gradient rule. No app chrome.
- **Paper card** centered on a pale background, ~1060px max, generous padding, subtle border/shadow.
- **Head row:** small "Invoice #1" label top-left; status pill top-right ("Awaiting Payment", amber dot). Below, the
  **subject** as the bold document title. Left column = client name (bold) + billing address + phone. Right column =
  a two-row facts panel (Issued / Due) separated from the left by a vertical divider, each row underlined.
- **Line table:** header `Product / Service | Qty. | Unit Price | Total` (right-aligned numerics). Each row = bold
  item name + muted description; qty/unit/total on the right. Rows separated by hairlines.
- **Totals block:** bottom-right only, its own left divider — Subtotal, then bold **Total**. (Discount/tax/deposit/
  balance rows would appear here when present; this invoice had none.)
- **Footer:** terms/disclaimer text, muted, full width.
- **Preview mode shows no Pay/Download controls.** The live client view adds payment affordances (Jobber Payments) —
  out of our campaign scope; we ship the document + secure view + browser Print/Save PDF only.

Confirmed the staff **More** menu order: Email, Create Similar Invoice, Preview as Client, Collect Signature,
**Print or Save PDF**, Close Invoice, Delete, Void Invoice — "Print or Save PDF" is Jobber's own PDF affordance
(browser print), confirming no separate PDF engine.

---

## Read-only research continuation — 2026-09-04 (observed live)

Inspected the signed-in account's invoice list and existing issued, unpaid invoice in the app browser.
Canceled payment creation, Close Invoice, Void Invoice, and header editing without changing any values
or saving. The observations below describe visible controls; no financial transition was executed.

- **Status presentation:** the overview says `Sent but not due`; the same invoice detail says `Awaiting
payment`. List filters offer Awaiting payment: past due / not yet due / all, Draft, Paid, Bad Debt,
  and Voided. Preserve the distinction between lifecycle facts and screen labels when implementing parity.
- **Manual collection:** Collect Payment opens a separate New Payment page. It shows Payment method,
  Transaction Date, Reference #, Details, account balance, and selectable outstanding invoices with an
  editable allocation amount per row. The originating invoice is preselected. Actions are Cancel, Save,
  and Save and Email Receipt. This account offers Other, Bank transfer, Cash, Check, Credit/debit card,
  and PayPal under `Create a payment record`; the schema's broader method enum is not evidence that
  every method is offered in every account.
- **Close Invoice:** the dialog offers With a payment, As bad debt, and Without recording a payment.
  The last choice explicitly says it changes status to paid without updating the client's account balance.
  Only the choices and explanation were inspected; their subsequent steps remain unverified live.
- **Void Invoice:** a confirmation modal warns that payment becomes unavailable and voiding cannot be
  undone. Reasons are Duplicate invoice, Created in error, Client request, and Other. The reason is for
  internal use and is not shown to the client. Cancel and Void are separate actions. Deposit release and
  notification behavior were not established by this modal.
- **Issued editing:** header editing remains available with subject, number, issued date, payment terms,
  due date, and Add Field, with local Cancel/Save controls. No changes were entered.
- **Issued More menu:** Email, Create Similar Invoice, Preview as Client, Collect Signature, Print or
  Save PDF, Close Invoice, Delete, and Void Invoice were visible. The presence of Delete does not establish
  eligibility or deletion consequences; it was not invoked. Customer preview was not opened, so no
  customer-view event was deliberately triggered.

**Official follow-through:** the [payment research](../../../docs/invoice-payment-research.md) and
[evidence matrix](../../../docs/invoice-jobber-evidence.md) now resolve the documented draft-payment,
closure, bad-debt, void, deletion, correction, and account-balance questions. Live-only limits above describe
what was actually tested; documented behavior is separately attributed. The redline is approved and applied; additional transitions remain proposals.

### Help-center sources

- Invoice Basics — https://help.getjobber.com/hc/en-us/articles/115009685047-Invoice-Basics
- Invoices List Page and Key Metrics — https://help.getjobber.com/hc/en-us/articles/39133270019991-Invoices-List-Page-and-Key-Metrics
- Bad Debt — https://help.getjobber.com/hc/en-us/articles/1500000583062-Bad-Debt
- How to Collect Payment on an Invoice — https://help.getjobber.com/hc/en-us/articles/360033907753-How-to-Collect-Payment-on-an-Invoice
- Invoice Reminders — https://help.getjobber.com/hc/en-us/articles/115009517847-Invoice-Reminders
- Batch Create Invoices — https://help.getjobber.com/hc/en-us/articles/115009687088-Batch-Create-Invoices
- Batch Deliver Invoices — https://help.getjobber.com/hc/en-us/articles/115009518207-Batch-Deliver-Invoices
- Progress Invoicing — https://help.getjobber.com/hc/en-us/articles/26297232277527-Progress-Invoicing
- Automatic Payments — https://help.getjobber.com/hc/en-us/articles/360036931633-Automatic-Payments
- Jobber Payments Basics — https://help.getjobber.com/hc/en-us/articles/115009571387-Jobber-Payments-Basics
- Manage your Jobber Payments Settings — https://help.getjobber.com/hc/en-us/articles/115009590727-Manage-your-Jobber-Payments-Settings
- Saving and Charging Payment Methods with Jobber Payments — https://help.getjobber.com/hc/en-us/articles/115009611087-Saving-and-Charging-Payment-Methods-with-Jobber-Payments
- Collecting Card Payments in the Field Using Jobber Payments — https://help.getjobber.com/hc/en-us/articles/8354601698583-Collecting-Card-Payments-in-the-Field-Using-Jobber-Payments-with-the-Jobber-App
- Bank Payments (ACH) — https://help.getjobber.com/hc/en-us/articles/1500004781762-Bank-Payments-ACH
- Tip Collection with Jobber Payments — https://help.getjobber.com/hc/en-us/articles/4410192275479-Tip-Collection-with-Jobber-Payments
- Billing History Box — https://help.getjobber.com/hc/en-us/articles/115009451467-Billing-History-Box

## Targeted transition follow-through

See [transition decisions](../../../docs/invoice-transition-decisions.md) before Part 2. Current official
Help confirms batch selection can complete incomplete Visits; it does not resolve partial-Draft effects,
partially paid Void, exact issued-progress monetary correction, or source rebilling after Void. Deposit
release proves no source-work release. The two approved traceability departures do not settle those gaps.

## UCRM transition approval

Jafar approved concrete D1–D5 in [the Invoice contract](../../../docs/invoice-behavior-contract.md).
Historical “unverified” labels above continue to describe Jobber evidence only. They no longer mean UCRM
behavior is undecided: partial Draft prepayment, explicit ordinary-payment disposition before Void,
progress correction chains, linked rebilling, and atomic batch Visit completion are approved UCRM behavior.
Part 2 design is for review; no implementation approval is implied.

## Payment receipts — 2026-09-05 (full flow recorded live on the trial account, then deleted)

**New Payment screen** (`/payments/new`): buttons bottom-right are **"Save and Email Receipt"** (secondary)
and **"Save"** (primary). "Save" for a recorded/offline payment, "Charge" for a Jobber Payments card charge.
Method dropdown under "Create a payment record": Other, Bank transfer, Cash, Check, Credit/debit card, PayPal
— exactly our six. Fields: Payment method, Reference #, Transaction Date, Details, then an "Outstanding
invoices" table (Invoice # / Due Date / Property Address / Total / Balance / Enter Payment), originating
invoice preselected. Recording a full payment flips the invoice to **Paid** and its primary action to
**Re-open Invoice**; a green banner "A payment of X from <client> has been recorded" with a **View payment
details** button.

**Payment Details screen** (`/payments/:id`) — observed live:
- Status pill "Succeeded". Top-right: **… More** (menu: **Download PDF**, **Delete**) and **Send Receipt**
  (primary green).
- Big amount, then a pencil (edits the amount). A client card (name, address, phone, email) with its own "…".
- **Details** section with a pencil: Transaction date, Method, Reference number, Details (free text),
  **Applied to: Invoice #N** (a link). The pencil edits date / method / details / applied-to.
- **Delete** → confirm modal "Deleting this Payment will permanently remove it from the billing history for
  <client>." Deleting returns to `/home`; the invoice goes back to Awaiting payment.

**The receipt document** (`… More → Download PDF`, served from `heavy.getjobber.com/balance_adjustments/:id.pdf`)
— observed live, this is the whole thing:
- Business name, bold, top-left.
- A dark filled badge top-right: **"Transaction date <Mon DD, YYYY>"** (same slot as the invoice's date badge).
- **"RECIPIENT:"** label, then client **name** (bold) and **billing address**. No client email or phone.
- Divider.
- Heading **"Receipt for Payment"**.
- **"Paid: $320.00"** (the amount).
- A small block: **Transaction date:** / **Method of payment:** / **Reference Number:**.
- Divider.
- The **Details** free-text note, verbatim.
- **That is all.** No receipt number. No invoice number. No line items. No balance / amount-still-owed. No
  logo (this account had none set). Currency printed as `$` regardless of the account's display currency.

**The "Send Receipt" dialog** — observed live:
- Editable **To** (recipient chips, prefilled with the client's email), **Subject**
  ("Receipt for payment from <Business> - <date>"), editable **Message** body
  ("Hi <name>, This email has a receipt attached to it for your payment of $320.00. Please keep this email
  for your reference. If you have any questions… Sincerely, <Business>").
- **Attachments:** `receipt.pdf` attached and checked — **Jobber attaches the PDF**, it does not send a
  client-hub link for receipts (unlike invoices/quotes).
- A **"Send me a copy"** checkbox. Cancel / **Send Email**.
- Also offered at creation time as **Save and Email Receipt** on the New Payment screen. No "copy link".

- Jobber Payments only: a settings toggle "Automatically email receipts to clients" fires a receipt after
  every successful **card** payment/refund. Irrelevant to us (we record only offline payments).
- A **Statement** (client account balance over a date range) is a separate document, not a receipt.

### How WE compare

- **Behavior/content follows Jobber; visual execution is ours** (Jafar 2026-09-05: "follow jobber, no
  guesswork" + "OURS should look Beautiful, Modern, Professional"). Our receipt is a **premium hosted page**
  at `/r/[token]` reusing the invoice customer-document paper shell, with browser Print/Save PDF — not a
  plain generated PDF.
- **Field set = exactly Jobber's:** business/brand header, "Transaction date" badge, RECIPIENT (name +
  billing address, no contact info), "Payment receipt" heading, **Paid: <amount>**, then transaction date /
  method / reference, then the details note. **No** receipt number, invoice number, line items, or balance.
  Money always shown (a receipt with the number removed is pointless); currency from the paying invoice's
  snapshot, not a literal `$`.
- **Email carries a link, not a PDF attachment** — forced by our approved "no server PDF engine" decision,
  and consistent with how we email invoices (6b-1). Modern-tool convention (Stripe-style).
- **Two entry points, mirroring Jobber:** a **"Save and email receipt"** secondary button on our
  CollectPaymentDialog, and **Send receipt** on the payment detail page.
- **Payment detail page** (`/(app)/payments/[id]`): Jobber has one and Send Receipt lives on it, so we build
  a read-only one — amount, method, transaction date, reference, details, Applied to: Invoice #N — with
  **Send receipt** + **Print / Save PDF**. Editing and deleting a payment (Jobber's pencil + … More → Delete)
  is ledger-correction work → deferred to a later part. Split: **6b-2a** = receipt document + hosted page +
  email + "Save and email receipt"; **6b-2b** = the payment detail page + "Send receipt" + wiring the
  invoice financial-history rows to link there.
