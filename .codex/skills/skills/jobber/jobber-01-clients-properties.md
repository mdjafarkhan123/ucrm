# Jobber Reference — Clients & Properties

> Source: `JobberJson.md` (schema, authoritative for fields/enums) + Jobber Help Center (behavior, cited).
> Part of the Jobber competitor reference set — see `jobber-00-overview-lifecycle.md` for the index and
> the full lead→cash lifecycle. Plain English throughout; **(unverified)** marks anything not confirmed
> by schema or help center.

The **Client** is the hub of Jobber's whole data model — every request, quote, job, invoice, and payment
hangs off it. A **Property** is a physical location that belongs to a client and is where work actually
happens. This file documents both, their sub-objects, and the behavior around them.

---

## 1. Client (`Client`)

> Schema description: _"Clients are the customers who pay for services on Jobber's platform — they belong
> to the Jobber account / service provider."_

A client can be a person or a business (`isCompany`), and can be a prospective **lead** (`isLead`) before
becoming a full client.

### 1.1 Core fields (from schema)

| Field                             | Type                                                  | Meaning                                                            |
| --------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------ |
| `id`                              | `EncodedId!`                                          | Opaque unique id.                                                  |
| `name`                            | `String!`                                             | Primary display name of the client.                                |
| `firstName` / `lastName`          | `String!`                                             | Person's name parts.                                               |
| `companyName`                     | `String`                                              | Business name (when `isCompany`).                                  |
| `title`                           | `String`                                              | Client's title (e.g. Mr/Ms/Dr).                                    |
| `secondaryName`                   | `String`                                              | Secondary contact name (e.g. spouse/partner).                      |
| `isCompany`                       | `Boolean!`                                            | Does the client represent a business.                              |
| `isLead`                          | `Boolean!`                                            | Is this a prospective **lead** (not yet a converted client).       |
| `email`                           | `String`                                              | Primary email.                                                     |
| `phone`                           | `String`                                              | Primary phone.                                                     |
| `emails`                          | `[email]!`                                            | All email addresses (one primary).                                 |
| `phones`                          | `[ClientPhoneNumber]!`                                | All phone numbers (one primary).                                   |
| `defaultEmails` / `defaultPhones` | list                                                  | Email/phone to use for a given message type (SMS vs email).        |
| `billingAddress`                  | `ClientAddress`                                       | Custom billing address.                                            |
| `billingAddressPresent`           | `Boolean!`                                            | Whether a custom billing address exists (else uses a property).    |
| `balance`                         | `Float!`                                              | Client's current outstanding balance.                              |
| `leadSource`                      | `String`                                              | Lead-source label, e.g. "Google", or a custom label; null if none. |
| `sourceAttribution`               | `SourceAttribution`                                   | Structured acquisition source of the client record.                |
| `utmMedium`                       | `String`                                              | UTM medium captured (e.g. "cpc").                                  |
| `tags`                            | `TagConnection!`                                      | Custom grouping labels.                                            |
| `customFields`                    | list                                                  | Client-level custom field values.                                  |
| `notes` / `noteAttachments`       | `ClientNoteConnection!` / `ClientNoteFileConnection!` | Internal notes + files.                                            |
| `isArchived` / `isArchivable`     | `Boolean!`                                            | Archive state / whether it can be archived.                        |
| `sampleData`                      | `Boolean!`                                            | Whether the record is Jobber demo/sample data.                     |
| `createdAt` / `updatedAt`         | `ISO8601DateTime!`                                    | Timestamps.                                                        |
| `jobberWebUri`                    | `String!`                                             | Deep link to this record in Jobber web app.                        |

### 1.2 Communication-preference flags (all `Boolean!`)

These are per-client opt-ins that gate Jobber's automated messaging — directly relevant to our automation
opt-out model:

| Field                      | Controls                              |
| -------------------------- | ------------------------------------- |
| `receivesFollowUps`        | Job follow-up messages.               |
| `receivesInvoiceFollowUps` | Invoice follow-up / dunning messages. |
| `receivesQuoteFollowUps`   | Quote follow-up messages.             |
| `receivesReminders`        | Assessment & visit reminders.         |
| `receivesReviewRequests`   | Review-request messages.              |

