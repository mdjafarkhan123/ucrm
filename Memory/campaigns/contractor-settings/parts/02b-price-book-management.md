# Part 2B: Price Book management

## Outcome

Owners and Administrators can manage their reusable products and services in Settings without altering
existing Requests or Quotes. Eligible Quote editors continue to use the existing picker, without gaining
the Settings management page.

## Approved behavior

- Settings → Price Book is visible only to Owners and Administrators.
- The page lists active items with keyset pagination. It searches names and descriptions, filters Product,
  Service, Labor, Taxable, and Tax exempt, and sorts by name, selling price, or most recently updated.
- An item has name, description, Product/Service, optional Labor for services, optional unit, selling price,
  private cost, markup calculator, and taxable default.
- Active names are case-insensitively unique within an organization. The first management page starts empty;
  no guessed catalog data is created.
- Adding an item to a Request or Quote remains a copy. Later Price Book edits or deletion never change that
  document line.
- Delete is permanent after a short named confirmation. It makes the name available again and leaves copied
  document lines intact. An item deleted by another manager is never recreated by a stale edit.
- Every edit is revision-protected. The edit view identifies the last editor and time; a stale manager can
  review the latest value or discard their draft.
- Members without cost permission never receive cost or profit data. Saved-item images, CSV import, bulk
  editing, extra categories, and full history are out of scope.

## Existing truth to reuse

- `catalog_items` and `/api/catalog-items` already provide tenant-scoped cursor paging, price/cost redaction,
  and the Quote/Request picker. Extend them; do not add a parallel catalog.
- `CatalogItemDialog.svelte` already has the child-record form and the cost/markup boundary.
- `catalog.view` continues to power the picker. The new Settings page/API requires an Owner or Administrator,
  independent of that permission.
- Request and Quote pricing rows own copied values. Existing foreign keys must preserve those rows when the
  source catalog template is deleted.

## Plan

1. Add the minimal catalog migration: active-name uniqueness, revision/editor metadata, permanent-delete
   command, and indexes for the approved keyset list queries. Test tenant isolation, stale edits, deletion,
   and history preservation; run the database performance gate.
2. Extend the existing catalog API with the bounded Settings-list query and validated Owner/Admin writes.
   Preserve the picker contract and add focused route tests; run the API performance gate.
3. Add the permission-aware Settings destination, warm route, and Price Book page. Reuse existing controls
   and dialog; defer its query until the route is entered and use targeted cache updates after writes.
4. Run Svelte/design/performance checks and browser verification for empty, create, edit, stale, delete,
   permission, redacted-cost, filters, sort, pagination, and mobile states.

## Non-discoverable risks

- The old implementation archives catalog items. This approved slice changes management deletion to a safe
  permanent delete and must not weaken historical document snapshots.
- Current `catalog.edit` is broader than the approved Settings-management authority. The picker remains
  available to Quote editors; Settings is not a new general catalog-edit permission.
- Name search and description search have different index needs. Do not claim both are index-backed unless
  the actual query/index design supports it.

## Completion gate

Authorized managers can safely create, find, filter, sort, revise, and permanently delete Price Book items;
all other staff have only the intended picker/cost visibility. Existing document lines remain unchanged,
stale and cross-tenant writes fail, paging stays cursor-based, and API, database, Svelte, browser, and
performance gates pass.

## Source pointers

- `docs/contractor-settings-blueprint.md` → **Price Book**
- `Memory/campaigns/quotes/parts/02b-price-book-drawer.md` → existing picker contract
- `supabase/migrations/20260820002436_quotes_pricing_foundation.sql` → `catalog_items`
- `src/routes/api/catalog-items/+server.ts` and `[id]/+server.ts` → existing API boundary
