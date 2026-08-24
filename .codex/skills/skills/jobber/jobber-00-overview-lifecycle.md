# Jobber Competitor Reference — Overview & Lifecycle

> **What this is.** A precise, plain-English reference to how **Jobber** (getjobber.com) models a
> contractor business, so we can build a competing CRM and know exactly what to **match** or **beat**.
> Built from two sources: (1) Jobber's live **GraphQL API schema** (`JobberJson.md` in repo root — the
> authoritative source for objects, fields, enums, mutations) and (2) the **Jobber Help Center**
> (behavior/UX, cited inline). This is a reference for AI-assisted development, **not** marketing copy.
>
> **No-guessing rule:** field/enum names are taken verbatim from the schema. Behavior is taken from the
> help center with a citation. Anything not confirmed by either is marked **(unverified)**.

This is the index for the Jobber reference set. Read the specific file for your domain.

| Topic                                                                                            | File                                  | Status   |
| ------------------------------------------------------------------------------------------------ | ------------------------------------- | -------- |
| **This file** — vocabulary, full lifecycle, object map, master status table, API basics          | `jobber-00-overview-lifecycle.md`     | ✅ built |
| **Clients & Properties** — the customer + location model, tags, custom fields, client hub basics | `jobber-01-clients-properties.md`     | ✅ built |
| **Requests & Leads** — work requests, assessments, lead intake/booking                           | `jobber-02-requests-leads.md`         | ✅ built |
| **Quotes** — quote object, line items, good-better-best, deposits, approvals                     | `jobber-03-quotes.md`                 | ✅ built |
| **Jobs, Visits & Scheduling** — one-off vs recurring, recurrence, assignments, calendar          | `jobber-04-jobs-visits-scheduling.md` | ✅ built |
| **Invoices & Payments** — invoice object, line items, payment records, Jobber Payments           | `jobber-05-invoices-payments.md`      | ✅ built |
| **Automations & Client Hub** — triggers/actions, self-serve client portal                        | `jobber-06-automations-clienthub.md`  | ✅ built |
| **API model & Mutations** — full query/mutation catalog, pagination, webhooks, rate limits       | `jobber-07-api-mutations.md`          | ✅ built |

---

## 1. Vocabulary (Jobber's terms → what they mean)

Jobber talks about two sides of every account:

- **Service Provider (SP)** = the contractor's business. In the API this is the **`Account`**
  ("The company of a Service Provider who uses Jobber for their business operations"). Team members are
  **`User`** records under the account.
