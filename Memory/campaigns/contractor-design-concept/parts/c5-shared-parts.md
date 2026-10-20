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
| 5 Pickers | CalendarPicker, TimePickerField, TimePicker, DateTimePicker, TimezonePicker, CountryPicker | Approved `uSXlT` "Pickers v2" 2026-10-19 (old `J3g7hi` deleted); built and verified 2026-10-20; proof `docs/evidence/2026-10-20-batch5/README.md` |
| 6a Small controls | Avatar, Toggle, RadioGroup, Tabs | Approved `GbgcY` 2026-10-19: Avatar A, Switch A, Radio A (improved live), Tabs B (soft capsules); looks in `avatars.md`, `tabs.md`, `inputs.md`; built and verified 2026-10-20; proof `docs/evidence/2026-10-20-batch6a/README.md` |
| 6b Inputs and chips | FilterChip, MoneyInput, QuantityInput, TagSelect | Approved `Fma1f` 2026-10-19: Filter A + name/value divider, Money B, Quantity B, Tags A tinted in their own colour; looks in `chips.md`, `inputs.md`; built and verified 2026-10-19. Proof: `docs/evidence/2026-10-19-batch6b/README.md` |
| 7 Small helpers | ListLoadMore, FormErrorSummary, PencilButton, KpiCard | Approved `eJ0QQ` 2026-10-19: Load more B (footer bar with count), Form error B (checklist card), Pencil button A (icon button), Number cards B with note 12/500; looks in `lists.md`, `notices.md`, `buttons.md`, `cards.md`; built, checked and merged to main 2026-10-20. Proof: `docs/evidence/2026-10-20-batch7-8/README.md` |
| 8 Photos and files | Lightbox, FileThumb, PhotoSlot, FileUploader | Approved `b4BxuV` 2026-10-19: Viewer A with B's glass count and joined download/close, File picture B (paper sheets, file-family tab colours) with A's big check/failed boxes, Photo box A, Upload list B; looks in `files.md`, colours in `colors.md`; built, checked and merged to main 2026-10-20. Proof: `docs/evidence/2026-10-20-batch7-8/README.md` |
| 9 Notes and attachments | AuthorMeta, NoteBody, NoteFiles, PendingFilesCard, AttachmentSurface | Approved `KuOmH` 2026-10-19: Author line B (name over time, Edited tag), Note text B (teal mention chip), Note files B (96×72 photos, file chips), Files waiting B (upload list lines) with A's red-edged failed row, Files card B (labelled Add); looks in `notes.md`, `files.md`; built, verified and merged to main 2026-10-20. Proof: `docs/evidence/2026-10-20-batch9/README.md` |
| 10 Price book | CatalogItemPicker, CatalogItemDialog, PriceBookDrawer | Approved `ZWTSi` 2026-10-20: Search list B with D's picture cards for items with a photo; New item pop-up C (new concept, green live preview); Drawer B with A's type tags on every row; looks in `price-book.md`; built and verified 2026-10-20; proof `docs/evidence/2026-10-20-batch10/README.md` |

