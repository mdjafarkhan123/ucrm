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

## 4. Live tour (observed live 2026-08-18)

Toured the live Jobber account (Requests list, a scheduled/overdue request, a new/unscheduled request, the
new-request form, and Settings → Requests and Bookings) via `claude-in-chrome`. Read and cancelled only —
nothing was saved, sent, converted, or deleted.

### 4.1 Requests list page

- Three metric cards above the table: **Overview** (counts by status: Needs approval, New, Assessment
  complete, Overdue, Unscheduled), **New requests** (past 30 days, with a trend %), **Conversion rate** (past
  30 days, with a trend %).
- Table columns: Client, Title, Property, Contact, Requested (date), Status (colored badge). Sortable columns
  show up/down carets; default sort is `STATUS_AND_REQUESTED_AT`.
- `Status` and `Date` are separate filter chips above the table, each opening a searchable checklist dropdown
  (statuses: All, Archived, Assessment complete, Converted, New, plus more on scroll — matches the schema
  enum). A live search box filters the request list itself.
- Header actions: **New Request** (primary button) and **More Actions → Customize Form / Share or Embed**
  (jumps into the booking-form settings covered in §4.4).

### 4.2 Request detail page — scheduled (assessment set) vs. new (unscheduled)

Both states share one layout: status badge + title top-left, an edit pencil beside the title, a **History**
icon (clock-with-arrow) and **More** menu top-right, plus one primary CTA that changes with state. A
client/property summary card sits below the title (name, property address, phone, email, and a `...` menu
with **View client profile / Edit client details / Change property**). A **Requested** / **Assessment** date
pair sits beside that card once an assessment exists. A standalone **Notes** card occupies the whole right
rail — empty state invites "Leave an internal note for yourself or a team member"; once notes exist it shows
author, timestamp, a pin/star, and thumbnails for any files attached to a note.

- **New / unscheduled** (no assessment yet): primary CTA is **Schedule Assessment** (calendar icon). No
  Product/Service section appeared on this one (it had none priced yet — the other request did, see below).
- **Scheduled / Overdue** (assessment booked, date passed): primary CTA becomes **Email Booking
  Confirmation**. Below the summary card: an **Overview** section (service-details Q&A merged into one
  freeform block, plus any submitted photos — edited inline via its own pencil, no separate dialog), an
  **Assessment** section (Instructions, Schedule date/time, assigned Team member(s), Checklists, a
  "Complete assessment" checkbox, and the configured client/team reminder offsets), a **Product / Service**
  section (line items with thumbnail, qty, unit price, total, then Subtotal/Total), and a **Labor** section
  at the very bottom ("Time tracked to this request will show here" — empty until a timesheet entry lands).
- **More menu** on a request: **Convert to Quote**, **Convert to Job**, **Archive**, **Print**, **Delete**.
  No separate "leave as Action Required" menu item was visible — that appears to just be *not acting* on a
  request whose assessment is complete.
- **History** icon opens a right-side **Request History** panel replacing the Notes rail: a chronological,
  field-level audit log ("Jafar Khan edited the request — Status: pending → scheduled", "... updated the
  assessment — Assigned to: empty → Jafar Khan", "... filled out a form — Share images...: → [file ids]",
  etc.), each entry showing actor, what changed, old → new value, and a timestamp. Filterable by Team, Type,
  and Date, sortable Newest/Oldest. This is a strong reference for our own activity-feed pattern.

### 4.3 Scheduling an assessment / creating a request

- **Schedule Assessment** opens an inline **"On-site assessment"** panel (not a modal) directly on the
  request page: Instructions textarea; Schedule with Start/End date + a **"Schedule later"** checkbox (checked
  by default — unchecking it reveals the date pickers) and Start/End time + an **"Anytime"** checkbox — the
  same three-state (Scheduled / Anytime / Unscheduled) model documented in §2.1; a Team section (assign
  members, "Email team when assigned" checkbox, a team-reminder-offset dropdown); a Checklists callout
  ("Attach custom-built checklists so nothing gets missed" → **Create a Checklist**); Cancel/Save. The
  request's existing Product/Service line items are shown read-only underneath, carried forward automatically.
