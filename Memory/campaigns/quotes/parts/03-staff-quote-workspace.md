# Part 3 - Staff Quote workspace

## Outcome

Authorized staff can create a Quote directly or from a Request, find it in a real list, edit its draft, and
read a truthful summary. No screen shows an action a later part still owns.

## Approved decisions (2026-08-20)

- Rail in Part 3 is Quote summary (read-only), Notes, Attachments. Discount and Tax wait for Part 4, Deposit
  for Part 6. No greyed placeholder blocks.
- Composer footer is Cancel / Save Quote. One save, then the new Quote's detail page.
- Quote number stays database-allocated and non-editable; the composer shows it as assigned on save.
- Contract disclaimer is plain draft-owned text. Settings-backed defaults stay out of scope.
- Header actions later parts own (Convert to Job, Send, View activity) are not rendered in Part 3.
- The list shows the four status Overview rows plus three placeholder metric tiles - Conversion rate, Sent,
  Converted - each reading a dash with a line saying what fills it. Jobber's real 30-day numbers wait for
  Part 5, because sending and approving do not exist yet. Jafar chose the placeholders over an empty row on
  2026-08-20: the blueprint shows three blocks there and the Requests list already looks this way.

## Reuse map - Part 3 builds almost no new UI

Every screen is assembled from parts the Requests and Clients pages already ship. Build nothing new that
appears in this table.

| Screen | Reuse |
| --- | --- |
| List | `PageContainer`, `PageHeader`, `SearchInput`, `Select`, `FilterBar`, `FilterField`, `DataTable`, `ListLoadMore`, `StatusOverviewCard`, `KpiCard`, `StatusBadge`, `EmptyState`, `ErrorState`, `LoadingSkeleton` |
| Composer | `RecordFormLayout`, `SectionBlock`, `RailCard`, `ClientPicker`, `Input`, `Textarea`, `Button`, plus the Products & Services block from 3C |
| Detail | `RecordDetailLayout`, `WorkRecordHeader`, `ClientSummaryCard`, `RecordFactsList`, `SectionBlock`, `RailCard`, `PencilButton`, `NotesPanel`, `AttachmentsCard` |

New files are limited to: the Quote status vocabulary, a Quote summary rail card, the shared Products &
Services block extracted in 3C, and the three route pages.

## Slices

| Slice | Scope | Gate |
| --- | --- | --- |
| 3A | Migration: draft `revision`, contract disclaimer, direct-create/draft-edit/line-replace/archive/restore commands, RLS, indexes. Routes: `POST /api/quotes`, `GET /api/quotes`, `PATCH /api/quotes/:id/draft`, archive/restore; extend `GET /api/quotes/:id`. | pgTAP + route tests pass; performance review on migration and routes |
| 3B | `/quotes` list page and live nav item | Browser: search, status and date filters, sorting, paging, empty state |
| 3C | `/quotes/new` composer; split `RequestPricingBlock` into one shared Products & Services block with per-document adapters | Browser: direct create, Request pricing block still behaves |
| 3D | `/quotes/[id]` detail on `RecordDetailLayout` + read-only Quote summary | Browser: converted Quote #1 and a direct Quote both read correctly |

## Checklist

- [x] 3A migration - `20260820160000_quote_workspace_commands.sql` and the follow-up
      `20260820163000_a_quote_is_a_real_linkable_entity.sql`, applied and verified on the dev project
- [x] 3A routes and tests - 31 route tests, 54 pgTAP assertions, performance review passed with one deferral
- [x] 3B list - `/quotes` page, live nav item, warm route, quote status vocabulary in `$lib/quotes/statuses.ts`,
      list fetchers in `$lib/quotes/api.ts`, browser-verified 2026-08-20
- [x] 3C composer and shared pricing block - `ProductsAndServicesBlock.svelte` is the shared block,
      `RequestPricingBlock.svelte` is now a 48-line request adapter, `/quotes/new` + `QuoteForm.svelte` +
      `QuoteSummaryCard.svelte` shipped, list's New Quote is a link, browser-verified 2026-08-20