| 11 File pickers | FilePicker, FileLabelsDialog, PhotoDescribeForm | Approved `K04pQm` 2026-10-20: Add files B (places side column, pick boxes, picked-files tray), Photo labels A (improved live), Photo details B (caption card, Not saved strip); looks in `files.md`; built and verified 2026-10-20; proof `docs/evidence/2026-10-20-batch11/README.md` |
| 12 Time clock | RunningClock, TimerElapsed, TimerRunningElsewhere (1b), WorkTimerControl (1b) | Approved `ooCwt` 2026-10-20 as a mix: Clock B (indigo capsule, breathing ring), Start/Stop A with B's indigo icons, Timer panel B, Running now B, visit row C (indigo-edged clock joined to a normal Stop timer, same height); look in `time-clock.md`; built by Codex, finished, verified and merged by Claude 2026-10-20; proof `docs/evidence/2026-10-20-batch12/README.md` |
| 13 Record page frame | TabPanel, RecordDetailLayout, DetailEditBar, ClientTagSelect (🔁 Tag picker); shared header WorkRecordHeader, RecordFactsList, LifecycleTrack (1b) | Approved `eHJn1` 2026-10-20: tabs B (band along the header card's foot), save bar A (white, like New job), opening-tab states, client tags and dark mode as drawn. Header: Jafar rejected the first shared-header drawing (it only redrew today's app, skipping the guide's options rule) and chose ONE header part for all six record pages, client included (today `clients/ClientDetailHeader` is separate from `work/WorkRecordHeader`). Options board `xrJ3f` 2026-10-20: A refined today, B highlights row, C coloured top, D next step panel, C approved 2026-10-20 (see § Batch 13 record header); fold the client header into the shared part when building |
| 14 Products and services | ProductsAndServicesBlock (states only; saved view `tNdkX` and edit `jFBRB` already approved) | Approved `vsT0H` 2026-10-20: B for all three rows (Empty B two choice tiles, Field worker B crew work list, Quote extras B grouped and signposted), row 4 shared parts as drawn, light and dark. See § Batch 14 |

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

## Icon tile hairline edge — approved 2026-10-20

Board `k4k5Na` (Jafar first picked soft depth, then changed to the hairline edge the same day). Rule in design
`icon-shapes.md`; token `--color-<meaning>--surface-edge` already in `_variables.scss` (dark falls back to the
tile colour). Builder: give every icon tile in code (shared tile styles, card header tiles, row tiles,
empty-state tiles) a 1px `--surface-edge` border; fill stays the plain surface. Pencil already follows.

### Icon tile edge — built and merged 2026-10-20

Every meaning tile uses `ui/IconTile` (size 20 added). Proof: `docs/evidence/2026-10-20-icon-tile-edge/README.md`.
Left on purpose: visit date badge, file thumbs, upload ring, day-clock mark, dark feature-card tiles, conversation
rail tiles, WorkRecordHeader white tile, Settings 60px solid badge, logos/buttons.
Decided 2026-10-20 (Jafar left it to Claude): plain grey/white icon squares (attachments, search results, website
chat, shared files, Banner, setup points…) become `IconTile tone="inactive"`, so there is one tile look. The
calendar/time field trigger buttons stay icon buttons (they act; tiles only label). Builder: sweep when free.

## Batch 14 Products and services — approved 2026-10-20

Board `vsT0H`. Jafar approved B for rows 1–3 and asked that no fill blends into what is behind it (guide rule 7).
Hand-off for the builder (restyle only; every control is live today):
- Empty, editable: hint "Nothing priced yet", one quiet line, then two choice tiles side by side on
  `--color-surface--background` with a 1px border: "Add a line item" (job tile, plus) opens a blank line;
  "Pick from the price book" (quote tile, book-open) opens the Price book drawer. Not editable: the quiet line only.
- Prices hidden (`showPrices` false): a crew work list on `--color-surface--background`: white line cards
  (radius 12, padding 12), 56 photo or kind tile, a count box ("12×", 16/700, `--color-surface--background`),
  name 15/600 + kind pill, description. Foot strip "Prices are hidden for your role." with a blue eye-off icon.
- Quote: heading lines are group titles 16/700 with a 4×18 quote-coloured bar; text lines show a file-text tile
  and no numbers; add-on rows tinted (`--color-warning--surface` recommended, `--color-inactive--surface`
  optional) with a 3px stripe in the same family and an outlined white pill; their money is secondary text.
  Locked message in an informative band under the header; "Client sees" foot strip with a client-coloured eye.
- New foot strips use `--color-surface--background`. Lock icons on invoice strips use the invoice colour.
- Row 4 (line menu, "Throw away these changes?" with Keep editing / Throw them away, loading, couldn't load
  without Try again, invoice Service date box with ×, progress invoice Item total / Due this invoice) as drawn.

## Batch 13 record header decisions (Jafar, 2026-10-20)

- One header part for all six record pages, client included.
- No call / text / email (or call / directions) icon buttons in the header: Jobber does not show them that way.
  The phone, email and address stay as plain text. Building removes `work/QuickContactButtons` from the
  record headers; the client page keeps Message and Request a review.

## Batch 13 record header — approved 2026-10-20

Board `xrJ3f` "Record header · C", light and dark. Jafar approved option C (coloured top) 2026-10-20.

Hand-off for the builder:
- One shared header for all six records; `clients/ClientDetailHeader` folds into `work/WorkRecordHeader`.
- Coloured top in the record type's surface colour; status shows in the pill and the 4px stripe.
- Top row: record tile + status pill, actions on the right. No record info line (number, version, dates).
- No call / text / email buttons: remove `work/QuickContactButtons` from headers; contact stays plain text.
  The client page keeps Message and Request a review.
- Four facts under the client line (from Jobber, `jobber-08-screen-patterns.md` and the live trial):
  Client: Main phone · Main email · Payment terms · Lead source. Request: Requested · Assessment · Service ·
  Came from. Quote: Quote # · Created · Sent · Approved/Declined. Job: Job # · Type · Dates (start → end;
  recurring shows its repeat) · Invoicing (`billing_timing`). Invoice: Invoice # · Issued · Due · Payment
  terms. Payment: Paid on · Method · Reference # · For invoice #. Missing facts show honest grey text
  ("Waiting for an answer", "None given").
- Footer: tabs band (client) or the Request → Paid track (work records).
- Status stripe (Jafar, 2026-10-20): a 4px band along the very top of the header card in the status pill's
  main colour (`--color-success`, `--color-warning`, `--color-critical`, `--color-informative`,
  `--color-inactive`), changing with the status; the card's rounded corners clip it. The tinted top stays the
  record type's colour.
- Client top uses `--color-client--surface-edge` (taupe 300), not `--color-client--surface`: the latter is the
  page colour and melted into the page in the live app.
- Client line contact (Jafar, 2026-10-20): address, phone and email are separate items, each with a bold icon
  in its meaning colour (map-pin client, phone time, mail conversation; Tabler stroke ≈2.25, 14px) and
  13/500 `--color-text`, 16 apart. Fact tile and address icons are bold too. Was one grey 12px line.
- Long address (Jafar, 2026-10-20, drawn under the Job header as "Long address stage"): phone and email never
  shrink; the address takes the rest of the line on one line and ends in "…". Hover or keyboard focus shows
  the shared `ui/Tooltip` with the full address and "Click to open in Google Maps"; the address is a link
  (underline on hover) opening Google Maps search for it in a new tab. Header height never changes.

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
