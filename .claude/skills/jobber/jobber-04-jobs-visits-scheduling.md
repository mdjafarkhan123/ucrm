# Jobber Reference — Jobs, Visits & Scheduling

> Source: `JobberJson.md` (schema, authoritative for fields/enums) + Jobber Help Center (behavior, cited).
> Part of the Jobber competitor reference set — see `jobber-00-overview-lifecycle.md` for the index/lifecycle,
> `jobber-03-quotes.md` for the Quote a job is usually converted from, and `jobber-05-invoices-payments.md`
> (J4) for what a completed visit bills into. Plain English; **(unverified)** marks anything not confirmed.

This is the **biggest domain** in Jobber. Three objects and one interface do all the work:

- **Job** — the _contract of work_ (schema: _"A detailed contract of work which Service Providers use to
  schedule work for a Service Consumer"_). It holds the client/property, line items, pricing, billing
  strategy, and the schedule template. It is **one-off** or **recurring**.
- **Visit** — _"each time a Service Provider goes to a client property to complete work"_ (schema). A job
  has one or many visits. A visit is the thing that lands on the calendar, gets a crew, and gets completed.
- **Event** — a non-client calendar block (holidays, team meetings) — schema: _"scheduled holidays, team
  meetings, etc."_ It shares the scheduled-item shape but isn't tied to a job.
- **ScheduledItemInterface** — the **calendar row abstraction**: Visits, Events, Assessments, basic Tasks,
  and quote/invoice reminders all implement it, which is how one calendar shows every kind of scheduled work.

Mental model to copy: **Job = the agreement + money; Visit = one calendar-slice of doing the work.** Money
lives on the job (or per visit); scheduling lives on visits. This is the exact split we adopted — see
[[schedule-hub-rebuild]] and [[jobber-flow-roadmap]].

---

## 1. Job (`Job`)

### 1.1 Fields (from schema)

| Field                               | Type                        | Meaning                                                        |
| ----------------------------------- | --------------------------- | -------------------------------------------------------------- |
| `id`                                | `EncodedId!`                | Opaque unique id.                                              |
| `jobNumber`                         | `Int!`                      | The job number.                                                |
| `title`                             | `String`                    | Job title / scheduling label.                                  |
| `instructions`                      | `String`                    | Instructions on the job (crew-facing).                         |
| `client`                            | `Client!`                   | The client on the job.                                         |
| `property`                          | `Property!`                 | The property the work is at.                                   |
| `quote`                             | `Quote`                     | The quote this job was converted from (if any).                |
| `request`                           | `Request`                   | The request this job traces back to (if any).                  |
| `salesperson`                       | `User`                      | Salesperson for the job.                                       |
| `source`                            | `Source!`                   | Where the job originated (see §1.6).                           |
| `jobType`                           | `JobTypeTypeEnum!`          | **One-off vs recurring** (see §2).                             |
| `jobStatus`                         | `JobStatusTypeEnum!`        | Current status (see §4).                                       |
| `startAt`                           | `ISO8601DateTime`           | Start date of the job.                                         |
| `endAt`                             | `ISO8601DateTime`           | End date of the job.                                           |
| `completedAt`                       | `ISO8601DateTime`           | Completion date.                                               |
| `defaultVisitTitle`                 | `String!`                   | Default title applied to new visits.                           |
| `arrivalWindow`                     | `ArrivalWindow`             | Job-level arrival window (see §1.5).                           |
| `lineItems`                         | `JobLineItemConnection!`    | The job's line items (see §1.3).                               |
| `total`                             | `Float!`                    | Total chargeable amount of the job.                            |
| `billingType`                       | `BillingStrategy!`          | Fixed-price vs visit-based (see §5).                           |
| `invoiceSchedule`                   | `InvoiceSchedule!`          | How/when the job gets invoiced (see §5).                       |
| `visitSchedule`                     | `VisitSchedule!`            | The recurring visit template (see §2.2).                       |
| `visits`                            | `VisitConnection!`          | The scheduled/unscheduled visits for this job.                 |
| `visitsInfo`                        | `VisitsInfo!`               | Counts (scheduled/unscheduled/past/future) — see §1.4.         |
| `invoices`                          | `InvoiceConnection!`        | Invoices raised for the job.                                   |
| `invoicedTotal`                     | `Float!`                    | Total already invoiced.                                        |
| `uninvoicedTotal`                   | `Float!`                    | Total not yet invoiced.                                        |
| `completedAndUninvoicedVisitsCount` | `Int!`                      | Completed visits awaiting invoicing (visit-based jobs only).   |
| `completedAndUninvoicedVisitsTotal` | `Float!`                    | $ value of those visits (0 for fixed-price jobs).              |
| `jobBalanceTotals`                  | `JobBalanceTotals`          | Total + outstanding balance from invoices/deposits (see §1.2). |
| `jobCosting`                        | `JobCosting`                | Profitability breakdown (see §6).                              |
| `expenses`                          | `ExpenseConnection!`        | Expenses booked against the job.                               |
| `timeSheetEntries`                  | `TimeSheetEntryConnection!` | All timesheet entries for the job.                             |
| `paymentRecords`                    | `PaymentRecordConnection!`  | Payments applied to this job's invoices.                       |
| `willClientBeAutomaticallyCharged`  | `Boolean`                   | Auto-charge setting for invoices.                              |
| `allowReviewRequest`                | `Boolean!`                  | Whether a Google-review SMS may be sent for this job.          |
| `nextDateToSendReviewSms`           | `ISO8601DateTime`           | Next allowed date for a review SMS.                            |
| `bookingConfirmationSentAt`         | `ISO8601DateTime`           | When booking confirmation was sent.                            |
| `notes` / `noteAttachments`         | connections                 | Internal notes + attached files.                               |
| `customFields`                      | list                        | Job-level custom field values.                                 |
| `jobberWebUri`                      | `String!`                   | Deep link in Jobber web.                                       |
| `createdAt` / `updatedAt`           | `ISO8601DateTime!`          | Timestamps.                                                    |

### 1.2 `JobBalanceTotals`

| Field               | Type    | Meaning                                               |
| ------------------- | ------- | ----------------------------------------------------- |
| `totalAmount`       | `Float` | Total balance of the job from its invoices.           |
| `outstandingAmount` | `Float` | Outstanding balance still to be paid (from invoices). |

### 1.3 Job line items (`JobLineItem`)

Jobs carry their **own** line items (not a live reference to the quote's). On quote→job conversion the items
are **snapshot-copied**, then the two evolve independently — we shipped the same model, see
[[job-line-items-snapshot-model]].

| Field                     | Type                           | Meaning                           |
| ------------------------- | ------------------------------ | --------------------------------- |
| `id`                      | `EncodedId!`                   | Unique id.                        |
| `name`                    | `String!`                      | Line item name.                   |
| `description`             | `String!`                      | Description.                      |
| `category`                | `ProductsAndServicesCategory!` | Product vs service.               |
| `quantity`                | `Float!`                       | Quantity.                         |
| `unitCost`                | `Float`                        | Internal cost per unit.           |
| `unitPrice`               | `Float!`                       | Price per unit to client.         |
| `totalCost`               | `Float`                        | Internal total cost.              |
| `totalPrice`              | `Float!`                       | Total price to client.            |
| `taxable`                 | `Boolean!`                     | Per-line taxable flag.            |
| `linkedProductOrService`  | `ProductOrService`             | The price-book item it came from. |
| `createdAt` / `updatedAt` | `ISO8601DateTime!`             | Timestamps.                       |

> Note: unlike `QuoteLineItem`, `JobLineItem` has **no** `optional` / `recommended` / `markup` / `textOnly` /
> `sortOrder` fields — upsell/optional selection is a _quote_ concern; by the time it's a job the scope is
> fixed. Cost + price (`unitCost`/`totalCost` alongside `unitPrice`/`totalPrice`) are still first-class so
> job costing works.

### 1.4 `VisitsInfo` (job-level visit counts)

| Field                    | Type              | Meaning                                             |
| ------------------------ | ----------------- | --------------------------------------------------- |
| `scheduledCount`         | `Int!`            | Incomplete visits that have a date.                 |
| `unscheduledCount`       | `Int!`            | Visits with no date yet.                            |
| `futureCount`            | `Int!`            | All incomplete scheduled + unscheduled visits.      |
| `pastCount`              | `Int!`            | Past incomplete visits up to end of today.          |
| `incompleteTotal`        | `Int!`            | Total incomplete visits.                            |
| `mostRecentVisitStartAt` | `ISO8601DateTime` | Start of the most recent visit (up to a threshold). |

### 1.5 `ArrivalWindow` (shared with Visit)

An arrival window communicates _"we'll arrive within a window"_ rather than an exact start. **The style +
duration are set once in Work Settings and apply to all jobs.** [Arrival Windows]

| Field                 | Type               | Meaning                                                 |
| --------------------- | ------------------ | ------------------------------------------------------- |
| `id`                  | `EncodedId!`       | Unique id.                                              |
| `startAt`             | `ISO8601DateTime!` | Window start.                                           |
| `endAt`               | `ISO8601DateTime!` | Window end.                                             |
| `duration`            | `Minutes!`         | Window length in minutes.                               |
| `centeredOnStartTime` | `Boolean!`         | Whether the window is centered on the visit start time. |

### 1.6 `Source` (job origin — enum)

Internal origin tag: `CLIENT`, `HOME`, `INTERNAL`, `IMPORT`, `FLAT_FILE_JOB_IMPORT`,
`GOOGLE_CALENDAR_JOB_IMPORT`, `GQL_API`, `JOB`, `JOB_NEW`, `JOBS_INDEX`, `ONBOARDING`, `ONLINE_BOOKING`,
`PROPERTY` (list continues). Useful mostly for attribution/reporting; not client-facing.

---

## 2. Job type — one-off vs recurring (`JobTypeTypeEnum`)

| Enum value  | Schema description                |
| ----------- | --------------------------------- |
| `ONE_OFF`   | "A one-off job"                   |
| `RECURRING` | "A job with a recurring schedule" |

**One-off** = one visit, or a few visits, until the work is done (spring cleanup, move-out clean, HVAC
repair); usually billed once at the end. **Recurring** = multiple visits on a repeating schedule (weekly
cleaning, snow removal, monthly mowing); billed multiple times (per visit / weekly / monthly). [Job Basics],
[Create a One-Off Job], [Create a Recurring Job]

> **Type is immutable.** _"Once a job is created, the job type cannot be switched… It would need to be
> recreated instead."_ [Job Basics] — a hard rule worth copying: don't let a one-off flip to recurring.

### 2.2 Recurrence model (`VisitSchedule` + `RecurrenceSchedule`)

The **`VisitSchedule`** on a job is the template Jobber uses to generate visits:

| Field                   | Type                 | Meaning                                                                                      |
| ----------------------- | -------------------- | -------------------------------------------------------------------------------------------- |
| `startDate` / `endDate` | `ISO8601DateTime`    | Schedule window.                                                                             |
| `startTime` / `endTime` | `ISO8601DateTime`    | Daily start/end time.                                                                        |
| `recurrenceSchedule`    | `RecurrenceSchedule` | The repeat rule (below).                                                                     |
| `assignedTo`            | `UserConnection!`    | Users assigned **at job creation** — _"may differ from users assigned to the job's visits."_ |

**`RecurrenceSchedule`** is just two fields — a machine rule + a human string:

| Field          | Type             | Meaning                                                      |
| -------------- | ---------------- | ------------------------------------------------------------ |
| `calendarRule` | `ICalendarRule!` | **iCalendar RRULE** string (the standard recurrence format). |
| `friendly`     | `String!`        | Human-readable summary, e.g. _"Weekly on Sundays."_          |

**Repeat options (help center):** visits can repeat **weekly, biweekly, monthly, or on a custom schedule.**
The **custom** schedule allows weekly / monthly / annually and **multiple days** — e.g. _"weekly on Mondays
and Wednesdays"_ or _"the 1st and 3rd Fridays of the month."_ [Create a Recurring Job]

**End conditions:** a recurring job can **end after a set duration** (e.g. 6 months) or **on an exact date.**
[Create a Recurring Job]

**"As needed" (no schedule yet):** the _"As Needed — We Won't Prompt You"_ option creates the job with **no
visits**; you add visits later. [Create a Recurring Job] (Mirrors the one-off _"Schedule later"_ path.)

> **Build note:** store the recurrence as an **RRULE** string (iCalendar) + a friendly summary, exactly like
> Jobber — don't invent a bespoke recurrence format. Generate concrete visit rows from the rule. Our
> recurring-jobs work is tracked in [[recurring-jobs-deferred]] / [[job-scheduling-recurring-billing-roadmap]].

---

## 3. Visit (`Visit`)

_"A visit… represents each time a Service Provider goes to a client property to complete work."_

### 3.1 Fields (from schema)

| Field                     | Type                         | Meaning                                                            |
| ------------------------- | ---------------------------- | ------------------------------------------------------------------ |
| `id`                      | `EncodedId!`                 | Unique id.                                                         |
| `title`                   | `String`                     | Visit title.                                                       |
| `isDefaultTitle`          | `Boolean!`                   | Whether the title is still the default.                            |
| `instructions`            | `String`                     | Instructions for this visit.                                       |
| `job`                     | `Job!`                       | The parent job.                                                    |
| `client`                  | `Client!`                    | The client.                                                        |
| `property`                | `Property!`                  | The property.                                                      |
| `startAt`                 | `ISO8601DateTime`            | Start. **Both `startAt` and `endAt` null = an unscheduled visit.** |
| `endAt`                   | `ISO8601DateTime`            | End (see above).                                                   |
| `duration`                | `Int`                        | Minute duration between start and end.                             |
| `allDay`                  | `Boolean!`                   | Whether it's a full-day item.                                      |
| `arrivalWindow`           | `ArrivalWindow`              | Arrival window for the visit.                                      |
| `assignedUsers`           | `UserConnection`             | Crew assigned to **this** visit.                                   |
| `visitStatus`             | `VisitStatusTypeEnum!`       | Status (see §3.2).                                                 |
| `isComplete`              | `Boolean!`                   | Whether it's been completed.                                       |
| `completedAt`             | `ISO8601DateTime`            | When it was completed.                                             |
| `completedBy`             | `String`                     | User/system that completed it.                                     |
| `actionsUponComplete`     | `[VisitActionUponComplete]!` | What can happen after completing (see §3.3).                       |
| `clientConfirmed`         | `Boolean!`                   | Whether the client confirmed the visit.                            |
| `isLastScheduledVisit`    | `Boolean!`                   | Whether it's the last visit on the job.                            |
| `lineItems`               | `JobLineItemConnection!`     | Line items for the visit (visit-based billing).                    |
| `invoice`                 | `Invoice`                    | The invoice for this visit (if raised).                            |
| `timeSheetEntries`        | `TimeSheetEntryConnection`   | Timesheets logged against the visit.                               |
| `incompleteJobFormsCount` | `Int!`                       | Incomplete job-form submissions on the visit.                      |
| `notes`                   | `JobNoteUnionConnection`     | Notes (attached at the job).                                       |
| `teamReminderOffset`      | `Minutes`                    | Minutes before start to notify the team.                           |
| `overrideOrder`           | `Int`                        | Manual ordering for anytime/unscheduled items.                     |
| `routingOrder`            | `Int`                        | Order the item should be routed in (map/route).                    |
| `createdBy`               | `User`                       | Who created the visit.                                             |
| `createdAt`               | `ISO8601DateTime!`           | Created timestamp.                                                 |

### 3.2 Visit statuses (`VisitStatusTypeEnum`)

| Enum value    | Schema description                                    | Plain English            |
| ------------- | ----------------------------------------------------- | ------------------------ |
| `ACTIVE`      | "A visit is still active"                             | Open/live.               |
| `UPCOMING`    | "An incomplete visit that is upcoming"                | Scheduled in the future. |
| `TODAY`       | "…scheduled today, which end time has not yet passed" | Due today.               |
| `LATE`        | "An incomplete visit which end time has passed"       | Overdue, not completed.  |
| `UNSCHEDULED` | "A visit that is unscheduled"                         | No date/time yet.        |
| `COMPLETED`   | "A visit that has been completed"                     | Done.                    |

### 3.3 What can happen after a visit completes (`VisitActionUponComplete`)

When you mark a visit complete you get a prompt: **Invoice now / Invoice later**; if it's the last visit,
also **close the job** or **leave it open**. [Job Basics / Job Costing search]

| Enum value                | Meaning                              |
| ------------------------- | ------------------------------------ |
| `INVOICE_NOW`             | Invoice this visit immediately.      |
| `INVOICE_LATER`           | Invoice it later.                    |
| `CLOSE_JOB`               | Last visit — close the job.          |
| `LEAVE_JOB_OPEN`          | Last visit — keep the job open.      |
| `CLOSE_JOB_INVOICE_NOW`   | Close the job **and** invoice now.   |
| `CLOSE_JOB_INVOICE_LATER` | Close the job **and** invoice later. |

> **Creating an invoice does not close the job** — the two are separate actions; to close you use the
> close-job path. [Job Costing / Invoices search]

### 3.4 Three kinds of visit (help center)

Jobber distinguishes three, and the schema encodes it via null start/end + `overrideOrder`/`routingOrder`:

1. **Scheduled visit** — has a date **and** time. Lands on the timed calendar grid.
2. **Anytime visit** — has a **date but no time** (leave start/end time blank). For route-based work where
   you don't commit to a clock time; ordered by route, not time. [Visits]
3. **Unscheduled visit** — **no date and no time** (`startAt`/`endAt` both null). A placeholder you assign a
   date to later. On a one-off with no start date, check _"Schedule later"_ + _"Add an unscheduled visit to
   the calendar."_ [Visits]

We built the same lane model (timed grid + an **Anytime lane** + unscheduled) — see [[schedule-hub-rebuild]].

---

## 4. Job statuses (`JobStatusTypeEnum`)

These are **derived from the visits/invoicing state**, not set by hand. [Jobs List Page and Key Metrics]

| Enum value                | Schema / help-center meaning                                                            |
| ------------------------- | --------------------------------------------------------------------------------------- |
| `active`                  | In progress (not closed). Umbrella that includes late/today/upcoming/etc.               |
| `upcoming`                | Active job with a visit in the future (after today).                                    |
| `today`                   | Active job with a visit today.                                                          |
| `late`                    | Active job with a visit whose date passed but wasn't marked complete.                   |
| `unscheduled`             | Job has visits created but set to be scheduled later.                                   |
| `action_required`         | Active but **no more upcoming visits** — prompt to schedule more or close. ("On hold.") |
| `on_hold`                 | **Alias for `action_required`** (schema says so explicitly).                            |
| `requires_invoicing`      | Has an overdue/due invoice reminder — prompt to create an invoice.                      |
| `expiring_within_30_days` | Active job expiring within 30 days.                                                     |
| `archived`                | Closed job that no longer needs invoicing — "done with."                                |

> **Requires-invoicing is a workflow lever:** when an invoice reminder becomes due, the job flips to
> `requires_invoicing`, which makes it easy to **batch-invoice** many jobs at once. [Jobs List Page],
> [Invoice Reminders] — a strong pattern to copy for our billing queue.

**Sort keys (`JobSortKey`):** `CLIENT_FIRST_NAME`, `CLIENT_PRIMARY_NAME`, `JOB_NUMBER`, `JOB_STATUS`,
`TOTAL_COST`, `UPDATED_AT`, `SCHEDULE` (next visit date), `VISIT_START_DATE` (most recent visit start).

---

## 5. Billing model (how a job turns into money)

Two schema enums drive this: **`BillingStrategy`** (what an invoice contains) and **`BillingFrequencyEnum`**
(when invoicing is prompted), plus `InvoiceSchedule`.

### 5.1 `BillingStrategy` (the `job.billingType`)

| Enum value    | Schema description                                           | Plain English                                                                                                                                                            |
| ------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `FIXED_PRICE` | "Each invoice is for a set amount"                           | Same amount each invoice; the **job's** line items are pulled onto the invoice (not the visit's). Good for flat-rate clients regardless of visit count. [Invoice search] |
| `VISIT_BASED` | "Invoices include all the billable work on completed visits" | Invoice bills whatever billable work sits on the **completed visits.**                                                                                                   |

### 5.2 `InvoiceSchedule`

| Field                | Type                    | Meaning                                     |
| -------------------- | ----------------------- | ------------------------------------------- |
| `billingFrequency`   | `BillingFrequencyEnum!` | When to invoice (below).                    |
| `recurrenceSchedule` | `RecurrenceSchedule`    | Recurrence for periodic billing.            |
| `scheduleSummary`    | `String!`               | Friendly string of the invoicing frequency. |

### 5.3 `BillingFrequencyEnum`

| Enum value      | Schema description                                               |
| --------------- | ---------------------------------------------------------------- |
| `ON_COMPLETION` | Invoice the client when the job is complete.                     |
| `PER_VISIT`     | Invoice the client on each visit.                                |
| `PERIODIC`      | Invoice periodically based on rules (uses `recurrenceSchedule`). |
| `NEVER`         | Never invoice automatically.                                     |

### 5.4 Invoice reminders (help center)

Invoicing in Jobber is prompt-driven via **invoice reminders** (set on the job's billing section → Reminders
tab → Add reminder): **after each visit**, **once when job completed**, **monthly on the last day**, or a
**custom schedule.** When a reminder becomes due the job moves to `requires_invoicing`. [Invoice Reminders]
Split/milestone billing on big jobs = **Progress Invoicing** (see `jobber-05` / [[quote-phase2-gaps]]).

> We shipped one-off split billing + manual recurring billing — see
> [[job-scheduling-recurring-billing-roadmap]]; full auto-invoice/auto-charge deferred
> ([[recurring-billing-autocharge-deferred]]).

---

## 6. Job costing (`JobCosting`) — profitability

_"The profitability data associated to a Job."_ Shown as **profit %** on completed jobs, **costs-so-far** on
in-progress jobs. [Job Costing]

| Field                   | Type       | Meaning                                                           |
| ----------------------- | ---------- | ----------------------------------------------------------------- |
| `totalRevenue`          | `Float!`   | Total revenue for the job.                                        |
| `totalCost`             | `Float!`   | Total cost.                                                       |
| `lineItemCost`          | `Float!`   | Cost from line items.                                             |
| `labourCost`            | `Float!`   | Labour cost (from timesheets × labour rate).                      |
| `labourDuration`        | `Seconds!` | Total labour time in seconds.                                     |
| `expenseCost`           | `Float!`   | Total expenses booked to the job.                                 |
| `profitAmount`          | `Float!`   | Revenue − cost.                                                   |
| `profitPercentage`      | `Float`    | Profit margin %.                                                  |
| `belowMinimumThreshold` | `Boolean`  | Whether profit % is below the account's minimum profit threshold. |

**Inputs:** labour comes from **timesheets** (employee time × their current labour rate), materials from
**line-item cost**, and **expenses** attached to the job. [Job Costing], [Expenses] Jobber also has
**Automated Job Costing** that pulls costs in automatically. [Automated Job Costing]

> The **minimum-profit-threshold flag** (`belowMinimumThreshold`) is the same idea as our target-margin
> tone on quotes ([[quote-phase2-gaps]]) — extend it to jobs so a job going unprofitable is flagged.

---

## 7. The scheduling / calendar model

### 7.1 `ScheduledItemInterface` — one calendar, many item types

Every schedulable thing implements a shared interface so a single calendar can render them all. **Common
fields:** `id`, `title`/`isDefaultTitle`, `startAt`/`endAt` (both null = unscheduled), `allDay`, `duration`,
`assignedUsers`, `createdBy`, `teamReminderOffset`, `overrideOrder`, `routingOrder`.

**`ScheduledItemType`** — what can appear on the calendar:

| Enum value         | Meaning                                  |
| ------------------ | ---------------------------------------- |
| `VISIT`            | A job visit.                             |
| `EVENT`            | A non-client event (holiday, meeting).   |
| `ASSESSMENT`       | An on-site assessment (see `jobber-02`). |
| `BASIC_TASK`       | A basic task.                            |
| `QUOTE_REMINDER`   | A reminder to follow up on a quote.      |
| `INVOICE_REMINDER` | A reminder to invoice.                   |

**`ScheduledItemStatus`:** `ACTIVE`, `COMPLETED`, `INCOMPLETE`, `OVERDUE`, `REMAINING`.
**Filter/sort:** `ScheduledItemsFilterAttributes`, `ScheduledItemsSortInput` / `ScheduledItemsSortKey`.

> **Design lesson:** Jobber does **not** overload "visit" to mean everything on the calendar. It has real
> `Event`, `Assessment`, `BasicTask`, and reminder item types, unified only by an **interface**. This is
> exactly the scope call in [[schedule-hub-rebuild]] (Job+Event only for now; our `appointments` table is
> really the Visit layer) and why we verify the entity before building [[feedback-verify-entity-model-before-building]].

### 7.2 `Event` (non-client calendar block)

| Field                            | Type                  | Meaning                              |
| -------------------------------- | --------------------- | ------------------------------------ |
| `id`                             | `EncodedId!`          | Unique id.                           |
| `title` / `isDefaultTitle`       | `String` / `Boolean!` | Title + default flag.                |
| `description`                    | `String`              | Event instructions.                  |
| `startAt` / `endAt`              | `ISO8601DateTime`     | Times (both null = unscheduled).     |
| `allDay`                         | `Boolean!`            | Full-day flag.                       |
| `duration`                       | `Int`                 | Minutes.                             |
| `assignedUsers`                  | `UserConnection`      | Assigned team.                       |
| `client`                         | `Client`              | Optional client link.                |
| `property`                       | `Property`            | Optional property link.              |
| `isComplete`                     | `Boolean!`            | Completed flag.                      |
| `isRecurring`                    | `Boolean!`            | Part of a recurring chain.           |
| `recurrenceSchedule`             | `RecurrenceSchedule`  | Repeat rule (same RRULE + friendly). |
| `recurringSummary`               | `String`              | Recurring summary string.            |
| `teamReminderOffset`             | `Minutes`             | Team reminder offset.                |
| `overrideOrder` / `routingOrder` | `Int`                 | Ordering/routing.                    |
| `createdBy`                      | `User`                | Creator.                             |

Note: an Event can **optionally** attach a client/property but doesn't require one — matching our finding
that a contact-less calendar item is a _separate object type_, not a job/visit ([[appointments-ux-overhaul-plan]]).

### 7.3 Calendar views, drag, map, routing (help center)

- **Views:** Month (high-level planning / coverage), Week (coordinate multiple jobs), Day (jump to a day).
  [New Schedule], [Month View], [Week View]
- **Drag to reschedule:** click-drag an appointment to move its day/date; **drag the edge to extend/shorten
  duration.** [New Schedule] — we implemented all of these gestures ([[schedule-hub-rebuild]] Phase 1).
- **Map view:** add a map to week/day view to see each team member's route, with directional lines showing
  the order of stops. [Map View]
- **Route optimization:** auto-reorders **anytime visits** into the most efficient order to cut backtracking
  / travel time (you don't hand-order them). [Route Optimization] Ordering is stored via
  `routingOrder`/`overrideOrder`.

---

## 8. Visit lifecycle & recurring-edit rules (help center)

### 8.1 Assigning crew

Assigning team members on a visit **updates only that visit, not the whole job** — _"the assigned team
members will update only that specific visit."_ [Visits] To push a crew change to the whole series you use
the **"Save and update future visits"** path. [Visits]

### 8.2 Editing one visit vs the whole schedule (recurring jobs)

- **Edit one visit** (from the schedule or the job's Visits section → Edit): affects **only that visit**; the
  rest of the series is untouched. Notifications also apply only to that visit. [Visits]
- **Edit the job's schedule** (start/end times, recurrence, or crew): **all _incomplete_ visits regenerate**
  to follow the new schedule/crew; **completed visits are never changed.** [Visits]

> This "this visit only vs this-and-future" split is the recurrence-edit rule to copy exactly — and it's why
> a blanket schedule PATCH must be recurrence-aware (a deferred follow-up noted in
> [[job-scheduling-recurring-billing-roadmap]]).

### 8.3 Completing & closing

Mark a visit complete → prompt to **Invoice now / later**; last visit adds **Close job / Leave open** (see
§3.3). Creating an invoice does **not** close the job; closing is its own action (→ `archived`). A job with
no more upcoming visits sits in `action_required` until you schedule more or close it.

---

## 9. Mutations & queries (from schema)

Jobber exposes a full job/visit mutation set (all return the object + `userErrors`). Introspection did **not**
expand `INPUT_OBJECT` fields, so exact input arguments aren't enumerable from `JobberJson.md`.

**Job mutations:** `jobCreate` · `jobEdit` · `jobClose` · `jobReopen` · `jobCreateLineItems` ·
`jobEditLineItems` · `jobDeleteLineItems` · `jobOrderLineItems` · `jobCreateNote` · `jobEditNote` ·
`jobDeleteNote` · `jobNoteAddAttachment`.

**Visit mutations:** `visitCreate` · `visitEdit` · `visitDelete` · `visitComplete` · `visitUncomplete` ·
`visitCreateLineItems` · `visitEditLineItems` · `visitDeleteLineItems` · `visitEditAssignedUsers` ·
`visitEditSchedule`.

> `visitEditSchedule` and `visitEditAssignedUsers` being **separate** mutations from `visitEdit` mirrors the
> §8.2 rule — schedule/crew changes are a distinct operation (they can cascade to future visits).

**Read queries:** `job(id)` / `jobs(filter, sort)` (`JobFilterAttributes`, `JobSortInput`/`JobSortKey`);
visit lists via `Job.visits` and the account-level scheduled-items query (`ScheduledItemsFilterAttributes`,
sort by `ScheduledItemsSortKey`). Visit sort: `VisitsSortableFields` = `CREATED_AT`, `START_AT`,
`CLIENT_PRIMARY_NAME`, `STATUS`.

---

## 10. How WE compare / what to match or beat

- **Job = contract + money, Visit = calendar slice.** This is the core split and we already adopted it
  ([[schedule-hub-rebuild]], [[jobber-flow-roadmap]]). Keep money on the job (or per-visit for visit-based)
  and scheduling on visits — don't let the two blur.
- **Three visit kinds are non-negotiable:** scheduled (date+time), **anytime** (date only, route-ordered),
  and **unscheduled** (placeholder). Our lane model matches; make sure route-ordering (`routingOrder`) and an
  anytime lane both exist, since route-based trades (lawn, cleaning, snow) live there.
- **Recurrence = RRULE + friendly string.** Store iCalendar RRULE, generate concrete visit rows, keep a human
  summary. Support weekly/biweekly/monthly **and a real custom** (multiple weekdays, "1st & 3rd Friday"),
  plus end-after-N or end-on-date, plus an "as needed / schedule later" no-visit mode.
- **Recurring-edit semantics to copy exactly:** edit one visit = that visit only; edit the job schedule/crew
  = **regenerate all incomplete visits, never touch completed ones.** This is the #1 place naive
  implementations break — make our schedule PATCH recurrence-aware.
- **Job type is immutable** (one-off ⇄ recurring requires recreate). Enforce it.
- **Billing model:** support both `FIXED_PRICE` (bills the job's line items, flat) and `VISIT_BASED` (bills
  completed visits), with frequency = on-completion / per-visit / periodic / never, driven by **invoice
  reminders** that flip the job to a "requires invoicing" state for **batch invoicing.** The requires-invoicing
  queue is a genuinely great UX lever — build it.
- **Job costing with a minimum-profit flag.** We have target-margin on quotes; extend the same green/amber/red
  - `belowMinimumThreshold` idea to jobs, fed by timesheets (labour), line-item cost, and expenses.
- **Arrival windows are an org-level setting** applied to all jobs (style + duration), surfaced per visit —
  cheap trust feature; adopt as configured-once.
- **One unified calendar via an interface, not an overloaded "visit."** Real Event/Assessment/Task/reminder
  item types sharing a `ScheduledItemInterface`. Where to **beat** Jobber: route optimization + map view are
  strong but paid/edition-gated — a clean, fast, free-feeling schedule with drag-resize, an anytime lane, and
  good mobile is the bar; polish there is our differentiation.

---

### Help-center sources

- Job Basics — https://help.getjobber.com/hc/en-us/articles/115009379027-Job-Basics
- Create a One-Off Job — https://help.getjobber.com/hc/en-us/articles/115009379047-Create-a-One-Off-Job
- Create a Recurring Job — https://help.getjobber.com/hc/en-us/articles/115009542848-Create-a-Recurring-Job
- Edit a Job — https://help.getjobber.com/hc/en-us/articles/115009379087-Edit-a-Job
- Visits — https://help.getjobber.com/hc/en-us/articles/7924045219479-Visits
- Jobs in the Jobber App — https://help.getjobber.com/hc/en-us/articles/8185260991127-Jobs-in-the-Jobber-App
- Schedule in the Jobber App — https://help.getjobber.com/hc/en-us/articles/6766253760279-Schedule-in-the-Jobber-App
- Arrival Windows — https://help.getjobber.com/hc/en-us/articles/13004689565463-Arrival-Windows
- New Schedule — https://help.getjobber.com/hc/en-us/articles/29840886387351-New-Schedule
- Schedule Overview | New Schedule — https://help.getjobber.com/hc/en-us/articles/36628696269975-Schedule-Overview-New-Schedule
- Month View of the Schedule | New Schedule — https://help.getjobber.com/hc/en-us/articles/33637299795607-Month-View-of-the-Schedule-New-Schedule
- Week View of the Schedule | New Schedule — https://help.getjobber.com/hc/en-us/articles/33641405662359-Week-View-of-the-Schedule-New-Schedule
- Route Optimization | New Schedule — https://help.getjobber.com/hc/en-us/articles/34303089729559-Route-Optimization-New-Schedule
- Map View | Legacy Schedule — https://help.getjobber.com/hc/en-us/articles/115009234307-Map-View-Legacy-Schedule
- Create New Visits for Existing Recurring Jobs (Snow Removal Workflow) — https://help.getjobber.com/hc/en-us/articles/36429203202071-Create-New-Visits-for-Existing-Recurring-Jobs-Snow-Removal-Workflow-New-Schedule
- Invoice Reminders — https://help.getjobber.com/hc/en-us/articles/115009517847-Invoice-Reminders
- Job Costing — https://help.getjobber.com/hc/en-us/articles/14343244961175-Job-Costing
- Automated Job Costing — https://help.getjobber.com/hc/en-us/articles/41272823874967-Automated-Job-Costing
- Expenses — https://help.getjobber.com/hc/en-us/articles/115009615927-Expenses
- Jobs List Page and Key Metrics — https://help.getjobber.com/hc/en-us/articles/39133110680343-Jobs-List-Page-and-Key-Metrics
