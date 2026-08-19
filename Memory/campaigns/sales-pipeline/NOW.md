# Sales Pipeline: Current Checkpoint

## Goal

Build one contractor-friendly commercial board from Request through Quote, copying Jobber's current Sales
Pipeline. Opportunities come from Requests and Quotes and carry ownership, follow-up and outcomes; Request,
Assessment and Quote records stay the operational truth, and a stage is only ever a projection of them.

## Active part

Part 1 closed 2026-08-19. Part 2, ownership/value/dates and the sort/filter bar, is active and approved;
items 1 through 5 are done. Packet: `parts/02-ownership-value-dates-sort-filter.md`.

## Exact next action

Implement Part 2 checklist item 6: the card's ownership action. Assign, reassign and clear the salesperson
from the card, without nesting a button inside the card's own button and without losing keyboard behavior —
see the non-discoverable risk in the packet. The owner/value/follow-up presentation is already built.

**This is where Part 2's write side starts.** `public.pipeline_update_opportunity_details` exists from item
1 and is the only way to write these fields, but nothing calls it yet: `src/routes/api/pipeline/` still holds
only the two GET routes. Item 6 adds the write route (Zod-validated, `pipeline.edit`-gated) that item 7's
Brief editing then reuses. Item 8 owns invalidating the board caches after those writes.

## Current truth

- Part 1 shipped: Opportunities are trigger-created from Requests only, stage is derived and never authored,
  and `/pipeline` renders the four protected Request stages with counts, paging, freshness and the Brief
  drawer. Detail is in `parts/01-request-side-foundation.md`. `outcome` only ever holds `open` until Part 4.
- Item 1 (`20260818232309`): the four columns, the `pipeline.view_value` permission, an owner-eligibility
  trigger, and `public.pipeline_update_opportunity_details` as the single write path. `authenticated` holds no
  privilege on `estimated_value` and no write privilege on `opportunities` at all (`20260818233632`), so
  **any future column is invisible to members until it is added to the column grant list**.
- Item 2 (`20260818233830`): `public.pipeline_board_page` is the board's only read and re-applies every rule
  it runs past by hand. `/api/pipeline/opportunities` omits the value field entirely without
  `pipeline.view_value`; `/api/pipeline/summary` returns `can_view_value` plus currency, locale and timezone.
- Item 3 (`20260819002041`) extended that same function with sort, direction, an owner filter, created-from/to
  bounds and a sort-aware cursor carrying its phase. The route takes `sort=stage|created|value`, `direction`,
  `owner=all|unassigned|<uuid>`, `date=<preset>|custom`, `from`/`to`. Defaults unchanged — verified live.
- **Money is refused twice for the value sort**, in route and function: an order is an answer about amounts.
  Missing values page as their own second phase, always last; a page may cross the boundary.
- **The cursor must stay a row comparison**, `(sort column, id) < (value, id)`, ties breaking in the sort's
  own direction. Written the long way round it becomes a filter and deep pages read and discard everything
  above them; `opportunities_board_idx` was rebuilt ascending for the same reason.
- Five board indexes on `opportunities`, all partial on open and not-closed, all measured on 50,000 rows:
  `_board_idx`, `_board_created_idx`, `_board_value_idx`, `_board_unvalued_idx`, `_board_owner_idx` (default
  sort only).
- Date presets become instants in `src/lib/server/pipeline/board.ts`, on calendar math now shared at
  `src/lib/server/time/calendar.ts` (moved out of `requests/status.ts`); `board.spec.ts` covers them.
- Item 4 (`20260819024238`) extended `pipeline_stage_counts` with the same owner and created-date filters
  and a per-column value total. It is now a definer function for the same reason every other value read is;
  `/api/pipeline/summary` answers `counts`, `result_count`, `value_totals` (omitted entirely without
  `pipeline.view_value`), `can_view_value` and the formatting. No new index — the grouped count and sum is
  an index-only scan on `opportunities_board_value_idx`, 22 ms on 50,000 open cards.
- Item 5 shipped 2026-08-19: the control bar, the URL-backed filter/sort state, filtered requests and query
  keys, the result count, and the permitted value total on each column heading. Browser-verified across
  owner, all three sorts, both directions, presets, custom range, deep links, back and forward.
- **The board's state is derived from the URL and must stay that way.** Holding it in `$state` and syncing
  it from an `$effect` left the summary a tick behind the columns — the back button restored filtered cards
  under unfiltered counts. Detail in the packet's "Item 5 as built".
- **`src/lib/pipeline/filters.ts` is the one filter vocabulary.** The sort, direction and date-preset lists
  moved there out of `$lib/server/pipeline/board.ts`, which browser code may not import; the server module
  re-exports them so the routes and schema kept one import. `boardFilterParams` builds both the URL and the
  request, and `boardFilterKey` builds both query keys, so a key can never describe a different set than
  its request.
- **Card presentation is already built.** `OpportunityCard.svelte` shows the owner avatar, a real value and
  the follow-up line with its overdue state. What item 6 still owes is the card's ownership action only.
- **The date presets are confirmed** (Jafar, 2026-08-19): Last week is the previous Sunday–Saturday, Last
  month the previous whole calendar month, Last 30 days is today plus the preceding 29, Last 12 months runs
  from the same local date a year ago through today, This month and This year run from the period's start
  through today. Every boundary is half-open in the organization's timezone and ends at the start of the
  following local day; weeks start Sunday for this release. `last_12_months` was corrected to match.
- `fetchAssignableTeam` in `src/lib/team/api.ts` (key `assignableTeamKey`) answers the eligible team list;
  the Salesperson filter already uses it, and the card's ownership action should too. No new route for it.
- Four Opportunities in the live org carry seeded owner/value/date data, including a real `$0.00` and an
  overdue follow-up. Editing them from the UI arrives with items 6 and 7. `SidePanel.svelte` in
  `src/lib/components/layout/` is the shared right-hand drawer, for Quote/Job/Invoice too.

## Blockers

None for item 6. Part 5 waits for the Quotes campaign.

## Protected work

Preserve `.claude/settings.local.json` and unrelated campaign work. Keep Requests and Assessments behavior
stable. Never write `stage` or `stage_entered_at` from application code. No placeholder Quote tables or
custom stages before Part 5.

## Required pointers

- `docs/sales-pipeline-behavior-contract.md`
- `Memory/campaigns/sales-pipeline/parts/01-request-side-foundation.md`
- `src/routes/api/pipeline/`, `src/lib/pipeline/`, `src/lib/server/pipeline/board.ts`
- `src/lib/server/access/permission.ts` — ask a second permission with `hasPermission(check.access, key)`
- `Memory/deferred/INDEX.md` — gated routes pay ~400 ms for the access resolver; the nav item is an ungated
  plain link; authenticated list reads are not rate limited
- `Design/pipeline/1.webp` .. `16.webp` and `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6–4.6.2 —
  the board reference. §4.6.1 is the current Jobber build; older `Design/Pipeline.webp` loses to it.

## Active-part completion gate

Part 2: staff can find and maintain accountable open work without Pipeline state contradicting Request truth,
and money appears on cards and column headers only once a real value exists.
