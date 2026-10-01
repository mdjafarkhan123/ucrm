# Pipeline upgrade — stage D: move, find, and work at volume

Approved by Jafar 2026-10-01. Plan § First-release
board (search, lead source, saved filters, table, bulk tools), § Movement and automation, § Platform; audit
items A5, B1, B7, B8, C5. D2, D4, and D6 are scale-sensitive — run the `performance-review` design branch first.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| D1 Move button on every card | Every allowed destination is offered without dragging; a blocked one gives the exact reason and next step; a reversible move offers a short Undo; an irreversible one asks first | A2, B3 | Using only the keyboard, a card goes from New requests to Assessment scheduled; a blocked destination explains why; Undo after "assessment required" puts the card back | Not started |
| D2 Search, lead source, and New button | Search by client or contact name, title, Request or Quote number, address, phone, and email; a lead-source chip and filter; a New request / New quote button | A1 | Typing a phone number finds its card; filtering by one lead source shows only those cards and the column counts and totals agree | Not started |
| D3 Saved filters | Each person saves their own filters; an admin shares filters with everyone | D2 | A salesperson's saved filter is still there after signing in again and only they see it; an admin's shared filter shows for everyone and only admins can change it | Not started |
| D4 Table view | The same cards as a sortable table with the same search and filters | D2 | Switching between Board and Table keeps the filters; a row opens the same Brief | Not started |
| D5 Phone view | A compact list with a stage picker and tap-to-move; nothing needs dragging | D1 | At phone width the list shows, a card opens its Brief, and a tap moves the card | Not started |
| D6 Bulk tools | Select several cards to change owner, add a Task, or place them in a custom stage; nothing else is offered in bulk | A2, D4 | Five selected cards are reassigned to one person at once; no bulk send, convert, close, or protected-stage move exists | Not started |

Carried from stage A: a card's menu lists every custom stage of its section in one flat list; the Move
button replaces it. Any new way of placing a card, bulk placement included, must go through
`pipeline_place_opportunity` so an on-hold stage still asks for its future Task — the board answers that
refusal (`NEEDS_FUTURE_TASK`) by opening the Task dialog in `PipelineColumn.svelte`.
