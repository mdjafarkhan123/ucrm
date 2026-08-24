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

> **Who may see cost is two separate permissions** (help center, checked 2026-08-20). **Show pricing**
> governs what the client pays — turn it off and that member cannot edit quotes or invoices at all.
> **Job costing** is the separate one that reveals unit cost and profit, and it can be off while the member
> still builds quotes every day. So a salesperson who prices work but never sees cost is a normal Jobber
> state, not an edge case. Cost is internal either way: the client never sees it, only the marked-up price.
> Our seeded roles match — office and sales edit quotes without `quotes.view_cost`; owner, admin and
> finance have it.

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
- **Signature is offered, not demanded:** "Since signatures aren't required to approve a quote" — the
  approval dialog lets a client **draw or type their name**, then press Approve, and approving without
  signing is allowed. A Client Hub setting **Require client signatures** turns it into a hard requirement
  for the whole account. [Quote Approvals] — _so the default is optional, and the requirement is an
  organization setting, not a rule baked into the approve button._
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

## 8. Live web tour (August 19, 2026)

Read-only tour of the current Jobber web app in the repository owner's trial account:

- The Quotes overview gives open-work tiles for **Draft**, **Awaiting response**, **Changes requested**,
  and **Approved**. It separately shows 30-day **Conversion rate**, **Sent**, and **Converted** metrics,
  then an all-quotes table with status/date filters, search, sortable client/number/created/status columns,
  property, and total.
- The new-quote composer is one document surface: title, client/property, quote number, custom fields,
  introduction, catalog or custom Product/Service lines, reorder, quantity, unit price, description, image,
  optional-line toggle, text-only rows, client-view controls, discount, tax, deposit/payment schedule,
  attachments, images, client message, contract/disclaimer default, and internal notes.
- Per-quote client-view controls independently show or hide quantities, unit prices, line totals, and
  totals. Their organization defaults live under PDF Style.
- Saving has distinct paths: **Save Quote** (draft), **Send as Email**, **Convert to Job**, or **Mark as
  Awaiting Response**. The Quotes list also exposes Templates and quote-data import.
- An Approved quote offers activity, Create Similar Quote, send by email, move back to Awaiting Response,
  archive, Preview as Client, Collect Signature, PDF, delete, and a primary Convert to Job action. The
  detail keeps client/property facts, dated status facts, document sections, and internal Notes together.
- A Request can already contain priced Product/Service lines. **Convert to Quote** opens an unsaved Quote
  with the client, property, request link, line name/description/quantity/unit price, and total preloaded;
  the Request remains visible in a context rail. This is copy-forward UX, not evidence that both records
  share the same persisted line-item rows.

### 8.1 The line-item block (August 20, 2026 — second tour, `/quotes/new`, quote detail, request detail)

This one block is reused verbatim across Quotes, Requests, Jobs, and Invoices. It has two states — a **read
table** and an **edit stack** — and the same component drives both the new-record composer and the
edit-in-place pencil on a saved record. Everything below was measured live on `secure.getjobber.com`.

> **This is a record of what Jobber does, not a spec to copy.** The pixel values, borders, and colors here
> exist so the structure is unambiguous — they are **not** ours to reproduce. Our looks come from
> `.claude/skills/design/` only. Take from this section: which fields exist, where they sit relative to
> each other, what appears when, and how it all behaves.

#### Read state

A four-column table under the section title, with the section pencil at the far top-right.

- Header row: **Line Item** (left aligned) · **Quantity** · **Unit Price** · **Total** (all right aligned).
- Each row: the item **name in bold**, and its **description on the next line in muted grey**, both inside
  the Line Item column. Qty / Unit Price / Total sit on the name's baseline, right aligned.
- A hairline separates rows. On **Request** (and only where a line has a photo) a **~52px rounded thumbnail**
  sits between the name block and the Quantity column. The Quote read table shows no thumbnail.
- Below the rows: an indented totals stack (starts at roughly the Quantity column) — **Subtotal**, then
  Discount and Tax **only when non-zero**, then a bold **Total** on its own rule.

#### Edit state — the row