- **Service Consumer (SC)** = the customer. In the API this is the **`Client`** ("the customers who pay
  for services... they belong to the Jobber account / service provider").

The core objects, in the order a job flows through them:

| Term           | API type        | Plain English                                                                                          |
| -------------- | --------------- | ------------------------------------------------------------------------------------------------------ |
| **Account**    | `Account`       | The contractor's company/tenant. Has `industry`, `countryCode`, `dedicatedPhoneNumber`, features.      |
| **User**       | `User`          | A team member / staff login on the account.                                                            |
| **Client**     | `Client`        | The customer (person or company). Can be a **lead** (`isLead: true`) before they become a real client. |
| **Property**   | `Property`      | A physical location owned by the client where work happens. A client can have 0, 1, or many.           |
| **Request**    | `Request`       | An incoming work request / job lead ("customer wants work done"). Often the first object created.      |
| **Assessment** | `Assessment`    | An on-site visit to scope/estimate the work before quoting. A schedulable item tied to a request.      |
| **Quote**      | `Quote`         | A priced estimate sent to the client for approval. Has line items, optional add-ons, deposits.         |
| **Job**        | `Job`           | The **contract / scope of work** that's been agreed to. Can be **one-off** or **recurring**.           |
| **Visit**      | `Visit`         | A single scheduled appointment on the calendar at the property to do (part of) the job's work.         |
| **Invoice**    | `Invoice`       | A bill sent to the client for completed work.                                                          |
| **Payment**    | `PaymentRecord` | Money received against an invoice (or a deposit).                                                      |

Supporting/adjacent objects seen in the schema: `Event` (calendar event not tied to a job),
`Task` (to-do, schedulable), `Expense`, `TimeSheetEntry` (time tracking), `ProductOrService`
(price-book line item), `TaxRate`, `Vehicle`, `MarketingItemType` (Google/Facebook marketing),
`OnlineBookingConfiguration`, `RequestSettings`, and Jobber Payments objects
(`JobberPaymentsCapitalLoan`, `PayoutRecord`, `PaymentMethodInterface`).

---

## 2. The full lifecycle (lead → cash)

Plain English: **a stranger asks for work → you scope & price it → they say yes → you schedule and do
the work → you bill them → they pay.** Jobber models each step as its own object, all hanging off the
**Client**. Here is the canonical happy path:

```
                 (someone wants work done)
                          │
   ┌──────────────────────▼───────────────────────┐
   │ REQUEST  (Request)                            │  ← online booking form, Client Hub "request work",
   │  • auto-creates a CLIENT as a LEAD (isLead)   │    contact form, or entered manually by staff
   └──────────────────────┬───────────────────────┘
                          │  (optional) book an on-site
                          ▼
   ┌──────────────────────────────────────────────┐
   │ ASSESSMENT (Assessment)                       │  ← a scheduled visit to look at the job and scope it
   │  • schedulable, assigned to a team member     │    (a.k.a. estimate/site visit)
   └──────────────────────┬───────────────────────┘
                          │  convert request →
                          ▼
   ┌──────────────────────────────────────────────┐
   │ QUOTE (Quote)                                 │  ← priced estimate: line items, optional add-ons
   │  status: Draft → Awaiting Response →          │    (good-better-best), optional deposit required
   │          Approved / Changes Requested         │    Client approves in Client Hub (or staff marks it)
   └──────────────────────┬───────────────────────┘
                          │  convert quote → (Quote status becomes CONVERTED, final)
                          ▼
   ┌──────────────────────────────────────────────┐
   │ JOB (Job)  = the contract/scope of work       │  ← ONE-OFF (single or few visits, one final invoice)
   │  • carries line items / pricing               │    or RECURRING (repeating visits on a schedule)
   └──────────────────────┬───────────────────────┘
                          │  job schedules one or more →
                          ▼
   ┌──────────────────────────────────────────────┐
   │ VISIT (Visit)  = a calendar appointment       │  ← scheduled (date+time), anytime (date only),
   │  • assigned to team member(s) at the property │    or unscheduled (neither). Marked complete on site.
   └──────────────────────┬───────────────────────┘
                          │  work done → bill it
                          ▼
   ┌──────────────────────────────────────────────┐
   │ INVOICE (Invoice)                             │  ← per visit, per job, or on a billing schedule
   │  status: Draft → Awaiting Payment → Paid      │    (recurring jobs can invoice many times)
   │          (Past Due if overdue)                │
   └──────────────────────┬───────────────────────┘
                          │  client pays
                          ▼
   ┌──────────────────────────────────────────────┐
   │ PAYMENT (PaymentRecord)                       │  ← Jobber Payments (card/ACH) or manually recorded
   │  • deposits can be collected before the job   │    (cash/check). Optional review request after.
   └──────────────────────────────────────────────┘
```

**Not every step is required — the flow has shortcuts.** Jobber lets you enter at almost any point:

- Create a **Client** directly (no request). A client imported from CSV is a real client, **not** a lead.
  [[client basics]]
- Create a **Quote** without a request; a **Job** without a quote; an **Invoice** without a job
  (a "one-off invoice"). These direct objects all still attach to a Client + Property.
- **Leads** enter as `Client` rows with `isLead: true` — a request from a brand-new person auto-creates
  the client as a lead. They stop being a lead once they meet client criteria (e.g. quoted/scheduled).

---

## 3. Object relationship map

Everything hangs off **Client**. The `Client` object exposes connections to every downstream object,
which tells you the intended hierarchy:

```
Account (the contractor / tenant)
└── Client (customer; may be isLead)
    ├── contacts            → ContactModel (multiple named contacts per client)
    ├── phones / emails     → ClientPhoneNumber / email (multiple, one primary each)
    ├── billingAddress      → ClientAddress
    ├── clientProperties    → Property (the physical service locations)
    │   └── Property
    │       ├── address     → PropertyAddress (geo-coded)
    │       ├── taxRate     → TaxRate
    │       ├── jobs / quotes / requests / scheduledItems
    │       └── recentPricing → ProductOrService (price memory per property)
    ├── requests            → Request
    ├── quotes              → Quote
    ├── jobs                → Job
    │   └── visits          → Visit
    ├── invoices            → Invoice
    │   └── payments        → PaymentRecord
    ├── notes / noteAttachments → ClientNote / ClientNoteFile
    ├── tags                → Tag
    ├── scheduledItems      → ScheduledItemInterface (visits, assessments, tasks, events, reminders)
    └── requestedWorkObjects → union of requests+quotes+jobs+invoices+treatments (unified timeline)
```

Key modeling facts:

- **`scheduledItems`** is a polymorphic connection (`ScheduledItemInterface`) — the calendar is a single
  stream of Basic Tasks, **Visits**, Events, **Assessments**, Quote Reminders, and Invoice Reminders.
  This is Jobber's unified "schedule" abstraction. (See `jobber-04`.)
- **`requestedWorkObjects`** (`RequestedWorkObjectUnionConnection`) is a unified **activity timeline** per
  client mixing requests, quotes, jobs, invoices, and treatments — how the client detail page shows history.
- A `Property` — not the client — is what carries `taxRate`, `recentPricing`, `routingOrder` (for route
  optimization), and geo-coordinates. Work is always tied to a property.

---

## 4. Master status table

All core status enums are confirmed from the schema below (each domain file has the full detail). Each
status's plain-English meaning is the important part for building parity.

### Quote statuses (`Quote.quoteStatus`) — [[quote approvals]] [[quote basics]]

| Status                | Meaning                                                                                         |
| --------------------- | ----------------------------------------------------------------------------------------------- |
| **Draft**             | Not sent yet; only visible to the contractor.                                                   |
| **Awaiting Response** | Sent to client; waiting for approval or a change request.                                       |
| **Changes Requested** | Client asked for changes.                                                                       |
| **Approved**          | Client approved (in Client Hub) or staff marked it approved manually.                           |
| **Awaiting Payment**  | Quote was sent to collect a **deposit**; waiting for that payment.                              |
| **Converted**         | Quote has been turned into a job. **Final** — stays Converted even if the job is later deleted. |
| **Archived**          | Quote archived/closed.                                                                          |

### Job statuses (`JobStatusTypeEnum`) — [[job basics]] [[jobs list page]] (full detail in `jobber-04` §4)

Derived from visit/invoicing state, not set by hand. Enum (schema): `active`, `upcoming`, `today`, `late`,
`unscheduled`, `action_required`, `on_hold`, `requires_invoicing`, `expiring_within_30_days`, `archived`.
| Status | Meaning |
| --- | --- |
| **Active** | In progress (not closed). Umbrella over late/today/upcoming/etc. |
| **Upcoming / Today** | Has a visit in the future / today. |
| **Late** | A visit's date passed but it wasn't marked complete. |
| **Unscheduled** | Visits created but set to be scheduled later. |
| **Action Required** | Active but **no more upcoming visits** — prompt to schedule more or close. **`on_hold` is an explicit alias for this** (confirmed in schema). |
| **Requires Invoicing** | An invoice reminder is due/overdue → flips here so jobs can be **batch-invoiced**. |
| **Expiring within 30 days** | Active job expiring within 30 days. |
| **Archived** | Closed job that no longer needs invoicing — you're done with it. |

### Visit states (`VisitStatusTypeEnum`) — [[visits]] [[job basics]] (full detail in `jobber-04` §3)

Enum (schema): `ACTIVE`, `UPCOMING`, `TODAY`, `LATE`, `UNSCHEDULED`, `COMPLETED`. Orthogonal to those, a
visit is one of **three kinds** by how it's placed on the calendar:
| Kind | Meaning |
| --- | --- |
| **Scheduled** | Has a date **and** a time. |
| **Anytime** | Has a date but **no** specific time (`startAt`/`endAt` time blank; route-ordered). |
| **Unscheduled** | Has **neither** date nor time (`startAt`/`endAt` both null — a backlog placeholder). |

### Request statuses (`RequestStatusTypeEnum`) — [[requests and leads]] (see `jobber-02`)

Enum values (schema): `new`, `unscheduled`, `upcoming`, `today`, `overdue`, `assessment_completed`,
`completed`, `converted`, `archived`. Plain English:
| Status | Meaning |
| --- | --- |
| **New / Pending** | New request created online or via Client Hub, not yet actioned. |
| **Unscheduled** | Assessment turned on but not yet placed on the calendar. |
| **Upcoming / Today / Overdue** | Calendar state of the scheduled assessment relative to now. |
| **Assessment completed / Action Required** | Assessment marked complete but request not yet converted/archived. |
| **Converted** | Converted to a quote or job. **Final** (like Quote Converted). |
| **Archived** | Archived/closed. |

### Invoice statuses (`InvoiceStatusTypeEnum`) — [[invoice basics]] [[bad debt]] (full detail in `jobber-05` §2)

Enum (schema): `draft`, `sent_not_due`, `awaiting_payment`, `paid`, `past_due`, `bad_debt`.
| Status | Meaning |
| --- | --- |
| **Draft** | Created, not sent / not marked-sent — contractor-only. |
| **Sent, not due** (`sent_not_due`) | Sent to the client; due date hasn't passed. |
| **Awaiting Payment** | Sent, unpaid (the "awaiting payment" label). |
| **Past Due** | Past its due date and unpaid → feeds invoice follow-ups / dunning. |
| **Paid** | Full balance paid, or manually marked Paid. |
| **Bad Debt** | Uncollectible write-off (remaining or full balance); stays in Jobber for the record, off the chase lists. |

**Closing an invoice** (`InvoiceCloseOptionsType`): `MARK_RECEIVED` (close, no payment) or `BAD_DEBT`
(write-off). Both reversible (`invoiceReopen`, `invoiceUnmarkBadDebt`). A job in **Requires Invoicing** feeds
batch invoice creation.

### Payment "adjustment" types (`IncomeAdjustmentType`) — (full detail in `jobber-05` §5)

Not a status but the money-movement discriminator on the payments ledger (schema): `PAYMENT`, `INVOICE`,
`DEPOSIT`, `REFUND`, `CORRECTION`, `INITIAL_BALANCE`, `FAILED_ACH_PAYMENT`, `BAD_DEBT`, `VOIDED`. Jobber
Payments charges also carry a processor status (`JobberPaymentTransactionStatus`: `PENDING`, `SUCCEEDED`,
`FAILED`, `REFUNDED`, `PARTIALLY_REFUNDED`, `IN_DISPUTE`, `DISPUTED`).

---

## 5. API model basics (what every domain file assumes)

Jobber's public API is **GraphQL** (single endpoint, versioned by date header). Facts that hold across
every object (details + full mutation catalog in `jobber-07`):

- **IDs are `EncodedId`** — every object's `id` is an opaque base64-style encoded string (not a raw DB
  integer). Passed back verbatim to fetch/mutate.
