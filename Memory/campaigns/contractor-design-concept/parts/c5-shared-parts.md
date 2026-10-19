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
| 4 Page parts | PageContainer, SectionBlock, RailCard, Breadcrumbs, Banner | Approved `j3jDI` 2026-10-19 (breadcrumb option C); for Codex to build |
| 5 Pickers | CalendarPicker, TimePickerField, TimePicker, DateTimePicker, TimezonePicker, CountryPicker | Drawn on `J3g7hi` 2026-10-19, **waiting for Jafar** |

## Approved reference and proof

Pop-ups: header with record-coloured tile, body, grey footer; radius 16. Confirmation tones follow meaning; focus starts on Cancel. Drawer 480 wide, floating 12 from the edges. Form dialogs retain live widths (400/600/640/940).

Page states: row-shaped loading placeholders, empty state with meaning-coloured tile and main action, error with red tile and Try again. Styling rules: design modules `modals.md`, `page-states.md`.

Fields: labels above boxes; quiet hover edge; dropdown chosen tick and disabled/hover/pressed options; textarea remaining/over-limit wording; search clear feedback; roomier status and record pills. Rules: `inputs.md`, `badges.md`. Build details, checks and screenshot pointers: `c5-fields-followup.md`.

## Screen-by-screen leftovers

About 96 form pop-ups keep buttons inside the body, around 120 have no icon, and empty states default to a blue tile. Fix each during its screen redesign. Separate controls such as CountryPicker, MoneyInput and StatusBadge remain on the checklist; completing the five field components does not complete those controls.

## Batch 4 (approved 2026-10-19)

Board `j3jDI` "Page parts every screen sits on". Page frame: no white sheet, cards on the warm page, widths full
(cap 1280) / two columns (360 side) / narrow 640; an unredesigned page keeps one white card. Section card and
side card = Card + Card header (already the gated Job details look), tile colour per subject (live default
`job` tone must become a per-caller tone); group inside a card = 16 title over a hairline. Breadcrumbs: white
capsule, dark back circle, chevrons, current step shaded. Banner: tinted strip radius 16, white 32 tile, one secondary action, no
close (live has none). Next batches: pickers, then small controls, then files and lists.
Codex builds approved parts and Schedule on its own branch; Claude draws, reviews and merges (Jafar 2026-10-19).

## Next

Continue remaining rows in `stages/list-1a-parts.md`, then Schedule. Build only approved designs; page-level journeys retain their existing behavior.

**Rollout rule (Jafar, 2026-10-19):** an approved built shared part applies at every call site. SegmentedControl, Checkbox and ClientPicker had their concept appearance gated by a page wrapper; restriction removed and verified live on New client and New job. Light/dark switch screenshots: `docs/evidence/2026-10-19-fields/client-switches-*.jpg`. Focused ESLint, Svelte compile and autofixer passed.
