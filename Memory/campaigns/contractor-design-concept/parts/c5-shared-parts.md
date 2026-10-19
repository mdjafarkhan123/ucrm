# C5 — Shared parts first

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3, tier 1
**Decision (Jafar, 2026-10-19):** draw and build the most-used shared parts before Schedule (option A), so later
screens reuse them.
**Done when:** each batch is approved in Pencil, built in its shared component, and ticked in `stages/list-1a-parts.md`.

## Batches, most used first

| Batch | Parts | State |
| --- | --- | --- |
| 1 Pop-ups | `ui/Dialog` (form pop-up), `ui/ConfirmDialog` ("are you sure?"), `layout/SidePanel` (side drawer) | Approved 2026-10-19 (`v2Y89`); **built 2026-10-19** |
| 2 Page states | `data-display/LoadingSkeleton`, `EmptyState`, `ErrorState` | Approved 2026-10-19 (`v2Y89`); **built 2026-10-19** |
| 3 Fields in code | `ui/Input`, `ui/Select`, `ui/Textarea`, `ui/Badge` (drawn ✅, not built), `ui/SearchInput` | Approved on Fields board `khuNF`; built and browser-checked 2026-10-19 |
| Then | the remaining `list-1a-parts.md` rows in order | — |

## Batch 1 — what the board shows

- Form pop-up: 40 tile in the record colour, title 20/600, optional hint naming the record, × icon button,
  line under the header; body padding 20 gap 16; footer on `--color-surface-background--subtle` with a top line,
  Cancel then the green save. Saving: spinner in the save button, label stays, Cancel disabled.
- "Are you sure?": 480 wide (live), padding 24, no ×. Tile tone: danger (critical, red danger·confirm button), go ahead
  (record colour, green), warning (yellow, "Go back" / "Complete anyway"), notice (one button).
- Side drawer: 480 wide (live 440; the file drawer's three buttons need 480), floating 12 from the edges,
  radius 16, header like the form pop-up, the page dimmed behind it.
- Form pop-up keeps the live widths (small 400, default 600, medium 640, large 940); example is small.
- Radius 16 (today 8) and `--shadow-base`. Tiles follow the colour map: the record the pop-up is about.
  Checked in light and dark; rechecked against the 12 design preferences 2026-10-19.

**Behaviour kept:** live props only (title, icon, tone, loading, cancel-less notice, subtitle, footer). The
hint line under a form pop-up's title is optional. Example wording is illustrative.

## Batch 2 — what the board shows

A Clients card in three states. Loading: row-shaped grey shapes (`--color-border`). Empty: 40 tile in the
page's colour, title 20/600, one line, the one main action. Couldn't load: red tile, live wording, Try again
(secondary, refresh icon). An empty section inside a card keeps the approved one quiet line.

## Built 2026-10-19

Shared `ui/IconTile` and `ui/DialogHeader` (form pop-up and drawer share it); design modules `modals.md`,
`page-states.md`. Checked live, light and dark: New expense, Delete visit (focus starts on Cancel), file
drawer, Test Folder empty, Reviews loading, Marketing couldn't load.

**Left for later screens (not done here):** ~96 form pop-ups keep their buttons inside the body instead of the
grey footer bar; ~120 pop-ups have no icon so show no tile; empty states default to the blue tile until each
screen sets its own colour (`tone`). Each screen's redesign fixes its own: the "Built means the whole piece" rule in `stages/list-index.md`.

## Next

Continue remaining shared parts in `stages/list-1a-parts.md`, then Schedule.

## Batch 3 — what the board shows (`khuNF`, approved 2026-10-19)

Branch `codex/concept-fields`, worktree `.worktrees/concept-fields`, claim `9435b544964a`.
Sections: Text box (empty, filled, mouse over, typing, problem, greyed out; required star, word or icon in
front, small 36), Dropdown (closed states, icon + word in front for filters, open list: radius 16, padding 8,
36 lines, chosen = bold + green tick, mouse over = `--color-surface--hover`, can't-be-picked greyed,
`--shadow-base`, 4–6 below the box), Big text box (96 tall, letters-left count under the right corner, over the
limit in red, problem, greyed out), Search box (× clears, small 38 in a table header with `--color-border`
edge; ⌘K only in the top bar), Status pill (status, record, without dot, plain label, small), and a client card
in light and dark.

**Jafar approved 2026-10-19:** pills roomier (padding 5 11, small 3 9; also on the `Status pill` part
`z1I4U`); mouse-over edge uses `--color-border--interactive--hover` instead of the near-black
`--color-border--section` in `inputs.md` (quieter than the typing ring); the count reads "408 left" /
"12 too many" instead of a bare number. Live behaviour only; nothing new added. Rules written into `inputs.md` and `badges.md`.


**Follow-up states:** approved and built 2026-10-19; proof and limits in `c5-fields-followup.md`.
