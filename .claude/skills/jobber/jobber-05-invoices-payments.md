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
per-job, and **batch**), reminders/dunning, deposits & progress invoicing, and the Jobber Payments money layer
(tips, ACH, tap-to-pay, capital loans).

---

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

## 2. Invoice statuses (`InvoiceStatusTypeEnum`) — from schema + [[invoice basics]]

Raw enum (schema): `draft`, `awaiting_payment`, `paid`, `past_due`, `bad_debt`, `sent_not_due`.

| Enum value         | Plain English (help center)                                                                                                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `draft`            | Created but **not sent** and not marked-sent — contractor-only. Leaves draft when sent (email/text) or marked sent.                                                                                                           |
| `sent_not_due`     | _"Awaiting payment but not yet due."_ Sent to the client; **due date hasn't passed.** (This is the schema's split of "Awaiting Payment" into a not-yet-due state.)                                                            |
| `awaiting_payment` | Sent, unpaid, due date logic in play. The help center's **"Awaiting Payment"** label = sent + unpaid + not past due.                                                                                                          |
| `past_due`         | **Past its due date** and not paid / not marked paid. Feeds the Past Due list + invoice follow-ups.                                                                                                                           |
| `paid`             | Full balance paid, **or** manually marked Paid.                                                                                                                                                                               |
| `bad_debt`         | Deemed partly/fully **uncollectible**; the remaining (or full) balance is written off to close the invoice and pull it out of Awaiting Payment / Past Due lists. **The invoice stays in Jobber for the record.** [[bad debt]] |

> **Reconciliation:** the overview file (`jobber-00`) summarized the flow as _Draft → Awaiting Payment → Paid
> (Past Due if overdue)_. The real enum adds **`sent_not_due`** (sent-but-not-yet-due, split out from
> "awaiting payment") and **`bad_debt`** (write-off). There is **no** separate "sent" or "viewed" status —
> viewing is tracked by `dateViewedInClientHub`, not a status.

**Closing an invoice** (`InvoiceCloseOptionsType`, from schema) has exactly two modes:
| Option | Meaning |
| --- | --- |
| `MARK_RECEIVED` | Mark the invoice **received without recording a payment** (close it, no money logged). |
| `BAD_DEBT` | Mark the invoice (or its remaining balance) as **bad debt** (uncollectible write-off). |

Closing is reversible: `invoiceReopen` re-opens a closed invoice and `invoiceUnmarkBadDebt` reverses a
bad-debt write-off (both are schema mutations — see §6).

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

### 5.5 Recording & collecting payments (help center)

- **Collect on an invoice:** open the invoice → **Collect Payment** (top right) → pick a method.
  Choose **Credit/Debit Card** to charge through Jobber Payments, or **"Create a payment record"** for an
  **offline** method (cash, check, etc.) you already received. [[how to collect payment]]
- **Record a deposit:** the **"Record deposit"** option logs a deposit received (method = cash, check,
  credit card, bank transfer, money order, or other, + amount, transaction date, details).
- When the full balance is covered, status flips to **Paid** automatically.

### 5.6 Jobber Payments money layer (help center) — [[jobber payments basics]]

- **Card fees** are a percentage per transaction, **set by your Jobber subscription plan**; accepts Visa /
  Mastercard / Amex, debit, **Apple Pay & Google Pay**. [[manage jobber payments settings]]
- **ACH bank payments:** all plans, **1% fee, US only** (runs on the ACH network). [[bank payments ach]]
- **Tips:** Jobber Payments can collect **tips** — default options **10% / 15% / 20%** of the invoice total,
  or a **custom** dollar amount; surfaced in Client Hub and the field app. [[tip collection]]
- **In the field:** collect card payments in the Jobber app via **tap-to-pay / card reader / terminal**.
  [[collecting card payments in the field]]
- **Automatic payments:** with a client's **saved payment method**, invoices can be **auto-created and
  auto-charged** — and when on, **invoice reminders are _not_ created** (nothing to chase). [[automatic payments]]
