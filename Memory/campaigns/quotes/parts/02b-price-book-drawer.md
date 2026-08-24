# Part 2B: Price Book Drawer

## Outcome

Give contractors one visible, fast way to browse and add reusable Products and Services while preserving the
existing custom-line path and document-owned snapshot rules.

Approved by Jafar on 2026-08-20 after comparing UCRM, ContractorOs, Jobber, and Housecall Pro behavior.
`docs/quote-behavior-contract.md` § Price book interaction is authoritative.

## Approved behavior

- The line-item editor presents **Add line item** and **Price book** as separate actions.
- Add line item creates and focuses a blank custom line.
- Price book opens an accessible right-side drawer. The existing Name-field suggestions remain available as the
  fast path when staff already know an item's name.
- The drawer supports server-backed search and Product/Service filtering. Results show name, description, unit,
  and customer price. Cost is shown only with the existing cost-view permission.
- Selecting an item immediately appends a document-owned snapshot and leaves the drawer open. The result visibly
  changes to Added, accidental repeat clicks are blocked, an intentional second copy remains possible, and a Done
  action closes the drawer.
- Staff can add several saved items in one opening. Added order is stable and matches the contractor's selection
  order.
- A picked line remains fully editable for this Request. Editing it never changes the saved catalog item.
- The drawer includes **Create new item** and **Add custom line**. Creating a reusable item uses the existing
  catalog create API and fills a new document line. Add custom line closes the drawer and focuses a blank row.
- A custom line may be saved to the Price book through an explicit action. A linked line may update its saved item
  only through an explicit action that says future uses change and existing documents do not.
- Saved-item images stay out of this slice and remain in `Memory/deferred/INDEX.md`.
- The dedicated Price Book management screen is a separately gated slice, not a hidden requirement for Part 2B.

## Implementation boundary

- Reuse the existing catalog tables, permissions, Zod validation, APIs, TanStack Query keys, and line snapshot
  fields. No schema, RLS, permission, package, or image change is approved by this packet.
- Build one shared drawer suitable for the Request editor and the Part 3 Quote workspace. Keep Request-specific
  save and conflict ownership in `RequestPricingBlock`.
- Use the installed accessible overlay primitives and the project design system. Preserve focus on open, Escape,
  keyboard navigation, scroll containment, and focus return to the Price book trigger.
- Keep catalog search server-backed and paged. Do not copy ContractorOs's load-the-whole-catalog store.
- Preserve the existing database-owned money calculations and optimistic pricing revision.

## Checklist

- [x] Inspect existing shared Sheet/Dialog wrappers and the current catalog picker/query seams.
      `layout/SidePanel.svelte` is the shared right-side panel; no new overlay was needed.
- [x] Implement the shared Price book drawer and visible Request actions.
      `components/quotes/PriceBookDrawer.svelte`, opened from a Price book button beside Add line item.
- [x] Add safe multi-add, Added/intentional-duplicate behavior, Done, Create new item, and Add custom line.
- [x] Add explicit save-to-catalog/update-catalog behavior without changing document snapshots implicitly.
      Both live on the line menu and open the prefilled `CatalogItemDialog`.
- [x] Add targeted component/API tests for permissions, repeated selection, order, and cache invalidation.
- [x] Run Svelte validation, formatting, checks, unit tests, build, and performance review.
- [x] Browser-verify the drawer.
- [ ] Run the remaining Part 2 Request pricing/conversion checklist: custom lines, edit/delete/save/reload,
      forced stale revision, catalog use, Convert to quote, photo carry-forward, and cancelled-photo
      deletion verified in `attachments`.

## Internal cost, settled 2026-08-20

Jobber splits this in two: **Show pricing** gates what the client pays and is a prerequisite for editing at
all, while **Job costing** separately reveals cost and profit and is routinely off for someone who builds
quotes daily. Our seeded roles already match — office and sales edit quotes without `quotes.view_cost`.
Following that:

- `/api/catalog-items` never selects the cost columns for someone without `quotes.view_cost`, and answers
  `can_view_cost` outright so an empty page still tells the drawer what to render.
- The pricing PATCH fills a price-book line's cost back in from the catalog item when the saver could not
  see it, so a salesperson's save never zeroes the owner's profit. It only touches a line that names a
  catalog item and arrives with no cost, so a frozen snapshot is never rewritten.
- The request pricing read still carries cost to everyone. Deferred, with the reason, in
  `Memory/deferred/INDEX.md`.

## Acceptance checks

- A contractor can add one common item quickly or several common items without reopening the Price book.
- A one-customer edit changes only the Request line. Catalog edits change only future additions.
- A cost-restricted staff member never receives or sees catalog cost through the drawer.
- Search remains responsive for a large tenant catalog and does not require downloading the full catalog.
- Closing or cancelling the surrounding Request edit cannot silently persist drawer additions.
- Keyboard and pointer users can open, search, filter, add, intentionally duplicate, and close the drawer.

## Evidence and risks

- ContractorOs evidence: `D:/Projects/ContractorOs/src/lib/components/quotes/CatalogPickerSheet.svelte` and
  `LineItemEditor.svelte`. Keep its visible drawer and editable snapshot behavior; improve its close-after-one-pick
  and whole-catalog client loading.
- Jobber supports saved and custom lines plus multi-selection in its quote app. Housecall Pro's Visual Price Book
  supports browsing and adding multiple items. Evidence informs this contract but does not replace it.
- The current inline combobox already owns create-new behavior. Avoid two competing creation implementations or
  two cache-invalidation paths when extracting the shared drawer.
