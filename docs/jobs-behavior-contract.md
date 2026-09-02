# Job behavior and architecture contract

Status: **Approved by Jafar on 2026-09-01** — Jobs campaign Part 3
Owner: Jobs campaign

## Purpose and authority

This contract defines approved Job truth from creation through visits, billing configuration, completion,
cancellation, and invoice handoff. Approval of this document does not itself authorize a migration, RLS change,
permission change, API route, or UI implementation; each later part still passes its own approval gate.

`docs/PRODUCT.md` §§13–16 owns the product boundary. This contract makes that boundary precise.
`docs/quote-behavior-contract.md` owns everything before conversion and is the pattern this contract follows:
integer money, database-owned calculation, tenant-safe composite keys, narrow atomic commands, and permission
enforcement in the database. Jobber is evidence for proven contractor behavior, not authority over UCRM.

Evidence: [live tour and coverage](../Design/Jobber%20Jobs/2026-08-31/README.md),
[official behavior research](research/jobber-jobs-official-behavior-2026-08-31.md),
[approved direction](research/jobs-discovery-and-proposal.md) (Part 2, approved 2026-09-01).

## Language and ownership

| Fact or side effect | Authoritative owner |
| --- | --- |
| Job identity, number, type, lifecycle state, scope lines, price basis, billing configuration, and Quote lineage | Jobs |
| A visit: its schedule shape, assignment, per-visit items, instructions, and completion | Jobs, through Job-owned Visit rows |
| Recurrence rule, generation of visits, and edit scopes | Jobs |
| Calendar presentation, drag-to-reschedule, routes, conflicts, and the anytime/backlog lanes | Schedule, reading Visit truth without copying it |
| Approved proposal content, published versions, customer decision, signature, and deposit requirement | Quotes; immutable after conversion |
| Invoice documents, issue/due dates, delivery, balances, and payment allocation | Invoices and Payments |
| Provider charge, callback, settlement, refund, dispute, and saved methods | Payments |
| Email/SMS transport, client reminders, on-my-way messages, and follow-ups | Communications |
| Triggered follow-ups from Job facts | Automation, consuming Job events from the existing event spine |
| Notes, tags, and attachments | The existing shared notes/tags/attachments subsystem, extended to Job and Visit targets |
| Labor time, expenses, and job costing inputs | Jobs Part 14, inside this contract's permission rules |

A Job is one agreed piece of work for exactly one organization, Client, and Property. A Visit is one calendar
occurrence of doing that work. **The Job is the agreement; the Visit is the appointment.** Money, scheduling, and
field records never collapse into one state machine.

## Identity, lineage, and snapshots

- The database allocates a monotonically increasing Job number per organization when the Job is first saved, using
  the same locked-counter pattern as Quotes. Numbers are never reused after close, archive, or deletion, and two
  concurrent creates can never receive the same number.
- `organization_id`, `client_id`, and `property_id` are required and protected by composite tenant-safe foreign
  keys. The Property must belong to the selected Client.
- Creating a Job for an archived Client restores the Client, per the Client contract. A removed or archived Property
  cannot receive new work. Active Jobs block Client archive and Property removal.
- A direct Job has no `quote_id`. A converted Job keeps its Quote id and approved version id permanently. At most
  one Job per Quote, enforced by a partial unique index, mirroring the one-Quote-per-Request rule.
- Conversion **copies**, never references, the accepted version's selected lines into Job-owned rows. Later Job
  edits never touch Quote history, and later Quote history can never rewrite Job scope. The Quote becomes terminal
  `converted` in the same transaction.
- The Job keeps live foreign keys to Client and Property for navigation. Customer-facing documents that must freeze
  identity are Invoices; the Job itself is a working record and reads current Client and Property data.

## Job type and scheduling model

Three shapes, matching Jobber and PRODUCT §13:

| Type | Meaning | Visits at creation |
| --- | --- | --- |
| One-off | A single job with one or more dates, no repetition | One by default, up to 20 in the create flow |
| Recurring | Repeating service or ongoing billing on a rule | Generated from the rule, previewed before save |
| Recurring, as-needed | An ongoing agreement dispatched when work is needed | **Zero.** No placeholder visit is manufactured |

Following Jobber, **job type is chosen at creation and cannot be switched afterwards.** The create form states this
before save. Changing the arrangement means a new Job, and **Create similar** carries title, type, schedule shape
without times, team, billing, and items forward.

A Visit has one of three schedule shapes, and editing converts freely between them:

| Shape | Stored | Reads as |
| --- | --- | --- |
| Scheduled | date and start time, optional end | A timed appointment |
| Anytime | date, no time | Work owed that day, shown in the anytime lane |
| Unscheduled | no date | Backlog work that still needs a date |

