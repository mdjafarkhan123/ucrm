# C5 — Shared parts first

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3, tier 1
**Decision (Jafar, 2026-10-19):** draw and build the most-used shared parts before Schedule (option A), so later
screens reuse them.
**Done when:** each batch is approved in Pencil, built in its shared component, and ticked in `stages/list-1a-parts.md`.

## Batches, most used first

| Batch | Parts | State |
| --- | --- | --- |
| 1 Pop-ups | `ui/Dialog` (form pop-up), `ui/ConfirmDialog` ("are you sure?"), `layout/SidePanel` (side drawer) | Drawn 2026-10-19 on `concept.pen` board "Concept · Foundation · Pop-ups · 1440" (`v2Y89`); **approved by Jafar 2026-10-19**; build next |
| 2 Page states | `data-display/LoadingSkeleton`, `EmptyState`, `ErrorState` | Drawn 2026-10-19, section "Loading, empty and couldn't load" on `v2Y89`; waits for Jafar |
| 3 Fields in code | `ui/Input`, `ui/Select`, `ui/Textarea`, `ui/Badge` (drawn ✅, not built), `ui/SearchInput` | Not started |
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

## Next

Jafar approves batch 2; then build batches 1 and 2 in their shared components.
