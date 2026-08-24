# Part 2: Pricing Foundation and Request Carry-forward

## Outcome

Create the smallest secure pricing foundation that lets staff maintain reusable Product/Service defaults, add priced
Product/Service and Labor rows to a Request, and atomically convert one Request into one Quote-owned draft snapshot
with exact totals and no shared mutable history.

Part 2 does not publish, send, approve, sign, decline, collect a deposit, project Quote Pipeline stages, or convert a
Quote to a Job.

## Approval boundary

`docs/quote-behavior-contract.md` is approved product and architecture truth. Part 2 still requires Jafar's explicit
approval of its concrete schema, RLS, permission, API, and implementation plan before code or migrations change.

## Approved behavior

- Catalog items are organization-owned reusable defaults, not historical work rows. A catalog edit affects future
  additions only.
- Catalog items support Product or Service category, name, description, unit label, customer unit price, internal
  unit cost, default taxability, active/archive state, and stable sort/search behavior. Labor uses Service category
  with a labor presentation role rather than a second pricing engine.
- Requests own ordered pricing rows. Staff may add an active catalog item or a custom row, then edit its snapshot
  without changing the catalog.
- Customer money and internal cost use signed bigint minor units; quantity uses `numeric(12,3)`; percentage/rate
  values use integer basis points. Floating point is forbidden in persistence and calculation.
- One database calculation contract computes line totals and Request subtotal using the approved rounding rule.
  Part 2 has no packages, add-ons, discounts, tax amount, deposits, or payment schedules; its rows preserve the fields
  later Quote versions need.
- Converting a Request locks it, rejects terminal/invalid state, allocates one Quote number, creates one Quote and one
  mutable draft version, copies Client/Property/organization/currency/address context and every Request pricing row,
  transfers eligible Tasks, marks the Request Converted, creates the Quote Opportunity identity needed later, and
  returns the same result on an identical idempotent retry.
- A unique tenant-scoped Request lineage prevents two Quotes even under concurrent conversion. A retry with a changed
  payload conflicts rather than returning the earlier result.
- Quote draft rows are owned by Quotes after copying. Later Request/catalog/property changes cannot change them.
- Existing Request behavior without pricing remains valid; an empty-priced Request may convert to a zero-subtotal
  draft only when the API makes that state explicit rather than fabricating $0 line items.

## Proposed implementation slice to validate before approval

- Add only the Part 2 columns/tables from the approved architecture: Quote counter, catalog items, Request pricing
  rows, minimal Quote identity, draft version header, and draft version lines. Defer recipients, links, decisions,
  signatures, deposits, events not required for conversion, and published-version machinery.
- Add tenant-safe composite foreign keys, checks, foreign-key indexes, catalog search/list indexes, Request row-order
  indexes, Quote number uniqueness, one-Request lineage, and one-draft constraints.
- Add permission keys for catalog/Request pricing and the minimal Quote create/view/edit surface only after checking
  the current role catalog. Do not seed later send/decision/deposit/convert-to-Job permissions.
- Use RLS on every public table, cached permission helpers, and narrowly granted database commands. Direct public
  table writes must not bypass conversion or snapshot invariants.
- Add Zod schemas and `/api/*` routes for catalog CRUD/archive, Request pricing replacement/editing, and atomic
  Request-to-Quote conversion. Keep the empty Quote validation/repository/service seams deep and explicit.
- Regenerate `src/lib/database.types.ts` only from the approved applied schema workflow.
- Add Request Product & Services and Labor UI only after the database/API slice passes. Reuse current Request forms,
  shared table/input/button patterns, SCSS/BEM, Tabler icons, Svelte 5 runes, and TanStack Query invalidation.

## Browser verification findings (2026-08-20) — block closing this part

Verification of the "Applied UI slice" below surfaced two problems. Full detail lives in `NOW.md` at the
time they were found; this is their permanent record.

1. **Qty input can't take a decimal.** `RequestPricingBlock.svelte` lines 262-273 (Products) and ~379-390
   (Labor): the `Input` uses a Svelte 5 get/set `bind:value` pair that round-trips every keystroke through
   `Number()`. Typing `1`, `.`, `5` produces `51` — the getter hands the DOM back a decimal-free string mid-
   edit, wiping the `.` and resetting cursor position. The field is meant to take decimals (`step="0.001"`,
   DB column `numeric(12,3)`) so this is a bug, not a design choice. Fix after item 2, since item 2 touches
   the same inputs.
2. **Line-item layout doesn't match Jobber.** Jafar toured a live quote
   (`https://secure.getjobber.com/quotes/63225286`) and confirmed our single-row `DataTable` per line
   doesn't match Jobber's two-row card (Name/Qty/Unit price/Total/delete on row 1; Description textarea +
   image-upload box on row 2; drag handle once 2+ lines exist). Full spec written up in
   `.claude/skills/jobber/jobber-03-quotes.md` §8.1 — read that before rebuilding. Jafar approved, this
   session: build image attachment now (reuse the existing polymorphic `public.attachments` table rather
   than a new column type — extend its `entity_type` check constraint, add a single nullable reference on
   `request_pricing_lines`; not yet designed — figure out draft/unsaved-line upload timing before writing
   the migration, and load `supabase-postgres-best-practices` first) and use a small drag library (Jafar
   named `svelte-dnd-action`; native HTML5 drag was rejected — no touch/mobile support). Applies to both
   Products/Services and Labor blocks (one component, one save call). Does **not** change Labor's manual-
   entry model itself — real Jobber Requests auto-populate Labor from timesheets instead, a known, deliberate
   divergence, out of scope here.

## Session 2 findings and rebuild (2026-08-20)