Derived operational labels, never stored: Upcoming, Today, Late, Completed. A Visit stores only its schedule fields
plus `completed_at`; the clock passing never writes a row.

## Job lifecycle

Stored Job states are `active` and `closed`. Deletion is not a state — it removes the record. Everything Jobber
shows as a status that we can compute, we compute:

| Label | Derived from |
| --- | --- |
| Upcoming / Today / Late | The Job's next incomplete Visit against today in the organization's timezone |
| Unscheduled | Active Job whose incomplete Visits have no dates |
| Action required | Active Job with no incomplete Visit remaining |
| Requires invoicing | Job with an outstanding invoice reminder or uninvoiced completed billable work |
| Archived | `closed` with nothing left to invoice |
| Ending soon | Recurring contract end date approaching, from the rule, not the last Visit |

| From | Command and actor | Guard and stored result | Downstream effect |
| --- | --- | --- | --- |
| New | Create job, `jobs.create` | Valid Client/Property, valid type and schedule; allocates the number and creates the Job and its Visits in one transaction | Emits `job_created`; a booking confirmation is a separate explicit choice |
| Approved Quote | Convert to job, `quotes.convert` | Current approval, deposit satisfied, no existing Job; copies scope | Quote becomes terminal `converted`; the deposit stays owned by Quotes and applies to the first Invoice |
| Active | Complete visit, `jobs.complete` | Visit belongs to the Job and is not already complete | Stamps `completed_at`; may make the Job Action required or Requires invoicing; emits `visit_completed` |
| Active | Close job, `jobs.close` | Explicit consequences preview acknowledged | Becomes `closed`; incomplete Visits are removed or completed per the preview's choice; emits `job_closed` |
| Closed | Reopen, `jobs.close` | Client and Property still valid | Returns to `active`. Removed Visits do **not** regenerate; scheduling is an explicit action |
| Active or closed | Delete, `jobs.delete` | Typed confirmation naming the visit count; refused when Invoices exist | Permanently removes the Job and its Visits |

Creating an Invoice never closes a Job. Closing a Job never sends anything and never charges anyone. Cancelling is
not a separate state: it is Close with the incomplete work removed, presented honestly (below).

**Improvement over Jobber, approved by Jafar 2026-09-01:** one consequences preview for Close and Cancel that
shows, together, the incomplete Visits affected, the completed work that stays, outstanding billing and reminders,
and any configured client messages or automatic charges that would still fire. Jobber makes the contractor discover
these in separate places.

## Scope, pricing basis, and money

- Job scope lives in Job-owned line items: ordered product, service, and text rows with quantity, customer price,
  internal cost, taxability, and optional image reference. Up to 100 lines, matching Jobber. Editing them never
  touches the price book item or any Quote version.
- Money rules are the Quote rules, unchanged: signed `bigint` minor units, `numeric(12,3)` quantity, basis-point
  rates, per-line exclusive tax after proportional discount allocation, one rounding pass. **One database
  calculation function owns Job arithmetic and shares the Quote fixture set**; no route, screen, or PDF recomputes it.
- Price basis is explicit and stored on the Job:

| Basis | Available for | Plain summary shown before save |
| --- | --- | --- |
| Job total | One-off | "$2,400 for the whole job" |
| Per visit | Recurring | "$120 per completed visit" |
| Fixed per billing period | Recurring | "$500 each month regardless of visit count" |

- Under per-visit pricing, a Visit may carry its own item quantities and those flow to the invoice for those dates.
  Under fixed-period pricing they do not, following Jobber. Switching basis on an existing Job is allowed, shows what
  it changes, and never rewrites an issued Invoice.
- A one-off Job may carry one payment schedule of ordered fixed or percentage installments totalling the Job total,
  the same shape as the Quote schedule. Each installment becomes an Invoice through an explicit action. Issued
  installments are not editable from the Job.
- A converted Job's totals open equal to the approved Quote total. A later scope change is a Job fact and does not
  reopen or contradict the Quote.

## Billing timing and collection, kept separate

Three distinct decisions, never merged into one selector:

1. **How is it priced?** The basis above.
2. **When do we invoice?** On closure, per completed visit, at month end, on custom dates, or manually with no
   reminders. One-off closure reminders default on, matching Jobber.
3. **How is payment collected?** Manual collection today. Automatic charging is owned by Payments, ships with
   Payments, and is never enabled as a side effect of choosing a billing frequency.

