# Part 5C-i: Quotes board read model + column rendering (no drag)

## Scope

The read side only, split off 5C per session-start approval (2026-08-23): make the board's two reads
(`pipeline_board_page`, `pipeline_stage_counts`) answer for the three Quote stages 5A already derives, and
render the Quotes column group on `/pipeline` reusing the exact components the Requests group already uses.
No drag gesture, no drop zones, no schedule dialog — that is 5C-ii, a separate session.

## What shipped

- Migration `supabase/migrations/20260902091000_pipeline_quote_board_read_model.sql`: widened
  `pipeline_board_page`'s `target_stage` check to accept `quote_draft`/`quote_awaiting_response`/
  `quote_changes_requested`, added a `left join public.quotes` and two new returned columns
  (`quote_id`, `quote_status`, the mirror of `request_id`/`request_status`). Widened `pipeline_stage_counts`'s
  fixed `unnest` array from 4 stages to all 7, so a Quote stage's count/total stop being silently dropped.
  No new index needed — `opportunities_board_idx`/`opportunities_board_owner_idx` already cover every stage
  value, and `quotes_pkey` already covers the new join. Client/property/title/estimated_value needed no new
  plumbing: `create_quote`/`convert_request_to_quote` already write them onto the opportunities row.
- pgTAP: `supabase/tests/database/pipeline_quote_board_read_model.sql`, 12 assertions, verified against the
  linked remote project (tenant isolation, money-guarding, both widened functions, Request side unbroken).
- `src/lib/pipeline/stages.ts`: `QUOTE_BOARD_STAGE_LABELS`, `AnyBoardStage` (`BoardStage | QuoteBoardStage`),
  `ALL_STAGE_LABELS`, `isAnyBoardStage`.
- `src/lib/server/validation/pipeline.schema.ts`: `boardQuerySchema.stage` widened to both groups.
- `src/lib/pipeline/api.ts`: `OpportunityCard.quote` (parallel to `.request`), `BoardColumnPage.stage`,
  `BoardCounts`, `BoardSummary.value_totals` all widened from `Record<BoardStage,...>` to
  `Record<AnyBoardStage,...>`.
- `src/routes/api/pipeline/opportunities/+server.ts`: shapes `quote` the same way `request` already is.
  Vitest coverage added (`opportunities.spec.ts`, "board column quote pointer").
- `src/routes/api/pipeline/summary/+server.ts`: counts/totals iterate `ALL_BOARD_STAGES` (both groups);
  `result_count` now sums across both groups, matching Jobber's single combined board count.
- `src/routes/(app)/pipeline/+page.svelte`: a second `SectionBlock` ("Quotes", `file-invoice` icon — the
  same icon already used on `/quotes`) below Requests, its own total badge (`quotesTotal`), a 3-column grid
  (`.pipeline__columns--quotes`, 2-column at the existing `1079px` breakpoint). `boardIsEmpty` now requires
  both groups to be empty.
- `PipelineColumn.svelte`: `stage` prop widened to `AnyBoardStage`, header label reads `ALL_STAGE_LABELS`.
- `OpportunityBriefDrawer.svelte`: stage chip uses `ALL_STAGE_LABELS`/`isAnyBoardStage`; a "View quote"
  button (parallel to "View request") appears when `opportunity.quote` is set, linking to
  `/(app)/quotes/[id]`.
