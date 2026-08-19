# Part 2: Ownership, Value, Dates, and Board Controls

Status: Approved by Jafar 2026-08-19. Closed 2026-08-19.

## Outcome

Staff can see who owns each open opportunity, identify overdue follow-up, record a genuine estimate and
planning dates, and narrow or order the whole board without changing Request or Assessment truth.

## Reference boundary

- Follow Jobber for one salesperson or Unassigned, card avatars, salesperson and created-date filters, and
  sorting by time in stage, created date, or value.
- A live Jobber Pipeline tour is unavailable on Jafar's trial. The authoritative visual evidence is
  `Design/pipeline/1.webp` .. `16.webp`, summarized in
  `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1, plus Jobber's official Sales Pipeline article.
- Deliberate UCRM differences: never render `$0.00` as missing data; omit lead source from the first release;
  add optional expected close and next follow-up from `docs/PRODUCT.md`; protect values from users without
  pricing/revenue visibility.

## Approved behavior

### Ownership

- An Opportunity has one salesperson or is Unassigned.
- Staff with Pipeline edit access can assign, reassign, or clear ownership from the card menu and the
  Opportunity Brief.
- The assigned person's avatar appears on the card. The brief shows their name and avatar.
- Only current organization members eligible to work in Pipeline may be newly assigned.
- Team-member removal or deactivation must not erase historical ownership. Do not invent a team lifecycle in
  this part; stop and report if preserving this requires changing the approved Team model.

### Estimated value

- A Request-backed Opportunity may have one optional manually maintained estimated value.
- Missing value renders as nothing, never `$0.00`, a dash presented as money, or a zero included in totals.
- A real value appears on the card, in the Opportunity Brief, and in its column's value total.
- The value may be cleared. A future Quote-backed Opportunity uses Quote truth instead of inheriting this
  estimate; Quote behavior remains Part 5.

### Dates

- Created date remains the card's primary date and the date-range filter's meaning.
- Expected close date is an optional planning date shown in the Opportunity Brief.
- Next follow-up is optional, shown in the brief and as a compact card line; overdue follow-up is visibly red
  and is also conveyed without relying on color alone.
- Editing value, owner, expected close, or next follow-up never changes `stage` or `stage_entered_at`.

### Board controls

- Add a desktop control bar above the board: Sort by, direction, Salesperson, created Date, and matching result
  count. Reuse accessible project controls.
- Sort choices: Time in stage, Created date, Value. Default remains newest stage entry first. Direction toggles
  newest/oldest or highest/lowest as appropriate. Missing values always remain last.
- Salesperson choices: All, Unassigned, or one eligible team member.
- Created-date choices: All, Last week, Last 30 days, Last month, This month, This year, Last 12 months, and a
  custom range. Calendar boundaries use the organization's timezone.
- Filters stack. Cards, column counts, column value totals, group count, and result count all describe the same
  filtered set. Paging one column must not reset or recount unrelated state incorrectly.
- The selected controls survive refresh and browser back/forward navigation.
- A filtered board with no matches keeps its columns and controls visible; it does not become the new-account
  empty state.
- Value totals and Value sorting are absent for users who cannot see pricing/revenue, including from payloads
  and indirect ordering. Pipeline view access alone must not leak money.

### Opportunity Brief

- Grow Part 1's existing drawer with one Opportunity details section: salesperson, estimated value, expected
  close date, and next follow-up.
- Keep View Request and the existing client/property/contact context stable.
- Part 3 adds tasks, notes, and activity to this drawer; Part 2 must extend it rather than replace it.

## Explicitly out of scope

- Lead-source display or filtering.
- Tasks, notes, activity, AI summaries, and task-derived follow-up behavior.
- Won, Lost, reopen, outcome tiles, and Sales Outcomes reporting.
- Quote stages, Quote values, dragging, custom stages, or any placeholder Quote schema.
- Mobile Pipeline behavior.

## Implementation checklist

- [x] Add the tenant-safe persisted owner/value/date foundation and secure write boundary. Preserve stage
      derivation and stage history exactly. Done 2026-08-19 in
      `supabase/migrations/20260818232309_pipeline_opportunity_ownership_value_dates.sql`: four columns, the
      `pipeline.view_value` permission, an owner-eligibility trigger, and
      `public.pipeline_update_opportunity_details`. `estimated_value` carries no member privilege at all, so
      every read of it must go through a definer function from here on.
- [x] Make owner, value, and dates available to board cards and the Opportunity Brief without exposing money
      to users lacking pricing/revenue access. Done 2026-08-19: `public.pipeline_board_page` (migration
      `20260818233830`) is the board's only read; `/api/pipeline/opportunities` omits the value field
      entirely without `pipeline.view_value`; `/api/pipeline/summary` carries `can_view_value` plus the
      organization's currency, locale and timezone. Cards show owner avatar, real values and the follow-up
      line; the Brief has a read-only Opportunity details section. Editing is still items 6 and 7.
- [x] Make each column's paging support the approved stacked filters and all three stable keyset sorts, with
      missing values last. Done 2026-08-19 in migration
      `20260819002041_pipeline_board_page_sort_and_filters.sql`: one extended `pipeline_board_page`, five
      board indexes, and `GET /api/pipeline/opportunities?sort=&direction=&owner=&date=&from=&to=`.
      Verified on 50,000 rows — ten full column walks, every sort and both directions, stacked owner and
      date filters, all complete with no repeated or lost card and no order break. Test rows deleted and
      the table reindexed. Two approved decisions changed under measurement, recorded below.
- [x] Make the board summary return filtered counts and permitted value totals in one board-level read.
      Done 2026-08-19 in migration `20260819024238_pipeline_board_summary_filters_and_totals.sql`:
      `pipeline_stage_counts` takes the same owner and created-date parameters the columns take and
      returns a per-column value total, and `/api/pipeline/summary` answers `counts`, `result_count`,
      `value_totals` (omitted entirely without `pipeline.view_value`) and the formatting. Verified live:
      the summary and the column read return the same set for the same filter. **The heading still does
      not render the total — item 5 owns that presentation.**
- [x] Add the control bar and URL-backed filter/sort state, and render the permitted value total on each
      column heading. Done 2026-08-19: `src/lib/pipeline/filters.ts` is the shared filter vocabulary the
      URL, the query keys and the two routes all read (the sort/direction/preset lists moved out of
      `$lib/server/pipeline/board.ts`, which browser code may not import); `BoardControls.svelte` is the
      pill bar; both query keys now carry the filters. Browser-verified: owner, all three sorts, both
      directions, presets, custom range, deep links, back and forward. **The URL is the only state** —
      see the derived-not-effect note below.
- [x] Add the card ownership action without nested interactive controls or lost keyboard behavior. Done
      2026-08-19: `PATCH /api/pipeline/opportunities/[id]/owner`, `pipeline.edit`-gated, is the first caller
      of `pipeline_update_opportunity_details`. `can_edit` was added to `/api/pipeline/summary` alongside
      `can_view_value` and threaded through `+page.svelte` → `PipelineColumn` → `OpportunityCard`.
      `OpportunityCard.svelte` is now a `<div>`: a stretched, transparent `<button>` (`z-index: 1`) covers
      it for the open action, and the owner control sits in its normal flow position with
      `position: relative; z-index: 2` so it is its own click/keyboard target instead of being swallowed by
      the button beneath it — never a button nested in a button. `DropdownMenu.svelte` gained an optional
      `trigger` snippet and `triggerClass` prop so the owner control could render the member's `Avatar` (or
      an unassigned placeholder) as the trigger, reusing its Root/Content/Item rather than a second dropdown
      implementation. The menu lists Unassigned plus `fetchAssignableTeam`'s list (already warmed by
      `BoardControls`'s Salesperson filter, same key, `staleTime: 300_000`); selecting one calls the new
      route and, on success, `invalidatePipeline(queryClient)`. Browser-verified: assign, reassign, clear,
      the drawer's Salesperson field agreeing with the card, the card's own open action still working from
      a precise click, and no console errors.
- [x] Extend the Opportunity Brief with editable Opportunity details and clear validation/failure feedback.
      Done 2026-08-19: three sibling routes beside `owner` (`.../value`, `.../expected-close`,
      `.../next-follow-up`), all calling `pipeline_update_opportunity_details`. `OpportunityCard`'s
      owner-assign dropdown moved into shared `OpportunityOwnerField.svelte` so the Brief could reuse it.
      New `OpportunityDetailsSection.svelte` gives each row a pencil that opens it in place — dropdown/date
      pickers commit on select, value commits on blur/Enter, Escape reverts — and a failed write shows
      inline on its own row rather than a toast, so the retryable value stays visible next to the error.
- [x] Invalidate affected Pipeline caches after writes while keeping unrelated cached work stable. Done
      2026-08-19 via the existing `invalidatePipeline(queryClient)`, same as the owner route. **Found and
      fixed same day:** the Brief holds `selected`, a click-time snapshot invalidation never reaches, so an
      edit updated the card underneath but not the open Brief until it was reopened. Fixed with a new
      `onUpdate(patch)` callback from `OpportunityDetailsSection` up to `+page.svelte`, merging each
      mutation's own response onto `selected`; `OpportunityOwnerField` gained `onAssigned` for the same
      reason, resolving the full owner record from its own loaded team list (the PATCH only returns an id).
      Browser-verified: editing any field updates the Brief, the card, and the column total together.
- [x] Regenerate database types and add proportional database, API, component, and browser checks. Done
      2026-08-19: no migration landed in items 7-8, and `src/lib/database.types.ts` already carried every
      Part 2 column and the RPC's signature from item 1, so type regeneration was confirmed unnecessary
      rather than skipped. Added `src/lib/server/validation/pipeline.schema.spec.ts` (the three new field
      schemas — value, expected-close, next-follow-up — including the negative/ceiling/non-finite/bad-shape
      refusals); a colocated `.spec.ts` beside each of the three sibling routes covering the permission
      short-circuit, validation-before-database-call, the null-clears path, both named database error codes
      (`23514`, `42501`), an unnamed error, and the empty-row not-found case; and
      `OpportunityDetailsSection.svelte.spec.ts` (`*.svelte.spec.ts`, the browser project) driving the
      estimated-value row's real pencil-click → type → blur/Escape flow against a mocked `fetch`, proving
      the commit-on-blur save, the Escape revert, and the inline (not toast) failure message with the
      retryable value still in the field. One thing worth keeping in mind for the next component test in
      this app: a shared mocked `Response` across two in-flight fetches (here, the Brief's own value PATCH
      racing the Salesperson field's team-list load) breaks the second reader, because a body stream can
      only be read once — build a fresh `Response` per call instead. 37 new tests, 517 total, all passing;
      `npm run check` is 0 errors.

## Acceptance checks

- An authorized user can assign, reassign, and clear an eligible salesperson; a read-only user cannot.
- All, one-person, and Unassigned filters return the same set reflected in cards, counts, totals, and results.
- Each date preset and custom range uses organization-local boundaries and combines with owner filtering.
- All sort choices and both directions remain stable across Load more; tied rows do not duplicate or disappear.
- Missing value is never rendered or counted as `$0.00`; real values format in the organization's currency.
- A user without pricing/revenue visibility receives no values/totals and cannot infer them through Value sort.
- Overdue follow-up is understandable visually and to assistive technology.
- Editing Part 2 fields cannot move a card or append a stage event.
- Filters survive reload and browser navigation; a zero-result filter keeps the board controls available.
- Desktop keyboard, focus, screen-reader labels, narrow-desktop wrapping, dark theme, and long names/titles pass.
- Tenant isolation, permission denial, invalid member/value/date input, and concurrent updates are verified.

## Required pointers

- `docs/PRODUCT.md` §10 and `docs/sales-pipeline-behavior-contract.md`
- `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6–4.6.2
- `Design/pipeline/1.webp` .. `16.webp`
- `Memory/campaigns/sales-pipeline/parts/01-request-side-foundation.md`
- `supabase/migrations/20260818133431_sales_pipeline_opportunity_foundation.sql`
- `src/routes/api/pipeline/`, `src/lib/pipeline/`, and `src/lib/components/pipeline/`
- `src/routes/api/team/assignable/+server.ts`, `src/lib/team/api.ts`, and shared UI wrappers

