# Jobber Reference — Requests, Assessments & Lead Intake

> Source: `JobberJson.md` (schema, authoritative for fields/enums) + Jobber Help Center (behavior, cited).
> Part of the Jobber competitor reference set — see `jobber-00-overview-lifecycle.md` for the index and
> the full lead→cash lifecycle, and `jobber-01-clients-properties.md` for the Client/Property model.
> Plain English throughout; **(unverified)** marks anything not confirmed by schema or help center.

A **Request** is the very first object in Jobber's flow — _"a request which a client will create when
they wish to enlist the help of a Service Provider for work"_ (schema). It's how a lead enters the
system: an online booking/request form, a Client Hub "request work" submission, or manual entry by staff.
An **Assessment** is an optional on-site visit to scope/price the work before quoting. This file covers
both, plus the request/booking form settings that drive online lead intake.

---

## 1. Request (`Request`)

> Schema description: _"A request which a client will create when they wish to enlist the help of a
> Service Provider for work."_

### 1.1 Fields (from schema)

| Field                       | Type                        | Meaning                                                                                       |
| --------------------------- | --------------------------- | --------------------------------------------------------------------------------------------- |
| `id`                        | `EncodedId!`                | Opaque unique id.                                                                             |
| `title`                     | `String`                    | Title of the work request.                                                                    |
| `client`                    | `Client!`                   | The client the request belongs to (auto-created as a lead for a new person).                  |
| `property`                  | `Property`                  | The service location for the request.                                                         |
| `contactName`               | `String`                    | Primary contact name provided in the request.                                                 |
| `companyName`               | `String`                    | Company name provided in the request.                                                         |
| `email`                     | `String`                    | Contact email provided in the request.                                                        |
| `phone`                     | `String`                    | Contact phone provided in the request.                                                        |
| `source`                    | `String!`                   | Where the request came from (e.g. the form/channel).                                          |
| `referringClient`           | `Client`                    | The client who referred this request (if it was a referral).                                  |
| `salesperson`               | `User`                      | Salesperson assigned to the request.                                                          |
| `requestStatus`             | `RequestStatusTypeEnum!`    | Current status (see §1.2).                                                                    |
| `isScheduled`               | `Boolean!`                  | Whether the request has a scheduled assessment.                                               |
| `isArchivable`              | `Boolean!`                  | Whether it can be archived.                                                                   |
| `arrivalWindow`             | `ArrivalWindow`             | Arrival time window for the associated assessment.                                            |
| `assessment`                | `Assessment`                | The on-site assessment associated with the request (0 or 1).                                  |
| `lineItems`                 | `RequestLineItemConnection` | Line items captured on the request.                                                           |
| `amounts`                   | `RequestAmounts!`           | Money on the request — `total` (`Float!`), summed from line items.                            |
| `quotes`                    | `QuoteConnection!`          | Quotes created from this request.                                                             |
| `jobs`                      | `JobConnection!`            | Jobs created from this request.                                                               |
| `tasks`                     | `TaskConnection!`           | Basic tasks attached to the request.                                                          |
| `notes` / `noteAttachments` | connections                 | Internal notes + attached files (`RequestNoteUnionConnection` / `RequestNoteFileConnection`). |
| `linkedCommunications`      | —                           | _(on `Assessment`; requests surface messages via the client timeline)_                        |
| `createdAt` / `updatedAt`   | `ISO8601DateTime!`          | Timestamps.                                                                                   |
| `jobberWebUri`              | `String!`                   | Deep link to the record in Jobber web.                                                        |

**`ArrivalWindow`** (shared with assessments/visits) — `startAt` / `endAt` (`ISO8601DateTime!`),
`duration` (`Minutes!`), `centeredOnStartTime: Boolean!` (whether the window is centered on the job's
start time). Purpose: tell the client "we'll arrive between 1–3pm" rather than an exact time.

