# Jobber Reference — API Model, Queries, Mutations & Webhooks

> Source: `JobberJson.md` (schema, authoritative for the query/mutation/webhook type names + enums) +
> Jobber **Developer Center** (behavior — versioning, OAuth, rate limits, webhook signing; cited). Part of
> the Jobber competitor reference set — see `jobber-00-overview-lifecycle.md` for the index/lifecycle. Each
> domain file (`jobber-01`…`06`) lists the object fields; **this file is the cross-cutting API contract**:
> how you authenticate, page, mutate, and subscribe to events. Plain English; **(unverified)** marks anything
> not confirmed by schema or developer docs.
>
> **Key limitation of the schema dump:** GraphQL introspection **does not expand `INPUT_OBJECT` fields** —
> every `...Input` / `...Attributes` type in `JobberJson.md` has `"fields": null`. So we know every mutation's
> _name_, _argument type name_, and _return payload_, but **not** the exact input arguments. Those come from
> Jobber's live API docs, not this dump. Wherever this file says "takes `XxxCreateInput`", the inner shape is
> **not enumerable from `JobberJson.md`**.

Jobber's public API is a single **GraphQL** endpoint (`https://api.getjobber.com/api/graphql`). Everything —
clients, quotes, jobs, visits, invoices, payments — is read through the **Query root** and changed through the
**Mutation root**. This file is the catalog of both, plus the Relay pagination model, the app/OAuth/webhook
model, and the throttling rules that govern how fast you may call it.

---

## 1. GraphQL basics that hold for every call

- **Single endpoint, POST GraphQL.** One URL; you send a query or mutation document. No REST resource paths.
- **IDs are `EncodedId`** (schema scalar, _"An encoded id"_). Every object's `id` is an opaque encoded string
  (base64-style), **not** a raw DB integer. You pass it back verbatim to fetch or mutate an object. Never
  parse or construct it.
- **Versioned by a date header.** The API version is set with the **`X-JOBBER-GRAPHQL-VERSION`** HTTP header,
  in **`YYYY-MM-DD`** format, and **specifying a version is required for all apps.** New versions are
  published to the changelog only when a breaking/dangerous change ships; **old versions are supported for a
  minimum of 12 months and remain accessible up to 18 months** from release. [dev: API Versioning]
- **Auth is OAuth 2.0.** Apps authenticate on behalf of a Jobber account via the OAuth flow (the `Application`
  type in the schema carries `oauthUrl`, `redirectUrl`, `applicationScopes`). Access is bounded by **scopes**
  — each scope grants read and/or write to a data area, and scopes both gate the API _and_ populate the
  consent screen a Jobber user sees when connecting the app. While an app is in **Draft** its scopes are
  freely editable; **once published, adding a scope forces every already-connected account to re-authorize.**
  [dev: App Authorization (OAuth 2.0)]
- **The tenant is implicit.** Every query is scoped to _"the account of the authenticated Service Provider"_
  (that phrase is in nearly every Query field description). You never pass an `account_id`; the OAuth token
  determines the tenant. This is Jobber's equivalent of our `org_id` isolation — enforced by the token, not a
  query argument.

---

## 2. The Query root (read side) — full getter catalog

The `Query` type is _"The query root of Jobber's GraphQL interface."_ Its fields fall into three groups:
**single-object getters** (by `id`), **list getters** (Relay connections, mostly capped at ~100), and
**config/meta getters**. All names below are **verbatim from the schema**.

### 2.1 Single-object getters (fetch one by `EncodedId`)

