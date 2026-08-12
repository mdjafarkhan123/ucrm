# Jobber Reference — Quotes

> Source: `JobberJson.md` (schema, authoritative for fields/enums) + Jobber Help Center (behavior, cited).
> Part of the Jobber competitor reference set — see `jobber-00-overview-lifecycle.md` for the index/lifecycle,
> `jobber-01-clients-properties.md` for Client/Property, and `jobber-02-requests-leads.md` for the Request
> that a quote is usually converted from. Plain English; **(unverified)** marks anything not confirmed.

A **Quote** is _"a cost estimate of work which Service Providers send to their clients before any work is
done"_ (schema). It carries line items (including **optional** upsell items and up to 3 **option sets** for
good/better/best), optional **deposits/payment schedules**, taxes, and a client-facing approval flow in
Client Hub (view → sign → approve → optionally pay deposit). This file documents the object, its line
items, statuses, deposits, and approvals.

---

## 1. Quote (`Quote`)

### 1.1 Fields (from schema)

| Field                            | Type                          | Meaning                                                                 |
| -------------------------------- | ----------------------------- | ----------------------------------------------------------------------- |
| `id`                             | `EncodedId!`                  | Opaque unique id.                                                       |
| `quoteNumber`                    | `String!`                     | Human quote number (non-unique, SP-assigned).                           |
| `title`                          | `String`                      | Description/title of the quote.                                         |
| `message`                        | `String`                      | Message to the client (cover note).                                     |
| `contractDisclaimer`             | `String`                      | Contract / disclaimer text shown on the quote (T&C / warranty block).   |
| `client`                         | `Client`                      | The client the quote is for.                                            |
| `property`                       | `Property`                    | The property the quote is for.                                          |
| `request`                        | `Request`                     | The request this quote was converted from (if any).                     |
| `salesperson`                    | `User`                        | Assigned salesperson.                                                   |
| `quoteStatus`                    | `QuoteStatusTypeEnum!`        | Current status (see §2).                                                |
| `lineItems`                      | `QuoteLineItemConnection!`    | The quote's line items (see §3).                                        |
| `amounts`                        | `QuoteAmounts!`               | Money breakdown (see §1.2).                                             |
| `taxDetails`                     | `TaxDetails`                  | Tax rate + amount details.                                              |
| `customFields`                   | list                          | Quote-level custom field values.                                        |
| `depositRecords`                 | `PaymentRecordConnection!`    | Deposit payments applied to the quote.                                  |
| `depositAmountUnallocated`       | `Float`                       | Paid deposit not yet tied to an invoice.                                |
| `unallocatedDepositRecords`      | `PaymentRecordConnection!`    | Deposit records not yet applied to an invoice and not refunded.         |
| `hasRefundableSurchargePayments` | `Boolean!`                    | Whether any deposit has a refundable surcharge amount.                  |
| `eligibleForFinancing`           | `Boolean!`                    | Whether the quote qualifies for **Wisetack** consumer-financing offers. |
| `jobs`                           | `JobConnection`               | Job(s) converted from this quote.                                       |
| `notes` / `noteAttachments`      | connections                   | Internal notes + files.                                                 |
| `tasks`                          | `TaskConnection!`             | Basic tasks attached to the quote.                                      |
| `linkedCommunications`           | `MessageInterfaceConnection!` | All messages related to this quote.                                     |
| `clientHubUri`                   | `String`                      | Client-Hub URL of the quote (client-facing).                            |
| `clientHubViewedAt`              | `ISO8601DateTime`             | When the client last viewed it in Client Hub.                           |
| `sentAt`                         | `ISO8601DateTime`             | When the quote was last sent to the client.                             |
| `transitionedAt`                 | `ISO8601DateTime!`            | When it entered its current status.                                     |
| `lastTransitioned`               | `QuoteLastTransitioned!`      | Dated history: `approvedAt`, `changesRequestedAt`, `convertedAt`.       |
| `createdAt` / `updatedAt`        | `ISO8601DateTime!`            | Timestamps.                                                             |
| `jobberWebUri`                   | `String!`                     | Deep link in Jobber web.                                                |

### 1.2 `QuoteAmounts` (money breakdown — all `Float!`)