**`RequestLineItem`** — `name` (`String!`), `description` (`String!`), `quantity` (`Float!`),
`category` (`ProductsAndServicesCategory` enum), `taxable: Boolean!`, `unitCost`/`unitPrice`,
`totalCost`/`totalPrice` (`Float`), `sortOrder` (`Int`), `linkedProductOrService` (`ProductOrService`
from the price book), `createdAt`/`id`. Note: request line items **have no `optional`/`markup`/`recommended`
flags** — those appear only on quote line items (see `jobber-03`). Requests capture _what the client asked
for_, not a priced/optioned estimate.

### 1.2 Request statuses (`RequestStatusTypeEnum`) — schema + help center

The **schema enum** exposes these values (verbatim):
`new`, `completed`, `converted`, `archived`, `upcoming`, `overdue`, `unscheduled`,
`assessment_completed`, `today`.

The **help center** describes the user-facing status labels and their meaning (label wording differs
slightly from the raw enum — the enum has extra calendar-derived values like `today`/`overdue`/`upcoming`
used for the assessment's schedule state):

| Status (help-center label)                 | Nearest enum                         | Meaning                                                                                                                                       |
| ------------------------------------------ | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pending / New**                          | `new`                                | A new request was created online or via Client Hub, not yet actioned.                                                                         |
| **Unscheduled**                            | `unscheduled`                        | An assessment has been turned on for the request but not yet placed on the calendar.                                                          |
| **Upcoming / Today / Overdue**             | `upcoming` / `today` / `overdue`     | Calendar state of the scheduled assessment relative to now.                                                                                   |
| **Assessment completed / Action Required** | `assessment_completed` / `completed` | The assessment was marked complete but the request hasn't been converted or archived yet — a prompt that _something needs to happen_ with it. |
| **Converted**                              | `converted`                          | Request was converted into a quote or job. **Final status** — like Quote "Converted."                                                         |
| **Archived**                               | `archived`                           | Request archived/closed.                                                                                                                      |

> Sources: [Request Basics], [Converting a Request to a Quote or Job], [Using Assessments to Schedule and
> > Convert Work Requests], [List Pages and Key Metrics].

### 1.3 Behavior (help center)

- **A request captures & organizes new work the moment a client reaches out.** When a client submits a
  form or contacts the business, Jobber creates a Request holding the work details so staff can review and
  decide what to do next. [Request Basics]
- **New person → auto-created as a lead.** A request from a brand-new person auto-creates the `Client` with
  `isLead: true` (see `jobber-01` §1.5). [[client basics]]
- **Convert to Quote or Job:** _More Actions → Convert to Quote_ (or Job). On conversion the original
  request details appear in a **right-side drawer** for reference while you build the quote/job line items.
  Converting is the terminal step — status becomes **Converted**. [Converting a Request to a Quote or Job]
- **Requests in the mobile app** exist as a first-class list too. [Requests in the Jobber App]

---

## 2. Assessment (`Assessment`)

> Schema description: _"An assessment represents each time a Service Provider goes to a client property to
> assess and plan for future work."_ It's a **schedulable item** (implements the same scheduling interface
> as visits/tasks/events) tied to a parent request — i.e. the on-site estimate/site-visit.

### 2.1 Fields (from schema)

| Field                       | Type                          | Meaning                                                        |
| --------------------------- | ----------------------------- | -------------------------------------------------------------- |
| `id`                        | `EncodedId!`                  | Unique id.                                                     |
| `title`                     | `String`                      | Title of the scheduled item.                                   |
| `isDefaultTitle`            | `Boolean!`                    | Whether the title is Jobber's default.                         |
| `instructions`              | `String`                      | Instructions for the assessment.                               |
| `request`                   | `Request!`                    | Parent request this assessment belongs to.                     |
| `client`                    | `Client!`                     | The client.                                                    |
| `property`                  | `Property`                    | The property to visit.                                         |
| `assignedUsers`             | `UserConnection`              | Team members assigned to do the assessment.                    |
| `createdBy`                 | `User`                        | User who created the scheduled item.                           |
| `startAt` / `endAt`         | `ISO8601DateTime`             | Start/end. **Both null = an unscheduled assessment.**          |
| `allDay`                    | `Boolean!`                    | Whether it's a full-day item.                                  |
| `duration`                  | `Int`                         | Minutes between start and end.                                 |
| `routingOrder`              | `Int`                         | Order for route optimization.                                  |
| `overrideOrder`             | `Int`                         | Manual ordering override for anytime/unscheduled items.        |
| `clientConfirmed`           | `Boolean!`                    | Whether the client has confirmed this assessment.              |
| `isComplete`                | `Boolean!`                    | Whether the assessment is complete.                            |
| `completedAt`               | `ISO8601DateTime`             | When it was completed.                                         |
| `teamReminderOffset`        | `Minutes`                     | Offset before start to notify the team.                        |
| `incompleteChecklistsCount` | `Int!`                        | Number of incomplete checklist submissions on this assessment. |
| `timeSheetEntries`          | `TimeSheetEntryConnection`    | Time tracked against the assessment.                           |
| `linkedCommunications`      | `MessageInterfaceConnection!` | All messages related to this work object.                      |

