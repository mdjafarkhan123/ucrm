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
| 5 Pickers | CalendarPicker, TimePickerField, TimePicker, DateTimePicker, TimezonePicker, CountryPicker | Approved `uSXlT` "Pickers v2" 2026-10-19 (old `J3g7hi` deleted); for Codex to build |
| 6a Small controls | Avatar, Toggle, RadioGroup, Tabs | Approved `GbgcY` 2026-10-19: Avatar A, Switch A, Radio A (improved live), Tabs B (soft capsules); looks in `avatars.md`, `tabs.md`, `inputs.md`; for Codex to build |
| 6b Inputs and chips | FilterChip, MoneyInput, QuantityInput, TagSelect | Approved `Fma1f` 2026-10-19: Filter A + name/value divider, Money B, Quantity B, Tags A tinted in their own colour; looks in `chips.md`, `inputs.md`; to build |
| 7 Small helpers | ListLoadMore, FormErrorSummary, PencilButton, KpiCard | Approved `eJ0QQ` 2026-10-19: Load more B (footer bar with count), Form error B (checklist card), Pencil button A (icon button), Number cards B with note 12/500; looks in `lists.md`, `notices.md`, `buttons.md`, `cards.md`; to build |

## Batch 5 redraw decisions (Jafar, 2026-10-19)

New behaviour approved: quick dates (Today, Tomorrow, Next week = next week-start day) above the month; end
times show their length from the start ("2 hr after start" chip). Declined: current local time in time-zone
rows; a 15-minute time list (Jafar: the live hour / minute-in-5s / AM-PM picker is more flexible — keep it,
improved look; Jafar picked the "indigo dial": hour : minute columns fading from a soft `color-time-surface` band, AM/PM segmented switch, green only on Done; A/C options deleted). Rule: per part, a new look or an improved live look, never a copy (design skill pref 9). Look: indigo
`color-time` tile at the front of date/time/time-zone boxes, weekday beside the date, raised green picked day,
today = bold date + green dot, slim quick-date pills (Jafar chose green over indigo), round flags, grey code/offset pills, typed letters in green.

## Batch 6b new behaviour (Jafar, 2026-10-19)

- Quantity: − / + change the count by 1; − is disabled at 1; typing decimals still works.
- Money: show thousands commas once the box is left; the sign comes from the business currency, so callers
  drop "(USD)" from labels.
- Tags: each tag uses the existing `tags.color` column (one of ten palette colours, stored as its light hex and
  mapped to the token family so dark mode follows). A new tag gets the next unused colour; whoever may create
  tags may change a tag's colour from the list's "⋯" menu; colour changes everywhere. Pick-only people see no
  "⋯". Replaces the random `colorForId` colours and the grey `quiet` look.

## Approved reference and proof

Looks live in design modules `modals.md`, `page-states.md`, `inputs.md`, `badges.md`. Build notes: confirmation
focus starts on Cancel; form dialogs keep live widths (400/600/640/940). Field build details, checks and
screenshots: `c5-fields-followup.md`.

## Screen-by-screen leftovers

About 96 form pop-ups keep buttons inside the body, around 120 have no icon, and empty states default to a blue tile. Fix each during its screen redesign. Other controls (MoneyInput, StatusBadge…) stay on the checklist separately.

## Batch 4 (approved 2026-10-19)

Board `j3jDI`; looks are in design modules `layout.md`, `cards.md`, `notices.md`. Build notes: the card tile's
live default `job` tone must become a per-caller tone; Banner has no close (live has none). Codex builds approved parts and Schedule on its own branch;
Claude draws, reviews and merges (Jafar 2026-10-19).

## Next

Continue remaining approved rows in `stages/list-1a-parts.md`. Batch 4 and Schedule are integrated; build only approved designs and retain existing page-level journeys.

**Rollout rule (Jafar, 2026-10-19):** an approved built shared part applies at every call site. SegmentedControl, Checkbox and ClientPicker had their concept appearance gated by a page wrapper; restriction removed and verified live on New client and New job. Light/dark switch screenshots: `docs/evidence/2026-10-19-fields/client-switches-*.jpg`. Focused ESLint, Svelte compile and autofixer passed.