Invoice reminders are **internal prompts for our team**, not messages to the client. The UI labels them
"Remind our team to invoice". A due reminder is what puts a Job in Requires invoicing; clearing it means creating the
Invoice or deleting the reminder. Chasing the customer for payment belongs to Invoices and Communications.

## Visits and edit scope

- Visits are created individually, in bulk from a date range or picked dates (max 20 per operation), or generated
  from a recurrence rule with a previewed count and first and last dates. Each Visit has its own title, schedule,
  assignment, and instructions, with a copy-to-all action.
- Recurrence supports weekly, biweekly, monthly, annual, multiple weekdays, and ordinal weekdays, ending on a date or
  after a duration, plus as-needed. The contract start date is separate from the first matching appointment.
- Edit scopes are distinct and named where the change is made:

| Scope | Does |
| --- | --- |
| This visit | Changes one occurrence only |
| Future unfinished visits | Copies **time of day** and **assigned team** forward onto later incomplete Visits |
| All unfinished visits | Replaces the recurrence rule; removes and regenerates incomplete Visits |

- **Completed Visits are never regenerated, moved, or deleted by a schedule change, and that protection lives in the
  database, not only in the screen.** Direct writes to `job_visits` are revoked from `authenticated`; the commands
  scope every schedule write to `completed_at is null`; and a trigger refuses to change a completed Visit's schedule
  or to delete one on its own, while still allowing the Job's own deletion to cascade.
- Changing the recurrence rule is a guarded action and lives only in **Edit all visits**. It is never offered as a
  checkbox inside the smaller future-update dialog, because the same destructive change must not exist behind a door
  that shows no consequences.
- Regeneration **discards the custom details of the incomplete Visits it replaces**, following Jobber, Housecall Pro,
  and ServiceTitan. The confirmation says so in those words before it runs. Automatically preserving customised
  Visits is a deliberate non-goal for now; see the deferred decisions below.
- Regeneration replaces **every incomplete Visit of the Job, past-dated ones included**, not only upcoming ones.
  Verified 2026-09-01 against four sources that agree and carry no past/future qualifier: Jobber's own in-product
  warning, captured at `Design/Jobber Jobs/2026-08-31/47-regenerate-warning-three-visits.png` — *"I understand that
  rescheduling will delete all incomplete visits and recreate them using the visit details above. This action cannot
  be undone."*; the Jobber Visits help article — *"all incomplete visits will be cleared and new visits will be
  created"*; the Jobber Job Basics help article — *"Updates made here apply to all incomplete visits in the job."*;
  and our own tour notes in `.claude/skills/jobber/jobber-04-jobs-visits-scheduling.md`. Where Jobber does want a
  past/upcoming distinction it says so explicitly — it draws that line when **closing** a Job, not when
  rescheduling one.
- Before a regeneration the user sees, in plain words, that incomplete Visits will be removed and recreated with
  their custom details lost, and that completed Visits remain. Exact counts are shown when the existing recurrence
  preview already yields them; no separate counting machinery is built for them.
- Bulk move by day offset, bulk delete, visit duplication into the same Job, and return visits are preserved.
  Deleting a Visit affects that Visit only; deleting a Job removes all of its Visits and says so first.
- Completing the final Visit of a one-off Job asks one question — is all work finished? — offering Finish job, Add a
  return visit, or Keep open. Invoice now or later is a separate answer.
- Arrival window is a Job-level setting with an organization default and a per-job override, applying across the
  Job's visits. Untimed and unscheduled work does not expose it.

## Field records

Notes, tags, and attachments reuse the shipped shared subsystem by extending its `entity_type` check to `job` and
`visit`; no parallel tables. Checklists, signatures, time entries, and expenses arrive in Parts 14–15 and inherit
this contract's permission and tenant rules.

Following Jobber's documented behavior, a required checklist answer produces a **warning and visible outstanding
work, not a hard block** on completing a Visit. Partial checklist answers save. Signature capture attaches a Job PDF
to the Job's notes rather than inventing a new record type.

## Costing

Costing compares revenue against item cost, labor, and expenses, and is internal. One-off costing spans the whole
Job; recurring costing covers a labelled trailing period. Screens always name the period and never present costs to
date as cash received. Changed labor rates apply forward only. The same material recorded as both an item cost and
an expense is double counting; the UI warns rather than silently reconciling.

## Staff permissions

Entitlement and membership are necessary, never sufficient. Proposed keys, following the Quotes precedent that only
money is split finely:

