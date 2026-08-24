# Quote behavior and architecture contract

Status: Approved by Jafar, 2026-08-19  
Owner: Quotes campaign

## Purpose and authority

This contract defines approved Quote truth from creation through customer decision, deposit readiness, Pipeline
outcome, and later Job conversion. Approval of this document does not itself authorize a migration, RLS change,
permission change, API route, or UI implementation; each implementation part still follows its approval gate.

`docs/PRODUCT.md` owns the product boundary. This contract makes that boundary precise. Jobber's current product
is evidence for proven contractor behavior, not authority over UCRM. The current Jobber help articles confirm that
quotes carry catalog or custom lines, fixed or percentage discounts, tax, deposits or payment schedules, customer
approval and signature, offline deposits, and explicit Quote-to-Job conversion. UCRM deliberately uses stronger
version integrity than Jobber: a material edit ends the old approval instead of leaving an edited Quote approved.

## Language and ownership

| Fact or side effect | Authoritative owner |
| --- | --- |
| Quote identity, number, lifecycle, current version, recipients, customer decisions, signature, expiry, deposit requirement, and conversion eligibility | Quotes |
| Reusable Product or Service defaults | Pricing catalog, introduced by Quotes and shared with Requests |
| Request scope and Request pricing before conversion | Requests |
| Immutable proposal text, pricing, client/property/branding snapshots, selections, totals, and customer-visible attachments | Quote version |
| Email/SMS transport, queueing, provider delivery, retry, bounce, complaint, replies, and message history | Communications |
| Public Quote authorization and customer commands | Quotes, through server-only secure-link endpoints |
| Provider charge, callback, settlement, refund, dispute, saved payment method, and invoice allocation | Payments |
| Quote card stage and Won/Lost projection | Pipeline, derived from Quote truth |
| Job scope, schedule, visits, and operational edits after conversion | Jobs |

A Quote is a priced proposal for exactly one organization, Client, and Property. It is either created directly or
from one Request. One Request may create at most one linked Quote in the first release, keeping Request conversion
and Task transfer unambiguous. A contractor who wants to present a different offer uses **Create similar** to make
an independent Quote for the same Client and Property; that copy does not inherit Request lineage. A later need
for multiple independent Quotes linked to one Request requires a separate approved change.

## Identity, lineage, and snapshots

- The database allocates a monotonically increasing Quote number per organization when the first draft is saved.
  A transaction locks the organization's counter, increments it once, and creates the Quote. Numbers are never
  reused after deletion, archive, failed delivery, or cancellation. Concurrent creates cannot receive the same
  number. Display prefixes and padding are presentation settings; the stored sequence remains numeric.
- `organization_id`, `client_id`, and `property_id` are required and protected by composite tenant-safe foreign
  keys. The Property must belong to the selected Client.
- Creating new work for an archived Client restores the Client, as required by the Client contract. A removed or
  archived Property cannot receive new work. Active Quotes block Client archive and Property removal until the
  Quotes are archived or converted.
- A direct Quote has no `request_id`. A Request-backed Quote keeps its Request id permanently. The atomic conversion
  copies Request pricing into Quote-version rows, transfers eligible Request Tasks, marks the Request Converted,
  and creates the Quote Opportunity. Quote and Request never share mutable pricing rows.
- The Quote keeps live foreign keys for navigation. Every published version separately snapshots the client display
  identity, service address, organization name/logo/contact details, currency, locale, tax description, and all
  customer-visible content. Later Client, Property, catalog, branding, or settings edits never rewrite a published
  version.
- A draft starts from current source data. Staff may refresh its client/property/branding snapshot before sending.
  Publishing freezes it. Correcting historical identity or address means issuing a new version, not editing history.

## Price book interaction

- Line-item editing exposes two clear actions: **Add line item** creates a custom row, and **Price book** opens a
  right-side browser for reusable Products and Services. The line Name field may also suggest price-book matches
  for staff who already know what they want.
