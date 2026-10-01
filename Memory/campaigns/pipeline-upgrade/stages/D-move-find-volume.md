# Pipeline upgrade — stage D: move, find, and work at volume

Approved by Jafar 2026-10-01. Plan § First-release
board (search, lead source, saved filters, table, bulk tools), § Movement and automation, § Platform; audit
items A5, B1, B7, B8, C5. D2, D4, and D6 are scale-sensitive — run the `performance-review` design branch first.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| D1 Move button on every card | Every allowed destination is offered without dragging; a blocked one gives the exact reason and next step; a reversible move offers a short Undo; an irreversible one asks first | A2, B3 | Using only the keyboard, a card goes from New requests to Assessment scheduled; a blocked destination explains why; Undo after "assessment required" puts the card back | Done 2026-10-01 |
| D2 Search, lead source, and New button | Search by client or contact name, title, Request or Quote number, address, phone, and email; a lead-source chip and filter; a New request / New quote button | A1 | Typing a phone number finds its card; filtering by one lead source shows only those cards and the column counts and totals agree | Done 2026-10-01 |
| D3 Saved filters | Each person saves their own filters; an admin shares filters with everyone | D2 | A salesperson's saved filter is still there after signing in again and only they see it; an admin's shared filter shows for everyone and only admins can change it | Done 2026-10-01 |
| D4 Table view | The same cards as a sortable table with the same search and filters | D2 | Switching between Board and Table keeps the filters; a row opens the same Brief | Done 2026-10-02 |
| D5 Phone view | A compact list with a stage picker and tap-to-move; nothing needs dragging | D1 | At phone width the list shows, a card opens its Brief, and a tap moves the card | Done 2026-10-02 |
| D6 Bulk tools | Select several cards to change owner, add a Task, or place them in a custom stage; nothing else is offered in bulk | A2, D4 | Five selected cards are reassigned to one person at once; no bulk send, convert, close, or protected-stage move exists | Not started |

Carried from stage A: a card's menu lists every custom stage of its section in one flat list; the Move
button replaces it. Any new way of placing a card, bulk placement included, must go through
`pipeline_place_opportunity` so an on-hold stage still asks for its future Task — the board answers that
refusal (`NEEDS_FUTURE_TASK`) by opening the Task dialog in `PipelineColumn.svelte`.

Carried from D1: F8 jumps the keyboard to the newest notification's button (Undo or Dismiss), app-wide.
Undo exists for the five assessment moves (`pipeline_undo_move`) and for custom-stage placement
(`pipeline_undo_placement`); both give the card back its time in stage, last two minutes, and only work
for the person who moved it. Still open: a refused *drag* snaps back without saying why. For stage F: an
Undo leaves two stage events (the move and its reverse) that reports should not count. `npm run check`
needs `NODE_OPTIONS=--max-old-space-size=8192`.

Carried from D2: search and the lead source filter go through `private.pipeline_board_filter_clause`, used by
both the columns and the counts — D3 saved filters and D4 Table must reuse it, not write their own.
Requests have no number, so search finds Quote numbers only. Speed: about 140 ms per column at 5,000 open
cards in one organization; rethink near 20,000.

Carried from D3: D4 Table must keep the Saved button working — it reads the board's controls through
`savedFilterQuery` in `$lib/pipeline/filters.ts`, so a Board/Table switch must not be stored as a filter control.

Carried from D4: the Table asks `pipeline_board_page` for scope `'all'` (`TABLE_SCOPE`), served by the
`opportunities_board_all_*` indexes — 15–30 ms at 5,000 open cards, 71 ms with search plus the Task order.
Board/Table is `view=table` in the URL plus a per-browser memory, never a filter. D6 bulk selection belongs on
`PipelineTable.svelte` (`DataTable` already has `selectable`). At phone width the table only scrolls sideways
until D5 adds the compact list.

Carried from D5: at 639px and narrower the page shows a stage picker plus one `PipelineColumn` (`dragEnabled={false}`), chosen with `MediaQuery` in `+page.svelte`; the Board/Table switch is hidden there. D6 bulk selection has no phone layout yet.
