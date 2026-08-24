# Part 2A: Taxes

## Outcome

Give owners and administrators one safe Taxes destination for maintaining shared tax rates and choosing the
Business default, while Quotes and future Invoices take a truthful copied tax value into each new draft.

This is the first independently verifiable slice of Settings Part 2. Price Book management and Quote Settings
are explicitly out of scope until this slice is complete.

## Approved behavior

- A saved tax rate has a name and a percentage greater than 0% and no more than 100%, with up to two decimal
  places.
- The Business default is either one saved active rate or the explicit **No tax** choice. It starts
  **Not configured**, which differs from **No tax**.
- A Property can inherit the Business default or pin one saved rate. A future Business-default change affects
  only future drafts for inheriting Properties; pinned Properties stay pinned.
- Existing drafts and published documents retain the named rate and percentage copied into them. A document
  may choose a different saved rate or a one-off named custom rate.
- A priced Quote cannot be published while tax is not configured until an authorized person chooses a saved
  rate, adds a one-off named custom rate, or explicitly confirms **No tax**. The message links to Taxes.
- Quote-pricing editors can use a one-off custom rate, but it never silently enters the shared list. Only
  owners and administrators may deliberately save it for future use; doing so does not change the Business
  default.
- Editing a saved rate explains how many Properties are pinned to it before saving. The edit affects only
  future drafts.
- A rate used by any Property cannot be permanently deleted. It may be made inactive: affected Properties
  remain pinned, but new selections omit it. Permanent deletion requires every affected Property to be
  reassigned first.
- Changing an inherited Business default needs confirmation when Properties inherit it, stating how many will
  use it for future documents and that existing documents do not change.
- Only owners and administrators can manage Taxes until finer permissions exist. Other roles do not see its
  Settings destination, and server authorization enforces the same rule.

## Dependencies and source pointers

- `docs/contractor-settings-blueprint.md` → **Taxes** is the authoritative product behavior.
- `docs/quote-behavior-contract.md` is the authoritative existing Quote behavior and must be reconciled
  before schema design.
- Existing Quote tax code, Properties, and current Invoice foundations determine whether an extension is safe
  or a small migration is required.
- `docs/PRODUCT.md` and `.claude/skills/jobber/jobber-03-quotes.md` provide the CRM vocabulary and existing
  competitor comparison. A live Jobber screen tour or supplied screenshots is required before UI design.

## First action checklist

- [x] Read the authoritative Taxes section and the current Quote behavior contract.
- [x] Audit current tables, migration history, validated write routes, Quote reads, and Property tax fields.
- [x] Decide source ownership, required indexes, cursor pagination where a rate list needs it, and whether an
      aggregate is needed before proposing database work. (No pagination needed — a saved-rate list stays
      small per org; plain tenant-scoped indexes suffice.)
- [x] Reconcile the existing per-Quote tax editor with the new saved-rate/default model — schema, RPC, and
      the `/api/quotes/[id]/tax` route are done; the `QuoteTaxCard.svelte` UI reconciliation is still pending.
- [ ] Tour the live Jobber Taxes/Quote screens — skipped per Jafar 2026-08-24: the approved blueprint already
      specifies exact behavior, and Jobber's real settings page (Tax ID field, Tax Groups, one page-wide save)
      has extra complexity deliberately not being copied. Not needed before implementation.
- [x] Present a focused design, risks, edge cases, migration/API/UI order, and checks for approval. Approved
      2026-08-24 ("keep it simple, no compromise on necessary features").

## Audit answers (2026-08-24)

- Quote tax fields: `quote_versions.tax_name`/`tax_rate_basis_points` were draft-editable free text only
  (via `set_quote_draft_tax`), frozen at publish by the existing `freeze_quote_version`. No distinction
  existed between "not configured" and "no tax" (both `name=null, rate=0`) — now split via the new
  `tax_source` column.
- Property tax fields: none existed. Added `properties.tax_rate_id` (nullable FK; null = inherit).
- Invoice tax model: no `invoices` table exists at all yet. Confirmed out of scope, stays deferred.
- Permission keys: `settings.business.edit`/`.view` split view-broad/edit-narrow; Taxes instead uses one
  `settings.taxes.manage` key granted only to owner/admin (hidden from every other role, per blueprint).
  Quote-pricing access remains `quotes.edit`; the "save as reusable rate" action inside the Quote Tax dialog
  is separately gated to `settings.taxes.manage` even for an authorized quote editor.
- Publish gate seam: `public.publish_quote()`, right after its priced-line-count check — now raises when the
  current draft's `tax_source = 'not_configured'`.

Migration shipped: see NOW.md for the two applied migration files and what they add.

## Non-discoverable risks

- Tax is money-critical. Persisted totals remain database-owned; client code must never recompute a saved
  total.
- Migrating a current Quote tax shape can accidentally reinterpret existing drafts. The audit must establish
  how historical name, percentage, exemption, and totals remain stable before any migration is drafted.
- Rate deletion and inactivation must distinguish Property references from copied document history: documents
  do not block deletion, while Properties do.
- Any tax rate counts shown in confirmation must be tenant-scoped and indexed; no whole-tenant scans.
- A hidden card is not authorization. Every read and write must enforce the same owner/administrator rule.
- The current worktree contains unrelated active changes. Preserve them and do not alter other campaign Memory
  or application files during registration.