> **Build note:** Jobber splits notification consent into **five independent per-client toggles** by
> message category, not one global "don't text me." Our per-contact SMS opt-out is coarser; matching
> Jobber means per-category preferences (quote / invoice / reminder / follow-up / review).

### 1.3 Relationship connections

`clientProperties` (`PropertyConnection`), `contacts` (`ContactModelConnection`), `requests`, `quotes`,
`jobs`, `invoices`, `messages` (`MessageInterfaceConnection`, all client messages newest-first),
`scheduledItems` (`ScheduledItemInterfaceConnection` — scheduled + unscheduled), `unallocatedDepositRecords`
(deposits taken but not yet applied to an invoice / not refunded), and `requestedWorkObjects`
(`RequestedWorkObjectUnionConnection` — the unified activity timeline: requests + quotes + jobs + invoices

- treatments, default newest-modified first).

Two performance-guard fields worth copying:

- `scheduledItemsAvailable: Boolean!` — returns **false** when the client has too many attached records to
  query efficiently; then `scheduledItems` returns empty and the UI should send the user to the main
  schedule instead. (Explicit "this list is too big to inline" escape hatch.)
- `ClientConnection.totalCount` carries a schema warning that using it **increases throttling** — Jobber
  discourages counting.

### 1.4 Client sub-objects

**`ClientPhoneNumber`** — `number` (as stored), `normalizedPhoneNumber` (E.164), `friendly` (display
format), `description` (type: Main, Mobile, etc.), `primary: Boolean!`, `smsAllowed: Boolean!` (can it
receive texts), plus links to `client` and `contact`.

**`ClientAddress`** (billing / property address) — `street`, `street1`, `street2`, `city`, `province`
(state/province), `postalCode`, `country`, `latitude`, `longitude`, `name`.

**`ClientNote`** — `message`, `pinned: Boolean!`, `createdBy` (`NoteCreatedByUnion` — user **or** app),
`lastEditedAt` / `lastEditedBy`, `fileAttachments` (`NoteFileInterfaceConnection`), and `linkedTo`
(`NoteLink` — a note can be linked to a client, quote, job, etc., not just the client). Notes support file
attachments via `ClientNoteAddAttachment`.

**`ClientMeta`** (fetched via the `clientMeta` query, not on `Client` itself):

- `clientHub: Boolean` — whether the client has Client Hub enabled.
- `counts` (`ClientCounts`) — association counts: `deposits`, `invoices`, `jobs`, `notes`, `payments`,
  `properties`, `quotes`, `requests`, `tasks`, `visits`. (Powers the client-summary badges cheaply.)

### 1.5 Behavior (help center)

- **Lead vs client:** when a new person submits a request they're auto-added to the client list **as a
  lead** (`isLead`), because they haven't met client criteria yet. Clients created by **CSV import are full
  clients, not leads** — no lead label after import. [[client basics]] [[lead management]]
- **Client page** = the entire history with that client. A "Contact Info" block shows phone(s), email(s),
  **payment terms**, **lead source**, **tags**, and client custom fields at the top. [[client basics]]
- **Tags** are labels to group clients; clicking a tag in the list filters to clients with it. [[client basics]]
- **Custom fields** are **internal-only when created** (only staff see them) but can later be made
  **client-facing**. Configured via `customFieldConfigurations`. [[custom fields]]
- **Archiving:** clients are archived (soft-close), not hard-deleted, when `isArchivable`. Mutation:
  `ClientArchive`.

---

## 2. Property (`Property`)

> Schema description: _"Properties are locations owned by Service Consumers where Service Providers provide
> service for."_ A client can have **0, 1, or many** properties. [[client basics]]

### 2.1 Fields (from schema)