- The Price book supports search and Product/Service filtering. Each result shows name, description, unit, and
  customer price. Internal cost appears only when the current staff member may view cost.
- Staff may add several saved items without reopening the Price book. The browser stays open, marks what was added,
  prevents accidental duplicate clicks, permits an intentional second copy, and ends through a clear Done action.
- Picking an item copies its current defaults into a new document-owned line. Staff may then change quantity,
  description, price, cost, taxability, or other line details for this customer without changing the saved item.
- Saving a custom line as a reusable item, or updating the saved item behind a linked line, is always an explicit
  action. Updating a saved item affects future additions only and never rewrites existing Request or Quote lines.
- The same Price book behavior is shared by Request and Quote line-item editors. A dedicated management screen is
  a separately gated slice. Saved-item images remain separately deferred and are not implied by this interaction.
- Staff with catalog-management permission see a settings action in the Price book browser. It opens the future
  **Settings → Price book** management page; staff who can browse but not manage the catalog do not see the action.

## Staff Quote financial rail

- The Quote detail blueprint owns placement: the right rail composes reusable **Quote summary**, **Discount**,
  **Deposit**, and **Tax** blocks. Existing Notes and Attachments remain their already-shipped shared components.
- Quote summary is read-only. It shows Subtotal, Discount, Tax, and Total. Staff with `quotes.view_cost` also see
  Cost, Estimated profit, and Margin; restricted staff and customer surfaces never receive those internal values.
- Discount, Deposit, and Tax each have two primary display states. Empty shows an explicit icon-and-label Add
  action. Configured shows the saved value plus a visible pencil and Edit action. The block surface is not an
  unlabeled hidden button.
- Add and Edit open a focused dialog with Cancel and a verb-named Save. The rail block has no inline edit state and
  updates only after the dialog saves successfully.
- The Discount dialog contains customer-facing Name (default **Discount**), Type (Percentage or Fixed amount),
  Value, and **Save discount**. Its configured state also offers **Remove discount**. The Tax dialog offers the
  effective Property/Business default, saved rates, No tax, and Custom for this Quote; custom asks for Name and
  Percentage and offers **Save as reusable tax rate** off by default. Saved-rate configuration remains separately
  gated and no unavailable Settings action is rendered early.
- The blocks share presentation and interaction contracts across approved commercial documents. Each document
  keeps its own authorization, persistence, versioning, and calculation rules; component reuse never shares
  mutable business state.

## Lifecycle

Stored Quote states are `draft`, `awaiting_response`, `changes_requested`, `approved`, `declined`, `archived`, and
`converted`. `expired`, `deposit_due`, and `ready_for_job` are derived labels, not stored states.

| From | Command and actor | Guard and stored result | Reversible and downstream effect |
| --- | --- | --- | --- |
| New | Save draft, authorized staff | Valid Client/Property; creates `draft` and its mutable draft version | Draft may be edited or archived |
| Draft | Send or Mark awaiting response, authorized staff | Draft passes document validation; atomically publishes a version and becomes `awaiting_response` | Communications delivery may follow; failed transport does not undo publication |
| Draft | Record offline approval, authorized staff | Publishes the version, records method/reason and optional in-person signature; becomes `approved` | A material revision ends this approval |
| Awaiting response | Request changes, current recipient | Current unexpired version and idempotent command; becomes `changes_requested` | Customer approval/decline controls close until staff republishes |
| Awaiting response | Approve, current recipient or authorized staff | Current unexpired version, valid selections, required signature policy satisfied; becomes `approved` | Pipeline marks only this Quote Opportunity Won; follow-ups stop |
| Awaiting response | Decline, current recipient or authorized staff | Current unexpired version; reason/note optional; becomes `declined` | Pipeline atomically marks only this Quote Opportunity Lost; it does not change other work |
| Changes requested | Revise, authorized staff | Clones the last published version into one mutable draft; becomes `draft` | Old version and request remain in history; old links are revoked |
| Changes requested | Republish unchanged, authorized staff | Explicit confirmation; same content receives a new version/link and becomes `awaiting_response` | Customer decisions bind only to the new version |
| Approved | Begin material revision, authorized staff | Explicit warning; clones a draft, revokes public links, becomes `draft` | Prior decision/signature remain immutable history but are no longer current; Pipeline Won reopens only if no Job exists |
| Declined | Revise/reopen, authorized staff | Explanation required; clones a draft and becomes `draft` | Pipeline records Reopened and returns to the Quote Draft projection |
| Any non-converted state | Archive, authorized staff | Reason required for Approved; stores prior state and becomes `archived` | Follow-ups and links stop; restoring returns to a valid prior state or Draft if the prior version is stale |
| Archived | Restore, authorized staff | Client/Property still valid and no Job exists | Records restoration; old public links stay revoked |
| Approved | Convert to Job, authorized staff | Current approval, current version, deposit readiness, no existing Job, Jobs available | One atomic Job handoff; becomes terminal `converted`; Pipeline Won becomes permanent |