| Field                      | Meaning                                          |
| -------------------------- | ------------------------------------------------ |
| `subtotal`                 | Line-item costs, before tax.                     |
| `discountAmount`           | Discount applied.                                |
| `nonTaxAmount`             | Portion exempt from tax (tax-exempt line items). |
| `taxAmount`                | Tax charged.                                     |
| `total`                    | Grand total (line items + tax).                  |
| `depositAmount`            | Deposit required on the quote.                   |
| `outstandingDepositAmount` | Deposit still to be collected.                   |

> **Build note:** Jobber tracks the **deposit as part of the quote's amounts** (required amount +
> outstanding), separate from the line-item total, and tracks **unallocated** deposit money so a deposit
> paid at approval can later be applied to whichever invoice is raised. Copy this: a deposit is money held
> against the quote, applied to an invoice on billing.

---

## 2. Quote statuses (`QuoteStatusTypeEnum`) — from schema

| Enum value          | Schema description                                      | Plain English                                                                                      |
| ------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `draft`             | "The default state of a quote"                          | Not sent; contractor-only.                                                                         |
| `awaiting_response` | "The state when the quote is sent to a client"          | Sent; waiting for the client.                                                                      |
| `changes_requested` | "The state when a client requests changes to the quote" | Client asked for changes.                                                                          |
| `approved`          | "The state when a quote is approved by a client"        | Client approved (signed) or staff marked approved.                                                 |
| `converted`         | "The state when a quote is converted to a job"          | Turned into a job — **terminal** (stays Converted even if the job is deleted; see `jobber-00` §6). |
| `archived`          | "The state when a quote is archived"                    | Archived/closed.                                                                                   |

> Note the **overview file's** table also lists an "Awaiting Payment" (deposit) state; the raw enum does
> **not** have a separate `awaiting_payment` value — a required-deposit quote stays `awaiting_response`
> until approved, and the deposit is collected _at approval_ via "Approve and Pay Deposit" (see §5).
> Treat "awaiting payment" as a UI/label nuance, not a distinct enum state. **(reconciled from schema)**

**`QuoteTransitionOnCreate` enum:** when creating a quote you may transition it straight to
`AWAITING_RESPONSE` (i.e. create-and-send). That's the only create-time transition exposed.

**`QuoteLastTransitioned`** records the dated history: `approvedAt`, `changesRequestedAt`, `convertedAt`
(all `ISO8601DateTime`).

---

## 3. Quote line items (`QuoteLineItem`)

### 3.1 Fields (from schema)

| Field                     | Type                           | Meaning                                                                         |
| ------------------------- | ------------------------------ | ------------------------------------------------------------------------------- |
| `id`                      | `EncodedId!`                   | Unique id.                                                                      |
| `name`                    | `String!`                      | Line item name.                                                                 |
| `description`             | `String!`                      | Description.                                                                    |
| `category`                | `ProductsAndServicesCategory!` | Product vs service category.                                                    |
| `quantity`                | `Float!`                       | Quantity.                                                                       |
| `unitCost`                | `Float`                        | Your cost per unit.                                                             |
| `unitPrice`               | `Float!`                       | Price per unit to the client.                                                   |
| `markup`                  | `Float`                        | Markup on the line item.                                                        |
| `totalCost`               | `Float`                        | Total cost (internal).                                                          |
| `totalPrice`              | `Float!`                       | Total price to client.                                                          |
| `taxable`                 | `Boolean!`                     | **Per-line taxable flag** (tax can be set per line).                            |
| `optional`                | `Boolean!`                     | Whether the line is an **optional add-on** the client can choose.               |
| `recommended`             | `Boolean`                      | For optional lines: whether it's recommended / has been selected by the client. |
| `textOnly`                | `Boolean!`                     | A text-only line (no qty/price — a note/heading).                               |
| `sortOrder`               | `Int`                          | Display order.                                                                  |
| `linkedProductOrService`  | `ProductOrService`             | The price-book item this line came from.                                        |
| `createdAt` / `updatedAt` | `ISO8601DateTime!`             | Timestamps.                                                                     |

> **Cost + markup + margin are first-class** on the line (`unitCost`, `markup`, `totalCost` alongside
> `unitPrice`/`totalPrice`) — this is how Jobber shows profitability while quoting. We shipped the
> equivalent (target-margin tone + markup⇄margin toggle, per-line taxable) — see [[quote-phase2-gaps]].

### 3.2 Optional line items & Good/Better/Best (help center)