- **Lists are Relay-style connections.** e.g. `ClientConnection` has `edges { cursor node }`, `nodes`,
  `pageInfo` (`hasNextPage`, `endCursor`), and `totalCount`. Pagination is cursor-based
  (`first/after`). The schema explicitly warns: **using `totalCount` raises your throttling risk.**
- **Most top-level list queries cap at ~100 recently-updated records** and take a `filter` argument
  (e.g. `clients` = "List of 100 recently updated clients satisfying a filter"). `users` caps at 10,000.
- **Mutations follow a `XxxCreate` / `XxxEdit` / `XxxArchive` naming pattern**, each returning a
  `...Payload` with the mutated object plus a **`userErrors`** list (Jobber's validation-error channel —
  a mutation can succeed at the HTTP level but return `userErrors`). Seen for Client:
  `ClientCreate`, `ClientEdit`, `ClientArchive`, `ClientCreateNote`, `ClientEditNote`, `ClientDeleteNote`,
  `ClientNoteAddAttachment`; for Property: `PropertyCreate`, `PropertyEdit`.
- **Top-level Query root** exposes single-object getters (`client`, `property`, `quote`, `job`, `visit`,
  `invoice`, `request`, `paymentRecord`, `user`, `task`, `event`, …) and list getters (`clients`,
  `properties`, `quotes`, `jobs`, `visits`, `invoices`, `requests`, `paymentRecords`, `products`,
  `taxRates`, `scheduledItems`, `timeSheetEntries`, `users`, `vehicles`, …), plus config/meta getters
  (`account`, `clientMeta`, `requestSettings`, `onlineBookingConfiguration`, `customFieldConfigurations`).
- **`similarClients`** (max 10) and **`clientMeta.counts`** exist for de-dup and client-summary UIs.

---

## 6. How WE compare (build notes)

Our CRM already mirrors most of this shape; the important deltas to keep in mind while building:

- **Lead model:** Jobber uses one `Client` row with an `isLead` flag rather than a separate "lead" table;
  a request from a new person auto-creates the lead. We use a `contacts` table with lead/customer status —
  same idea. Match the "request auto-creates a lead" behavior.
- **Property as the work anchor:** Jobber attaches tax rate, pricing memory, and geo/routing to the
  **property**, not the client. If we want route optimization and correct tax, work must be property-scoped.
- **Unified schedule stream:** Jobber's calendar is one polymorphic `scheduledItems` feed (visits +
  assessments + tasks + events + reminders). Our Schedule hub rebuild ([[schedule-hub-rebuild]]) is aiming
  at the same thing — this confirms the target model.
- **`userErrors` pattern:** Jobber returns validation errors inside a successful response. Our fixed API
  error shape (`{ error, field_errors }`) is the equivalent — keep field-level errors first-class.
- **Quote "Converted" is terminal:** worth copying — once a quote becomes a job it never reverts, even if
  the job is deleted. Prevents double-conversion.

```

```