| Field                          | Type                                | Meaning                                                         |
| ------------------------------ | ----------------------------------- | --------------------------------------------------------------- |
| `id`                           | `EncodedId!`                        | Unique id.                                                      |
| `client`                       | `Client`                            | Owning client.                                                  |
| `address`                      | `PropertyAddress!`                  | The physical address (geo-coded).                               |
| `name`                         | `String`                            | Property label (e.g. "Main house", "Warehouse").                |
| `contacts`                     | `ContactModelConnection`            | Contacts specific to this property.                             |
| `taxRate`                      | `TaxRate`                           | **Tax rate lives on the property**, not the client.             |
| `recentPricing`                | `ProductOrServiceConnection`        | Recently-used line items **for this property** (price memory).  |
| `routingOrder`                 | `Int`                               | Property's order in route optimization.                         |
| `isBillingAddress`             | `Boolean`                           | Whether this property doubles as the billing address.           |
| `customFields`                 | list                                | Property-level custom fields.                                   |
| `jobs` / `quotes` / `requests` | connections                         | Work attached to this specific property.                        |
| `scheduledItems`               | `ScheduledItemInterfaceConnection!` | Visits, tasks, assessments, events, reminders at this property. |
| `createdAt`                    | `ISO8601DateTime!`                  | First created.                                                  |
| `jobberWebUri`                 | `String!`                           | Deep link.                                                      |

**`PropertyAddress`** — `street`, `street1`, `street2`, `city`, `province`, `postalCode`, `country`,
`name`, `coordinates` (`GeoPoint`), and `geoStatus` (`GeoStatus` enum — state of geo-coding the address).

### 2.2 Why property-level matters (build note)

Jobber deliberately puts **tax rate, pricing memory, routing order, and geo-coordinates on the property**.
Consequences to match:

- **Tax is correct per location** — a client with properties in two tax jurisdictions bills correctly.
- **Route optimization** needs geo-coded properties with a `routingOrder`.
- **Price memory** (`recentPricing`) is per property, so repeat work at the same site pre-fills prior pricing.

Mutations: `PropertyCreate`, `PropertyEdit` (both return `...Payload` with `userErrors`). No hard delete
exposed for properties in the sampled schema **(unverified whether a `PropertyArchive`/delete exists)**, but
the UI does offer Delete — see below.

### 2.3 How the client screen handles properties (live tour, 2026-08-17)

Toured on a real client record, so this supersedes guesses from the help centre.

- **A client has no address of its own.** Jobber's Edit Client form carries title, name, company, role, a
  billing-contact checkbox, phones, emails, payment terms, lead source and additional details — and no
  address field anywhere. Every address in the product belongs to a property. Do not model a client address.
- **Properties is the first block** on the Client information tab, above Contacts and Work overview, with a
  `+` in its top-right corner. Each property is one row: the full address in bold, then a map-pin
  ("View on map") and a pencil ("Edit property").
- **Add property dialog:** property name (optional — theirs is literally called "A property"), Street 1,
  Street 2, City, Province, Postal code, Country, a tax-rate select, and two collapsed sections —
  Property details (custom fields) and Property contacts, described as "for contacts with access limited to
  this property, e.g., tenants". Buttons Cancel / Add Property.
- **Edit property dialog** is the same form prefilled, plus a red **Delete** bottom-left and a ticked
  checkbox **"Billing address is the same as property address"**. Unticking it reveals a second complete
  address form, so **Jobber stores an optional billing address on each property** rather than nominating one
  property as the billing one. Our `properties.is_billing_address` boolean is a weaker model that cannot
  express "this rental bills to that management office"; settle the shape when invoicing lands.
- **Both dialogs write on their own button** rather than staging into a page-level save. We keep that for
  child records — see the save rule in `jobber-08-screen-patterns.md`.

What we deliberately left out of our build: tax rate, custom fields, property contacts, and billing address.

### 2.4 The client's Communication tab (live tour, 2026-08-17)

The second tab on the client detail page. It is a **read-only history, not a composer** — there is no send
control inside it. Sending starts from the envelope button in the page header.

The body is one card holding a flat list of messages, newest first, divided by hairlines rather than one
card per message. Each row carries:

- a channel icon and `To: <name>, <email>` on the left, with the date right-aligned on the same line
- the subject, then the start of the body in grey on the same wrapped paragraph, truncated with an ellipsis
  after roughly two lines
- a status pill underneath, e.g. `Not sent`

Everything is included — automated messages count. The rows observed were assessment reminders and a
service-visit follow-up generated by automations, not messages a person typed.

The right rail gains a **`Last communication`** card on this page: date and time, the subject, a
`Read more...` link, and a chevron opening the full history.

Not yet observed: what a row opens when clicked, whether inbound replies and SMS appear in the same stream,
and whether the list filters or paginates.

---

## 3. Client Hub (client-facing portal) — basics