| Query field      | Returns                  | Notes                                                                            |
| ---------------- | ------------------------ | -------------------------------------------------------------------------------- |
| `account`        | `Account`                | The account the authenticated user belongs to (no id arg — it's _your_ account). |
| `assessment`     | `Assessment`             | Single assessment.                                                               |
| `client`         | `Client`                 | Single client.                                                                   |
| `clientContact`  | `ContactModel`           | A single named contact on a client.                                              |
| `clientPhone`    | `ClientPhoneNumber!`     | A single client phone number.                                                    |
| `event`          | `Event`                  | Single calendar event.                                                           |
| `expense`        | `Expense`                | Single expense.                                                                  |
| `invoice`        | `Invoice`                | Single invoice.                                                                  |
| `invoiceSample`  | `Invoice`                | A sample invoice (industry demo data).                                           |
| `job`            | `Job`                    | Single job.                                                                      |
| `marketingItem`  | `MarketingItemType`      | A single marketing item.                                                         |
| `paymentRecord`  | `PaymentRecordInterface` | Single payment record (interface — branch on `__typename`).                      |
| `payoutRecord`   | `PayoutRecord`           | Single Jobber Payments payout.                                                   |
| `product`        | `ProductOrService!`      | Single price-book product/service.                                               |
| `property`       | `Property`               | Single property.                                                                 |
| `quote`          | `Quote`                  | Single quote.                                                                    |
| `request`        | `Request`                | Single work request.                                                             |
| `task`           | `Task`                   | Single task.                                                                     |
| `timeSheetEntry` | `TimeSheetEntry`         | Single timesheet entry.                                                          |
| `user`           | `User`                   | Single team member; **with no id, returns the current user.**                    |
| `vehicle`        | `Vehicle`                | Single vehicle.                                                                  |
| `visit`          | `Visit`                  | Single visit (tied to a Job).                                                    |

### 2.2 List getters (Relay connections — note the caps)

**Almost every top-level list caps at ~100 recently-updated records** and takes a `filter` argument. The cap
is stated in each field's description; the exceptions are called out.

| Query field                                    | Returns                                | Cap / note (from schema description)                                                                                                                |
| ---------------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `clients`                                      | `ClientConnection!`                    | "List of **100** recently updated clients satisfying a filter".                                                                                     |
| `clientPhones`                                 | `ClientPhoneNumberConnection!`         | All client phone numbers, sorted by most recently updated clients.                                                                                  |
| `clientEmails`                                 | `EmailConnection!`                     | Search client emails by name/email; blank term → most recently active.                                                                              |
| `similarClients`                               | `ClientConnection!`                    | De-dup helper — **never returns more than 10.**                                                                                                     |
| `properties`                                   | `PropertyConnection!`                  | "List of **100** recently updated properties".                                                                                                      |
| `requests`                                     | `RequestConnection!`                   | "**100** recently updated work requests".                                                                                                           |
| `quotes`                                       | `QuoteConnection!`                     | "List of **100** recently updated quotes satisfying a filter".                                                                                      |
| `jobs`                                         | `JobConnection!`                       | "**100** recently updated jobs".                                                                                                                    |
| `visits`                                       | `VisitConnection!`                     | Sortable; default sort `START_AT` ascending.                                                                                                        |
| `invoices`                                     | `InvoiceConnection!`                   | "List of **100** recently updated invoices satisfying a filter".                                                                                    |
| `invoiceSamples`                               | `InvoiceConnection!`                   | Sample invoices for the account's industry.                                                                                                         |
| `paymentRecords`                               | `PaymentRecordInterfaceConnection`     | "List of **100** recently sent payment records satisfying a filter".                                                                                |
| `paymentMethods`                               | `PaymentMethodInterfaceConnection`     | "List of **100** Jobber Payments payment methods".                                                                                                  |
| `payoutRecords`                                | `PayoutRecordConnection!`              | Jobber Payments payouts.                                                                                                                            |
| `capitalLoans`                                 | `JobberPaymentsCapitalLoanConnection!` | Recently-updated Jobber Capital loans.                                                                                                              |
| `products`                                     | `ProductOrServiceConnection!`          | "List of **100** services and products".                                                                                                            |
| `taxRates`                                     | `TaxRateConnection!`                   | The account's tax rates.                                                                                                                            |
| `tasks`                                        | `TaskConnection!`                      | Sortable; default sort `START_AT` ascending.                                                                                                        |
| `expenses`                                     | `ExpenseConnection`                    | Expenses for the account.                                                                                                                           |
| `expenseSuggestions`                           | `ExpenseSuggestionConnection!`         | Autocomplete from existing expenses.                                                                                                                |
| `expenseUploads` / `expenseUploadDocuments`    | connections                            | Draft expense-upload OCR pipeline.                                                                                                                  |
| `externalReminders`                            | `ExternalReminderConnection!`          | External reminders for the account.                                                                                                                 |
| `marketingItems` / `socialMarketingItems`      | `MarketingItemTypeConnection!`         | Marketing content (Google/Facebook).                                                                                                                |
| `scheduledItems`                               | `ScheduledItemInterfaceConnection!`    | **The unified calendar** — Basic Tasks, Visits, Events, Assessments, Quote Reminders, Invoice Reminders, for a list of team members on a given day. |
| `supplierInvoiceBatches`                       | `SupplierInvoiceBatchConnection!`      | Supplier-invoice OCR batches.                                                                                                                       |
| `timeSheetEntries` / `timeSheetEntriesByGroup` | connections                            | Timesheets for users on a day / grouped by job or label.                                                                                            |
| `users`                                        | `UserConnection!`                      | "List of **10,000** users satisfying a filter" — the one big cap.                                                                                   |
| `vehicles`                                     | `VehicleConnection!`                   | Vehicles for the account.                                                                                                                           |
| `appAlerts`                                    | `AppAlertConnection!`                  | "List of **100** app alerts".                                                                                                                       |
| `apps`                                         | `ApplicationConnection!`               | Installed/available apps.                                                                                                                           |
| `customFieldConfigurations`                    | `CustomFieldConfigurationConnection!`  | "List of **100** custom field configurations".                                                                                                      |

> **The "100 recently updated" cap is the single most important API fact.** You cannot page past the 100 most
> recently-updated records of a top-level list in one filter view — you **narrow with `filter` and sort**, you
> don't deep-paginate an unbounded set. To sweep an entire book of business you filter by date windows or
> status and collect batches. `users` (10,000) and `similarClients` (10) are the only different caps.

### 2.3 Config / meta getters

| Query field                                     | Returns                        | Purpose                                                                                            |
| ----------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------- |
| `clientMeta`                                    | `ClientMeta`                   | Client-summary metadata (`counts`, etc. — see `jobber-01`).                                        |
| `requestSettings` / `requestSettingsCollection` | `RequestSettings` / connection | Request + online-booking configuration (see `jobber-02`).                                          |
| `onlineBookingConfiguration`                    | `OnlineBookingConfiguration`   | Self-serve booking config (see `jobber-02`/`jobber-06`).                                           |
| `customFieldConfigurations`                     | connection                     | Custom-field definitions.                                                                          |
| `paymentRefundReasons`                          | list                           | All possible refund reasons for a payment.                                                         |
| `requestAuditEventActors`                       | list                           | Distinct users who changed a request/assessment/line-items/notes/forms.                            |
| `webHookEvent`                                  | `WebHookPayload!`              | **Internal** query to retrieve the payload sent to a developer when a webhook fires (for testing). |

---

## 3. The Relay connection / pagination model

Every list is a **Relay-style connection**. Using `ClientConnection` (verbatim) as the canonical shape — all
`XxxConnection` types follow it:

| Field        | Type        | Meaning                                                                                                                                                                        |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `edges`      | `[XxxEdge]` | The edge wrappers (each = `cursor` + `node`).                                                                                                                                  |
| `nodes`      | `[Xxx!]!`   | The objects directly (shortcut past edges when you don't need cursors).                                                                                                        |
| `pageInfo`   | `PageInfo!` | Pagination cursors (see below).                                                                                                                                                |
| `totalCount` | `Int!`      | _"The total count of possible records in this list. Supports filters. **Please use with caution. Using totalCount raises the likelyhood you will be throttled.**"_ (verbatim). |

**`XxxEdge`** (e.g. `ClientEdge`, _"An edge in a connection"_): `cursor: String!` (_"A cursor for use in
pagination"_) + `node: Xxx!` (_"The item at the end of the edge"_).

**`PageInfo`** (_"Information about pagination in a connection"_): `hasNextPage: Boolean!`,
`hasPreviousPage: Boolean!`, `endCursor: String` (_"When paginating forwards, the cursor to continue"_),
`startCursor: String`.

**How you page (standard Relay):** pass `first: N, after: <endCursor>` to walk forward; loop while
`pageInfo.hasNextPage`, feeding `pageInfo.endCursor` back as `after`. Cursors are opaque — never construct
them. Backward paging uses `last`/`before` with `startCursor`.

> **Two throttle traps baked into this model:** (1) **`totalCount` costs you** — the schema explicitly warns
> it raises throttle risk, so don't request it unless you need the number. (2) Deep pagination burns points
> (§7) — Jobber's own guidance is to **page in batches with a delay** rather than pull everything at once.

---

## 4. The Mutation root (write side) — full catalog

The `Mutation` type is _"The mutation root of Jobber's GraphQL interface."_ The naming pattern is rigid and
worth internalizing: **`<object><Verb>`** in camelCase — `Create`, `Edit`, `Archive`/`Unarchive`,
`Close`/`Reopen`, `Delete`, `Complete`/`Uncomplete`, plus note & line-item sub-operations. Every mutation
returns a **`<Object><Verb>Payload`** carrying the mutated object **plus a `userErrors` list** (see §5).

Below is **every mutation in the schema**, grouped by domain. (Input argument shapes are `INPUT_OBJECT`s and
are **not** introspectable — see the header note.)

### 4.1 Clients & Properties

| Mutation                                                   | Returns                          | Does                                                      |
| ---------------------------------------------------------- | -------------------------------- | --------------------------------------------------------- |
| `clientCreate`                                             | `ClientCreatePayload`            | Create a client.                                          |
| `clientsCreate`                                            | `ClientsCreatePayload`           | Create **multiple** clients at once (bulk/import).        |
| `clientEdit`                                               | `ClientEditPayload`              | Update a client by id.                                    |
| `clientArchive` / `clientUnarchive`                        | `ClientArchive/UnarchivePayload` | Archive / restore a client (**no hard-delete mutation**). |
| `clientCreateNote` / `clientEditNote` / `clientDeleteNote` | note payloads                    | Client note CRUD.                                         |
| `clientNoteAddAttachment`                                  | `ClientNoteAddAttachmentPayload` | Attach a file to a client note.                           |
| `propertyCreate`                                           | `PropertyCreatePayload`          | Create a property for an existing client.                 |
| `propertyEdit`                                             | `PropertyEditPayload`            | Modify a property.                                        |

### 4.2 Requests & Assessments

| Mutation                                                                     | Returns                                                     |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `requestCreate` / `requestEdit`                                              | `RequestCreate/EditPayload`                                 |
| `requestArchive` / `requestUnarchive`                                        | archive payloads                                            |
| `requestCreateLineItems` / `requestEditLineItems` / `requestDeleteLineItems` | line-item payloads                                          |
| `requestCreateNote` / `requestEditNote`                                      | note payloads                                               |
| `requestEditJobForms`                                                        | `RequestEditJobFormsPayload` (attach/detach form templates) |
| `assessmentCreate` / `assessmentEdit` / `assessmentDelete`                   | assessment payloads                                         |
| `assessmentComplete` / `assessmentUncomplete`                                | mark assessment complete/incomplete                         |

### 4.3 Quotes

| Mutation                                                               | Returns                       |
| ---------------------------------------------------------------------- | ----------------------------- |
| `quoteCreate` / `quoteEdit`                                            | `QuoteCreate/EditPayload`     |
| `quoteCreateLineItems` / `quoteEditLineItems` / `quoteDeleteLineItems` | line-item payloads            |
| `quoteCreateTextLineItems`                                             | text (heading/note) line item |
| `quoteCreateNote` / `quoteEditNote`                                    | note payloads                 |

> **No `quoteApprove`, `quoteConvert`, or `quoteSend` mutation exists in the schema** — approval, conversion
> to a job, and delivery are Client-Hub / web-app actions, not public mutations. (Consistent with `jobber-03`.)

### 4.4 Jobs

| Mutation                                                                               | Returns                  |
| -------------------------------------------------------------------------------------- | ------------------------ |
| `jobCreate` / `jobEdit`                                                                | `JobCreate/EditPayload`  |
| `jobClose` / `jobReopen`                                                               | close / reopen a job     |
| `jobCreateLineItems` / `jobEditLineItems` / `jobDeleteLineItems` / `jobOrderLineItems` | line-item CRUD + reorder |
| `jobCreateNote` / `jobEditNote` / `jobDeleteNote` / `jobNoteAddAttachment`             | note CRUD + attachment   |

### 4.5 Visits & scheduling (the unified "appointment" layer)

| Mutation                                                               | Returns / does                                                                        |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `visitCreate`                                                          | Add visits to a job.                                                                  |
| `visitEdit`                                                            | Update a visit by id.                                                                 |
| `visitDelete`                                                          | Delete a visit.                                                                       |
| `visitComplete` / `visitUncomplete`                                    | Mark a visit complete / uncomplete.                                                   |
| `visitEditSchedule`                                                    | Edit a visit's schedule (date/time).                                                  |
| `visitEditAssignedUsers`                                               | Edit who's assigned.                                                                  |
| `visitCreateLineItems` / `visitEditLineItems` / `visitDeleteLineItems` | per-visit line items.                                                                 |
| `updateFutureVisits`                                                   | **Update future visits for a (recurring) job** — the "apply to this and future" path. |
| `appointmentEditSchedule`                                              | Edit schedule for **any** appointment type (task, visit, assessment, event).          |
| `appointmentEditAssignment`                                            | Edit team-member assignment for any appointment (task/visit/assessment).              |
| `appointmentEditCompleteness`                                          | Mark any appointment complete/incomplete.                                             |
| `taskCreate` / `taskEdit` / `taskDelete`                               | Task (to-do) CRUD.                                                                    |
| `eventCreate`                                                          | Create a calendar event (not tied to a job).                                          |

> The `appointment*` trio is a **polymorphic scheduling API** over the unified `ScheduledItem` model (see
> `jobber-04`) — one mutation edits the schedule/assignment/completion of a task, visit, assessment, **or**
> event. Mirrors the `scheduledItems` query. This is exactly the shape our Schedule-hub rebuild is chasing
> ([[schedule-hub-rebuild]]).

### 4.6 Invoices & billing

| Mutation                                | Returns / does                                                      |
| --------------------------------------- | ------------------------------------------------------------------- |
| `invoiceCreate` / `invoiceEdit`         | Create / edit an invoice.                                           |
| `invoiceMarkAsSent`                     | Mark a draft invoice as sent (no delivery).                         |
| `invoiceClose`                          | Close an invoice (`MARK_RECEIVED` or `BAD_DEBT` — see `jobber-05`). |
| `invoiceReopen`                         | Re-open a paid/closed invoice.                                      |
| `invoiceUnmarkBadDebt`                  | Reverse a bad-debt write-off.                                       |
| `invoiceCreateNote` / `invoiceEditNote` | Invoice note CRUD.                                                  |

> **No public `paymentRecordCreate`, refund, or `invoiceSend` mutation** — recording money, refunding, and
> actually _delivering_ an invoice happen in the web app / Client Hub / Jobber Payments, not the sampled
> public schema (consistent with `jobber-05` §7). `PAYMENT_CREATE` **does** exist as a **webhook** topic
> (§6), so an app can _react_ to payments it can't _create_.

### 4.7 Catalog, tax, expenses, vehicles, users, misc.

| Mutation                                                                                                          | Returns / does                                                                     |
| ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `productsAndServicesCreate` / `productsAndServicesEdit`                                                           | Price-book product/service CRUD (returns generic `CreatePayload` / `EditPayload`). |
| `taxCreate` / `taxGroupCreate`                                                                                    | Create a tax rate / tax group.                                                     |
| `expenseCreate` / `expenseEdit` / `expenseDelete`                                                                 | Expense CRUD.                                                                      |
| `expenseUploadCreate` / `expenseUploadClose` / `expenseUploadDocumentConvert` / `…Discard` / `…Retry`             | Receipt-OCR pipeline (upload → parse → convert to Expense).                        |
| `supplierInvoiceUpload` / `supplierInvoiceDocumentRetry` / `supplierInvoiceDocumentsCreateExpenses`               | Supplier-invoice OCR → expenses.                                                   |
| `vehicleCreate` / `vehicleDelete` / `vehiclesUpdate`                                                              | Vehicle CRUD.                                                                      |
| `userEdit`                                                                                                        | Update a team member (no `userCreate` — inviting staff is a web-app action).       |
| `onMyWayTrackingLinkCreate`                                                                                       | Create an "on my way" client tracking link.                                        |
| `customFieldConfigurationCreate{Area,Dropdown,Link,Numeric,Text,TrueFalse}` / `…Edit` / `…Archive` / `…Unarchive` | Custom-field definition CRUD (one create mutation per field type).                 |
| `marketingItemMarkAsSent` / `marketingItemMarkAsFailed` / `marketingUpdateChannelProfile`                         | Marketing-content publish results + channel profile.                               |
| `appAlertEdit`                                                                                                    | Edit app alerts for an account.                                                    |
| `appDisconnect`                                                                                                   | Forcefully disconnect an account from the requesting app.                          |
| `appInstanceLastSyncDateEdit`                                                                                     | Record the app's last sync date.                                                   |
| `webhookEndpointCreate` / `webhookEndpointDelete`                                                                 | Manage webhook endpoints (§6).                                                     |

---

## 5. The `userErrors` channel (Jobber's validation contract)

Every mutation payload carries a **`userErrors`** list. Its type is **`MutationErrors`** (_"User errors that
are triggered by a mutation"_), with exactly two fields:

| Field     | Type        | Meaning                                                         |
| --------- | ----------- | --------------------------------------------------------------- |
| `message` | `String!`   | The human-readable error message.                               |
| `path`    | `[String]!` | **The field that triggered the error** (a path into the input). |

**The critical behavior:** a mutation can **succeed at the HTTP/GraphQL layer (200, no top-level `errors`) yet
still fail the business operation**, returning the failure inside `userErrors` with an empty/absent mutated
object. You must **always check `userErrors` before assuming success** — top-level GraphQL `errors` are for
malformed queries / auth / throttling; `userErrors` are for "your data was invalid." The `path` field maps an
error to a specific input field, exactly like inline form-field errors.

> This is the direct analogue of **our fixed API error shape** (`{ error, field_errors }`, CLAUDE.md Rule 15):
> `message` ↔ our `error`, and `path` ↔ our `field_errors` keys. Jobber validates the exact same way — keep
> field-level errors first-class.

---

## 6. Apps & Webhooks (event subscriptions)

### 6.1 The app model (`Application`)

An **`Application`** (_"Applications which improve Jobber's experience"_) is a third-party integration. Fields
from schema: `name`, `displayName`, `author`, `description`, `applicationScopes` (the granted scopes),
`logoUrl`, `learnMoreUrl`, `marketplaceUrl`, `manageAppUrl`, `oauthUrl`, `redirectUrl`, `beforeStartingContent`,
`installationStepsContent`, `id`. Webhooks and OAuth are configured **at the app level**, and an app is
connected **per account** by the OAuth flow (§1).

### 6.2 Webhook topics (`WebHookTopicEnum`) — from schema

Webhook topics are `{OBJECT}_{EVENT}`. **You must hold the matching read scope for a topic to receive it**
(e.g. read-clients for any `CLIENT_*`). [dev: Setting up Webhooks] Full enum (verbatim):

| Object              | Topics                                                                                 |
| ------------------- | -------------------------------------------------------------------------------------- |
| **App**             | `APP_CONNECT`, `APP_DISCONNECT`                                                        |
| **Client**          | `CLIENT_CREATE`, `CLIENT_UPDATE`, `CLIENT_DESTROY`                                     |
| **Property**        | `PROPERTY_CREATE`, `PROPERTY_UPDATE`, `PROPERTY_DESTROY`                               |
| **Request**         | `REQUEST_CREATE`, `REQUEST_UPDATE`, `REQUEST_DESTROY`                                  |
| **Quote**           | `QUOTE_CREATE`, `QUOTE_UPDATE`, `QUOTE_DESTROY`, `QUOTE_SENT`, `QUOTE_APPROVED`        |
| **Job**             | `JOB_CREATE`, `JOB_UPDATE`, `JOB_DESTROY`, `JOB_CLOSED`                                |
| **Visit**           | `VISIT_CREATE`, `VISIT_UPDATE`, `VISIT_DESTROY`, `VISIT_COMPLETE`                      |
| **Invoice**         | `INVOICE_CREATE`, `INVOICE_UPDATE`, `INVOICE_DESTROY`                                  |
| **Payment**         | `PAYMENT_CREATE`, `PAYMENT_UPDATE`, `PAYMENT_DESTROY`                                  |
| **Payout**          | `PAYOUT_CREATE`, `PAYOUT_UPDATE`, `PAYOUT_DESTROY`                                     |
| **Product/Service** | `PRODUCT_OR_SERVICE_CREATE`, `PRODUCT_OR_SERVICE_UPDATE`, `PRODUCT_OR_SERVICE_DESTROY` |
| **Timesheet**       | `TIMESHEET_CREATE`, `TIMESHEET_UPDATE`, `TIMESHEET_DESTROY`                            |
| **Expense**         | `EXPENSE_CREATE`, `EXPENSE_UPDATE`, `EXPENSE_DESTROY`                                  |
| **User**            | `USER_CREATE`, `USER_UPDATE`                                                           |
| **Marketing**       | `MARKETING_ITEM_UPDATE`                                                                |
| **On-my-way**       | `ON_MY_WAY_TRACKING_LINK_REQUEST`                                                      |

> **Notable schema note on `VISIT_CREATE`:** _"When multiple visits are created in a recurring schedule, only
> the **first** visit will notify."_ So a recurring job that generates 52 weekly visits fires **one**
> `VISIT_CREATE`, not 52 — critical if you're syncing visits to another calendar.

### 6.3 The webhook payload (`WebHookPayload`) — from schema

The POST body an app receives (_"everything is selected in this type"_):

| Field       | Type                | Meaning                                                                                                                  |
| ----------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `topic`     | `WebHookTopicEnum!` | Which event (`{OBJECT}_{EVENT}`).                                                                                        |
| `accountId` | `EncodedId!`        | The account that triggered it.                                                                                           |
| `itemId`    | `EncodedId!`        | The id of the object that changed — **you then query it for details** (the webhook carries the id, not the full object). |
| `occuredAt` | `ISO8601DateTime!`  | When the event occurred _(sic — schema spells it `occuredAt`)_.                                                          |
| `appId`     | `String!`           | The app that should receive it.                                                                                          |

### 6.4 Webhook endpoints (`WebhookEndpoint`) + delivery behavior

- **`Webhook` enum** (scope of a subscription): `APP_WEBHOOK` (app-level) vs `ACCOUNT_WEBHOOK` (account-level).
- **`WebhookEndpoint`** object (schema): `id`, `url` (_"URL to be notified at when an event for the topic
  occurs"_), `topic` (`WebHookTopicEnum!`), `app` (`Application!`), `account` (`Account!`), `createdAt`,
  `updatedAt`.
- **Managed via** `webhookEndpointCreate` (takes `WebhookEndpointCreateInput`; returns `webhookEndpoint` +
  `userErrors`) and `webhookEndpointDelete` (returns `deletedWebhookEndpoints` + `userErrors`).
- **Delivery contract (dev docs):**
  - Each request includes a **base64 `X-Jobber-Hmac-SHA256` header**, computed from your app's **OAuth client
    secret** + the payload → **verify it to authenticate the request.** [dev: Setting up Webhooks]
  - Webhooks fire when _any account with your app installed_ performs the topic action; the URL gets a POST
    with the payload body.
  - **You must respond within 1 second.** [dev: Setting up Webhooks]
  - **At-least-once delivery** — the same webhook may arrive **more than once** (e.g. a network-timeout retry).
    **Detect duplicates from the payload and handle idempotently.** [dev: Setting up Webhooks]

> This maps cleanly onto **our outbox/worker model** (CLAUDE.md Rules 9–12): treat Jobber's `itemId` +
> `occuredAt` as the idempotency key, respond fast (ack, then process async), and never trust an unsigned
> body. Our BullMQ workers already dedupe on an idempotency key — same pattern.

---

## 7. Rate limits & throttling

Two independent limiters guard the API (dev docs — no schema types exist for these; **behavioral, cited**):

1. **DDoS / request-count limiter (Rack::Attack):** **2,500 requests per 5 minutes**, enforced
   **per app+account** (not per IP). Exceeding it returns **HTTP 429 Too Many Requests** for that account.
   [dev: API Rate Limits]
2. **GraphQL query-cost limiter (leaky bucket):** every app+account has a points budget that refills over
   time. Reported throttle status: **`maximumAvailable` = 10,000 points**, `currentlyAvailable` = your
   remaining points, **`restoreRate` = 500 points** (restored per interval). A query's **cost scales with how
   much it asks for** (fields, connections, `totalCount`), and when you run out you're throttled until points
   restore. [dev: API Rate Limits]

**Jobber's own anti-throttle guidance:** page in **batches** (don't pull everything at once), add a **timed
delay** between calls so `currentlyAvailable` can refill at `restoreRate`, and **avoid `totalCount`** unless
needed (the schema itself warns it raises throttle risk). [dev: API Rate Limits]

> **Cost model (unverified specifics):** the exact per-field point costs and the precise refill interval
> aren't pinned down in the search results beyond the `10,000 max / 500 restore` figures — treat the numbers
> as the documented ceiling/rate and the _formula_ as Shopify-style complexity scoring **(unverified detail)**.

---

## 8. What is NOT in the public API (build-planning gaps)

Confirmed absences across this whole reference set — actions Jobber does **only** in its web app / Client Hub,
not via public mutations (so a competitor integrating with Jobber can't automate these, and _we_ should decide
whether to expose them):

- **No payment recording / refunding** (`paymentRecordCreate`, refund) — but `PAYMENT_*` webhooks exist.
- **No invoice/quote _delivery_** (`invoiceSend`, `quoteSend`) — only `invoiceMarkAsSent`; `QUOTE_SENT` is a
  webhook, not a mutation.
- **No quote approval / conversion** (`quoteApprove`, `quoteConvert`) — Client-Hub actions; `QUOTE_APPROVED`
  is a webhook.
- **No hard-delete for core records** — clients/requests use `archive`/`unarchive`; jobs use `close`/`reopen`;
  invoices use `close`/`reopen`. (Visits/tasks/expenses/line-items/vehicles do have `delete`.)
- **No automations API at all** — automations are 100% web-app configured (see `jobber-06`; zero schema types).
- **No `userCreate`** — only `userEdit`; inviting staff is a web-app action.

---

## 9. How WE compare (build notes)

- **`userErrors` = our `{ error, field_errors }`.** Jobber's `MutationErrors { message, path }` is exactly our
  fixed error shape (Rule 15). Keep returning field-scoped errors (`path` → `field_errors` key) on a 200-ish
  success envelope; don't throw HTTP 500s for validation failures.
- **Opaque IDs.** Jobber's `EncodedId` hides DB integers from clients. We expose UUIDs — fine, but the lesson
  is _never_ let a client enumerate or construct another tenant's id. Our RLS + `org_id` filter is the real
  guard; opaque ids are defense-in-depth.
- **The "100 recently-updated" cap is a deliberate design, not a limitation to copy blindly.** It forces
  filter-first access and protects the DB. Our list stores already page + filter (Rule 18); we don't need a
  hard 100 cap, but we **should** cap unbounded list endpoints and require a filter/date window for big sweeps.
- **`totalCount` is expensive — make counts opt-in.** Jobber warns that counting rows raises throttle risk.
  Our KPI strips (`/api/*/stats`) already compute counts server-side in dedicated endpoints — keep counts off
  the hot list path, exactly as Jobber implies.
- **Webhook discipline to match:** HMAC-sign outbound webhooks, **respond in <1s then process async**, and
  design for **at-least-once** (dedupe on a stable key). Our outbox → BullMQ pipeline already does ack-then-work
  - idempotency keys — this validates the model. Also copy the **"recurring series fires ONE create event"**
    rule so we don't spam integrators with 52 weekly-visit events.
- **Versioned API from day one.** Jobber's dated `X-JOBBER-GRAPHQL-VERSION` + 12–18 month support window is
  the gold standard for not breaking integrators. If/when we open a public API, version by date header and
  publish a changelog; never silently break a payload shape.
- **Rate-limit with a leaky bucket + cost scoring, not just req/min.** Jobber runs **both** a crude
  request-count DDoS guard (429) **and** a cost-based points bucket (10k max / 500 restore). For our future
  public API, a two-tier limiter (cheap flood guard + complexity budget) is the proven shape.
- **What to _beat_:** Jobber's public API **can't record payments, send documents, or convert quotes** — big
  gaps that force integrators back into the UI. If we expose a clean, permissioned **write** path for
  send/convert/collect-payment (through our outbox so automations still fire), that's a concrete differentiator
  for contractors who want true end-to-end automation.

---

### Sources

**Schema:** `JobberJson.md` — `Query` (root getters), `Mutation` (full mutation catalog), `MutationErrors`,
`PageInfo`, `ClientConnection`/`ClientEdge` (Relay shape), `EncodedId`, `Application`, `Webhook`,
`WebhookEndpoint`, `WebHookPayload`, `WebHookTopicEnum` (all read from the local introspection dump).

**Jobber Developer Center** (behavior, via WebSearch — WebFetch is 403-blocked on getjobber.com):

- API Rate Limits — https://developer.getjobber.com/docs/using_jobbers_api/api_rate_limits/
- API Versioning — https://developer.getjobber.com/docs/using_jobbers_api/api_versioning/
- App Authorization (OAuth 2.0) — https://developer.getjobber.com/docs/building_your_app/app_authorization/
- GraphQL queries or mutations — https://developer.getjobber.com/docs/using_jobbers_api/api_queries_and_mutations/
- Setting up Webhooks — https://developer.getjobber.com/docs/using_jobbers_api/setting_up_webhooks/
- Getting Started — https://developer.getjobber.com/docs/getting_started/