Two problems found live in the browser, both approved and code-complete, **neither browser-verified yet**:

1. **Decimal-quantity bug and layout mismatch.** `RequestPricingBlock.svelte` rendered one `DataTable` row
   per line; Jobber's real card is two rows (name/qty/price/total + a "…" Delete menu, then description +
   an image square, drag handle once 2+ lines) per §8.1. The quantity field's old get/set `bind:value` also
   round-tripped every keystroke through `Number()`, stripping a typed "." mid-edit.
2. **No manual Labor section, full stop.** Jafar toured the live app, saw a separate typed "Labor" block next
   to "Products and services," and flagged it as not matching Jobber: a Quote has no Labor section at all
   (just Service-category lines); a Request's Labor section in real Jobber is read-only, auto-filled from
   time tracking, never typed. Approved fix: drop the manual Labor block entirely, one merged "Products and
   services" section, a crew's time priced as a plain Service line. `is_labor` stays in the schema (existing
   rows, future real time-tracking Labor) but the UI no longer sets or shows it.

**Migration applied:** `20260820040150_request_pricing_line_images`.

- `attachments` gets `unique (organization_id, id)` so other tables can reference it tenant-safely.
- `request_pricing_lines.image_attachment_id` — live FK to `attachments(organization_id, id)`,
  `on delete set null`. The browser uploads the photo the moment it is picked (existing presign → R2 →
  `POST /api/attachments` flow, reused as-is, scoped to `entity_type = 'request'`, `entity_id` = the
  Request), holds the returned id in the draft line same as name/price/qty, and Save resends it.
- `quote_version_lines.image_attachment_id` — **not** a foreign key, on purpose, mirroring
  `source_catalog_item_id`: a Request-side attachment deletion (from the Request's own, unrelated
  Attachments card) must never reach into a Quote's already-converted, frozen line.
- `replace_request_pricing_lines` validates any `image_attachment_id` in a line's JSON belongs to this
  org, `entity_type = 'request'`, and this Request's `entity_id` before accepting it (`23514` otherwise) —
  a line cannot claim someone else's uploaded file.
- `convert_request_to_quote`'s copy `insert … select` carries `image_attachment_id` across like every other
  column. This was rewritten from the real applied function body (read from
  `20260820002553_quotes_request_conversion.sql` directly, not reconstructed from memory) with only that one
  column added — do not treat it as a redesign.