- [ ] 3D detail - implementation and static gates passed 2026-08-20; Jafar deferred its two-record browser
      gate into Part 4 when ending the session

## What 3A left for the pages

- `POST /api/quotes`, `GET /api/quotes` (search, status and date filters, sort by created or number, keyset
  paging), `GET /api/quotes/counts`, `GET|PATCH /api/quotes/:id/lines`, `PATCH /api/quotes/:id/draft`,
  `POST /api/quotes/:id/archive` and `/restore`, and an extended `GET /api/quotes/:id`.
- Client sort is not offered: the name lives on `clients`, so it cannot be keyset paged from an index on
  `quotes`. Created and Quote number are the two sorts, both index-backed.
- The Overview card counts live and scans the tenant; see `Memory/deferred/INDEX.md`.

## What 3B left for 3C and 3D

- The Quote number in the table is plain text and rows do not navigate, because `/quotes/[id]` does not
  exist until 3D. 3D turns the number into the link and gives `DataTable` its `onRowActivate`.
- `New Quote` in the header is disabled with a reason. 3C turns it into a link to `/quotes/new`.
- The bulk bar's Archive is disabled; `POST /api/quotes/:id/archive` already exists behind it.
- `GET /api/quotes` now also returns the organization's `locale`, so the Total column writes money the same
  way the pricing block does.

## What 3C left for 3D

- The shared block's saved-document mode is what 3D's `/quotes/[id]` uses: pass `lines`, `revision`,
  `editable`, `attachTo={{ entityType: 'quote', entityId }}` and an `onSave` that PATCHes
  `/api/quotes/:id/lines`. `GET` there returns `source_catalog_item_id`, so the adapter maps that name to
  `catalog_item_id` before handing rows over.
- Line photos are off in the composer (`attachTo` null) because nothing exists to attach them to before
  Save. They come back on the detail page. Jafar's call, 2026-08-20.
- Saving lands on `/quotes?saved=<number>` with a confirmation line. 3D points it at the quote instead.
- `GET /api/quotes/counts` now also returns `currency_code` and `locale`; `fetchQuoteOverview` replaced
  `fetchQuoteCounts`. That is how the composer knows the money format before a quote exists.
- The Overview rail card shows Subtotal and Total only. Tax and Discount rows arrive with Part 4.

## Non-discoverable risks

- `RequestPricingBlock.svelte` is 1194 lines and bound to the request pricing API. Copying it for Quotes is the
  wrong move; 3C splits it once, and the Request page must be re-verified after the split.
- Business conflicts use `P0409`. `40001` is retried by PostgREST and the request never answers.
- Quote #1 belongs to demo request "Panel upgrade quote" (263f718d) and its pricing is frozen.
- The TypeScript half of the notes/attachments seam was still refusing quotes after 3A widened the
  database. Three more edits fixed it: `linkedEntityTypeSchema`, browser `EntityType`, and all four
  branches of `$lib/server/access/collaboration.ts` (quote view rides `quotes.view`, writes ride
  `quotes.edit`). A quote note now saves; verified in the browser.
- Widening the polymorphic notes/attachments seam takes three edits, not two: the four `entity_type` checks,
  the view/manage dispatchers, and `private.linked_entity_exists`. Missing the third refused every quote
  attachment with "The linked quote was not found in this organization."
- The archived-client rule in the contract says new work restores the client. `create_quote` refuses instead,
  matching what Request creation already does; restoring on create is a Clients-side decision nobody has made.

## Pointers

- `docs/quote-behavior-contract.md` - Identity/lineage, Staff Quote financial rail, Lifecycle.
- `.claude/skills/jobber/jobber-03-quotes.md` §8.1 line block, §8.2 list/composer/detail tour.
- `Design/Quotes new.jpg`, `Design/Quote Details.jpg` - blueprints.
- `parts/02-pricing-and-request-carry-forward.md` - shipped pricing foundation.