- **New Request** (staff-created) is a single full-page form, not a wizard: Title, client picker, a read-only
  "Requested on" date (defaults to today), an **Overview** section (service-details textarea + a
  drag-and-drop photo uploader, 10 max), an **On-site assessment** empty-state card (truck icon, "Visit the
  property to assess the job before you do the work" — click to expand the same panel as §4.3 above), a
  **Product / Service** section (**Add Line Item** button, Subtotal/Total), and a **Notes** empty-state card.
  One Cancel/Save Request pair at the bottom for the whole page — no per-section save.

### 4.4 Settings → Requests and Bookings

- **Forms** card lists every form (e.g. "Assessment Booking Form", "Default Form") with a `Booking default` /
  `Request default` toggle per form (only one of each can be active) and a `...` menu: **Edit / Preview /
  Share links / Add tracking**.
- **Edit** opens a full drag-and-drop form builder: a live form preview on the left (starts with a locked
  "Contact information" section — name, company, email + marketing-email consent checkbox, phone +
  marketing-SMS consent checkbox, address), and a **Manage form** rail on the right with two tabs:
  - **Add Questions** — "Add section" (splits the form into another page) plus custom question types: Short
    answer, Long answer, Dropdown (single/multi), Checkbox, Radio, Numerical, Upload images, Yes/No toggle.
  - **Settings** — Form title, Form description, a **Form Pages** toggle (sections = separate pages), the
    **Request default** toggle, a **Require assessment booking approval** toggle ("Review and confirm
    assessment bookings before they're scheduled"), a **Service areas** toggle with an "Edit service area"
    link, and a **Booking Availability** collapsible section. This is a materially bigger builder than the
    schema table implied — full custom-field authoring, not just the three `bookingType`s.
- **Checklists**, **Customization** (branding, reuses Business Profile), and **Availability** (Business Hours
  pulled from Company Settings, Service areas) round out the settings page.

### 4.5 Confirmed / corrected against schema

- The three-state schedule model (Scheduled/Anytime/Unscheduled) and the `assessment_completed`/`overdue` etc.
  status labels from §1.2–§2.1 match what's on screen exactly.
- The "complete → convert / leave Action Required / archive" branch from §2.2 was **not directly observed**
  as an explicit prompt in this trial account (no assessment was actually marked complete during the tour,
  per the read-and-cancel rule) — worth a follow-up look before Part 1 sign-off if the exact prompt wording
  matters for our build.
- The booking-form builder is a full custom-form authoring tool (drag-drop questions, multi-page sections,
  branding), well beyond the `RequestSettings` field table in §3.1. Treat that table as the data model and
  this section as the actual authoring UX — the gap between them is a scope decision for Part 1 (see open
  questions in the campaign proposal).

---

## 4.6 Sales Pipeline board (from Jafar's screenshot, `Design/Pipeline.webp`, 2026-08-18)

Jafar's Jobber plan does not include Sales (it is a paid "Lab" add-on), so this board was never toured live.
Everything below is read off one full-page screenshot he supplied. It is the whole board scrolled, not one
screen: the seven columns do not fit across a normal window, and the columns themselves run past the fold.

- Page title `Sales Pipeline`, with a `Give Feedback` button on the right. Sales sits in the main left nav
  with a `Lab` badge beside it.
- Two small outcome tiles under the title, side by side, each with a chevron opening a list:
  `Won (4) / Past 30 days` and `Lost (0) / Past 30 days`. Outcomes are never board columns.
- The columns sit inside one bordered board, split into two labelled groups by a vertical divider:
  - **Requests** (icon + total badge `13`): New requests `4`, Assessment unscheduled `2`,
    Assessment scheduled `1`, Assessment completed `6`.
  - **Quotes** (icon + total badge `11`): Draft `4` `$60,000`, Awaiting response `5` `$75,000`,
    Changes requested `2` `$30,000`.
  - The group total is the sum of its columns. Only Quote columns carry money — a Request column has a
    count and nothing else, because a request has no price yet.
- Column header: name on the left, count on the right, value underneath on the Quote side.
- Card, in order: title (wraps to as many lines as it needs — one card in the shot runs four lines), client
  name in muted grey, then the amount in bold on Quote cards only, then a footer row of a calendar icon with
  a date on the left and a small age chip (`1d`) on the right.
- Cards are white with a hairline border and rounded corners on a very light column background. Columns are
  separated by thin vertical rules, and every column is the same width.
- An empty column keeps its header and count and shows nothing underneath — no empty-state art. In the shot,
  Assessment scheduled has one card and acres of empty column below it.
- Nothing on the board creates work: there is no add button on a column, no card menu, and no visible drag
  handle. Cards are the only interactive thing.

### 4.6.1 The current board, from the help article and Jafar's 16 screenshots

Sources: https://help.getjobber.com/en/articles/sales-pipeline/ and `Design/pipeline/1.webp` .. `16.webp`,
captured 2026-08-18. These show a **newer build than `Design/Pipeline.webp`** — the nav item is now
`Pipeline` with a briefcase icon rather than `Sales` with a `Lab` badge, and the board gained a control bar,
money on Request columns, lead source, salespeople, tasks, notes, and editable stages. Where the two
disagree, these win.

**Page layout, top to bottom**

1. Org name, then `Won (n) / Past 30 days` and `Lost (n) / Past 30 days` tiles, each a chevron opening the
   Sales outcomes report. On the right, a green `+ Add new` button and a `... More actions` button.
2. A control bar of pill controls: `Sort by | Time in stage` with a separate up/down arrow button beside it,
   `Salesperson | All`, `Lead source | All`, a calendar `Date | All`, then a plain `(16 results)` count.
   Sort choices are time in stage, created date, and value.
3. One bordered board split by a vertical divider into `Requests` and `Quotes` groups, each with an icon and
   a total-count badge.

**Column header** — name on the left with a small lightning-bolt icon on the right (it marks the stage's
automatic entry rule), then a second row carrying a count pill and a money total. **Both groups show money**;
a Request column reads `1  $0` when nothing is priced. Empty columns keep the header and show nothing.

**Card**, top to bottom: title, client name in grey, the amount in bold (present on Request cards too, as
`$0.00`), an optional lead-source chip (tag icon + `Referral`, `Instagram`), then a footer row of calendar +
date on the left and, on the right, the salesperson's avatar and an age chip (`0h`, `5d`, `181d`). A card may
carry one open task line beneath the footer, in red when overdue (`Call Colin on Thursday @ 12`).

**Freshness** shows as a coloured left edge stripe plus the age chip's tint: nothing at `0h`, red stripe and
red chip once stale. The article's rule is green under an hour, red over 24 hours.

**Card `...` menu** (`5.webp`): `Salesperson` and `Mark as lost`. `Mark as lost` is greyed out for a Draft
quote. `Salesperson` opens a small dialog with a searchable list of staff and a `Clear Option` link at the
bottom, so a card can be unassigned.

**Opportunity Brief** — clicking a card opens a right-side drawer, never a page (`7.webp`, `8.webp`,
`11.webp`):

- Header: `Request for Sandra Morris` / `Quote for Robin Schneider`, the amount underneath, then a stage chip
  and an age chip side by side, and a close X.
- A client card: name with a status dot, the property address, phone and email as links, and a `...` menu.
- `Quick actions` as outline buttons — `View Request` on a request; `Email`, `View Request`, `View Quote` on
  a quote that came from one.
- `Opportunity summary`: an AI paragraph in a gradient-bordered box with a sparkle icon and a
  `Was this helpful?` thumbs pair.
- `Tasks`: a count pill and `+ Add task`, `No tasks yet` when empty, and a `COMPLETED · 1` sub-header with the
  finished ones struck through. Max 5 open and 5 completed.
- `Notes`: a `+` button; each note carries author avatar and name, a `Client` chip, a timestamp, the text,
  image thumbnails with a `+1` overflow link, and a `Linked note` label showing it lives on the underlying
  record. `@Nathaniel` mentions render inline.
- `New Task` dialog (`9.webp`): the client card with a `Select a property` picker, `Title`, `Instructions`,
  a `Schedule` block (start/end date, start/end time, `Schedule later`, `Anytime`), a `Team` assign select,
  and `Repeats`.

The official Sales Pipeline article was updated 2026-07-15 and is more precise than those screenshots for
Pipeline-specific Tasks and Notes. It documents the smaller Brief Task form: required title, optional
instructions, one owner, and one due date. Every Pipeline user may create, edit, complete, reopen, or delete;
the actions are internal and send no client communication. Each Opportunity has at most five open and five
completed Tasks. The card shows the earliest-due open Task, breaking ties by creation order; with no due dates,
it shows the oldest open Task. Dated Tasks also appear on the assignee's Schedule.

The same article documents Task lifecycle: Request-to-Quote transfers Tasks; Lost Request completes them;
Lost Quote or archive permanently deletes them; Won does not carry them into the Job. Brief Notes default to
the backing Request/Quote, may instead link to the Client, save immediately, and appear beside existing Notes.
The official Brief has no embedded activity/history section; record history remains on the full Request or
Quote page. These current documented rules win over inference from the screenshots.

**Edit stages** (`13.webp`, `14.webp`): the two groups side by side, each with `+ Add a stage`. Every
built-in stage shows a padlock and a read-only `Rule` card. Verbatim rules:

| Stage | Opportunities enter when |
| --- | --- |
| New requests | A new request is created |
| Assessment unscheduled | An assessment is required for the request but not scheduled yet |
| Assessment scheduled | An assessment for the request has been scheduled |
| Assessment completed | The assessment for the request has been completed but hasn't been converted to a quote or a job yet |
| Draft | A new quote has been created but has not been sent to you client yet |
| Awaiting response | A quote that has been sent to your client and is awaiting approval or a change request |
| Changes requested | A quote that has been sent to your client and a client is requesting changes on |

A custom stage instead gets a drag handle, a delete icon, an editable name (`New stage 1`), and no rule. It
appears as a normal column on the board and accepts drags without restriction.

**Sales outcomes report** (`16.webp`), reached from the Won/Lost tiles: a `Type | Won` filter and a date
range, then a table of `Title`, `Name`, `Created At`, `Won At`, `Total`, every column sortable, with
`Showing 1-4 of 4 items`, a per-page select, and prev/next arrows.

**Movement:** cards advance automatically when the underlying record changes, and staff may drag forward.
Dropping into a protected stage first demands the action that stage represents. Backward movement is
refused. Won is automatic on quote approval or job creation; Lost is always by hand, with an optional reason.

The current official article does not document reopening a Lost Pipeline Opportunity, restoring its archived
Request/Quote, or how a reopened Opportunity affects the Won/Lost tiles and Sales Outcomes report. Treat all
Pipeline reopen behavior as an UCRM product decision rather than Jobber parity.

**Nothing is created on the board.** Opportunities only ever come from Requests and Quotes.

**Mobile:** the Jobber app has no pipeline at all. Tasks and notes are web-only.

**Access:** Plus plan or paid add-on, plus the request and quote view/create/edit permissions.

### 4.6.2 What we take from it (approved 2026-08-18)

Jobber's current pipeline is our reference and overrides the earlier UCRM opportunity model. Full text in
`docs/sales-pipeline-behavior-contract.md`.

- Same seven protected stages, same two groups, same entry rules.
- Opportunities come only from Requests and Quotes. No standalone creation, and `+ Add new` in the screenshots
  is Jobber's global create button, not a way to author an opportunity.
- One card per record, not one identity across both: a converted Request leaves the Request stages and its
  Quote appears in Draft as a new card.
- Same freshness rule — green under an hour, neutral to 24 hours, red after — measured from stage entry.
- Forward-only drag with the required action, copied exactly, but not until both groups exist.
- Deliberate differences: desktop only, because our mobile app is separate work; one page-level scroll with an
  accessible `Load more` per column instead of Jobber's per-column scroll; no lead source, because Jobber's own
  screens and docs disagree about it.
- Part 3 copies the five-open/five-completed Task limits, card priority, and lifecycle above. UCRM preserves a
  real read-only role: `pipeline.view` reads Brief Tasks/Notes and `pipeline.edit` gates mutations.
- Part 3 Notes support Request/Client linking and core create/view/edit/delete. Attachments, mentions, pinning,
  advanced Task scheduling, notifications, and Schedule UI wait for their owning domains.
- An embedded Opportunity activity timeline is deferred rather than presented as Jobber parity; Jobber does
  not put one in this drawer, and UCRM's current generic activity is not complete enough to be honest history.
- Part 4 follows Jobber's automatic Won, manual Lost, source archive, optional lost reason, Task lifecycle,
  active-board removal, tiles, and Sales Outcomes report. UCRM adds reasoned Lost reopen: it restores the
  Request and only the Tasks auto-completed by that loss, removes the record from current Lost reporting, and
  retains both transitions in immutable history.

## 5. How WE compare (build notes)

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

## 6. What we built (Part 1, shipped and browser-verified 2026-08-18)

Staff-side request intake and on-site assessment scheduling/completion. Public booking forms and real
Quote/Job conversion are explicitly out of scope — see the deferred items in `Memory/deferred/INDEX.md`
for what that leaves undone.

- **`requests.status` stores six values**, not the schema's nine — `upcoming`/`today`/`overdue` are never
  written. They're derived at read time from the assessment's start time against the org's timezone
  (`src/lib/server/requests/status.ts`), the same rule planned for job visits later. The derived value
  travels as `status` on every API response; `stored_status` is the persisted column. Never write the
  derived one.
- **Zero or one assessment per request.** Both `starts_at`/`ends_at` null means booked but undated
  (Jobber's "Unscheduled"); assignees are a join table, not an array column.
- **List page:** Overview card rows are New, Unscheduled, Overdue, Assessment complete — counts are
  read-only and counted on demand, clicking one does not filter. Pagination is load-more, not numbered
  pages; a date filter is deferred, Status ships. The header renders as a filled grey card rather than
  Jobber's status-tinted stripe, because the blueprint (`Design/Requests.jpg`) wins on that call per
  CLAUDE.md rule 5.
- **New Request page:** title, a client-search combobox, and a service-overview textarea are the only
  required-feeling fields, matching `Design/Request new.jpg`. `property_id` is required server-side even
  though the blueprint shows no property field — resolved by auto-selecting the client's primary property
  on pick, surfacing a "Change property" control only when that client has more than one. The On-site
  assessment and Products & services blocks render as static empty states on this page (not the inline
  editable panel Jobber itself offers pre-save) because both need the request to already exist — assessment
  scheduling opens correctly once you land on the saved request's own detail page.
- **List pages stay separate pages per work-object type and share components** (`FilterBar`, `DataTable`,
  `KpiCard`, `StatusOverviewCard`) — never one page switched by type. The header/summary-card and Primary
  Info card (`src/lib/components/work/`) are built as reusable components for this same reason: Quote, Job,
  and Invoice will need the identical shape.
- **Known gaps, not yet decided:** request-list search doesn't match client name (only `title` and
  `service_type`); filtering by Status filters the *stored* status, so "Unscheduled" also returns rows
  currently badged Overdue/Today; the third KPI card ("Assessments booked") has no real data source yet;
  no `requests.*` permission keys are seeded, so every request route only checks organization membership.
  See `Memory/deferred/INDEX.md` for each one's reactivation trigger.

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