`converted` never reopens, including if the Job is later deleted. Approval never creates a Job silently. A resend of
an already approved version may deliver a copy but does not ask for a second approval.

### Expiry

Expiry is optional. A Quote is derived as Expired when its current published version is awaiting a customer decision
and `expires_at` has passed in the organization's timezone. An expired link may show only a safe expired message;
it cannot approve, decline, request changes, or reveal the document. Extending expiry is customer-visible and creates
a new published version and rotated link. There is no background write merely because the clock passed.

## Versions, edits, and signatures

- A Quote has at most one mutable draft version and any number of immutable published/superseded versions. Version
  numbers are consecutive per Quote and assigned only when published. Published rows and their child rows reject
  update/delete through database guards, including privileged application mistakes.
- A publish command calculates totals, creates a canonical document hash, assigns the next version number, freezes
  the version, replaces the Quote's current published version, and revokes older links in one transaction.
- Staff read the draft while one exists and the current published version otherwise, so a Quote with nothing in
  progress still shows its lines, money, and customer copy. A published version on screen is read-only: no screen
  offers an edit the database would refuse.
- Cloning a published version into a new draft recalculates that draft, so a revision opens showing the money its
  published version showed. A version is never created with defaulted totals.
- Staff see a version named only where a publication exists. A Quote that has never been published shows no
  version number, because a draft nobody has seen is not version one.
- Material changes include client or property snapshot; currency; customer-visible lines,
  add-ons, quantities, prices, discounts, tax, deposit/payment schedule, introduction, message, terms, warranty,
  expiry, customer-view controls, organization branding, and customer-visible media or attachments.
- The first proposal-section release exposes Introduction, Client message, Contract disclaimer, and
  customer-visible attachments/images. Extra warranty or terms text belongs in Contract disclaimer until a
  separately approved section needs its own behavior.
- Internal title, salesperson/owner, private notes, expected close date, next follow-up, and recipients
  are non-material only while they do not change customer-visible output or the accepted amount.
- Quote numbers are system allocated and not editable in the first release. Internal cost is frozen when a version is
  published; correcting it does not rewrite history and waits for a deliberate new proposal version or later Job
  costing. Custom numbers and post-publication cost corrections require separately approved behavior.
- A signature belongs to one published version and one decision. It records signer name, method (`typed`, `drawn`,
  `in_person`), signed time, document hash, terms hash, recipient/contact when known, and security evidence such as
  truncated IP and user-agent. Drawn signature files remain private. Verbal approval records `offline_verbal` and
  never fabricates a signature.
- Signing is offered, not demanded. A customer may approve with a typed name, a drawn signature, or
  nothing at all, following Jobber's default; requiring a signature organization-wide is a setting, and it
  arrives with the settings surface. The staff pad is an in-person approval rather than a separate act:
  collecting a signature records the approval with method `in_person`, and from a draft it publishes the
  version first so the signature belongs to a real document.