Two distinct upsell mechanisms — **don't conflate them**:

1. **Optional line items** (`optional: true`, `recommended`): the client can **check on** extra
   products/services at approval time in Client Hub. When they approve, selected optional items are
   included and the quote total updates to include them; unselected optionals show as greyed-out.
   [Optional Line Items on Quotes], [Quoting on the Grow Plan]
2. **Quote Options / packages ("good-better-best"):** a quote can include **up to 3 option sets**, so you
   present good/better/best packages, product alternatives, or service tiers in a clean layout; the client
   picks one. (This is a newer "Quotes Options" feature, distinct from optional line items.)
   [Quotes Options (Beta)], [Advanced Quote Customization]

- **Line-item images** and optional-item selection in Client Hub are **Grow-plan** features — Jobber's
  client-facing upsell surface. [Quoting on the Grow Plan]
- **Quote templates** let you save reusable quotes. [Quote Templates]

---

## 4. Deposits & payment schedules (help center)

- **Add a deposit or payment schedule** to be collected when the client approves. With Jobber Payments on,
  clients pay it straight from Client Hub. [Optional Line Items…], [Deposits on Quotes]
- **Deposit calculation:** choose **Percentage (%)** of the total (e.g. 25%) **or** a **Fixed Amount ($)**
  (e.g. $300). [Deposits on Quotes]
- **Required deposit gates the job:** when a quote has a _required_ deposit, the client must pay it before
  work starts — Client Hub shows **"Approve and Pay Deposit"** instead of plain "Approve." [Deposits on Quotes]
- **Deposit money is tracked as unallocated** until applied to an invoice (`unallocatedDepositRecords`,
  `depositAmountUnallocated`); refundable surcharges are flagged (`hasRefundableSurchargePayments`).
  [Quote Deposits and Jobber Payments]
- **Progress invoicing / payment schedules** exist for larger jobs (milestone billing). [Progress Invoicing]
- **Financing:** `eligibleForFinancing` ties into the **Wisetack** consumer-financing integration — the
  client can finance the quote. (We deferred financing — see [[quote-phase2-gaps]].) [Jobber & Wisetack…]

---

## 5. Approvals & client flow (help center)

- **Client approves in Client Hub:** they view the quote, then **sign** (draw or type their name) and
  approve. If a required deposit exists, it's **"Approve and Pay Deposit."** [Quote Basics], [Deposits on Quotes]
- **Signature invalidation on edit:** if an **Approved** quote's _total, deposit, line items, client
  message, contract/disclaimer, or quote number_ is edited, the client's **signature is removed** from the
  signature line and Client Hub. [Deposits on Quotes] — _strong integrity rule worth copying._
- **Manual approval:** if the client approves verbally, staff can **More → Approved** to mark it approved.
  [Quote Approvals]
- **Changes requested:** clients can request changes online; **all admins are emailed** when a client
  approves or requests changes. You edit and **re-send**; they approve the updated version. [Quote Approvals]
- **Follow-ups vs reminders (two different things):**
  - **Quote follow-ups** (select plans) — auto-send a reminder to the _client_ after N days if the quote
    isn't approved, using the same channel the quote was sent (text or email). Gated per-client by
    `receivesQuoteFollowUps` (see `jobber-01` §1.2). [Quote Approvals]
  - **Quote reminders** (all plans) — an internal to-do added to _your_ schedule, auto-assigned to the
    quote's creator, to follow up manually. [Quote Approvals]
- **In-person / on-the-spot signing** ("close in the field") is supported — client signs on the SP's
  device. (We shipped the equivalent — see [[quote-phase2-gaps]].)

---

## 6. Mutations & queries (from schema)

Jobber's public API exposes **create/edit** and line-item/note operations, but **not** explicit
approve/convert mutations (those are web-app actions):

