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
| 5 Pickers | CalendarPicker, TimePickerField, TimePicker, DateTimePicker, TimezonePicker, CountryPicker | `J3g7hi` rejected (traced the live pickers); redrawn as `uSXlT` "Pickers v2" 2026-10-19, **waiting for Jafar** |

## Batch 5 redraw decisions (Jafar, 2026-10-19)

New behaviour approved: quick dates (Today, Tomorrow, Next week = next week-start day) above the month; time
pop-up is one 15-minute list (typing any time still works; replaces hour/minute/AM-PM columns); end-time list
shows each line's length from the start ("2 hr"). Declined: current local time in time-zone rows. Look: indigo
`color-time` tile at the front of date/time/time-zone boxes, weekday beside the date, raised green picked day,
today = green date + dot, round flags, grey code/offset pills, typed letters in green. After approval, delete
`J3g7hi`.

## Approved reference and proof

Looks live in design modules `modals.md`, `page-states.md`, `inputs.md`, `badges.md`. Build notes: confirmation
focus starts on Cancel; form dialogs keep live widths (400/600/640/940). Field build details, checks and
screenshots: `c5-fields-followup.md`.

## Screen-by-screen leftovers

About 96 form pop-ups keep buttons inside the body, around 120 have no icon, and empty states default to a blue tile. Fix each during its screen redesign. Other controls (MoneyInput, StatusBadge…) stay on the checklist separately.

## Batch 4 (approved 2026-10-19)

Board `j3jDI`; looks are in design modules `layout.md`, `cards.md`, `notices.md`. Build notes: the card tile's
live default `job` tone must become a per-caller tone; Banner has no close (live has none). Next batches:
pickers, small controls, then files and lists. Codex builds approved parts and Schedule on its own branch;
Claude draws, reviews and merges (Jafar 2026-10-19).

## Next

Continue remaining rows in `stages/list-1a-parts.md`, then Schedule. Build only approved designs; page-level journeys retain their existing behavior.

**Rollout rule (Jafar, 2026-10-19):** an approved built shared part applies at every call site. SegmentedControl, Checkbox and ClientPicker had their concept appearance gated by a page wrapper; restriction removed and verified live on New client and New job. Light/dark switch screenshots: `docs/evidence/2026-10-19-fields/client-switches-*.jpg`. Focused ESLint, Svelte compile and autofixer passed.