Each line is a **card of stacked rows**, not a table row. The card sits between two gutters:

```
[ 24px drag gutter ] [ ---------- content ---------- ] [ 40px actions gutter ]
```

- **Content row 1** — CSS grid, `3fr 1fr 1fr 1fr`, `gap: 8px`, row height **50px**:
  **Name** · **Quantity** · **Unit price** · **Total**.
- **Content row 2** — `margin-top: 8px`, height **130px**: a **Description** textarea spanning the first
  three columns, and a **square image box** in the last column (244×129, `1px dashed #DADFE2`, radius 8).
- **Content row 3** — `margin-top: 8px`: the **"Mark as optional"** checkbox. **Quote only** — the Request
  version of the block has no optional checkbox.
- **48px of space** between one line card and the next.
- Below the last card: **Add Line Item** (green solid) and **Add Text** (white outline). The Request version
  shows **Add Line Item only** — no Add Text.

#### Edit state — the fields

Every one of the four fields is a **floating-label box**, never a placeholder:

- Box: 50px tall, `1px solid #DADFE2`, radius 8, white.
- Label: absolutely positioned at the top of the box, 12px/20px, muted `#49646F`, 16px side padding. It
  reads as a placeholder when the field is empty and shrinks to the top once there is a value or focus.
- Value: 14px/20px `#032B3A`, padding `20px 16px 8px`, left aligned — **money is left aligned in edit mode**
  even though it is right aligned in the read table.
- **Total is a field in the same style, not a plain figure** — it just never accepts input.
- Description is a 5-row textarea, no manual resize.

#### Edit state — the gutters

- **Drag handle** (⠿, 6-dot) in the left gutter. It **appears on hover** of the row and only once there are
  **two or more lines**. Dragging it reorders the lines; verified live.
- **`...` menu** in the right gutter, aligned to row 1. It **also only appears with two or more lines**, and
  it holds exactly one item: **Delete** (red trash icon + "Delete").

#### Behavior

- **Name is a catalog combobox.** Typing opens a dropdown grouped under a category header ("Services"), each
  result showing **name, description, and price** on one row, price right aligned. The list scrolls, and it
  **flips above the field** when there is no room below. Picking a result fills **name, description, and
  unit price**; Quantity stays at 1.
- After picking a catalog item, a small **"Fill With:"** popover offers **Last job** — the price and text
  used for that item last time — with an X to dismiss. Pricing memory, offered rather than applied.
- If nothing matches, the dropdown shows a single **"+ Create new item"**. That opens an **Add Product /
  Service** modal: Item type (Service/Product), Name (prefilled with what was typed), Description, a 3-up
  **Unit cost · Markup (%) · Unit price** row, a full-width image dropzone, an **Exempt from Tax** checkbox,
  and Cancel / **Create**. Typing a name and simply moving on keeps the line as a one-off, uncatalogued.
- **Add Line Item appends a card, focuses its Name, and immediately opens the full catalog dropdown.**
  Defaults are Quantity 1, Unit price 0.00.
- **Add Text appends a text-only card**: full-width Name, Description, and the image box — no Quantity, no
  Unit price, no Total, no optional checkbox. It keeps the drag handle and the `...` Delete.
- **Quantity accepts decimals** and shows exactly what was typed (`0.25`, `2.5`) — no forced formatting.
- **Unit price is a masked money field**: while focused it shows the bare number (`9999`); on blur it
  formats to the org currency with a symbol, thousands separators, and 2 decimals (`৳45.50`).
- **Total recalculates live** as qty or price changes, **rounded half-up to 2 decimals** (0.25 × 45.50 →
  ৳11.38), and the Subtotal below updates with it.
- **Empty Name validates on blur, not on Save**: red border plus an inline `⊘ Line item name is required`
  under the field, which pushes the rest of the card down.
- **Image box:** `accept="image/*"`, single file. Empty = dashed border with a centred green Upload icon
  button. Filled = solid border, the photo, and a green **pencil** (replace) plus a red **trash** (remove)
  stacked at the right edge, both always visible.