Full treatment (settings, referrals, documents) is in `jobber-06-automations-clienthub.md`. The essentials:

**What it is:** a self-serve online portal where the client can _"approve quotes, check appointment
details, pay invoices, print receipts, or request more work — all in one place."_ Mobile-friendly, no
login-password required (accessed via a secure link). [[what do your clients see in client hub]]

**What the client can see/do:**

- **Requests** — submit a new work request via a simple form; it lands in the contractor's account. [[what do your clients see]]
- **Quotes** — approve a quote or request changes. On the **Grow plan**, the client can also select
  **optional line items** and see **line-item images** (this is Jobber's good-better-best / upsell surface). [[what do your clients see]]
- **Appointments** — see all past appointments and their **next 5 upcoming** (within 5 years). [[what do your clients see]]
- **Invoices / Payments** — pay invoices online (with Jobber Payments or a 3rd-party integration), pay
  required **deposits**, and **print receipts**. [[what do your clients see]]
- Sections are organized as **requests, quotes, appointments, invoices**. [[what do your clients see]]

`ClientMeta.clientHub` tells you whether hub is enabled for a given client.

> **Build note:** Client Hub is a major moat — it turns the CRM into a two-sided product (contractor +
> customer). The upsell angle (optional line items + images visible to the client at approval time) is the
> piece most worth beating: make the client-facing approve/pay/upsell flow excellent.

---

## 4. Available actions / mutations (Clients & Properties)

| Action              | Mutation                                     | Returns                               |
| ------------------- | -------------------------------------------- | ------------------------------------- |
| Create client       | `ClientCreate` (`ClientCreateInput`)         | `client`, `userErrors`                |
| Edit client         | `ClientEdit` (`ClientEditInput`)             | `client`, `userErrors`                |
| Archive client      | `ClientArchive`                              | `client`, `userErrors`                |
| Add client note     | `ClientCreateNote` (`ClientCreateNoteInput`) | `client`, `clientNote`, `userErrors`  |
| Edit client note    | `ClientEditNote`                             | `client`, `clientNote`, `userErrors`  |
| Delete client note  | `ClientDeleteNote`                           | `client`, `deletedNote`, `userErrors` |
| Attach file to note | `ClientNoteAddAttachment`                    | `attachmentsToBeAdded`, `userErrors`  |
| Create property     | `PropertyCreate` (`PropertyCreateInput`)     | `client`, `properties`, `userErrors`  |
| Edit property       | `PropertyEdit` (`PropertyEditInput`)         | `property`, `userErrors`              |

Read queries: `client(id)`, `clients(filter)` (100 recently updated), `clientMeta`, `clientPhone`,
`clientPhones`, `clientEmails` (fuzzy search by name/email), `similarClients` (≤10, for de-dup),
`property(id)`, `properties` (100 recently updated). Filter/sort via `ClientFilterAttributes`,
`ClientPhoneFilterAttributes`, `PropertyContactFilterAttributes`, `PropertyScheduledItemsFilter`.

---

## 5. Import & reporting notes (help center)

- **CSV client import:** spreadsheet must be **< 2.5 MB (~5,000 rows)**. Only these lead sources import:
  **Facebook, Google, Instagram, Flyer, Referral, Vehicle Wrap, Other** — **custom lead sources cannot be
  imported.** Imported rows are full clients (not leads). [[import clients]]
- **Clients Report** and **Lead Management** exist as dedicated reporting surfaces. [[clients report]] [[lead management]]

---

### Help-center sources

- Client Basics — https://help.getjobber.com/hc/en-us/articles/115009450867-Client-Basics
- Lead Management — https://help.getjobber.com/hc/en-us/articles/360038221373-Lead-Management
- Custom Fields — https://help.getjobber.com/hc/en-us/articles/115009735928-Custom-Fields
- Import Clients — https://help.getjobber.com/hc/en-us/articles/360034980534-Import-Clients
- Clients Report — https://help.getjobber.com/hc/en-us/articles/28490419170071-Clients-Report
- What Do Your Clients See in Client Hub? — https://help.getjobber.com/hc/en-us/articles/1500011237822-What-Do-Your-Clients-See-in-Client-Hub
- Client Hub Settings — https://help.getjobber.com/hc/en-us/articles/115009571307-Client-Hub-Settings
