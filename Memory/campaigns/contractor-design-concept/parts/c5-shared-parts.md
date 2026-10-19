# C5 — Shared parts first

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3, tier 1.
**Decision:** Jafar chose shared parts before Schedule, 2026-10-19.
**Done when:** each batch is approved in Pencil, built in its shared components and ticked in `stages/list-1a-parts.md`.

## Completed batches

| Batch | Parts | State |
| --- | --- | --- |
| 1 Pop-ups | Dialog, ConfirmDialog, SidePanel | Approved `v2Y89`; built 2026-10-19 |
| 2 Page states | LoadingSkeleton, EmptyState, ErrorState | Approved `v2Y89`; built 2026-10-19 |
| 3 Fields | Input, Select, Textarea, Badge, SearchInput | Approved `khuNF`, including added interaction states; built and checked 2026-10-19 |

## Approved reference and proof

Pop-ups: header with record-coloured tile, body, grey footer; radius 16. Confirmation tones follow meaning; focus starts on Cancel. Drawer 480 wide, floating 12 from the edges. Form dialogs retain live widths (400/600/640/940). Live light/dark proof: New expense, Delete visit, file drawer.

Page states: row-shaped loading placeholders, empty state with meaning-coloured tile and main action, error with red tile and Try again. Live proof: Test Folder empty, Reviews loading, Marketing error. Styling rules: design modules `modals.md`, `page-states.md`.

Fields: labels above boxes; quiet hover edge; dropdown chosen tick and disabled/hover/pressed options; textarea remaining/over-limit wording; search clear feedback; roomier status and record pills. Light/dark form example remains on the Fields board. Rules: `inputs.md`, `badges.md`. Build details, checks and screenshot pointers: `c5-fields-followup.md`.

## Screen-by-screen leftovers

About 96 form pop-ups keep buttons inside the body, around 120 have no icon, and empty states default to a blue tile. Fix each during its screen redesign. Separate controls such as CountryPicker, MoneyInput and StatusBadge remain on the checklist; completing the five field components does not complete those controls.

## Next

Continue remaining rows in `stages/list-1a-parts.md`, then Schedule. Build only approved designs; page-level journeys retain their existing behavior.

**Rollout rule (Jafar, 2026-10-19):** an approved built shared part applies at every call site. SegmentedControl, Checkbox and ClientPicker had their concept appearance gated by a page wrapper; removing that restriction is the current corrective slice.