- Material revision never deletes an old signature. It makes the old decision non-current, preserves the signed
  version, and requires a new decision/signature under the organization's current signature policy.

## Customer choices and exact money

A quote line is either work the customer has to take or an add-on they may take:

- Required lines are always included.
- Optional add-ons are independently selected by the customer. Unselected add-ons remain visible in the immutable
  version and its decision history as unselected.
- A Quote offers no Good/Better/Best packages. Alternatives are separate independent Quotes, often made with
  **Create similar** and given clear titles. Approving one never closes another automatically because the system
  cannot know whether they are alternatives or separate scopes. Staff may archive or decline the others after
  confirming with the customer.

The first release uses the organization's ISO 4217 currency from `organization_settings.currency_code`, frozen on
the Quote version. One Quote cannot mix currencies. Currency changes affect new drafts only.

- Stored money is signed `bigint` minor units, never JavaScript/Postgres floating point. Quantity is
  `numeric(12,3)` and must be positive for priced lines. Percentage, tax, markup, and margin rates use integer basis
  points, where 100 basis points equals 1%. Customer price and internal cost are separate.
- Each selected line total is `round(quantity * unit_price_minor)` to the nearest minor unit, with half values away
  from zero. Text/headings have no quantity or money.
- Selected subtotal is required lines plus selected add-ons.
- The first release supports one named Quote-level discount. Its customer-facing name defaults to **Discount** and
  may be changed to a plain label such as **Summer discount**. It is fixed or percentage, versioned, and material.
- A fixed discount is capped at the selected subtotal. A percentage discount uses the selected subtotal and rounds
  once to minor units. Following Jobber, the discount reduces the non-taxable selected subtotal first and then the
  taxable selected subtotal. Within an affected group it is allocated proportionally; leftover minor units follow
  stable line order. This makes taxable and non-taxable net amounts reproducible.
- Tax is exclusive in the first release. Each taxable line applies the version's tax basis points to its
  post-discount net amount and rounds per line. Non-taxable lines receive no tax. Inclusive tax and compound or
  multiple tax rates require a later approved extension.
- The first release uses one named tax rate or No tax. Precedence is Quote override, then Property default, then
  Business default. A Quote may choose a saved rate or enter a named custom rate. Authorized staff may explicitly
  save that custom rate for future use; the save option defaults off. The selected name and rate are frozen into
  the Quote version.
- Saved tax rates and the Business default belong to **Settings → Business → Taxes**. The Quote Tax dialog links to
  that management area. Per-line tax exemption remains a Price book/document-line default and override.
- Grand total is selected subtotal minus discount plus tax. A percentage deposit applies to that final selected
  grand total and rounds once. A fixed deposit cannot exceed the grand total.
- Internal cost and margin never affect the customer total. Margin is calculated from pre-tax, post-discount
  customer revenue minus selected line cost. Customer documents and public endpoints never include cost, markup,
  margin, or private notes.

One database calculation function owns these rules and returns the itemized calculation. API, staff UI, secure page,
PDF, Pipeline value, approval, deposit, and Job conversion consume that result. They do not reimplement arithmetic.

## Deposits and payment schedules

Approval, deposit satisfaction, and Job readiness are separate facts:

- A Quote has either no deposit requirement or one payment schedule. A deposit-only schedule has one required first
  installment. A milestone schedule has ordered fixed or percentage installments whose total equals the Quote total;
  only its first installment may be the required Quote deposit.
- The Deposit dialog first asks **Deposit only** or **Payment schedule**. Deposit only accepts a fixed amount or a
  percentage due on approval. Payment schedule accepts ordered fixed or percentage installments with descriptions.
  Organization-wide deposit presets do not ship; a later Quote template may carry its own deposit configuration.
- The requirement is versioned because add-on selection can change it. The approval decision freezes the
  selected total and exact required deposit amount.
- `deposit_satisfied_at` is derived from accepted, non-voided deposit records equaling the frozen required amount.
  A required deposit blocks `ready_for_job` and conversion until satisfied. Partial deposit recording is rejected in
  this campaign; Payments may later introduce an approved partial-payment lifecycle.