## Item 3 design — approved by Jafar 2026-08-19, shipped with two measured corrections

Two things the design assumed turned out to be wrong when measured, and the shipped code follows the
measurement. Both are recorded in full in the migration's own comments.

1. **The cursor is a row comparison, and ties break in the sort's own direction.** The design's
   "less than, or equal and then the id" cursor is a filter to Postgres, not an index condition: on page
   200 of a 12,500-card column it read and threw away 5,024 rows and touched 67 buffers, against 0 rows and
   4 buffers for `(sort column, id) < (value, id)`. A row comparison only works when both index columns run
   the same way, so ties now break on the id in the same direction as the sort.
2. **`opportunities_board_idx` was rebuilt, not reused.** It was descending with an ascending id after it,
   which no row comparison can use; it is now ascending on both, read forward for oldest first and backward
   for newest first. This is the same one index doing the same one job, in the shape the cursor needs — not
   a duplicate of it.
3. **Five board indexes, each measured.** The two the design named, plus one for the unestimated half of
   the value sort (without it the planner sorts every unestimated card in the column before applying the
   limit), plus the owner-leading one the design left conditional — it turned one salesperson's cards in a
   12,500-card column from 12,266 buffers and 11 ms into 5 buffers and 0.9 ms, so it earned its place. It
   covers the default sort only; filtering while also re-sorting by date or value stays a scan.