- **Client view** sits under the lines on a Quote (not on a Request): an eye icon, the words "Client view",
  and a **Change** link that expands **inline** — helper text ("Adjust what your client will see on this
  quote. To change the default for all future quotes, visit the **PDF Style**.") over four green checkboxes:
  **Quantities · Unit prices · Line item totals · Totals**. Change flips to Cancel while open.
- **Totals block** under the lines: Subtotal, `Add Discount`, `Add Tax`, bold Total, then
  `Add Deposit or Payment Schedule`.
- **Saving is section-scoped:** editing a saved record's block shows a sticky **Cancel / Save** bar for that
  section, and the page title switches to "Edit Request Line Items". Cancelling with edits pending opens a
  **"Discard changes?"** dialog — "You have unsaved changes. Are you sure you want to cancel editing?" —
  with **Keep Editing** and a red **Discard**.

#### Not yet observed

Mobile width. The extension could not resize the live window, so the narrow-screen behavior of this block
is still unknown — do not guess at it.

**How WE compare:** our shipped `RequestPricingBlock.svelte` was rebuilt earlier on 2026-08-20 toward this
shape but has not been compared against the real thing until now. The gaps to close are recorded in
`Memory/campaigns/quotes/parts/02-pricing-and-request-carry-forward.md`.

Separately, `jobber-02-requests-leads.md` §4.2 notes the **Request** page's **Labor** section is not
manually-entered line items at all — it is auto-populated read-only from time tracking ("Time tracked to
this request will show here"), confirmed again on this tour. Our app has no Labor UI (approved 2026-08-20);
a crew's time is priced as an ordinary Service line.

### 8.2 Staff list, composer, and detail (August 20, 2026 — Part 3 tour)

This read-only pass revisited the three staff surfaces immediately before planning our Quote workspace.
Reference captures live in `Design/Jobber Quotes/`; they document structure and behavior, not our visual style.

- **List:** one page combines a four-row Overview (**Draft**, **Awaiting response**, **Changes requested**,
  **Approved**), three separate 30-day metrics (**Conversion rate**, **Sent**, **Converted**), and one
  searchable table. The table columns are Client, Quote number/title, Property, Created, Status, and Total;
  Client, Quote number, Created, and Status are sortable. Status and date filters sit above the table.
  Overview rows count but do not act as filters. More Actions contains Templates and Import Quote Data.
- **Composer:** Quote number is prefilled, while Title and Client are the first editable facts. One document
  surface contains Products / Services, client-view controls, totals, optional Discount, Tax, and Deposit or
  Payment Schedule, optional Attachments / Images / Client Message sections, a default Contract / Disclaimer,
  and internal Notes. Client view expands inline and independently controls Quantities, Unit prices, Line item
  totals, and Totals. Save paths are **Save Quote**, **Send as Email**, **Convert to Job**, and **Mark as
  Awaiting Response**.
- **Approved detail:** status, history, primary **Convert to Job**, and More actions stay in the record header.
  More offers Create Similar Quote, Email, move to Awaiting Response, Archive, Preview as Client, Collect
  Signature, PDF, and Delete. The header then shows the title, client/property/contact card, Quote number,
  Created date, and Approved date. The document sections stay in the main column; internal Notes stay in a
  separate sidebar.
- **History:** View activity opens **Quote History** with Team, Type, and Date filters plus newest/oldest order.
  Events name the actor and action, timestamp them, and may show field-level before/after values. In the trial
  data this included created, line added, approved, and cost changed events.

**How WE compare for Part 3:** reuse the existing Clients/Requests list primitives (`DataTable`, compact
`KpiCard`, `StatusOverviewCard`, search/filter toolbar) and the shared work-record/detail primitives
(`WorkRecordHeader`, `ClientSummaryCard`, `RecordFactsList`, Notes, Attachments, and activity). Follow the two-
column UpliftContractor blueprints in `Design/Quotes new.jpg` and `Design/Quote Details.jpg`; Jobber supplies
behavior and information hierarchy only. Quote numbers remain database-allocated and non-editable in our
approved contract, even though Jobber exposes the number field in its composer.

---

### 8.3 Sending, awaiting response, approval, and signature (August 21, 2026 — Part 5 tour, observed live)

A read-mostly pass over the three states a quote passes through between staff and customer. One throwaway
quote (#2) was created, marked awaiting response, previewed as the client, then deleted; the account's real
quote was only read.

**Header by status.** One green primary action, named for the next step, plus a history clock icon and a
`More` menu:

| Status            | Primary action     | `More` menu                                                                                                                                       |
| ----------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Draft             | **Send Email**     | Convert to Job, Create Similar Quote / _Mark as…_ Awaiting Response, Approved / Preview as Client, Collect Signature, Print or Save PDF, Delete   |
| Awaiting response | **Send Email**     | Convert to Job, Create Similar Quote / _Mark as…_ Approved, Archive / Preview as Client, Collect Signature, Print or Save PDF, Delete             |
| Approved          | **Convert to Job** | Create Similar Quote / _Send as…_ Email / _Mark as…_ Awaiting Response, Archive / Preview as Client, Collect Signature, Print or Save PDF, Delete |

The `Mark as…` group only ever lists the states the quote is not already in, so the menu never offers a
no-op. Archive appears only once a quote has left Draft. Nothing here is a version control: Jobber has no
visible version list on the quote.

**Facts row grows with the lifecycle.** Draft shows Quote # and Created. Marking awaiting response adds a
**Sent** date; approval adds an **Approved** date. The dates are stamped facts in the same list, not a
separate timeline.

**Mark as Awaiting Response is one click.** No dialog, no confirmation, no email — the status chip flips,
a `Quote marked as awaiting response` toast appears, and the Sent date is stamped today. It is the offline
"I already gave them the quote" path, and it is what makes the quote visible and approvable in Client Hub.

**Send as Email could not be toured**: the trial account's own email is unverified, so choosing Email opens a
`Verify your email` gate ("You must verify your email address before you are able to send any email or SMS
messages from Jobber") instead of the send composer. The composer's fields remain unobserved — do not guess
at them.

**Collect Signature** is the staff-side in-person close, available in every status including Draft. It opens
a `Signature Pad` dialog: a large draw area with a `Clear` button, a dotted signature line labelled _Write
signature_, a `Send your client a copy` checkbox, and Cancel / Submit. Nothing else — no name field, no
typed-signature alternative on desktop.

**Preview as Client** opens the real Client Hub page in a new tab with `?preview=true`. The customer view is:
company name bar; a document card carrying Quote #, the status chip, client + property + phone, a facts
column (`Sent on`, later `Approved on`), the Product / Service table, totals, and a validity footer ("This
quote is valid for the next 30 days, after which values may be subject to change."). Beside it sits a
separate sticky rail card: **Quote Total** as a large figure, then **Approve** (primary) and **Request
Changes** (secondary) stacked full width. On an already-approved quote both buttons are gone and only the
Approved chip and `Approved on` date remain.

Outside preview the same URL is the logged-in Client Hub, with a left nav (Requests, Quotes, Appointments,
Invoices, Log Out, Refer a Friend), a `Back` link, and `Download PDF`. **Staff cannot approve from there** —
clicking Approve shows the tooltip _"This action is only available for your clients"_. The customer's own
approve-and-sign dialog therefore stays unobserved; only the help-center description of it is available.

**Metrics count events, not rows.** After the tour quote was deleted, the list's 30-day **Sent** tile still
read `1 · ৳500`. Sent appears to count the send/mark event rather than surviving quotes.

**How WE compare for Part 5:** the shape maps onto what Parts 3-4 already built. Our published-version
freeze is the thing Jobber does not show, so `Mark as awaiting response` and `Send` both become publish
actions on our side, and our header keeps the Version row Jobber has no equivalent for. The status-aware
primary action, the `Mark as…` group that hides no-ops, the growing facts row, the one-click offline send,
the signature pad with its "send the client a copy" option, and the two-button customer decision rail
(Approve / Request Changes) are all worth copying. The email composer is not observed, so our send dialog
follows our own Communications boundary rather than a guessed copy of Jobber's.

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