- Before online Payments exists, the customer can approve and sign but the secure page clearly says the required
  deposit must be arranged with the contractor. It shows no card, bank, or working-looking payment control.
- An authorized staff member may later record one full offline cash/check/other deposit with received date, amount,
  method, safe reference, reason, actor, and idempotency key. This creates an immutable accounting event; corrections
  use a reversing event rather than edit/delete.
- Deposit money stays linked to the Quote and approved version. Payments later owns provider state and allocation to
  Job/Invoice balances without changing the original deposit event or approved total.

## Recipients, delivery, and secure public access

- Quotes owns document recipients and their contact snapshot. Communications owns the actual To/CC message,
  delivery, retry, bounce, complaint, reply, and follow-up execution.
- CC access is link-specific and does not grant Client Portal access. Each recipient receives a separate random
  256-bit token bound to organization, Quote, version, recipient, allowed actions, and expiry.
- Only a SHA-256 token hash is stored. Raw tokens appear only in the generated URL. Resend rotates links for the
  affected recipients. Older, superseded, revoked, consumed where appropriate, or expired links return a generic
  unavailable/outdated response without client, organization, or Quote details.
- What a customer may see is defined once, in one private database function, and both readers call it: the token
  resolver for the customer and the staff preview for the office. A second builder of that payload — for preview,
  for PDF, or anywhere else — is not allowed, because the day the two drift is the day the customer copy shows
  something staff never checked.
- Public endpoints run on the server. `anon` receives no table or function access to Quote data. The server resolves
  the token hash, checks link/version/status/recipient/action scope, rate limit, and idempotency, then calls one
  narrowly scoped database command. The service key never reaches browser code or payloads.
- A link can read only its rendered customer snapshot and submit allowed commands for that version. It can never read
  catalog source rows, other recipients, private attachments, notes, costs, margins, staff identity not shown on the
  document, another version, or another tenant.
- The customer's own rail offers two actions: Approve and Request changes. Declining remains a valid customer
  transition in this contract but is not offered to them, because a Decline button gives an unsure client a
  one-click way to end a job instead of asking a question; staff record a decline after speaking to them.
  Following Jobber's client view. Jafar's call, 2026-08-21.
- Every answer, from the customer or from staff, is an immutable row bound to one published version, with the
  actor kind, the method, the message and safe evidence. Exactly one is current per Quote. A material revision
  ends the current answer without deleting it and revokes every live link in the same transaction, so nobody
  can approve the document being rewritten.
- Link expiry is enforced wherever a link is resolved or used, and an expired link is the one unavailable state
  allowed to name itself. Authoring an expiry is separate work: a valid-until date is customer-visible, so it
  belongs on the version and arrives with the send surface.
- First meaningful view is recorded once when the rendered document becomes visible, not from email security
  scanners, link previews, HEAD requests, or a token lookup. Repeated views remain activity but do not change the
  first-view time.
- Public GET and command endpoints use separate per-IP and per-token-hash limits. Responses and logs redact tokens,
  signature data, private references, and customer content. Security events keep safe hashes and reason codes.

## Staff permissions

Package entitlement and membership are necessary but never sufficient. Proposed permission keys are:

| Permission | Allows |
| --- | --- |
| `quotes.view` | Quote identity, lifecycle, client/property context, and customer-visible document fields |
| `quotes.view_price` | Customer prices, discounts, taxes, totals, and deposit requirement |
| `quotes.view_cost` | Internal cost, markup, margin, and profitability |
| `quotes.create` | Direct creation and Request conversion |
| `quotes.edit` | Draft/revision content changes, catalog use, and recipient management |
| `quotes.send` | Publish, mark awaiting, send, resend, rotate links, and extend expiry |
| `quotes.record_decision` | Offline approval, decline, in-person signature, and reopen/revise decisions |
| `quotes.record_deposit` | Record and reverse offline deposit events |
| `quotes.convert` | Convert an eligible approved Quote to a Job |