- **Payouts & capital:** `PayoutRecord` / `Payout` / `PayoutStatus` model deposits to the SP's bank;
  **`JobberPaymentsCapitalLoan`** models Jobber Capital lending offers (`offeredAdvanceAmount`,
  `acceptedAdvanceAmount`, `loanFeeAmount`, `status`, `expiresAfter`, Stripe-Capital-backed). Financing to the
  _contractor_, distinct from Wisetack financing to the _client_.
- **Surcharge / convenience fee (pass processing cost to the client):** the schema exposes surcharge plumbing
  (`hasRefundableSurchargePayments`, refundable-surcharge flags), but whether Jobber lets you **add a client
  surcharge** in settings was **not confirmed** in the help center results — **(unverified)**.

---

## 6. Reminders & dunning (help center)

- **Invoice follow-ups (dunning):** up to **two** automatic reminders for invoices in **past-due** status,
  sent by **email or text** asking the client to pay. You set **how many days after the due date** each fires
  — **max 90 days.** [[invoice reminders]]
- **Requires Invoicing:** an invoice reminder coming due flips the **job** to _Requires Invoicing_ so it
  surfaces for **batch** billing (see §4.1). [[invoice reminders]]
- **Review requests:** after payment, an SMS **Google-review** request can be sent (`allowReviewRequest`,
  `nextDateToSendReviewSms` gate the cadence). (Reputation domain — later file.)
- **Automatic payments override reminders:** if auto-pay is on, reminders aren't generated (§5.6).

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

## 8. How WE compare (build notes)

- **Status parity:** we need Jobber's split of "sent but not due" (`sent_not_due`) vs "awaiting payment" vs
  **`past_due`**, plus a real **`bad_debt`** write-off state that keeps the record but removes it from the
  chase lists. Confirm our invoice status enum covers _sent-not-due_, _past-due_, _bad-debt_, and that
  bad-debt only writes off the **remaining** balance when partially paid.
- **Close modes:** copy the two-mode close — **Mark Received** (close, no money) vs **Bad Debt** (write-off) —
  and make both **reversible** (`reopen` / `unmark bad debt`). Cheap, and matches accountant expectations.
- **`invoiceBalance` + `tipsTotal` split:** keep balance = total − payments as a live field, and keep **tips
  on top** of (not inside) the taxable total. Our tips work (M7, [[invoice-quote-parity-tracker]]) should
  already do this — verify.
- **Adjustment-type ledger:** Jobber records payments, deposits, refunds, corrections, failed-ACH reversals,
  bad-debt, and voids on **one** connection distinguished by `IncomeAdjustmentType`. A single money-movement
  ledger with a type discriminator beats separate tables — worth matching for clean billing history.
- **`CREDIT_CARD` (outside) vs `JOBBER_PAYMENTS` (processed) distinction:** our payment model should record
  _how_ money came in (offline card vs processed card vs ACH vs Zelle/Venmo/etc.) — Jobber's 15-value
  `PaymentType` is a good target list, plus `PaymentOrigin` for terminal/tap-to-pay/online provenance.
- **Batch billing loop:** the **Requires Invoicing → Batch Create → Batch Deliver** pipeline is the biggest
  operational win for high-volume trades (lawn/clean/HVAC). Our job "Requires Invoicing" status already exists
  (`jobber-04`); build the batch-create + batch-deliver on top of it. See [[jobs-operations-gaps-deferred]].
- **Progress invoicing (Item Total / Due This Invoice):** for big-ticket trades, the two-column client view
  (full price vs installment now) + deposits-applied-at-billing is the pattern to match. We deferred
  quote-side milestone presentation ([[quote-phase2-gaps]] #5) — the invoice side is where it pays off.
- **Automatic payments suppress reminders:** wire the same rule — if auto-charge is on for a client, don't
  generate dunning reminders. Aligns with our outbox/automation model ([[recurring-billing-autocharge-deferred]]).
- **Capital vs consumer financing:** two different products — **Jobber Capital** (loan to the _contractor_)
  and **Wisetack** (financing for the _client_). Don't conflate; both are partner integrations, both deferred
  for us until real volume.

---

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
