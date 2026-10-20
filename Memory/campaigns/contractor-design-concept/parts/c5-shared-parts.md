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
| 4 Page parts | PageContainer, SectionBlock, RailCard, Breadcrumbs, Banner | Approved `j3jDI` 2026-10-19 (breadcrumb option C); built and merged |
| 5 Pickers | CalendarPicker, TimePickerField, TimePicker, DateTimePicker, TimezonePicker, CountryPicker | Approved `uSXlT` "Pickers v2" 2026-10-19 (old `J3g7hi` deleted); for Codex to build |
| 6a Small controls | Avatar, Toggle, RadioGroup, Tabs | Approved `GbgcY` 2026-10-19: Avatar A, Switch A, Radio A (improved live), Tabs B (soft capsules); looks in `avatars.md`, `tabs.md`, `inputs.md`; for Codex to build |
| 6b Inputs and chips | FilterChip, MoneyInput, QuantityInput, TagSelect | Approved `Fma1f` 2026-10-19: Filter A + name/value divider, Money B, Quantity B, Tags A tinted in their own colour; looks in `chips.md`, `inputs.md`; built and verified 2026-10-19. Proof: `docs/evidence/2026-10-19-batch6b/README.md` |
| 7 Small helpers | ListLoadMore, FormErrorSummary, PencilButton, KpiCard | Approved `eJ0QQ` 2026-10-19: Load more B (footer bar with count), Form error B (checklist card), Pencil button A (icon button), Number cards B with note 12/500; looks in `lists.md`, `notices.md`, `buttons.md`, `cards.md`; built, checked and merged to main 2026-10-20. Proof: `docs/evidence/2026-10-20-batch7-8/README.md` |
| 8 Photos and files | Lightbox, FileThumb, PhotoSlot, FileUploader | Approved `b4BxuV` 2026-10-19: Viewer A with B's glass count and joined download/close, File picture B (paper sheets, file-family tab colours) with A's big check/failed boxes, Photo box A, Upload list B; looks in `files.md`, colours in `colors.md`; built, checked and merged to main 2026-10-20. Proof: `docs/evidence/2026-10-20-batch7-8/README.md` |
| 9 Notes and attachments | AuthorMeta, NoteBody, NoteFiles, PendingFilesCard, AttachmentSurface | Approved `KuOmH` 2026-10-19: Author line B (name over time, Edited tag), Note text B (teal mention chip), Note files B (96×72 photos, file chips), Files waiting B (upload list lines) with A's red-edged failed row, Files card B (labelled Add); looks in `notes.md`, `files.md`; built and verified on `codex/concept-batch9`, waiting to merge. Proof: `docs/evidence/2026-10-20-batch9/README.md` |
| 10 Price book | CatalogItemPicker, CatalogItemDialog, PriceBookDrawer | Approved `ZWTSi` 2026-10-20: Search list B with D's picture cards for items with a photo; New item pop-up C (new concept, green live preview); Drawer B with A's type tags on every row; looks in `price-book.md`; to build |

| 11 File pickers | FilePicker, FileLabelsDialog, PhotoDescribeForm | Approved `K04pQm` 2026-10-20: Add files B (places side column, pick boxes, picked-files tray), Photo labels A (improved live), Photo details B (caption card, Not saved strip); looks in `files.md`; to build |
| 12 Time clock | RunningClock, TimerElapsed, TimerRunningElsewhere (1b), WorkTimerControl (1b) | Drawn `ooCwt` 2026-10-20, waiting for Jafar: A improved live (green pill, separate Stop timer), B new concept (Time indigo clock; Stop inside your own clock; running panel shows the time as its number; "running elsewhere" panel). Tables stay ➖ (DataTable left out). |

## Batch 11 notes (Jafar, 2026-10-20)

- Add files B's tray shows the files already picked, with × to unpick; it adds no new data. Labels stay grey:
  file labels have no colour column, and colours were not asked for.

## Batch 6b new behaviour (Jafar, 2026-10-19)

- Quantity: − / + change the count by 1; − is disabled at 1; typing decimals still works.
- Money: show thousands commas once the box is left; the sign comes from the business currency, so callers
  drop "(USD)" from labels.
- Tags: each tag uses the existing `tags.color` column (one of ten palette colours, stored as its light hex and
  mapped to the token family so dark mode follows). A new tag gets the next unused colour; whoever may create
  tags may change a tag's colour from the list's "⋯" menu; colour changes everywhere. Pick-only people see no
  "⋯". Replaces the random `colorForId` colours and the grey `quiet` look.

## Batch 10 new behaviour (Jafar, 2026-10-20)

- Search list: items with a photo show as picture cards before the rows of their group.
- New item pop-up C: 940 wide; the left side previews the line live as fields are typed, with the price, a cost
  bar and "You keep $X · N%" worked out from cost and price. People who may not see costs see no bar, legend or
  cost. Unit moves into the price strip; labor and tax are option rows. Title "New price book item"
  (board approved as drawn, 2026-10-20).
- Drawer: the foot counts lines added since it opened; added rows keep the count chip and an Add again button.

## Approved reference and proof

Looks live in design modules `modals.md`, `page-states.md`, `inputs.md`, `badges.md`. Build notes: confirmation
focus starts on Cancel; form dialogs keep live widths (400/600/640/940). Field build details, checks and
screenshots: `c5-fields-followup.md`.

## Screen-by-screen leftovers

About 96 form pop-ups keep buttons inside the body, around 120 have no icon, and empty states default to a blue tile. Fix each during its screen redesign. Other controls (MoneyInput, StatusBadge…) stay on the checklist separately.

## Next

Continue remaining approved rows in `stages/list-1a-parts.md`. Batch 4 and Schedule are integrated; build only approved designs and retain existing page-level journeys.

Earlier approved picker decisions and shared-rollout proof: `docs/contractor-shared-parts-approved-notes.md`.