There is no separate archive permission. Archive, restore, delete-eligible-draft, and create-similar all read
`quotes.edit` — Jobber's own documented split is this coarse too (one bundled edit grant; only *seeing cost* is
split out, per `jobber-03-quotes.md` §1.1), and the commands already built (`archive_quote`, `restore_quote`)
gate on `quotes.edit`. Decided with Jafar 2026-08-21, `parts/05d-quote-utilities.md`.

Owner/admin receive all by default. Proposed defaults give Office and Sales view/price/create/edit/send/decision/
convert, Finance view/price/cost/deposit, and Field only `quotes.view` unless Jafar chooses broader access.
`quotes.view_price` and `quotes.view_cost` are enforced in read models and API payloads, not by hiding columns.
Permission keys/defaults and their RLS use require Jafar's separate schema/RLS approval.

## Proposed database architecture

This is the minimum proposed shape, not an applied schema:

| Object | Purpose and important invariants |
| --- | --- |
| `organization_quote_counters` | One row per organization; locked atomic allocation; next number never decreases |
| `catalog_items` | Organization-owned reusable Product/Service defaults; name, description, category, unit, customer price, cost, taxability, active/archive state; changes never rewrite snapshots |
| `request_pricing_lines` | Request-owned priced Product/Service and labor rows; tenant-safe Request FK; copied, never shared, on conversion |
| `quotes` | Identity, tenant/client/property/request FKs, number, internal title/owner, stored state, prior archived state, current/draft version ids, decision/deposit/conversion timestamps; unique `(organization_id, quote_number)` and partial unique Request lineage |
| `quote_versions` | Quote-owned draft/published snapshot header, version number, currency/locale/address/branding, customer copy, discount/tax, expiry, totals, document hash, publication time; one draft and unique version number per Quote |
| `quote_version_lines` | Ordered product/service/text/heading snapshots with required/optional membership, quantity, minor-unit price/cost, rates, taxability, image reference, and calculated line totals |
| `quote_version_schedule_items` | Ordered fixed/percentage payment milestones; exact approved amounts frozen by the decision |
| `quote_version_attachments` | References existing private attachment objects and customer visibility; published links are immutable |
| `quote_recipients` | Quote-owned To/CC/contact snapshot and allowed customer actions; no general portal membership |
| `quote_access_links` | Version/recipient scope, token hash, expiry, rotation/revocation, first meaningful view, last view; raw token never stored |
| `quote_decisions` | Immutable approval/change/decline/reopen facts, actor kind/id, version, canonical selection JSON, selected totals, reason/note, idempotency; at most one current approval per Quote |
| `quote_signatures` | Version/decision-bound signature metadata and private drawn-file reference; no fabricated signature for verbal approval |
| `quote_deposit_events` | Immutable offline receipt/reversal now and processor-linked events later; exact amount, method, reference, actor, version, idempotency |
| `quote_events` | Safe lifecycle/activity history; actor, event type, prior/new state, version and related message/Job ids; redacted metadata only |
| `quote_command_receipts` | Unique organization/action/idempotency key, request hash, target/result ids; identical retry returns the first result and changed payload conflicts |

All public tables use UUID ids to match the current repository, duplicate `organization_id` on tenant-owned child
rows, and use composite foreign keys `(organization_id, parent_id)` so cross-tenant links are impossible. Every
foreign key and RLS predicate receives a supporting index. Primary read indexes start with organization and match
actual access paths, including Quote list keyset pagination, current status, Client, Property, Request, number,
recipient token hash, and event history. Partial indexes cover active/non-converted work. Money checks prevent
negative prices/costs, invalid rates, impossible schedules, and totals outside signed bigint range.

Published immutability, allowed transitions, one-draft/one-current-decision rules, tenant relationships, Quote number
allocation, calculation, and idempotency are database invariants. Application services orchestrate them but cannot
bypass them. External email or payment calls never occur while database row locks are held.