> **Schedule-state model (shared with Visits):** `startAt`+`endAt` set with a time = **Scheduled**; a date
> but no specific time = **Anytime**; both null = **Unscheduled**. Same three-state model documented for
> visits in `jobber-00` §4. The `Assessment` here uses `overrideOrder` + `routingOrder` exactly like other
> scheduled items, confirming Jobber's single polymorphic calendar stream.

### 2.2 Behavior (help center)

- **What it's for:** an assessment blocks time on the calendar for a team member to visit the property and
  scope the job before quoting/starting work. Triggered from the request via the _truck icon_ /
  "Visit the property to assess the job before you do the work." [Scheduling an Assessment]
- **Assign team:** the _Assign_ button chooses which team members complete the assessment. [Scheduling an Assessment]
- **Arrival windows:** communicate "we'll arrive within this window" instead of an exact time; you enter
  the client's available dates + preferred arrival times. [Scheduling an Assessment]
- **Reminders:** assessment & visit reminders notify the client before you arrive — email, text, or both;
  automatic on a schedule or sent manually. Gated per-client by `receivesReminders` (see `jobber-01` §1.2).
  [Assessment and Visit Reminders]
- **Booking confirmation:** _Text Booking Confirmation_ or _More Actions → Email Booking Confirmation_.
  [Scheduling an Assessment]
- **Complete & convert:** mark the assessment complete from the calendar or the request; you're then
  prompted to **convert the request to a quote or job, leave it as "Action Required," or Archive it.**
  [Using Assessments to Schedule and Convert Work Requests]

### 2.3 Mutations (from schema)

| Action              | Mutation                                     | Returns                                                        |
| ------------------- | -------------------------------------------- | -------------------------------------------------------------- |
| Create assessment   | `AssessmentCreate` (`AssessmentCreateInput`) | `assessment`, `request`, `userErrors`                          |
| Edit assessment     | `AssessmentEdit` (`AssessmentEditInput`)     | `assessment`, `userErrors` _(unverified exact payload fields)_ |
| Complete assessment | `AssessmentComplete`                         | `assessment`, `userErrors`                                     |

_(Introspection did not expand `INPUT_OBJECT` field lists, so create/edit input arguments aren't enumerable
from `JobberJson.md` — marked accordingly.)_

---

## 3. Request & Booking Forms — online lead intake (`RequestSettings`, `OnlineBookingConfiguration`)

Jobber's lead intake is driven by configurable public forms. Each account can have multiple forms
(`RequestSettings` is a paginated connection), one marked `default`.

### 3.1 `RequestSettings` fields (from schema)