- Orphan cleanup (Jafar's explicit call): best-effort, not deferred. Removing a line's photo, deleting the
  line, or hitting Cancel deletes any attachment uploaded *during that edit session* that never got saved
  (`RequestPricingBlock.svelte`'s `uploadedThisSession` set + `discardIfOrphaned`). A photo that was already
  on a saved line before the session started is never auto-deleted this way.
- **Not yet updated:** `supabase/tests/database/quotes_pricing_foundation.sql` still says `plan(92)` with no
  assertions for `image_attachment_id` validation or carry-forward. Do this before closing Part 2.

**UI rebuild applied**, `src/lib/components/quotes/RequestPricingBlock.svelte` — full rewrite:

- One `SectionBlock` ("Products and services"), no second Labor block. Each line is a two-row `.pricing-card`
  (not a `DataTable` row): row 1 is `CatalogItemPicker` name / `QuantityInput` / `MoneyInput` / computed
  total / a `DropdownMenu` holding only Delete; row 2 is a `Textarea` description + a 72×72 image square.
  Drag-reorder via `svelte-dnd-action`'s `dragHandleZone`/`dragHandle` (new dependency), handle shown only
  once `draftLines.length > 1`, `animate:flip`. Read (non-editing) state renders the same card shape,
  read-only, description/photo only shown when present.
- New `src/lib/components/forms/QuantityInput.svelte` — same draft/blur-commit shape as `MoneyInput.svelte`
  (typing lives in local text state; the bound number only updates on blur), fixing the decimal-strip bug at
  its root rather than patching the old inline get/set binding.
- Image upload reuses `$lib/collaboration/api.ts` wholesale (`presignAttachmentUpload`,
  `uploadAttachmentFile`, `createAttachment`, `deleteAttachment`, `attachmentImageUrl`) and
  `createImageThumbnail` — no new upload code, same flow `AttachmentsCard.svelte` already uses, just one
  file per line instead of a queue, and immediate (not staged-until-save).
  `CatalogItemPicker`'s `labor` prop is now optional (`fetchCatalogItems`/`catalogItemsKey` too) — omitting
  it searches the whole price list, since there is no Labor half to split any more.
- **Not done yet, Jafar asked for it this session:** every line-item input (Name, Qty, Unit price,
  Description) should show a real `label`, not placeholder text. `QuantityInput`/`MoneyInput`/`Textarea`
  already accept `label` — just pass one. `CatalogItemPicker` has no label support yet; add it (mirror
  `ui/Input.svelte`'s floating-label markup/CSS since it's a custom combobox, not built on `Input`).
- **Not verified yet:** after this rebuild Jafar said live "the UI is not matching with Jobber" and asked to
  pause before finding out exactly what. Next session must open the real quote
  (`https://secure.getjobber.com/quotes/63225286`) beside the local Request page and fix whatever the
  screenshots show — do not assume the rebuild is correct just because it is code-complete.
- `npm run check`, prettier, and the full unit suite (690/690, one test's expected payload updated for the
  new `image_attachment_id` field) are all clean as of this session. **The `performance-review` skill was not
  run for any of this session's layers before the pause — run it first in the next session.**

## Checklist

- [x] Inspect the current local/remote schema and migration workflow; identify exact existing helpers to reuse.
- [x] Present the concrete tables, columns, constraints, indexes, RLS policies, permissions, functions, routes, and
      staged verification plan to Jafar.
- [x] Obtain explicit schema/RLS/permission and implementation approval. Approved 2026-08-20; see "Approved
      concrete plan" section above.
- [x] Add failing database/API calculation, tenancy, conversion, replay, and concurrency tests first where practical.
      `supabase/tests/database/quotes_pricing_foundation.sql`, 92 assertions, written before the migrations.
- [x] Implement catalog and Request pricing persistence plus exact calculation.
- [x] Implement atomic Request-to-Quote draft snapshot conversion and Task transfer.
- [x] Implement server validation/repository/service/API boundaries with field errors and idempotency.
      Five routes, 44 API tests. Data access stayed inline in the routes, matching every other route in this
      repository; the empty `quotes.repository.ts` / `quotes.service.ts` seams were left empty rather than
      filled with a layer nothing else uses.
- [x] Implement the approved Request pricing UI without changing established Request/Assessment behavior.
      See "Applied UI slice" below. `npm run check` and `npm run build` both clean; unit suite 690 passing.
- [x] Regenerate types, run database advisors, inspect missing foreign-key indexes, and run proportional checks.
      Advisors flag no new unindexed foreign key. `npm run check` clean.
- [x] Browser-verify desktop Request pricing and conversion; verify stale/retry/error states. Mobile is out
      of scope for now (Jafar, 2026-08-20). Done 2026-08-20; see "Session 9" below, including the two
      defects it caught and their fixes.
- [x] Resolve the Product & Services/Labor deferral and update Memory at the completion gate. Resolved
      2026-08-20: the hand-typed Labor block was dropped, and what remains is a real time-tracking Labor
      block, recorded in `Memory/deferred/INDEX.md`.

## Acceptance checks

- Two organizations cannot read, infer, link, or mutate each other's catalog, Request pricing, Quotes, versions, or
  lines through tables, read models, functions, or APIs.
- Catalog edits never rewrite Request rows or Quote draft snapshots already created.
- The same quantity and minor-unit inputs produce the same line/subtotal in database, API, and UI presentation.
- Concurrent conversion attempts create exactly one Quote, one draft version, one copied row set, one Quote
  Opportunity, and one Task transfer. Identical retry returns that Quote; changed replay conflicts.
- Failed conversion leaves the Request, Tasks, Opportunity, counter, Quote, and copied rows in one consistent state.
- Request pricing remains usable when no catalog item is selected and remains optional for existing Requests.
- Quote draft data contains no recipient link, signature, approval, deposit, delivery, Job, or working-looking future
  capability.
- Query plans use organization-first indexes for catalog lists, Request pricing, Quote lineage, and draft reads; RLS
  helpers do not execute once per returned row.

## Required verification

- Database tests for constraints, exact rounding boundaries, tenant-safe FKs, RLS roles, immutable source copying,
  Request uniqueness, rollback, idempotency, and concurrent conversion.
- API tests for Zod field errors, permission denial, archived inputs, stale state, empty pricing, retry, changed replay,
  and shaped money/cost payloads.
- Unit tests for formatting only; calculation truth stays in the database contract.
- `npm run check`, targeted test suites, Supabase database tests, advisors, migration status, and generated-type diff.
- Browser verification of catalog/custom rows, quantity/price/cost edits, Product & Services/Labor separation, save,
  reload, conversion, duplicate-click protection, and preserved Request context.

## Source pointers

- `docs/quote-behavior-contract.md`
- `docs/PRODUCT.md` §12
- `docs/client-property-behavior-contract.md`
- `.codex/skills/jobber/jobber-03-quotes.md` §§3 and 8
- `Memory/deferred/INDEX.md` Product & Services/Labor item
- `Design/Request Details.jpg` and `Design/Request new.jpg`
- `supabase/migrations/20260808054034_initial_crm_foundation.sql`
- `supabase/migrations/20260818133431_sales_pipeline_opportunity_foundation.sql`
- `supabase/migrations/20260819080000_pipeline_outcome_engine.sql`
- `src/routes/api/requests`, `src/lib/components/requests`, and empty Quote server seams

## Approved concrete plan (2026-08-20)

Jafar approved this exact shape. Implementation has not started — no migration written or applied yet.

- **Migration 1** `quotes_pricing_foundation`: `organization_quote_counters` (no prior counter pattern existed,
  built fresh with a locked-row increment), `catalog_items`, `request_pricing_lines` (+ `requests.pricing_revision`
  int for optimistic-concurrency replace), `quotes`/`quote_versions`/`quote_version_lines` (status check allows all
  seven contract states but Part 2 only ever writes `draft`; no package/add-on/discount/tax columns — those are
  Part 4's additive migration, not built early). One rounding calculation function shared by both line tables.
  RLS: `catalog_items`/`request_pricing_lines` get ordinary permission-checked CRUD; `quotes`/`quote_versions`/
  `quote_version_lines` are view-only, no direct write grants. New permission keys: `catalog.view`, `catalog.edit`,
  `quotes.view`, `quotes.view_price`, `quotes.view_cost`, `quotes.create`, `quotes.edit`. Request pricing routes
  check organization membership only (matching current Request routes), not a new permission key — seeding the
  full `requests.*` matrix stays a separate deferred decision.
- **Migration 2** `quotes_request_conversion`: adds `opportunities.quote_id` (nullable, tenant-safe FK, `on delete
  cascade`), partial unique `(organization_id, quote_id) where quote_id is not null`. Edits
  `private.opportunity_apply_stage()` — the only Part 1 Pipeline code touched — adding one branch:
  `quote_id is not null → stage 'request_closed'`. Without this the new Opportunity defaults to `new_request` and
  wrongly shows on the live board; reusing `request_closed` avoids inventing a forbidden Pipeline Quote-stage
  placeholder. `public.convert_request_to_quote(request_id, idempotency_key, request_hash)`, `security definer`,
  same lock→check→act template as `pipeline_mark_opportunity_lost`:
  1. Lock the Request. Existing Quote for it (partial-unique catches this): same key+hash → return it; same
     key+different hash → conflict; different key → conflict (already converted).
  2. **Conversion allowlist is `new`, `unscheduled`, `assessment_completed` only** (Jafar's explicit rule,
     matching Jobber: a completed assessment is Action Required and stays convertible). Reject `completed`,
     `converted`, `archived`.
  3. Lock/increment the counter; insert `quotes` + `quote_versions` (draft) + `quote_version_lines` copied from
     `request_pricing_lines`.
  4. Insert the new Opportunity (`client_id`/`property_id` from the Quote, `quote_id` set, `request_id` null) — the
     trigger above assigns `request_closed` automatically.
  5. **Tasks: move only `status = 'open'` rows** to the new Opportunity's `opportunity_id`; `completed` Tasks stay
     on the original Request Opportunity as history (Jafar's explicit rule — Tasks only have these two statuses).
     No 5-task-limit check needed: the destination starts empty and the source already respects the limit.
  6. Set `requests.status = 'converted'` — this alone fires the existing `requests_resync_opportunity_stage`
     trigger, which moves the *original* Opportunity to `request_closed` and drops it off the board with zero
     other code changes (verified: `private.request_pipeline_stage` already maps `completed|converted|archived` →
     `request_closed`, already excluded from `opportunities_board_idx` and `pipeline_board_page`'s stage list).
  7. Return the Quote.
- **API routes**: `POST/GET/PATCH /api/catalog-items`, `PATCH /api/requests/:id/pricing`,
  `POST /api/requests/:id/convert-to-quote`, `GET /api/quotes/:id`. No publish/version/decision routes yet.
- **Verified against live schema 2026-08-20**: stored `requests.status` values are exactly
  `new, unscheduled, assessment_completed, completed, converted, archived`
  (`src/lib/requests/statuses.ts`, `20260808054034_initial_crm_foundation.sql`). Opportunity/stage machinery in
  `20260818133431_sales_pipeline_opportunity_foundation.sql`, task machinery in `20260819053723_task_foundation.sql`,
  board reader in `20260819060000_pipeline_board_page_open_task.sql`. No `quote_command_receipts`-style generic
  idempotency table exists anywhere in the repo — every prior command (e.g. `pipeline_mark_opportunity_lost`) scopes
  its own idempotency column on the target row instead, which is why Part 2 uses `conversion_idempotency_key`/
  `conversion_request_hash` directly on `quotes` rather than the contract's originally proposed generic table.

## Non-discoverable risks

- The project uses imperative migrations against a remote Supabase project with demo data. Schema/RLS changes still
  need explicit approval, clean migration history, database-level verification, and advisor review.
- The existing Opportunity model currently centers Request identity. Quote Opportunity support must be the minimum
  identity needed for atomic conversion, not an early implementation of Pipeline Quote columns.
- Money represented as JavaScript `number` can exceed exact integer range. APIs must use safe integers or decimal
  strings at the boundary and reject unsupported values.
- Replacing all Request pricing rows is simple but can lose concurrent edits. The implementation plan must choose and
  test an optimistic revision or row-command boundary before coding.

## Applied database slice (2026-08-20)

Migrations `20260820002436_quotes_pricing_foundation`, `20260820002553_quotes_request_conversion`,
`20260820003326_quotes_rls_permission_lookup_once_per_query`. Tests: `supabase/tests/database/quotes_pricing_foundation.sql`, 92/92.

What the API layer must call, and the exact error codes it must map:

- `public.pricing_line_total_minor(quantity numeric, unit_price_minor bigint) -> bigint`. The only rounding
  rule; both line tables compute `line_total_minor`/`line_cost_total_minor` as stored generated columns from
  it, so no TypeScript may recompute a line total.
- `public.replace_request_pricing_lines(request_id uuid, expected_revision integer, lines jsonb) -> jsonb`
  returning `{revision, line_count, subtotal_minor}`. Line object keys: `name`, `category` (`product`/`service`),
  `is_labor`, `catalog_item_id`, `description`, `unit_label`, `quantity`, `unit_price_minor`, `unit_cost_minor`,
  `is_taxable`. Errors: `40001` stale revision (409, reload), `23514` validation/closed request (422 field errors),
  `42501` not yours or not found (404), `54000` over 200 lines.
- `public.convert_request_to_quote(request_id uuid, idempotency_key text, request_hash text) -> jsonb`
  returning `{applied, quote_id, quote_number, quote_version_id, status, line_count, subtotal_minor}`.
  `applied:false` means an identical retry. Errors: `40001` conflict (409), `23514` ineligible status or bad key
  (422), `42501` no `quotes.create` or wrong tenant (404). Convertible statuses are `new`, `unscheduled`,
  `assessment_completed` only.

Decisions taken during implementation that the approved plan did not spell out:

- `request_pricing_lines` is **view-only** with the replace function as its single write path, not "ordinary
  permission-checked CRUD". Replace-all through PostgREST cannot be atomic and cannot bump `pricing_revision`.
  Told to Jafar; reverse only if he says so.
- `quote_version_lines.source_catalog_item_id` carries no foreign key on purpose: a catalog row disappearing
  must never reach into a quote's frozen copy.
- Subtotals are written by the two commands, not by triggers, because nothing else may write those tables.
- No `field` role permission was seeded for catalog or quotes, though the contract proposed `quotes.view`.
  Field has no client access at all today. Approved as shipped 2026-08-20.
- `catalog.view` / `catalog.edit` are gated on the `core.quotes` plan feature, added to
  `permissionFeaturePrefixes` in `src/lib/server/access/effective.ts` and approved 2026-08-20. An
  organization without quotes cannot build a price list.

## Applied API slice (2026-08-20)

Five routes, all validating with Zod before any database access, all reads `private, no-cache` and all
writes `no-store`. 44 tests across four spec files; the whole server suite is 655 passing.

- `GET|PATCH /api/requests/[id]/pricing` — GET returns `{revision, subtotal_minor, editable, lines[]}`;
  the revision is what the next PATCH must send back. PATCH calls `replace_request_pricing_lines` and
  returns its `{revision, line_count, subtotal_minor}` unchanged. `40001` → 409 with `reason: 'stale'`,
  `54000` → 422 on `lines`, `23514` → 422 on `form`, `42501` → 404. Nothing in TypeScript recomputes a
  line total.
- `POST /api/requests/[id]/convert-to-quote` — 201 either way; `applied: false` is the identical retry.
  `40001` → 409 with `reason: 'already_converted'`, `23514` → 422, `42501` → 404. The permission
  (`quotes.create`) is checked by the function, not the route, so a foreign request answers the same way.
- `GET|POST /api/catalog-items`, `GET|PATCH /api/catalog-items/[id]` — gated on `catalog.view` /
  `catalog.edit`. Keyset paged on `"<name>|<id>"`, 25 default and 50 ceiling. `archived` on the PATCH sets
  or clears `archived_at`; there is no delete. Absent fields are not written, so a PATCH of one field
  cannot blank a description — only an explicit `null` clears one.
- `GET /api/quotes/[id]` — gated on `quotes.view`. `quotes.view_price` and `quotes.view_cost` decide the
  select list, so money a person may not see is never fetched, not fetched and then stripped.

Error mapping lives in `src/lib/server/quotes/errors.ts`, schemas in
`src/lib/server/validation/quotes.schema.ts`. Data access stayed in the route handlers, which is what every
other route in this repository does; `quotes.repository.ts` and `quotes.service.ts` are still empty.

Performance evidence (remote project, seeded to 20,000 catalog rows inside a rolled-back transaction):
first page 4 buffers / 0.09 ms and deep cursor page 40 buffers / 0.13 ms, both index scans on
`catalog_items_organization_name_idx` with no sort step. Name search is the one seq scan — deferred,
repo-wide, see `Memory/deferred/INDEX.md`.

## Applied UI slice (2026-08-20)

Built, but **not yet browser-verified** (Chrome extension was not connected this session) — code-complete
and passing every automated check only.

- `src/lib/components/quotes/RequestPricingBlock.svelte` — the whole Request pricing UI. Owns **both**
  "Products and services" and "Labor" `SectionBlock`s in one component, because they are one underlying line
  list sharing one `pricing_revision` — `replace_request_pricing_lines` replaces the whole set in a single
  call, so two independently-saving blocks would spuriously 409 each other. Follows `AssessmentBlock`'s
  established pattern of a self-contained record with its own query, its own edit/save state, and its own
  Save/Cancel bar, rather than riding the page's shared dirty bar. Handles: catalog-picked and custom rows,
  a Product/Service segmented toggle shown only on custom (non-catalog) rows in the Products & Services
  section, per-line delete, live client-side total preview using the same `round(qty * unit_price_minor)`
  rule as `pricing_line_total_minor` (safe to mirror in JS because quantity/price are never negative here),
  a stale-revision (409) notice that discards the draft and refetches rather than silently overwriting, and
  a locked read-only state once `editable: false` comes back from the GET.
- `src/lib/components/quotes/CatalogItemPicker.svelte` — combobox modeled on `work/ClientPicker.svelte`,
  searching `GET /api/catalog-items` filtered `labor=exclude` or `labor=only` per section, prefetched on
  hover. Typing without picking anything is a first-class path (creates a custom line) since no catalog
  management UI exists yet to populate the price list — a failed/empty search never blocks typing.
  Debounced 300 ms, matching `ClientPicker`.
- `src/lib/components/forms/MoneyInput.svelte` — filled the empty seam. Wraps `ui/Input.svelte`; binds a
  minor-units integer behind a plain decimal-dollar text field, committed on blur, same inline-edit shape as
  the Pipeline's estimated-value field (`pipeline/OpportunityDetailsSection.svelte`).
- `src/lib/quotes/api.ts` — new client module (`fetchRequestPricing`, `saveRequestPricing`,
  `fetchCatalogItems`, `convertRequestToQuote`), matching the `readOrThrow` / query-key conventions in
  `$lib/requests/api.ts`.
- `GET /api/requests/[id]/pricing` now also returns `currency_code`/`locale` via the existing cached
  `organizationFormatting()` helper (`$lib/server/requests/timezone.ts`), added to the same `Promise.all` —
  no new round trip. Needed so the pricing block formats money in the organization's own currency.
- `src/routes/(app)/requests/[id]/+page.svelte`: replaced the two static empty-state placeholders with
  `<RequestPricingBlock>`; wired "Convert to quote" for real (primary action and menu item), generating a
  fresh `crypto.randomUUID()` idempotency key per click and a `` rev-{revision}:lines-{count} `` fingerprint
  read from the pricing query cache. On success, shows an inline confirmation with the new Quote number and
  stops offering conversion once `stored_status === 'converted'` — **decided with Jafar this session**: stay
  on the Request and show a plain confirmation rather than redirect anywhere, since no Quote detail page
  exists yet to send anyone to.
- **Decided with Jafar this session:** custom (typed, non-catalog) lines in Products & Services get a small
  Product/Service segmented toggle per row, defaulting to Product, rather than always defaulting silently —
  catalog-picked rows never show it since their category comes from the catalog item.
- **Build-breaking bug found and fixed in the already-applied API slice, not introduced this session:**
  `catalog-items/+server.ts` exported `CATALOG_SELECT` and `catalog-items/[id]/+server.ts` imported it from
  its sibling route file — SvelteKit's route-export validator rejects any non-handler export from a
  `+server.ts`, which crashed `npm run build` at the postbuild analysis step (a check `npm run check` never
  runs). Moved the constant to `src/lib/server/quotes/selects.ts`. No behavior change.

## Session 3 — live Jobber tour of the line-item block (2026-08-20)

Full tour recorded permanently in `.claude/skills/jobber/jobber-03-quotes.md` §8.1 (rewritten, much more
detailed). Read that first. Nothing was saved in Jafar's Jobber account.

**Scope of the rebuild, settled by Jafar 2026-08-20:** we take **structure and behavior** from Jobber and
nothing else. Borders, spacing, radius, type scale, colors and exact widths stay ours — they come from
`.claude/skills/design/`. An earlier version of this list treated Jobber's pixel values as gaps; they are
not. Our bordered line card, our surface colors and our spacing scale are all correct as they stand.

### Structure pass — done 2026-08-20 (items 1-9 below all applied)

`RequestPricingBlock.svelte` and `CatalogItemPicker.svelte` rebuilt. `npm run check` clean (the only two
warnings are pre-existing, on the dashboard page), prettier clean, 690/690 unit tests pass. Verified live at
`localhost:5173/requests/1cba696d-84b5-49ab-b7e8-36df93881d97` in both states — a demo line was saved on
that request so the block has something to show.

What landed beyond the nine items: `CatalogItemPicker` grew a `label` prop with its own copy of
`ui/Input.svelte`'s floating-label behavior (it is a custom combobox, not built on `Input`); the money
formatter is now a `$derived` built once per currency instead of a fresh `Intl.NumberFormat` per figure
(six per line per render); the read table's photo column only renders when some line has a photo; the empty
state's "Add a line item" now hands back an actual line instead of an empty editor; and new lines default
to `category: 'service'`, which is what the database already falls back to, now that the type toggle is gone.

Still open: the behavior gaps (10-15) below.

### Gaps — structure (all applied)

1. **Row 1 proportions.** Name should dominate; Quantity, Unit price and Total should be three equal, much
   narrower columns. Ours is `minmax(160px,2fr) 90px 130px 100px auto` — three different fixed widths.
2. **Drag handle and `...` menu belong in gutters outside the field row**, one on each side, so the four
   fields keep their alignment. Ours has the menu as a fifth grid column.
3. **The photo is a column, not a thumbnail.** It sits under Total, roughly as wide as that column and as
   tall as the description beside it. Ours is a 72px tile in a `1fr 72px` grid.
4. **Description is a real writing box**, tall enough for a few lines (Jobber shows 5 rows). Ours is 2.
5. **Total reads as a labelled field, not bare text** — same shape as the three editable fields, just not
   typeable.
6. **Read state is a table**, with **Line Item / Quantity / Unit Price / Total** headers, the description
   under the name inside the Line Item column, and a thumbnail in its own column before Quantity. Ours
   reuses the edit card grid and has no headers.
7. **Footer:** Add Line Item sits alone under the lines; the totals block is separate and right aligned.
   Ours puts the button and the subtotal on one row.
8. **Every field gets a real label** (Jafar's standing instruction from session 2), not a placeholder.
9. **Drop the Product/Service `SegmentedControl` from the Name cell.** Jobber has no type toggle on a line
   — type is chosen only when creating a catalog item.

### Gaps — behavior

10. Catalog dropdown should **group by category header** and show **name + description + price** per row,
    and **flip above the field** when there is no room below. Ours groups nothing and omits price.
11. No **"+ Create new item"** entry, and no Add Product / Service dialog (Item type, Name, Description,
    Unit cost / Markup % / Unit price, image, Exempt from Tax, Create).
12. **Add line item** should focus the new Name and **open the catalog list immediately**. Ours appends a
    blank line and stops.
13. **Photo affordance has two states**: an empty drop target with an upload control, and a filled state
    showing the photo with **replace** and **remove** controls. Ours only has add and remove.
14. **Cancel with pending edits must confirm** ("Discard changes?" — Keep Editing / Discard). Ours discards
    silently.
15. **Empty Name validates on blur**, showing "Line item name is required" under the field — not on Save.

### Confirmed correct by omission

- **No "Mark as optional"** on a Request — Quote-only in Jobber too.
- **No "Add Text"** row on a Request — Jobber's Request block only has Add Line Item.
- **No Labor section** — matches Jobber (its Request Labor is read-only time tracking).

### Confirmed money behavior

- Quantity accepts decimals and shows exactly what was typed (`0.25`, `2.5`), no forced formatting.
- Unit price shows the bare number while focused and formats to currency on blur.
- Line total recalculates live, rounded half-up to 2 decimals (0.25 x 45.50 -> 11.38).

### Deferred / not observed

- **"Fill With: Last job"** — after picking a catalog item Jobber offers the price and text used for that
  item last time, in a small dismissible popover. Pricing memory; own feature, not part of this rebuild.
- **Mobile width** — the extension could not resize the live Jobber window, so the narrow-screen behavior
  of this block is unknown. Do not guess it; tour it before building mobile.

### Session 4 — the two open questions from session 3, answered (2026-08-20)

- **Description character counter removed.** Jobber shows none, so ours goes. `Textarea` gained a
  `showCount` prop (default `true`, so no other screen changes); the pricing description passes
  `showCount={false}`. `maxlength={2000}` stays — it silently matches the database check, nothing on
  screen mentions it.
- **Empty photo box no longer reads disabled.** It was a grey camera icon on the grey page background.
  Now white fill, a green Tabler `upload` icon, and a subtle green hover tint — the empty state Jobber has
  (§8.1). The box was always functional; it just looked switched off.
- Browser-verified in edit mode; `npm run check` clean, prettier clean.
- **Filled photo state built (gap item 13, done).** Solid border instead of dashed, and two always-visible
  round buttons stacked at the photo's right edge: a green pencil that reopens the picker (the existing
  swap path already deletes the replaced upload) and a red trash that clears it. The old dark `x` badge is
  gone. Verified by seeding an `attachments` row plus `image_attachment_id` on the demo line, screenshotting
  the filled box, then deleting the seed — the request is back to 0 attachments and no line image.

- **Line photo upload was broken; fixed.** One hidden file input was shared by the whole block, with a
  `uploadTargetId` variable remembering which line had asked for it. Picking a photo did nothing at all —
  no attachment row was ever written. Each line now owns its own input and passes its own id to
  `handleFileChosen(id, files)`, so nothing has to be remembered between the click and the file coming
  back. Verified end to end on `52011e21-eb29-4f27-9a99-75c88f4cc875` through the tunnel: pick, upload to
  R2, `attachments` row written, filled state with pencil + trash, Save, and the id persisted on the line.
  R2 itself was never the problem. Test data removed afterwards.
- Removing an already-saved photo leaves the file orphaned in R2 — logged in `Memory/deferred/INDEX.md`.

### Session 5 — behavior pass, first three items (2026-08-20)

- **"Add line item" focuses the new Name and opens the price list** (gap item 12). `addLine()` awaits a tick
  and focuses `pricing-name-<id>`; the picker already opens on focus, so nothing else was needed.
- **Cancel with unsaved edits asks first** (gap item 14). `ConfirmDialog`, "Throw away these changes?" /
  "Keep editing" / "Throw them away". Dirty is a JSON compare of the saved lines against the draft, with
  completely untouched blank lines filtered out — clicking "Add line item" and changing your mind closes
  without a dialog, which is the common case.
- **Empty Name complains on blur, under the field** (gap item 15). `CatalogItemPicker` gained `invalid`,
  `errorMessage` and `onBlur`; the block tracks a per-line `nameTouched`. Copy is "Give this line a name."
  The Save-time check stays as the backstop.
  - The blur guard needed a second try. Reaching for the dropdown blurs the input while the list is still
    open, so an immediate `if (!open)` check never fired. It now re-checks on a `setTimeout(…, 0)`, after
    the click has settled — open means still inside the picker, shut means really gone.
- All three browser-verified on the demo request; the demo data is unchanged. `npm run check` clean,
  prettier clean, 690/690 unit tests pass.
- Left in the behavior pass: gap items 10 and 11 — the grouped catalog dropdown with price per row and
  above/below flipping, and "+ Create new item" with its Add Product / Service dialog.

### Session 6 — behavior pass closed (2026-08-20)

Gap items 10 and 11 are done, so the whole behavior pass is finished.

- **Grouped price list with prices** (item 10). `CatalogItemPicker` splits one page of results into
  **Products** / **Services** groups (`Combobox.Group` + `GroupHeading`), each row showing name,
  description and the price right aligned. The API already returns name order, so grouping is a split and
  never a re-sort. The picker takes `currencyCode`/`locale` from the block and builds one
  `Intl.NumberFormat` per currency. Flipping above the field needed no code — bits-ui already does it, and
  it was watched doing it live.
- **"+ Create new item"** (item 11), pinned in a footer under the scrolling list and **always shown** —
  Jafar's call, against Jobber, which only offers it when nothing matches. It opens
  `src/lib/components/quotes/CatalogItemDialog.svelte`: item type, name prefilled with what was typed,
  description, a 3-up Unit cost / Markup % / Unit price row, Exempt from tax, Cancel / Create. It saves
  itself through the existing `POST /api/catalog-items` (no new route), invalidates `['catalog-items']`,
  and fills the line exactly as picking an existing item does.
- Markup is never stored — `src/lib/quotes/markup.ts` converts between it and the cost/price pair in both
  directions (7 unit tests). Two things came out of driving it live: markup shows **nothing** until both a
  cost and a price exist (a cost alone was reading as "-100"), and the field is **never disabled**, because
  a disabled middle field makes Tab jump from Unit cost straight to Unit price.
- The tick that used to sit on every result row is gone. It never meant anything — the combobox value is
  not bound to the line's catalog id — and Jobber's rows are name/description/price only.
- **No image field in the dialog** — deferred by Jafar, logged in `Memory/deferred/INDEX.md`.
- Browser-verified end to end on the demo request: create an item, list groups and flips above the field,
  pick fills name/description/price with quantity left at 1, Cancel still asks before throwing changes away.
  The two catalog items made while testing were deleted afterwards; the demo line is untouched.
- `npm run check` clean, prettier clean, 697/697 unit tests, `npm run build` clean (largest chunk 96 kB, no
  new dependency). `performance-review` ran for the Svelte layer.

### Session 7 — performance review of the migration and API layers (2026-08-20)

- **Five lookups inside the two write functions had no organization to match on**, so they could not use the
  leading column of any index and walked the whole one instead: the delete and the subtotal in
  `replace_request_pricing_lines`, and the line copy and the copied subtotal in `convert_request_to_quote`.
  Measured on a 300,000-row scratch copy of `request_pricing_lines`: **214 ms / 2,807 buffers** to find 6
  rows by request alone, **0.18 ms / 4 buffers** with the organization added. A security definer function
  gets no RLS predicate added for it, so nothing was supplying it. Fixed in
  `20260820121500_quotes_pricing_tenant_scoped_lookups.sql`, applied.
- **The pipeline card lookup could not be fixed that way** — conversion locks the card before the request, so
  the organization is not known yet. New partial index `opportunities_request_lookup_idx (request_id) where
  request_id is not null`. It also covers `private.opportunity_resync_from_request`, which asks the same
  question on every request status change.
- **Catalog search escaped nothing.** The escape used one backslash inside a template literal, which JS
  reads as an escaped dollar sign, so the replacement inserted the literal text of the placeholder instead
  of escaping the wildcard. Now matches the repo escape (`clients/+server.ts`, `duplicates.ts`), with a
  regression test.
- Checked and fine: keyset paging with a hard page ceiling, no `select *` anywhere, `Promise.all` on
  independent reads, deliberate cache headers, the in-process org-settings cache, the task move using
  `tasks_opportunity_open_idx`.
- Rate limiting on these routes joins the existing deferred entry. The `ilike '%term%'` seq scan is already
  deferred as an app-wide decision.
- 698/698 unit tests, `npm run check` clean, prettier clean, advisors show nothing new.

### Session 8 — pgTAP for the line photo, and the bug it caught (2026-08-20)

- **13 new assertions** in `supabase/tests/database/quotes_pricing_foundation.sql`, plan now **105**: the
  column on both tables, the index, the request-side FK and the deliberate absence of a quote-side one, the
  photo surviving a save, two refusals (a photo taken for a different request, a photo from another
  organization), the photo copied onto the quote line at conversion, and deleting the upload clearing the
  request line while the quote copy keeps it.
- **The delete assertion failed, and it was right to.** `on delete set null` on a composite foreign key
  nulls **every** column in the key, `organization_id` included, so deleting a photo a line pointed at
  raised `23502` instead of clearing the reference. A contractor removing a photo from a request's
  Attachments card got a database error. Fixed in
  `20260820133000_pricing_set_null_clears_only_the_reference.sql` with Postgres 15's column list —
  `on delete set null (image_attachment_id)` — applied, and the same fix given to
  `request_pricing_lines_catalog_organization_fk` and `quotes_draft_version_organization_fk`.
- Four older tables carry the identical mistake (client and property contact methods, opportunities'
  current outcome event, tasks' completing outcome event). They belong to closed campaigns and are logged
  in `Memory/deferred/INDEX.md` rather than changed here.
- All 13 behaviors were verified against the remote project in one rolled-back transaction, the convention
  this file documents. Nothing persisted; the demo request is untouched.

### Session 9 — the Part 2 browser gate, and the two defects it caught (2026-08-20)

Every remaining browser scenario passed, two of them only after a fix.

**Passed as built:** custom lines (the price-list dropdown offers a one-off line when nothing matches);
edit, delete, save and reload keep exact money (3 x $125.55 = $376.65, subtotal $876.65 after a full
reload); the Price book adds and re-adds catalog items safely; Cancel asks before discarding and restores
the saved lines; a line photo uploaded and then cancelled is **deleted** from `attachments`, and one that
is saved survives; conversion carried the photo onto the quote line.

**Defect 1 — a refused save never came back.** Both write functions raised SQLSTATE `40001` for a
business conflict. That is Postgres' serialization failure, and PostgREST retries it, so a refusal that
never changes its mind never answered. Back to back on one request: correct revision 334 ms, stale
revision no answer at 35 s, ordinary `check_violation` 447 ms; the same call straight to PostgREST
returned in 0.78 s. The editor sat on a spinning Save with no message, and each abandoned attempt left a
transaction holding the request row's lock, which blocked every later save on that request. Fixed in
`20260820150000_quotes_conflict_code_is_not_a_retry_signal.sql` with `P0409`, mapped in
`src/lib/server/quotes/errors.ts`; the three pgTAP assertions and two API specs now expect `P0409`.
Verified live: stale save is now a 409 in 1.5 s and the block shows "Someone else changed this pricing
while you were editing. Here is the latest version." with the fresh lines.

**Defect 2 — Convert to quote was disabled on most requests.** `canConvert` required
`assessment.completed_at`, so a `new` or `unscheduled` request could never be quoted, contradicting
Jafar's approved allowlist (`new`, `unscheduled`, `assessment_completed`) that the database already
enforces. Now gated on that allowlist. The suggested next-step button still walks Schedule assessment →
Complete assessment → Convert to quote, which is Jobber's ladder and stays as it was.

**Conversion verified end to end:** request 263f718d became Quote #1, draft, 4 lines, subtotal 87665
matching the request, one line carrying its photo, one quote, one version, request `converted`, and its
pricing now refuses edits with "This request is closed and its pricing cannot be changed." An identical
retry returned the same quote with `applied: false` in 475 ms; a different idempotency key returned 409
`already_converted` in 297 ms — the case that used to hang.

**Open question for Jafar (visual only):** in the read view the line photo sits in its own column between
the name and Quantity, which stretches the row; and a line photo also appears in the request's
Attachments card. Neither is wrong, both are worth a glance.