## RLS and command boundary

- Enable RLS on every new public table. Authenticated SELECT policies call the repository's cached permission helper
  once per query and filter by permitted organization. Price and cost use separate protected read models or server
  projections so withheld values never enter unauthorized payloads.
- Ordinary authenticated clients receive no broad INSERT/UPDATE/DELETE grants on Quote tables. `/api/*` routes call
  narrowly granted atomic functions for creation, edits, publication, decisions, deposit recording, and conversion.
- Any necessary `security definer` command lives with an empty/explicit search path, validates `auth.uid()`, tenant
  membership, entitlement, exact permission, target ownership, and current version inside the function, has PUBLIC
  and `anon` execution revoked, and grants only the exact signature to `authenticated`.
- Public customer routes do not use authenticated-user RLS as public authorization and do not grant `anon` access.
  Server-only token resolution is the single public seam.
- UPDATE paths have both visibility and write checks. No policy trusts `user_metadata`, UI visibility, request-supplied
  organization ids, or stale JWT permission claims.

## Atomic commands and API surface

Every POST/PATCH body is validated with Zod before database access and returns `{ error, field_errors }` for user
corrections. Proposed routes are grouped by business command:

- `POST /api/quotes` and `POST /api/requests/:id/quote` create direct or Request-backed drafts.
- `GET /api/quotes`, `GET /api/quotes/:id`, and version reads return permission-shaped keyset data.
- `PATCH /api/quotes/:id/draft` edits only the mutable draft with an expected revision number.
- `POST /api/quotes/:id/publish`, `/send`, `/resend`, and `/extend` calculate/freeze/rotate atomically, then enqueue
  Communications work after commit with a durable outbox/idempotency key.
- `POST /api/quotes/:id/offline-decision`, `/archive`, `/restore`, and later `/deposit` execute explicit commands.
- `GET /q/:token` and `POST /api/public/quotes/:token/{view,changes,decline,approve}` expose only token-scoped data
  and version-bound idempotent actions.
- `GET /quotes/:id/preview` is Preview as client: a signed-in staff read of the same customer document, built by the
  same database function, with no token, no recipient and no link created by looking. It renders outside the app
  shell through the one customer renderer, its decision controls are inert, and `?print=1` opens the print dialog on
  arrival. It shows the current published version, or the draft when nothing has been published yet, so a quote can
  be checked before it is sent. Prices are withheld from its payload for a member without `quotes.view_price`.
- `POST /api/quotes/:id/convert-to-job` locks Quote then approved version in consistent order, verifies deposit
  readiness and absence of a Job, copies selected scope into Job-owned rows, records both events, and makes Converted
  terminal in one transaction.

Request-to-Quote conversion, approval, decline/Pipeline outcome, offline deposit recording, and Job conversion each
lock their target rows, check idempotency before current-state rejection, and commit all domain changes together.
Optimistic draft edits use an integer `revision`; stale writers receive Conflict and must reload rather than silently
overwriting another person's work.

## Cache and event boundaries

TanStack Query owns browser server state. Successful commands invalidate only affected keys: Quote detail/version,
Quote list/counts, Client work history, Request detail/list after conversion, Pipeline column/summary/outcomes after
stage or decision changes, and later Job detail/list after conversion. Public pages do not share staff caches.

Quote events are durable facts. Communications consumes `quote_published`, `quote_send_requested`, and follow-up stop
conditions. Pipeline consumes Quote lifecycle decisions. Jobs consumes only the explicit conversion command. Payments
later consumes the frozen deposit requirement and writes payment/deposit events through its approved seam.

## Verification required before a part closes

- Database tests prove number uniqueness under concurrency, tenant-safe FKs, one Quote per Request, published-row
  immutability, allowed transitions, terminal conversion, and idempotent replay/conflict behavior.
- Table-driven calculation tests cover fractional quantity, half-cent boundaries, fixed/percentage discounts,
  taxable/non-taxable allocation, add-ons, zero totals, maximum values, fixed/percentage deposits, and
  schedule equality. The same fixtures must pass database and TypeScript presentation tests.