| Field                                                              | Type                       | Meaning                                                                                                     |
| ------------------------------------------------------------------ | -------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `id`                                                               | `EncodedId!`               | Unique id.                                                                                                  |
| `name`                                                             | `String`                   | Form name.                                                                                                  |
| `description`                                                      | `String`                   | Form description shown to clients.                                                                          |
| `enabled`                                                          | `Boolean!`                 | If disabled, the form is **not visible to clients**.                                                        |
| `default`                                                          | `Boolean!`                 | Whether this is the account's default form.                                                                 |
| `bookingType`                                                      | `BookingType!`             | What the form creates on submit: `NONE` (request only), `ASSESSMENT` (request + assessment), `JOB` (a job). |
| `requiresBookingApproval`                                          | `Boolean!`                 | Whether submissions need manual approval before hitting the schedule.                                       |
| `serviceAreasEnabled`                                              | `Boolean!`                 | Whether the client must be within the service area to submit.                                               |
| `connectedToGoogle`                                                | `Boolean!`                 | Whether this form powers Google's "Book Online" integration.                                                |
| `efficientSchedulingType`                                          | `EfficientSchedulingType!` | Buffer strategy: `NONE`, `BUFFER_TIME`, `DRIVE_TIME`.                                                       |
| `bufferDurationMinutes`                                            | `Minutes!`                 | Fixed buffer between appointments (location-agnostic).                                                      |
| `maxDriveTimeMinutes`                                              | `Minutes!`                 | Only offer slots within this drive time of other appointments.                                              |
| `earliestAvailabilityMinutes`                                      | `Minutes!`                 | Earliest bookable lead time.                                                                                |
| `intervalDurationMinutes`                                          | `Minutes!`                 | Slot interval granularity offered to clients.                                                               |
| `requestUrl` / `embeddedRequestUrl`                                | `String`                   | Public + embeddable form URLs.                                                                              |
| `requestEmbedScript`                                               | `String`                   | HTML embed snippet for the form.                                                                            |
| `formAssignments`                                                  | list                       | Where this form is currently used.                                                                          |
| `successMessageTitle` / `successMessageDescription` / `successUrl` | `String`                   | Post-submit success page/message.                                                                           |

**`BookingType` enum:** `NONE` = form creates a **request only** (review before scheduling);
`ASSESSMENT` = creates a **request with an assessment** (client picks an on-site slot);
`JOB` = creates a **job** booked straight into the schedule.

**`EfficientSchedulingType` enum:** `NONE` = allow back-to-back; `BUFFER_TIME` = fixed buffer between
appointments; `DRIVE_TIME` = buffer sized by the client's location and drive time from other appointments.

### 3.2 `OnlineBookingConfiguration` fields (from schema)

| Field                     | Type         | Meaning                                            |
| ------------------------- | ------------ | -------------------------------------------------- |
| `id`                      | `EncodedId!` | Unique id.                                         |
| `acceptingOnlineBookings` | `Boolean!`   | Whether the public booking page is currently live. |
| `bookingUrl`              | `String!`    | The account's unique, shareable booking page URL.  |
| `bookingEmbedScript`      | `String`     | HTML for embedding the booking form on a website.  |

### 3.3 Behavior (help center)

- **Three form types**, matching `bookingType`:
  - **Request form** (`NONE`) — collects the work details + preferred dates; lands as a **Request** to
    review before scheduling. Use when you want to vet work before committing calendar time.
  - **Assessment booking form** (`ASSESSMENT`) — the client picks an available on-site slot based on your
    team's real availability.
  - **Job booking form** (`JOB`) — the client books a service **directly into your schedule**.
    [Requests and Bookings Settings], [Online Booking]
- **Booking approval:** with _Require assessment booking approval_ on, submissions arrive as **Needs
  Approval** requests instead of auto-confirming; you accept/decline before they hit the schedule. New
  assessment booking forms default this **on**. [Requests and Bookings Settings]
- **Service areas:** each form has its own service-area setting; when on, clients must be within your
  service area to submit. [Requests and Bookings Settings]
- **Where forms live:** settings under _Gear → Settings → Requests and Bookings_; forms can be embedded on
  a website and shared on social media. [Requests and Bookings Settings], [Add your Request and Booking
  Forms to your Website and Social Media]

### 3.4 Mutations (Requests) — from schema