The approved design, unchanged in every other respect:

- **One function, extended.** `pipeline_board_page` gains `sort_key`
  (`stage_entered_at` | `created_at` | `estimated_value`), `sort_direction`, an owner filter
  (`all` | `unassigned` | one member), and created-from/created-to bounds. No second read model.
- **Cursor becomes sort-aware.** It carries the sort it was made for plus that sort's value and the id;
  a cursor whose sort does not match the request is refused rather than silently paging the wrong order.
- **Missing values last, and still keyset.** Value sorting pages the estimated rows first and the
  unestimated ones after, with the phase carried in the cursor, so nulls never break the cursor.
- **Money stays gated.** Sorting by value is refused for a caller without `pipeline.view_value`, so the
  order itself cannot be used to read amounts.
- **Calendar boundaries** are turned into timestamps in the API from the organization's timezone, so the
  function stays simple and the presets are testable.
- **The salesperson filter is a normal supported path**, not an edge case, and is tested as one.
- **Smallest index set first.** Reuse `opportunities_board_idx` for the stage-entry sort — never build a
  duplicate of it. Add only the two missing sort shapes
  `(organization_id, stage, <created_at | estimated_value>, id) where outcome = 'open' and stage <>
  'request_closed'`, ascending served by a backward scan. Add an owner-leading variant only when
  `EXPLAIN (ANALYZE, BUFFERS)` shows it materially improves the measured plan; an index that does not
  earn its place is not kept.