- RLS tests cover every role and permission combination, cross-tenant ids, withheld price/cost, revoked membership,
  archived clients/properties, direct table writes, and every Quote child table.
- Public security tests cover random/invalid/expired/rotated tokens, recipient and version crossing, stale approval,
  replay with same/different payload, rate limits, scanner-safe viewing, log redaction, and exclusion of private data.
- Transaction tests race two sends, approvals, declines, Request conversions, deposit records, and Job conversions.
  Exactly one business result and one history event may win.
- Integration tests prove delivery failure does not corrupt Quote state, material revision revokes old links and ends
  current approval, approval stops follow-ups, required deposit blocks Job readiness, and conversion copies rather
  than references mutable scope.

## Explicit boundaries and later dependencies

- Communications must exist before real email/SMS delivery, provider status, replies, or automated follow-ups ship.
  Quotes can publish and mark Awaiting response without pretending transport succeeded.
- Payments must approve online collection, callbacks, settlement, refunds, disputes, saved methods, partial payments,
  and invoice allocation. Quotes ships no fake processor UI.
- Pipeline Part 5 resumes only after real Quote state/decision commands exist. Approval and decline must update the
  backing Quote Opportunity atomically.
- Jobs must define Job-owned snapshots before terminal conversion ships. Until then, the Quote may become Approved
  and ready, but Convert to Job remains unavailable with an honest dependency message.
- Client Portal may later unify authenticated customer access. Quote secure links remain Quote-owned and narrowly
  scoped.
- Reusable Quote templates, multiple taxes, tax-inclusive pricing, multiple currencies per
  organization, financing, custom Quote numbering, and multiple Quotes from one Request are later extensions.
- Part 4 may build and verify the immutable freeze/clone foundation without exposing a publish action. Sending and
  Mark awaiting response remain Part 5 actions and are the first staff controls that publish a version.

## Approval decisions requested

Jafar's approval of Part 1 confirms these choices together:

1. One Request creates at most one Quote; alternatives are versions and add-ons.
2. Customer-facing published versions are immutable, and material revision ends current approval.
3. Stored states exclude Expired, Deposit due, and Ready for job; those are derived facts.
4. Customer approval is separate from deposit satisfaction; offline full deposit recording is the honest pre-Payments
   path, with no partial deposit or fake online control.
5. Exact totals use minor-unit integers, quantity to three decimals, basis-point rates, per-line exclusive tax after
   discount allocation, and database-owned calculation.
6. Public links are recipient/version bound, hashed, rotated on resend, server-only, and never backed by `anon` table
   access.
7. The proposed table/function/RLS/API/permission boundaries are suitable for a later separately approved migration.

## Evidence

- `docs/PRODUCT.md` §§10 and 12
- `docs/build-sequence.md` §§3–5, 7–8, and Communications
- `docs/sales-pipeline-behavior-contract.md`
- `docs/contractor-email-contract.md`
- `docs/client-property-behavior-contract.md`
- `.codex/skills/jobber/jobber-00-overview-lifecycle.md`
- `.codex/skills/jobber/jobber-03-quotes.md`, including the August 19, 2026 live tour
- Jobber Help Center: [Quote Basics](https://help.getjobber.com/en/articles/quote-basics/), [Quote Approvals](https://help.getjobber.com/en/articles/quote-approvals/), [Discounts](https://help.getjobber.com/en/articles/discounts/), [Tax Settings](https://help.getjobber.com/en/articles/tax-settings/), [Products & Services List](https://help.getjobber.com/en/articles/products-services-list/), and [Deposits on Quotes](https://help.getjobber.com/en/articles/deposits-on-quotes/), checked August 20, 2026
- Current migrations through `20260819090000_pipeline_sales_outcomes_report.sql`, generated database types, empty
  Quote server seams, and the existing organization settings, permissions, attachments, Requests, and Pipeline model