| Permission | Allows |
| --- | --- |
| `jobs.view` | Job identity, type, lifecycle, client and property context, scope names, and schedule |
| `jobs.view_price` | Customer prices, discounts, taxes, totals, payment schedule, and billing configuration |
| `jobs.view_cost` | Internal cost, labor cost, expenses, profit, and margin |
| `jobs.create` | Direct creation and Quote conversion (with `quotes.convert`) |
| `jobs.edit` | Scope, billing configuration, details, notes and attachments, create similar |
| `jobs.schedule` | Create, move, assign, and delete Visits, and change recurrence |
| `jobs.complete` | Complete and un-complete Visits |
| `jobs.close` | Close, cancel, and reopen a Job |
| `jobs.delete` | Permanent deletion |

Owner and admin receive all. Proposed defaults: Office and Sales get view, price, create, edit, schedule, complete,
and close; Finance gets view, price, and cost; Field gets `jobs.view` and `jobs.complete` only. `jobs.view_price` and
`jobs.view_cost` are enforced **in the database**, not only in read models: `authenticated` holds no SELECT grant on
money columns of `jobs`, `job_line_items`, `job_visit_line_items`, or `job_payment_schedule_items`, which reach a
route only through protected read models that apply the permissions themselves. A money column added later stays
unreadable until it is named in a grant on purpose.

## Proposed database architecture

Minimum proposed shape, not an applied schema:

| Object | Purpose and important invariants |
| --- | --- |
| `organization_job_counters` | One row per organization; locked atomic allocation; never decreases |
| `jobs` | Identity, tenant/client/property/quote FKs, number, title, type, stored state, price basis, billing timing, arrival window, instructions, contract start and end, closed and reopened timestamps; unique `(organization_id, job_number)`; partial unique `quote_id` |
| `job_line_items` | Ordered Job-owned scope rows; quantity, minor-unit price and cost, taxability, image reference, line totals; max 100 per Job |
| `job_recurrence_rules` | One optional rule per recurring Job: frequency, interval, weekdays, ordinal pattern, start, end date or duration, as-needed flag |
| `job_visits` | Job-owned occurrence: nullable date, start and end, title, instructions, `completed_at`, completed_by, source (generated, manual, return, duplicated); tenant-safe composite FK to the Job |
| `job_visit_assignments` | Visit-to-member assignment; unique per member and visit |
| `job_visit_line_items` | Optional per-visit item quantities under per-visit pricing only |
| `job_payment_schedule_items` | Ordered fixed or percentage installments totalling the Job total; issued installments are locked |
| `job_invoice_reminders` | Internal prompts: due date, rule origin, owner, completed state; drives Requires invoicing |
| `job_events` | Safe lifecycle and activity history: actor, event type, prior and new state, related visit/invoice/quote ids; redacted metadata; feeds the existing Automation event spine |
| `job_command_receipts` | Unique organization, action, and idempotency key; an identical retry returns the first result and a changed payload conflicts |

UUID ids, `organization_id` duplicated on every child row, composite `(organization_id, parent_id)` foreign keys so a
cross-tenant link is impossible, and a supporting index behind every foreign key and RLS predicate. Primary read
indexes start with organization and match real access paths: Job list keyset pagination, derived-status filters,
Client, Property, Quote lineage, number, and the Schedule's bounded date-window read of `job_visits`. Partial indexes
cover active Jobs and incomplete Visits. Check constraints prevent negative money, invalid rates, an installment set
that does not total the Job, a timed Visit without a date, and per-visit items under fixed-period pricing.

Job number allocation, type immutability, allowed transitions, completed-Visit protection, one Job per Quote, scope
copying on conversion, calculation, and idempotency are **database invariants**. Application services orchestrate
them and cannot bypass them. No external email or payment call happens while row locks are held.

## RLS and command boundary

- RLS on every new table. Authenticated SELECT policies call the repository's cached `private.has_permission` helper
  once per query and filter by permitted organization.
- Ordinary authenticated clients get no broad INSERT, UPDATE, or DELETE grants on Job tables. `/api/*` routes call
  narrowly granted atomic functions.
- Any `security definer` command has an explicit empty search path, validates `auth.uid()`, membership, entitlement,
  exact permission, and target ownership inside the function, revokes PUBLIC and `anon`, and grants only its exact
  signature to `authenticated`.
- UPDATE paths carry both visibility and write checks. No policy trusts `user_metadata`, UI visibility,
  request-supplied organization ids, or stale JWT claims.

## Atomic commands and API surface

Every POST and PATCH body is validated with Zod before database access and returns `{ error, field_errors }`.

- `POST /api/jobs` creates a Job with its initial Visits in one transaction.
- `POST /api/quotes/:id/convert-to-job` stays the Quote-owned command already specified in the Quote contract; it
  calls the Job creation function inside the same transaction.