- **Required test matrix**, on 50,000 rows with a skewed owner distribution and most values null:
  All, Unassigned and one assigned person, across every sort and both directions, with deep cursors and
  restrictive date ranges. Prove both phases of Value sorting stay stable and efficient, with missing
  values always last, and that no page repeats or loses a row.
- **Tenant and money protections are preserved throughout**, and the 50,000 test rows are deleted and the
  table reindexed and analyzed afterwards.

## Item 4 as built — 2026-08-19

- **`pipeline_stage_counts` stopped being a security invoker function.** Members hold no privilege on
  `estimated_value`, so an invoker `sum()` is simply refused. It is now definer and re-applies the same
  rules by hand: tenant and `pipeline.view` from `private.permitted_organizations`, money behind
  `private.member_has_permission(..., 'pipeline.view_value')`.
- **Client visibility is deliberately not one of those rules.** A member who cannot see a client still
  sees that client's card with its details blanked, so the card is still counted. Counting only readable
  clients would make the heading disagree with the column under it.
- **No new index.** Measured on 50,000 open cards in one organization: the grouped count and sum is an
  index-only scan on `opportunities_board_value_idx` — 622 buffers, 0 heap fetches, 22 ms. Owner-filtered
  is 972 buffers / 18 ms, date-filtered 3,411 buffers / 9 ms. Test rows deleted, table reindexed and
  vacuumed.