| Action                      | Mutation                                          | Returns                                |
| --------------------------- | ------------------------------------------------- | -------------------------------------- |
| Create request              | `RequestCreate` (`RequestCreateInput`)            | `request`, `userErrors`                |
| Edit request                | `RequestEdit` (`RequestEditInput`)                | `request`, `userErrors`                |
| Edit request line items     | `RequestEditLineItems` / `RequestCreateLineItems` | `request`, `userErrors`                |
| Edit request job forms      | `RequestEditJobForms`                             | _(request job-form assignments)_       |
| Add / edit request note     | `RequestCreateNote` / `RequestEditNote`           | `request`, `requestNote`, `userErrors` |
| Archive / unarchive request | `RequestArchive` / `RequestUnarchive`             | `request`, `userErrors`                |

Read queries: `request(id)`, `requests(filter)` (100 recently updated), `requestSettings`,
`onlineBookingConfiguration`. **No public "convert request → quote/job" mutation is exposed** in the
sampled schema — conversion appears to be a web-app action, not an API mutation **(unverified whether a
convert mutation exists under a different name)**.

---

## 4. How WE compare (build notes)

- **Requests are a distinct lead-intake object, not just a "new contact."** Jobber separates _the ask_
  (Request, with its own line items + status lifecycle) from _the priced estimate_ (Quote). Our contacts +
  pipeline model should treat an inbound request as its own record that **converts** into a quote/job, and
  keep a terminal **Converted** status so the same lead can't be double-processed. This mirrors our
  Schedule-hub work ([[schedule-hub-rebuild]]) and lead-source plumbing ([[lead-sources-report-deferred]]).
- **Three form types is the industry pattern to match:** _request-only_ (review first), _assessment
  booking_ (client self-books an on-site estimate), and _job booking_ (book straight into the schedule).
  We already have public booking ([[phone-field-industry-upgrade]] shipped it for booking); the gap to
  close is the **`bookingType` switch + booking-approval gate + service-area gate** per form.
- **Assessment = our "Visit"/on-site event, tied to a request.** Jobber's assessment is a schedulable item
  with assign, arrival window, reminders, checklist count, and a **complete→convert** prompt. When we build
  the estimate/site-visit flow, copy the _mark complete → "convert to quote/job, leave Action Required, or
  archive"_ branch — it's the moment leads move down the funnel.
- **Efficient scheduling (buffer / drive-time) is a real differentiator.** `DRIVE_TIME` slotting (only
  offer times within N minutes' drive of existing jobs) is worth beating — it directly reduces windshield
  time for contractors. Our booking currently offers fixed slots; drive-time-aware availability is a
  standout feature.
- **Arrival windows** ("we'll arrive 1–3pm") are expected by home-service clients — build them as a
  first-class field on both assessments and visits, not free text.

---

### Help-center sources

- Request Basics — https://help.getjobber.com/hc/en-us/articles/115009737048-Request-Basics
- Requests in the Jobber App — https://help.getjobber.com/hc/en-us/articles/8195739126039-Requests-in-the-Jobber-App
- Converting a Request to a Quote or Job — https://help.getjobber.com/hc/en-us/articles/360056871013-Converting-a-Request-to-a-Quote-or-Job
- Using Assessments to Schedule and Convert Work Requests — https://help.getjobber.com/hc/en-us/articles/360005363854-Using-Assessments-to-Schedule-and-Convert-Work-Requests
- Scheduling an Assessment — https://help.getjobber.com/hc/en-us/articles/360005363854-Scheduling-an-Assessment
- Assessment and Visit Reminders — https://help.getjobber.com/hc/en-us/articles/360033608974-Assessment-and-Visit-Reminders
- Requests and Bookings Settings — https://help.getjobber.com/hc/en-us/articles/39026037947543-Requests-and-Bookings-Settings
- Online Booking — https://help.getjobber.com/hc/en-us/articles/13808363916951-Online-Booking
- Add your Request and Booking Forms to your Website and Social Media — https://help.getjobber.com/hc/en-us/articles/360026249434-Add-your-Request-and-Booking-Forms-to-your-Website-and-Social-Media
- List Pages and Key Metrics — https://help.getjobber.com/hc/en-us/articles/22710819158935-List-Pages-and-Key-Metrics