- `OpportunityCard.svelte`: the card's `...` menu ("Mark as lost") is hidden entirely for a quote-backed
  card. This is a real behavior decision, not just wiring: 5A's design left
  `pipeline_mark_opportunity_lost` refusing every quote-backed opportunity outright (quote Lost/Reopen is
  automatic off the Quote's own Decline/archive/Revise), so the dialog this menu opens would fail on submit
  for every Quote card, not only a Draft one the way Jobber greys it out. Hiding it (rather than reproducing
  Jobber's grey-out) matches our actual backend rule.

## Verified this session

`npm run check` clean for every file this part touched (two pre-existing, unrelated failures on untracked
files logged to `Memory/deferred/INDEX.md`, not caused by this work). Full pipeline vitest suite: 19 files,
150 tests passing. `performance-review` run on the DB+API layer: `EXPLAIN (ANALYZE, BUFFERS)` against a real
organization's data confirmed `opportunities_board_owner_idx` still drives the query for a Quote stage, the
new `quotes` join is already covered by `quotes_pkey` (no new index needed, Postgres will switch from its
current small-table seq scan to an indexed nested loop as a tenant's quote count grows), and the summary
widening added no new round trip.

## Browser verification (2026-08-23) — passed, one real gap found and fixed

Opened `/pipeline` for org `18f0d717-904e-48d8-bd99-9df7e3844cda`. Client/title/age, the count badge, the
absent "..." menu, and the Brief's "View quote" button (opened the correct quote, correct total) all passed
immediately. Money did not: every Quote card and the "Awaiting response" column total were blank, even
though the underlying quotes were fully priced ($473.45, $285.00, $876.65).

Root cause: `opportunities.estimated_value` — the only field any card or column total ever reads — was never
written for a quote-backed row by `create_quote`/`convert_request_to_quote`/the similar-quote clone, despite
this packet's original "What shipped" section claiming it needed no new plumbing. It didn't hold: none of
those functions' `insert into public.opportunities (...quote_id...)` statements include the column. Jobber's
own card layout (`jobber-02-requests-leads.md` §4.6.1) confirms the amount belongs on every Quote card,
including `$0` before anything is priced — this was the "amount" half of the checklist, not a side issue.

### Value sync fix (same session)

`supabase/migrations/20260902091100_pipeline_quote_card_value_sync.sql` makes a quote-backed opportunity's
`estimated_value` a derived field, never a manual one:

- `private.quote_current_total_minor(quote_id)` reads whichever `quote_versions` row is current for a quote
  (draft wins over published — the same choice `src/routes/api/quotes/[id]/+server.ts` already makes).
- A `before insert on opportunities` trigger fills it at creation (only when the caller left it null, so a
  fixture that legitimately knows the answer isn't clobbered — production inserts never supply it, the
  column is off both the INSERT and UPDATE grant lists for `authenticated`).
- Two `after update` triggers — one on `quote_versions` (`total_minor`), one on `quotes`
  (`draft_version_id`, `current_published_version_id`) — resync on every later price edit or publish. Two
  separate trigger functions, not one branching on `tg_table_name`: plpgsql caches a compiled trigger
  function's `new`/`old` field lookups per function, and sharing one across `quotes` and `quote_versions`
  threw `record "new" has no field "quote_id"` the first time the untaken branch from an earlier call
  finally ran — caught by the new pgTAP file, not by hand-testing.
- The resync update predicates on `(organization_id, quote_id)` together, matching
  `opportunities_quote_unique` — the same seq-scan mistake `private.opportunity_resync_from_quote`
  (20260902090700) already documented for this table, caught by `EXPLAIN (ANALYZE, BUFFERS)` before it
  shipped.
- `pipeline_update_opportunity_details` now refuses `set_value` for a quote-backed opportunity
  (`check_violation`, same refusal shape `pipeline_mark_opportunity_lost` already uses for quote-backed
  Lost) — the manual editor is no longer a legal way to fight the sync. A backfill sets every existing
  quote-backed opportunity's value immediately.
- Frontend: `OpportunityDetailsSection.svelte`'s pencil-edit for Estimated value is hidden for a quote-backed
  card (`canEditValue = canEdit && opportunity.quote === null`), matching `OpportunityCard.svelte`'s
  existing `canMarkLost` carve-out for the same reason.
- New pgTAP: `supabase/tests/database/pipeline_quote_card_value_sync.sql`, 8 assertions (insert-time fill,
  request-side untouched, price-edit resync, publish resync, manual-edit refusal, request-side manual edit
  still works, helper reads back the same total) — all passing against the linked remote project. The
  original 12-assertion `pipeline_quote_board_read_model.sql` suite still passes unchanged.
- `npm run check` clean; full pipeline vitest suite still 150/150 (the frontend edit only narrows a
  `{#if}` guard, no behavior the existing specs assert on changed).

Re-verified live after the fix: all three Quote cards show their amount, the column total reads
`$1,635.10`, matching the sum.

## Open, not a gate for this part

`/pipeline` stacks the Requests and Quotes groups in two separate `SectionBlock`s (Quotes below Requests).
Jobber puts both groups side by side in one bordered board split by a vertical divider
(`jobber-02-requests-leads.md` §4.6.1). Raised with Jafar 2026-08-23 during this verification; this packet's
original scope was reusing the Requests group's existing components, not the two-groups arrangement, so it
does not block closing 5C-i. See `ROADMAP.md`'s standing decisions for the open question.

## Non-goals (5C-ii, separate session)

No `svelte-dnd-action` wiring, no drop-zone styling, no schedule-assessment dialog, no calling
`dragOpportunity()`/`allowedDragTargets()` from the UI (both already exist from 5B, unused until 5C-ii).

## Source pointers

- `parts/05b-drag-and-move-api.md` — the drag endpoint and transition table 5C-ii wires up.
- `parts/05a-quote-opportunity-identity-and-outcomes.md` — why quote-backed Lost/Reopen never goes through
  `pipeline_mark_opportunity_lost`, the reasoning behind hiding the card menu above.
- `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1 — card/column shape both groups share.