- **The heading total is an on-demand aggregate, not a materialized view**, because it has to answer for
  whatever the staff member just filtered to and has to match the cards exactly. The ceiling is measured,
  not assumed: revisit if one organization's open board passes roughly 100,000 cards.
- **`result_count` is added up from the four counts**, never counted separately, so it cannot disagree
  with the headings.
- **The date presets are confirmed by Jafar** (2026-08-19): Last week is the previous Sunday–Saturday,
  Last month the previous whole calendar month, Last 30 days is today plus the preceding 29, Last 12
  months runs from the same local date a year ago through today, This month/year run from the period's
  start through today; every boundary is half-open in the organization's timezone, ending at the start of
  the following local day, weeks starting Sunday. `last_12_months` was corrected to match — it used to
  start the day after.

## Item 5 as built — 2026-08-19

- **The applied filters are `$derived` from the URL, never `$state` written from an `$effect`.** The first
  build held them in state and synced them in an effect, which runs after the render that read it: the
  columns re-keyed and the summary did not. On the back button the cards came back filtered while the
  counts, totals and result line still described the board you had just left, and no summary request fired
  at all. The same mistake also fired the summary twice on every forward change. Both went away with the
  derived. Anything added to this bar must stay derived from the URL.
- **An incomplete custom range simply does not apply the date filter.** A range with neither end chosen is
  refused by the schema, so rather than firing it and showing a validation failure, `applied` drops the
  range while keeping owner and sort. The controls show "Pick at least one end of the range."
- **A filtered board with no matches keeps its columns and controls.** `boardIsEmpty` is now
  `requestsTotal === 0 && !isFiltered`, so only a genuinely empty board gets the new-account message.
- **A `sort=value` link in the hands of a member without money** falls back to the default sort once the
  summary answers `can_view_value: false`, rather than 403-ing all four columns.
- Each control change costs exactly five requests — four columns and one summary — measured in the browser.
- The date pill says "Created" rather than carrying only Jobber's calendar icon: our other two pills are
  labelled, and three pills reading "All" tell nobody which is which.
- `Select`'s dropdown sizes itself to its trigger (`--bits-floating-anchor-width`), so a select dropped into
  a shrink-wrapping pill needs an explicit width or every option truncates to a letter and an ellipsis.

## Standing rules this part established

- Members hold **no** privilege on `estimated_value` and **no write privilege at all** on `opportunities`
  (migrations `20260818232309` and `20260818233632`). Every read of value and every write of the Part 2
  fields goes through a definer function that checks the caller. A new column on this table is invisible to
  members until it is added to the column grant list.
- `pipeline_board_page` runs with owner rights, so it re-applies by hand every rule row level security would
  have applied: tenant and `pipeline.view` from `private.permitted_organizations`, client details behind
  `can_view_client`, owner name behind current team membership, value behind `pipeline.view_value`. Any
  column added to it must be checked the same way.
- `requireOrganizationPermission` now returns the resolved access alongside `auth`; ask a second permission
  with `hasPermission(check.access, key)` rather than resolving again.

## Non-discoverable risks

- The only existing revenue-related permission is customer-specific and may not express Pipeline pricing
  visibility correctly. The approved behavior requires a real pricing/revenue permission boundary; do not
  silently leak values through the existing `pipeline.view` response.
- `organization_members` currently has no inactive-member lifecycle. Preserve historical ownership without
  expanding Part 2 into Team lifecycle work.
- The current board index and cursor assume only `stage_entered_at desc`. Every added sort/filter combination
  must remain keyset-paged and measured against realistic data before its index shape is accepted.
- The card is currently one large button. A card menu cannot become a button nested inside that button; preserve
  one clear card-opening target and independent accessible menu behavior.
- Part 1 and adjacent campaigns are uncommitted user work. Preserve unrelated changes and the protected files
  named in `NOW.md`.

## Completion gate

Staff can find and maintain accountable open work without Pipeline state contradicting Request truth. Money
appears only when real, stays permission-safe, and every card/count/total remains consistent under filtering,
sorting, paging, and edits.