- `GET /api/jobs` and `GET /api/jobs/:id` return permission-shaped keyset data with derived status labels computed
  once, in the database.
- `PATCH /api/jobs/:id` edits Job details, scope, and billing configuration with an expected `revision`; a stale
  writer gets Conflict and reloads.
- `POST /api/jobs/:id/visits`, `PATCH /api/jobs/:id/visits/:visitId`, `DELETE …`, and
  `POST /api/jobs/:id/visits/bulk-move` handle scheduling, each taking an explicit edit scope.
- `POST /api/jobs/:id/visits/:visitId/complete` and `/uncomplete` are idempotent per visit.
- `POST /api/jobs/:id/close`, `/reopen`, and `DELETE /api/jobs/:id` execute lifecycle commands after their
  consequences preview, which is itself a read endpoint returning exactly what the confirm dialog shows.
- `POST /api/jobs/:id/invoice` hands off to Invoices when that subsystem exists; until then it is absent, not faked.

Each command locks its target rows in a consistent order, checks idempotency before current-state rejection, and
commits all domain changes together.

## Cache and event boundaries

TanStack Query owns browser server state. Successful commands invalidate only affected keys: Job detail, Job list and
counts, Schedule windows containing changed Visits, Client work history, Quote detail after conversion, and later
Invoice keys. Job events are durable facts consumed by Automation and by Invoices; no subsystem polls Job tables.

## Verification required before a part closes

- Database tests: number uniqueness under concurrency, tenant-safe FKs, one Job per Quote, type immutability,
  allowed transitions, completed-Visit protection under every edit scope, and idempotent replay and conflict behavior.
- Calculation tests reusing the Quote fixtures, plus per-visit and fixed-period revenue and installment totals.
- RLS tests over every role and permission combination, cross-tenant ids, withheld price and cost, revoked
  membership, archived Client or Property, and direct table writes.
- Transaction tests racing two conversions, two completions, two closes, and two bulk moves. Exactly one business
  result and one history event may win.
- Integration tests proving conversion copies rather than references, that closing sends nothing, and that reopening
  does not resurrect deleted Visits.

## Explicit boundaries and later dependencies

- Invoices and Payments must exist before invoice generation, progress invoicing, automatic charging, or
  payment-failure handling ship. Until then a Job may reach Requires invoicing honestly and say the next step is not
  available yet.
- Schedule owns the calendar; Jobs owns Visit truth. Neither duplicates the other's rows.
- Communications owns visit reminders, on-my-way, and confirmations. Automation owns triggered follow-ups.
- Checklists, signatures, time, expenses, costing exports, supplier-document costing, chemical records, route
  optimization, dispatch, batch as-needed visit creation across many Jobs, and mobile and offline behavior keep
  explicit owners in Parts 12–16 or their dependency campaigns. Appearing later is not dropping them.
- **Deferred schedule-editing decisions, recorded 2026-09-01 rather than implemented.** Each is a product decision to
  revisit, not an oversight: automatic preservation of customised Visits across a regeneration; switching a scheduled
  recurring Job to as-needed; switching an as-needed Job to a real schedule (the database currently makes
  `is_as_needed` immutable, so this is not a free by-product of the editor); collision handling when a regenerated
  date already carries a Visit; and seasonal pause and resume of a recurring Job.
- Still unverified live and therefore not settled as implementation requirements: completed-visit pricing after Job
  item edits, deletion impact on invoices, deposits and expenses, reopen regeneration, progress-invoice customer
  presentation, and checklist completion blocking. Resolve each inside the part that codes it.

## Approval decisions requested

Approving this contract confirms these together:

1. The Job is the agreement and the Visit is the appointment; scheduling, billing, and field records stay separate.
2. Job type is fixed at creation, as-needed creates no visits, and there is no draft Job state.
3. Stored states are only `active` and `closed`; Upcoming, Today, Late, Unscheduled, Action required, Requires
   invoicing, Archived, and Ending soon are derived.
4. Cancelling is Close with one honest consequences preview rather than a separate status.
5. Price basis, invoice timing, and payment collection are three separate decisions, and invoice reminders are
   internal prompts labelled as such.
6. Conversion copies the approved Quote scope into Job-owned rows, one Job per Quote, and never rewrites Quote
   history.
7. Completed Visits are protected from every schedule change **by the database**, and regeneration discards the
   custom details of the incomplete Visits it replaces, matching Jobber, Housecall Pro, and ServiceTitan.
8. The proposed table, function, RLS, API, and permission boundaries — including `jobs.view_price` and
   `jobs.view_cost` enforced in the database — are suitable for a later, separately approved migration.