| Action                 | Mutation                                                                       | Returns                            |
| ---------------------- | ------------------------------------------------------------------------------ | ---------------------------------- |
| Create quote           | `QuoteCreate` (`QuoteCreateAttributes`; may transition to `AWAITING_RESPONSE`) | `quote`, `userErrors`              |
| Edit quote             | `QuoteEdit` (`QuoteEditAttributes`)                                            | `quote`, `userErrors`              |
| Create line items      | `QuoteCreateLineItems` (`QuoteCreateLineItemAttributes`)                       | `quote`, `userErrors`              |
| Create text line items | `QuoteCreateTextLineItems` (`QuoteCreateTextLineItemAttributes`)               | `quote`, `userErrors`              |
| Edit line items        | `QuoteEditLineItems` (`QuoteEditLineItemAttributes`)                           | `quote`, `userErrors`              |
| Delete line items      | `QuoteDeleteLineItems`                                                         | `quote`, `userErrors`              |
| Add / edit quote note  | `QuoteCreateNote` / `QuoteEditNote`                                            | `quote`, `quoteNote`, `userErrors` |

_(Introspection did not expand `INPUT_OBJECT` fields, so the exact create/edit input arguments aren't
enumerable from `JobberJson.md`.)_ **No public `QuoteApprove` / `QuoteConvertToJob` mutation** appears in
the sampled schema — approval, change-requests, and conversion are done in the web app / Client Hub, not via
the public API **(unverified whether such mutations exist under different names)**.

Read queries: `quote(id)`, `quotes(filter, sort)` (`QuoteFilterAttributes`, `QuotesSortInput` /
`QuotesSortKey` — e.g. sort by property street). Client-view config: `QuoteClientViewOptionsInput`.

---

## 7. How WE compare (build notes)

- **Two upsell mechanisms, not one.** To reach Jobber parity we need **both** _optional line items_ (client
  checks add-ons at approval, total updates) **and** _option sets / good-better-best_ (up to 3 packages the
  client chooses between). We already have good-better-best + per-line taxable + margin/markup (see
  [[quote-phase2-gaps]] — done & verified); confirm the **optional-item selection in the client portal**
  (client toggles, total recalculates) is fully wired, since that's the highest-converting piece.
- **Deposit model to match exactly:** percentage **or** fixed; _required_ deposits gate the job with an
  **"Approve and Pay Deposit"** action; deposit money is held **unallocated** and applied to an invoice at
  billing. Our invoice↔quote deposit handling should carry the same unallocated→applied lifecycle.
- **Signature-invalidation rule is a keeper.** Editing any material field of an approved quote (total,
  deposit, line items, message, disclaimer, quote number) **voids the signature**. This prevents
  bait-and-switch and is cheap to implement — adopt it.
- **Contract/disclaimer is a dedicated field** (`contractDisclaimer`), separate from the cover `message`.
  We shipped org-default + per-quote T&C ([[quote-phase2-gaps]] #7) — matches.
- **Follow-ups (to client) vs reminders (to staff) are separate features** gated by different plans and by
  the per-client `receivesQuoteFollowUps` toggle. Keep the two distinct in our automation model.
- **Converted is terminal** — same rule as requests: a quote that became a job never reverts. Enforce it to
  block double-conversion.

---

### Help-center sources

- Quote Basics — https://help.getjobber.com/hc/en-us/articles/115009378727-Quote-Basics
- Quote Approvals — https://help.getjobber.com/hc/en-us/articles/115012715008-Quote-Approvals
- Optional Line Items on Quotes — https://help.getjobber.com/hc/en-us/articles/360046575473-Optional-Line-Items-on-Quotes
- Quoting on the Grow Plan — https://help.getjobber.com/hc/en-us/articles/360049853114-Quoting-on-the-Grow-Plan
- Quotes Options (Beta) — https://help.getjobber.com/hc/en-us/articles/33970469537047-Quotes-Options-Beta
- Advanced Quote Customization — https://help.getjobber.com/hc/en-us/articles/28400864393495-Advanced-Quote-Customization
- Quote Templates — https://help.getjobber.com/hc/en-us/articles/29292809768983-Quote-Templates
- Deposits on Quotes — https://help.getjobber.com/hc/en-us/articles/115009379007-Deposits-on-Quotes
- Quote Deposits and Jobber Payments — https://help.getjobber.com/hc/en-us/articles/115009611207-Quote-Deposits-and-Jobber-Payments
- Progress Invoicing — https://help.getjobber.com/hc/en-us/articles/26297232277527-Progress-Invoicing
- Jobber and Wisetack Consumer Financing Integration — https://help.getjobber.com/hc/en-us/articles/360056100954-Jobber-and-Wisetack-Consumer-Financing-Integration
- Quotes in the Jobber App — https://help.getjobber.com/hc/en-us/articles/7760313735575-Quotes-in-the-Jobber-App
