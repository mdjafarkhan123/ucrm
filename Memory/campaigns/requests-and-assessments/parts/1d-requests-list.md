# Part 1d — Requests list page

Slice: the first screen where the request routes meet real data. Plan presented to Jafar 2026-08-18 and
**not yet approved** — he paused the session before answering. Nothing is built.

## Build order — each layer through its own performance review before the next

1. **Counts.** Migration for a SQL function that groups the counts, called by a new
   `GET /api/requests/counts`. The route works out today's start and end in the organization's timezone
   and passes them in, so the derived-status rule stays only in `src/lib/server/requests/status.ts` and
   the database just buckets. **Do not write the timezone rule a second time in SQL** — two copies of it
   will drift, and `upcoming` / `today` / `overdue` are wrong the moment they do.
2. **`src/lib/requests/api.ts`.** Types, fetchers, query keys for the list and the counts. Nothing for
   requests exists browser-side yet.
3. **The page** `src/routes/(app)/requests/+page.svelte`, on `Design/Requests.jpg`, top to bottom: header
   with New Request and More Actions; the stat row; search plus Filters; the table. Add `/(app)/requests`
   to the warm list in `src/routes/(app)/+layout.svelte`.

## Approved behavior

- **Columns are Jobber's, not the blueprint's.** Client, Title, Property, Contact, Requested, Status.
  The blueprint's table is a reused client-list mock — its `Name / Address / Contact / Tags / Status` and
  its "New Client" button belong to that screen, not this one. The blueprint still decides the blocks and
  where they sit: the stat row, the search-and-Filters bar, the checkbox column, the row `...` menu.
- **Overview counts, Jafar 2026-08-18:** counted on demand through one small route, not a materialized
  view — accurate always, and swappable later without touching the page. The counts are **read-only**;
  clicking one does not filter the list, matching Jobber. Filtering stays with the Status chip.
- **The blueprint's three KPI placeholders, Jafar 2026-08-18:** draw all three saying what they are
  waiting for, the way Client detail does with Lifetime value. Do not drop them and do not invent
  numbers. Real trends need history; conversion rate needs quotes and jobs to exist.
- Build the Overview card as `StatusOverviewCard` in `src/lib/components/work/` — Quotes, Jobs and
  Invoices all get the same card, per the list-page shape in `jobber-08`.
- Bulk select and More Actions render but are switched off with an honest reason, like the Clients page.
  The actions behind them do not exist.

## Still needing Jafar's answer — all three flagged, none answered

- **New Request button.** Proposed shipping it disabled with an honest reason, since `/requests/new` is
  1f and the button would 404 until then.
- **Load more instead of numbered pages.** The list API is cursor-only, which is what keeps it fast at
  scale but means there is no page 5 to jump to. Jobber has numbered pages. He may want that priced out.
- **Date filter chip dropped.** The list API filters by status only. Proposed shipping Status now and
  deferring Date rather than half-building it.

## Completion gate

Real requests listed with Jobber's columns and the Overview status card; verified in browser.

## Source pointers

- `Design/Requests.jpg` — the blocks and their placement.
- `.claude/skills/jobber/jobber-02-requests-leads.md` §4.1 — the list screen.
- `.claude/skills/jobber/jobber-08-screen-patterns.md` — the shared list-page shape.
- `src/routes/api/requests/+server.ts` — the cursor list this page calls.
- `src/routes/(app)/clients/+page.svelte` — our list-page conventions, but note it pages by offset and
  this one cannot.