## Likely delivery order (not yet approved for implementation)

1. Establish the present authoritative tax fields and readers, then choose the smallest schema boundary that
   supports saved rates, default selection, Property inheritance, and copied document tax truth.
2. Add tenant-scoped commands and read models behind validated `/api/*` routes, with optimistic revision
   protection for each independently saved Taxes change.
3. Add focused database, server-route, and client API tests before the Settings page is connected.
4. Build the permission-aware Taxes page using existing Settings and shared UI components wherever their
   interaction shape already fits.
5. Connect Quote drafting to one server-owned default-resolution path and retire no existing behavior until
   equivalent coverage shows it is safe.
6. Run the required performance review after each touched layer, then complete browser verification.

The audit can revise this order only where existing implementation makes a simpler safe sequence necessary.
It cannot expand the slice into Price Book, Quote terms, representative content, mandatory signatures, quote
numbering, templates, or target-margin configuration.

## Read and cache boundaries

- The eventual rate list must be tenant-scoped and cursor-paginated if it can exceed a small static Settings
  list. Its user-facing search/sort behavior must follow the audit rather than assume full-list download.
- Tax rate detail, Business default, and Property assignment must have clear query ownership and stable keys
  before UI work. Existing TanStack Query conventions are the source of truth.
- A Taxes mutation invalidates only the affected Taxes/default/Property/new-draft reads. It never wipes every
  cached Quote or blocks navigation while refetching.
- Rate usage counts for an edit/delete confirmation are calculated server-side. They reveal only the current
  organization’s Properties and must not return property identities unless the user can already access them.

## Open audit questions

- Which current Quote tax fields are immutable snapshots, which are draft-editable, and which calculation
  function owns their totals?
- Does the current Property model already hold the distinction between inherited and specifically assigned
  tax, or must the migration introduce it without overloading an unrelated field?
- Is an Invoice tax model already live enough that it needs to consume shared rates in this slice, or must it
  remain an explicitly deferred consumer until Invoice Settings exists?
- Which existing permission keys precisely represent owner/administrator access and quote-pricing access, and
  do their server helpers already provide the required visibility boundary?
- Does the existing Quote publish flow have a readiness seam suitable for a Not-configured tax gate, or does
  that gate need a narrowly scoped extension?

Answer these from code and approved documents during the first action checklist; do not resolve them by
inventing a model or adding speculative fields.

## Acceptance checks

- This packet remains the only active first slice for Part 2 until Jafar approves its focused implementation
  plan.
- The eventual implementation proves all saved/default/pinned/custom/no-tax paths, including safe historical
  behavior, with focused database and route tests.
- It proves no unauthorized user can read or mutate shared Taxes, and no unauthorized response exposes private
  money data.
- It verifies the normal Settings and Quote flows in the browser at desktop and 390px unless Jafar explicitly
  waives a pass.
- Targeted cache invalidation refreshes affected Taxes, Properties, and new Quote-draft defaults without
  blocking navigation.

## Completion gate — met 2026-08-24

An authorized contractor can safely maintain tax rates and the Business default; future drafts choose the
right copied rate; existing work stays unchanged; permission, conflict, deletion/inactivation, and
not-configured paths are tested; and the Settings plus Quote experience is browser-verified.

**Closed.** The deferred Quote/Property tax picker slice shipped 2026-08-24: migration
`20260902100200_settings_taxes_picker.sql` (`organization_tax_picker`, OR-gated on
`quotes.edit`/`property.manage`/`settings.taxes.manage`), `GET /api/settings/taxes/picker`,
`QuoteTaxCard.svelte` redesigned for the five-source model (business default / property default / saved
rate / custom / no tax, each showing its resolved preview), `saveQuoteTax`/`QuoteDetail` updated to the
current `quoteTaxSchema` shape, and `PropertyDialog.svelte`'s pin-vs-inherit Tax field. Fixed one real bug
found while verifying: `GET /api/clients/[id]` was not selecting `properties.tax_rate_id`, so a saved pin
round-tripped to the database correctly but the dialog showed "Inherit" again on reopen — added the column
to that route's select. Also fixed the three stale `proposal-commands.spec.ts > tax` tests that still posted
the old `{name, rate_basis_points}` shape (tracked in
`Memory/deferred/eight-vitest-failures-in-the-quotes-and-team-specs.md`, now resolved). All three layers
performance-reviewed; `npm run check` 0 errors; full suite back to only the two pre-existing, unrelated
failure clusters (quote.spec.ts's missing `rpc` mock, team role/permission 409-vs-500). Browser-verified live
(agent-driven, Jafar's own Chrome/dev app/database): a new quote correctly resolved "Business default —
Sales tax — 10%" on creation; the Edit-tax dialog listed all five options with correct resolved previews;
switching to a custom rate ("Eco fee", 2.5%) saved and displayed correctly; the Property dialog's Tax field
correctly showed "Inherit business default (Sales tax — 10%)", pinning to the saved rate persisted and
survived a reopen after the fix above, and was reverted back to Inherit to leave demo data clean.

Part 2A is fully closed. Select Part 2B Price Book only after Jafar confirms it is next.
