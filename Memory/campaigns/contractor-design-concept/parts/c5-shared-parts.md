# C5 — Shared parts first

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3, tier 1
**Decision (Jafar, 2026-10-19):** draw and build the most-used shared parts before Schedule (option A), so later
screens reuse them.
**Done when:** each batch is approved in Pencil, built in its shared component, and ticked in `stages/list-1a-parts.md`.

## Batches, most used first

| Batch | Parts | State |
| --- | --- | --- |
| 1 Pop-ups | `ui/Dialog` (form pop-up), `ui/ConfirmDialog` ("are you sure?"), `layout/SidePanel` (side drawer) | Drawn 2026-10-19 on `concept.pen` board "Concept · Foundation · Pop-ups · 1440" (`v2Y89`); **approved by Jafar 2026-10-19**; build next |
| 2 Page states | `data-display/LoadingSkeleton`, `EmptyState`, `ErrorState` | Not started |
| 3 Fields in code | `ui/Input`, `ui/Select`, `ui/Textarea`, `ui/Badge` (drawn ✅, not built), `ui/SearchInput` | Not started |
| Then | the remaining `list-1a-parts.md` rows in order | — |

## Batch 1 — what the board shows

- Form pop-up: 40 tile in the record colour, title 20/600, optional hint naming the record, × icon button,
  line under the header; body padding 20 gap 16; footer on `--color-surface-background--subtle` with a top line,
  Cancel then the green save. Saving: spinner in the save button, label stays, Cancel disabled.
- "Are you sure?": 440 wide, padding 24, no ×. Tile tone: danger (critical, red danger·confirm button), go ahead
  (record colour, green), warning (yellow, "Go back" / "Complete anyway"), notice (one button).
- Side drawer: 480 wide (live 440; the file drawer's three buttons need 480), floating 12 from the edges,
  radius 16, header like the form pop-up, the page dimmed behind it.
- Radius 16 and `--shadow-base` stronger than today's 8 radius. Checked in light and dark.

**Behaviour kept:** live props only (title, icon, tone, loading, cancel-less notice, subtitle, footer). The
hint line under a form pop-up's title is optional. Example wording is illustrative.

## Next

Draw batch 2 (page states) on the same board, show Jafar; then build batches 1 and 2 in their shared components.
