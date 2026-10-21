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
| 15 Notes panel | collaboration/NotesPanel (1b): note field, pinned note, note menu, changes waiting for Save, every state | Approved `l9ZBWI` A 2026-10-20 (refined live; B write-at-top with pinned shelf not chosen). Look in `notes.md` → Notes panel. See § Batch 15 |
| 16 Email From line | communications/EmailSenderLabel (1b): every state | Approved `I5mY7I` B 2026-10-20 (teal sender chip; A refined text line not chosen). Look in `chips.md` → Sender chip. See § Batch 16; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 17 Caption and labels pop-up | files/PhotoDescribeDialog (1b): every state | Approved `Y0ECPJ` A 2026-10-20 (photo on top; B photo beside not chosen). Look in `files.md` → Caption and labels pop-up. See § Batch 17; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 18 Record files card | files/RecordFilesCard (1b): every state, menu, remove pop-up | Approved `pH9PB` A 2026-10-20 (photos then document lines; B newest-photo gallery not chosen). Look in `files.md` → Record files card. See § Batch 18; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 19 Writing boxes | forms/FormNotesCard, settings/automation/EmailActionEditor, SmsActionEditor (1b): every state | Approved `qf1uu` 2026-10-20: Notes box B (Notes panel field, taller), email A and text A (one message sheet with value chips; text adds a cost meter). Looks in `notes.md` → Note box on a new record, `inputs.md` → Message sheet. See § Batch 19; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 20 Pop-over and filter chips | ui/Popover, data-display/DateRangeChip, ui/FilterChipMulti (1b): every state | Approved `e18rX` 2026-10-20: B for all three (pop-over with a coloured top band and an arrow; date chip with the time tile and a 440 From → To panel; multi chip with green +2 and a menu with "3 chosen", count pills and a Clear foot). Looks in `modals.md` → Pop-over, `chips.md`. See § Batch 20; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 21 Activity feed | collaboration/ActivityFeed (1b): with events, loading, nothing yet, couldn't load, dark | Approved `gZ6rR` 2026-10-20: A · Timeline (B Day log deleted). Look in `notes.md` → Activity feed. See § Batch 21; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 22 Files on a message | communications/ConversationAttachments (1b): every state, text message, Chat with Uplift, dark | Approved `mZdBv` 2026-10-20: B · preview cards inside the message (A clean pills deleted). Look in `files.md` → Files on a message. See § Batch 22; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 23 Jafar panel sign-in | jafar/JafarAuthCard (1b) and the four /jafar sign-in pages: every message state; 1440 light and dark | Approved `Y0A1Z` 2026-10-20: B · Split screen (A deleted). Look in `layout.md` → Sign-in screens. See § Batch 23; built, checked and merged 2026-10-20, proof `docs/evidence/2026-10-20-batch16-23/README.md` |
| 24 Discount, tax and totals | layout/RailRow, work/RecordDiscountCard, work/RecordTaxCard, quotes/QuoteSummaryCard (1b): every state, both pop-ups, dark | Approved `qY4yb` A 2026-10-20 (refined rows, pink Total band; B money tiles not chosen). Looks in `cards.md` → Side card rows, Totals card. See § Batch 24; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch24/README.md` (`QuoteSummaryCard` deleted, unused) |
| 25 First block on New forms | work/PrimaryInfoCard (1b) on New request, quote, invoice | **Superseded 2026-10-20** by the shared create form (Approved B, `m4ibfF` / `pM2Vf` / `NhVGQ`, part `new-request-top-form.md`); board `U8RY1n` deleted. Do not build Batch 25 |
| 26 Marketing email preview | marketing/MarketingTemplatePreview, MarketingTemplatePreviewDialog (1b): Review step, loading, couldn't load, dark | Approved `l62Og` A 2026-10-20 (refined pop-up; B inbox line and device stage deleted). Look in `modals.md` → Email preview pop-up. See § Batch 26; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch26-28/README.md` |
| 27 Channel menu and message settings | communications/ComposerChannelMenu, clients/CommunicationSettingsDialog (1b): every state, dark | Approved `DXj9z` A + A 2026-10-20 (B Send-by button and tick tiles deleted). Looks in `chips.md` → Channel pill, `modals.md` → Communication settings pop-up. See § Batch 27; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch26-28/README.md` |
| 28 Questions on a public form | forms/PublicFormQuestion (1b): every question kind, hover, focus, dark | Approved `Y3od0z` B 2026-10-20 (one card per question; A plain deleted). Look in `inputs.md` → Questions on a public form. See § Batch 28; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch26-28/README.md` |
| 29 Import steps | imports/ImportStepper, ImportUploadStep, ImportMapStep, ImportReviewStep (1b): no file yet, map, review, dark | Approved `oxtmi` A 2026-10-20 (steps on one column; B side panel deleted). Look in `layout.md` → Setup steps. See § Batch 29; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch29-30/README.md` |
| 30 Booking a call | jafar/booking/BookingFrame, BookingMonth, BookingTimePicker, BookingStatus, BookingFacts, BookingBackButton (1b) on `/book/[slug]` and `/book/manage/[token]` | Approved `TC3iU` A 2026-10-20 (one card, refined; B split screen deleted). Look in `layout.md` → Booking page. See § Batch 30; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch29-30/README.md` |
| 33 Number cards on list pages | data-display/KpiCard replaces work/AttentionCard + MoneyFeatureCard on Clients, Requests, Quotes, Jobs, Invoices; Reviews too | Approved `fzPaM` B 2026-10-21 (free-standing cards in one row, money card is the same card in green; A in-box deleted). Fixed set per page: Clients 4, Quotes 5, Invoices 5, Requests 6, Jobs 6, Reviews 4. 48 tile/24 icon; number with its short label under it, beside the tile (Jafar 2026-10-21); arrow in the top corner; note band kept. Narrow: even rows 6→3+3→2+2+2. Built 2026-10-21 using KpiCard on all six pages; dark mode follows existing tokens. Proof: `docs/evidence/2026-10-21-kpi-cards/README.md`; handover: `parts/batch33-kpi-build.md` |
| 37 Customer group pop-up | marketing/CustomerGroupDialog, CustomerGroupRuleBuilder, AsyncMultiPicker, FreeTextChipInput, CustomerGroupPreview (1b): every state, dark | Approved `PLExJ` B 2026-10-21 (rules list beside a purple recipients panel; A refined pop-up deleted). Restyle only (Jafar 2026-10-21: no new features, nothing removed). Look in `modals.md` → Customer group pop-up. Hand-off: the panel hint drops "above" (conditions sit beside it); every other word stays. Built and checked 2026-10-21 (`CustomerGroupPreview variant="panel"` for the pop-up only; campaign steps keep their look), proof `docs/evidence/2026-10-21-batch37-38-40/README.md` |
| 38 Profile photo pop-up | profile/ProfilePhotoDialog (1b): your photo, moving and zooming, no photo yet, not a photo, saving, couldn't save, removing, dark | Approved `n2ujB` B 2026-10-21 (dark photo studio with a live preview of the top bar, a Schedule visit and an Inbox conversation; A refined pop-up deleted). Same steps and words as live; previews only show. Look in `modals.md` → Profile photo pop-up. Token `--color-photo-studio` added. Built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch37-38-40/README.md` |
| 39 Weekly hours | settings/WeeklyHoursEditor (1b) on Settings → Business hours and the setup wizard's hours question: hover, typing, end before start, can't change, one column, dark | Approved `DhRBV` B 2026-10-21 (Week planner: one row per day with a 24-hour bar; A refined day cards deleted). Restyle only (same switches, periods, words and limits). Look in `inputs.md` → Weekly hours. See § Batch 39; built and checked 2026-10-21, proof `docs/evidence/2026-10-21-batch39/README.md` |
| 40 Signature pad | ui/SignaturePad (1b), in Collect signature on quotes and jobs and on the customer's quote page: Type it, typing, nothing drawn, signing, signed with Clear, saving, dark | Approved `alWwd` A 2026-10-21 (Refined pad: switch and Clear above the paper, × mark on the line, Full name under; B signing slip deleted). Restyle only (same switch, words, Clear and Full name). Look in `inputs.md` → Signature pad. Hand-off: the switch's chosen icon takes the record's colour, so the pad needs to know quote or job; paper stays white with dark ink in both modes, as live. Built and checked 2026-10-21 (`record="job"` on the job dialog), proof `docs/evidence/2026-10-21-batch37-38-40/README.md` |
| 41 Automatic follow-up card | automation/InquiryAutomationCard (1b), on a Request's side column and a website chat in the Inbox: waiting, stuck (email not set up), step can't run, paused by staff, paused because the customer replied, needs attention, stopped with reason, view only, saving, Stop pop-up and saving, loading, empty, couldn't load, dark | Approved `jXc9n` B 2026-10-21, **built 2026-10-21** (proof `docs/evidence/2026-10-21-batch41-followup/README.md`; header Add button not built: no such control live) (Next message first: status-tinted panel with the next send time in big type, sent-messages trail, visible Pause/Resume, Skip, Stop; earlier ones one line each; Stop pop-up slip naming the follow-up; A refined rows deleted). Restyle only: same states, words, controls and hidden-without-access rule. Look in `cards.md` → Automatic follow-up card. Hand-off: the ⋯ menu becomes visible buttons (same three actions; Skip's accessible name stays "Skip next step"); the paused sentence splits into the big reason line and the rest under it |
| 42 Client form | clients/ClientForm (1b): New client page and Edit client page (from the client page's ⋯ menu): Company with an exact match, Edit (no address, Notes, Attachments; Lead can't be picked for a customer), couldn't save, file didn't upload, dark | **Approved A by Jafar 2026-10-21** ("A"); B and its dark copy deleted. Board `fJ8Mx` "Concept · Batch 42 · Client form · Approved A · 2026-10-21" (light `Hk64M`, states `Gk62B`, dark `K1F6h`). Look in `layout.md` → New client page. **Built 2026-10-21** with the no-blend parts (proof `docs/evidence/2026-10-21-no-blend/README.md`). Restyle only: every live field, switch, warning, word and button kept. A refined cards: client-taupe header card (title + Client type / Status switches in the coloured top) holding Primary details, coloured front icons on email (conversation), phone (time), billing email (invoice), company (client); Client address card; rail Lead source, Tags, Notes, Attachments. B new concept: page header on the page, one client sheet with section names in a 156 left column, Person/Company and Lead/Customer as pick tiles (adds short hints under each: Jafar to confirm), and a live client card at the top of the rail (preview of name, status, contact, address, lead source, tags; similar/exact warning strip on it). Save bar: Cancel · Save & create another · Save client. Blend fix 2026-10-21 (Jafar: guide rule 7): `--color-client-surface` equals the page colour in light and the subtle track in dark, so on this board field boxes sit on `color-surface-background`, the switch track in the coloured top is white with the chosen option in client-surface, B's pick tiles sit in a page-colour well with the chosen tile white, the B page-header tile and the Lead pill are white. Still white-on-white from shared parts (secondary buttons, top bar) and near-white (Notes field, Files empty box): Jafar said yes, see § No-blend shared parts (top bar excepted) |

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
Follow-up the same day (Jafar: no hand-built tiles): grey, white and dark-card squares also use `IconTile`
(`white`, `tone="feature"`). Only circles (timeline markers, upload rings), buttons and step numbers stay as they are.
Calendar/time field trigger buttons stay icon buttons (they act; tiles only label).

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

## Batch 24 Discount, tax and totals — approved 2026-10-20

Board `qY4yb`, A · refined rows (B money tiles and green total card deleted). Restyle only; same five tax
choices, discount fields, instant saves, stale-save message and no-access words. Looks in `cards.md` → Side
card rows, Totals card; pop-ups follow `modals.md` → Form pop-up. Hand-off for the builder:
- `RailRow`: 32 tile (inactive; warning when waiting), label over value, optional sub line, amount at the right,
  pencil. Discount row: "Loyalty · 5% off" with "−$218.00"; Tax row: "Sales tax 8%" over the source
  ("From the property"), "$331.36". Not configured: warning tile and value, no pill.
- New quote (and wherever the standalone cards appear) uses the one "Discount and tax" card with rows, like the
  quote page; the standalone `RailCard` mode with "Add discount" / "Set tax" buttons retires.
- `QuoteSummaryCard`: "Overview" with calculator tile; Total band in the record colour (invoice blue on
  `InvoiceForm`); team-only panel with lock, profit green, margin bar.
- Pop-ups: discount 440 wide (name, Percentage | Amount switch with icons, value; Remove discount at far left);
  tax 400 (Tax select, custom name + Rate % in one row, reusable checkbox, info note strip). Save buttons get
  the check icon.

## Batch 25 First block on New forms — approved 2026-10-20, superseded the same day

Superseded by the shared create form (Approved B); board `U8RY1n` deleted. The hand-off below is history only.

Board `U8RY1n`, A · fact in the page header (B facts column deleted). Restyle only; same fields, client picker,
Change property and errors. Look in `layout.md` → Create pages. Hand-off for the builder:
- `PrimaryInfoCard` (New request, quote, invoice) becomes the approved New job block: card header in the record
  colour ("The request", "The quote", "The invoice"), the title field ("Subject" on invoices), then the client
  picker / picked client card full width. No right-hand fields column.
- Its `fields` snippet content leaves the block: Quote # / Invoice # ("Given when you save") and Requested on
  (the date) become the page-header pill New job already uses, tile in the record colour.
- New job builds its own block in `JobForm`; whether it moves onto `PrimaryInfoCard` is asked of Jafar (not yet agreed).

## Batch 26 Marketing email preview — approved 2026-10-20

Board `l62Og`, A · Refined pop-up (B inbox line and device stage deleted). Restyle only; same switch, render,
loading and Try again. Look in `modals.md` → Email preview pop-up. Hand-off for the builder:
- `MarketingTemplatePreviewDialog`: Growth `mail` tile and the quiet line in the header; no footer.
- `MarketingTemplatePreview`: segmented switch with `monitor` / `smartphone` icons; the frame becomes the subtle
  well with the email centred on white. The Review step shows the same body inside its Message card.

## Batch 27 Channel menu and message settings — approved 2026-10-20

Board `DXj9z`, A + A (B Send-by button and tick tiles deleted). Restyle only; same channels, ticks, words, link
and Done. Looks in `chips.md` → Channel pill and `modals.md` → Communication settings pop-up. Hand-off:
- `ComposerChannelMenu`: white raised pill with the teal icon; dropdown list with teal icons and the check; one
  channel only is the teal look-only pill. Same in the folded reply box and the review automation's Send by.
- `CommunicationSettingsDialog`: group rows with record-colour tiles; Not sending becomes the yellow strip; the grey
  notice becomes the notice strips (warning for Do not disturb with rows at 50%, informative for No marketing);
  consent note with the shield icon.

## Batch 28 Questions on a public form — approved 2026-10-20

Board `Y3od0z`, B · One card per question (A plain questions deleted). Restyle only; same question kinds, star,
help and values. Look in `inputs.md` → Questions on a public form. Hand-off:
- `PublicFormQuestion` takes its number (its place in the form, from the caller) for the orange tile.
- Choices become tap tiles (the whole tile is the label); pick-one and Yes / No side by side, Yes / No with thumbs tiles.
- Also used in `reviews/ReviewFeedbackJourney`; photo questions keep the page's upload box.

## Batch 30 Booking a call — approved 2026-10-20

Board `TC3iU`, A · One card, refined (B split screen deleted). Restyle only; same steps, fields, words, time-zone
change, taken-time return and rules on `/book/[slug]` (and the parts `/book/manage/[token]` shares). Look in
`layout.md` → Booking page. Hand-off:
- `BookingFrame`: brand mark gets the leaf tile; card radius 20, 1080 wide; summary gets the host avatar row and
  32 fact tiles (time clock, conversation video/phone); the `meta` snippet's chosen time becomes the time box.
- `BookingMonth`: open days white ringed circles with a green dot (no light-green fill); chosen solid green; ‹ ›
  as icon buttons. `BookingTimePicker`: times column 240; hover adds the arrow.
- `BookingStatus`: 56 status tile on a white top; `BookingFacts` rows get 40 tiles; the change hint moves to the
  foot band. `BookingBackButton` keeps the quiet button.
- The month's "8 open times" count was not added; no new words.

## Batch 29 Import steps — approved 2026-10-20

Board `oxtmi`, A · Steps on one column (B side panel deleted). Restyle only; same steps, choices, words, caps
and rules, for client, Price book and opening-balance imports. Look in `layout.md` → Setup steps. Hand-off:
- Page header gets the 40 tile in the import's colour (client taupe; Price book and balances pick theirs); no eyebrow.
- Each step panel opens with the shared Card header and ends in the pop-up footer bar; Continue keeps its arrow.
- Map table: arrow cell between your column and our field; matched boxes start with a green circle-check; an
  unmatched row is `--color-warning--surface` with a "Pick one" small pill under the samples.
- Review: four count cards with 32 tiles; attention and "Nothing gets sent" as notice strips.

`work/RecordTrack` is marked 🔁 Batch 13: it only wraps the approved `LifecycleTrack`.

## Batch 22 Files on a message — approved 2026-10-20

Board `mZdBv`, B · preview cards (A deleted). Restyle only; same instant upload, caps, error words, remove, and
`getAttachments`/`reset`. Hand-off for the builder:
- `ConversationAttachments`: cards 60 high, two across, 8 apart, laid out under the message text, not among the
  footer buttons; the paperclip stays in the footer (first in Chat with Uplift). Callers (`ConversationComposer`,
  `ManualEmailDialog`, `SupportConversation`) give the cards their place; `display: contents` goes.
- Card: the approved 40 file picture (`files.md`), name over type · size, round × top-right; uploading has the
  green foot bar; failed has the red edge and the reason. Rejection lines stay under the files.

## Batch 23 Jafar panel sign-in — approved 2026-10-20

Board `Y0A1Z`, B · Split screen (A centred card deleted). Restyle only; same fields, words, buttons and flows on
`/jafar/login`, `join`, `forgot-password`, `reset-password`. Hand-off for the builder:
- `JafarAuthCard` becomes the split layout: green brand panel left (fixed content), the page's form right with
  no card. Its eyebrow prop moves into the panel pill; title and intro stay per page.
- New: a status tile prop for message screens (done green, expired yellow); the error line becomes the critical box.
- Phone layout waits for the native apps (desktop only).

## Batch 21 Activity feed — approved 2026-10-20

Board `gZ6rR`, A · Timeline (B deleted). The earlier unfinished Batch 21 board `p8S73H` (record money cards) was
deleted on Jafar's word; those cards are still ⬜. Restyle only; same query, day groups, names and empty words.
Hand-off for the builder:
- `ActivityFeed`: day pill + rule; round 28 markers in the event's meaning colour joined by a 2px line; summary
  14/500 heading; author line with 24 avatar. Map event types to colours per `notes.md` → Activity feed.
- Loading becomes row-shaped placeholders; Couldn't load becomes the standard page state with Try again
  (refetch) — Jafar approved the board that shows it.

## Batch 20 Pop-over and filter chips — approved 2026-10-20

Board `e18rX`, B for all three (drawn by a helper agent; A options deleted). Jafar's note: the A and B options
were too alike ("same look, colour changed in places"); later boards must offer clearly different options.
Restyle only; same open/close, value, clear and filtering behaviour. Hand-off for the builder:
- `ui/Popover`: tinted top band in the caller's meaning colour, white 32 tile, 16/600 title, × in the band;
  arrow towards the trigger. Callers pass the meaning colour and icon. The Visit pop-up keeps its approved look.
- `DateRangeChip`: icon becomes the 24 time tile; panel 440 with From → To on one line and a foot with Clear
  dates and Done.
- `FilterChipMulti`: needs an icon prop (16, `--color-interactive`); "+N" in `--color-interactive`; menu head
  with name and "N chosen", count pills, Clear foot.
- Open: quick ranges in the date panel (This week, This month, Last 30 days) — idea on the board, waiting for
  Jafar's yes. Old boards `uSXlT` and `Fma1f` still have 11px captions (12px sweep).

## Batch 19 Writing boxes — approved 2026-10-20

Board `qf1uu` (Notes B, email A, text A; drawn by a helper agent, unchosen options deleted). Restyle only; same
fields, value buttons, counts, Send from and save flow. Hand-off for the builder:
- `FormNotesCard`: the note field gains the Notes panel field look, three lines tall, with "Team only" (lock) and
  the letters-left count inside its foot; error line under it.
- `EmailActionEditor`: subject and message in one sheet; the value buttons become chips in a values bar at the
  sheet's foot with the count; hint line under the sheet.
- `SmsActionEditor`: the same sheet without subject; the letters · segments · cost line becomes the cost meter;
  Send from stays a select. Same in the optional text of "Reply by text or email".
- The step card's grey icon becomes a `--color-conversation` tile (drawn as context; part of the step header).
- Open: Jafar has not yet answered the "what the customer sees" preview idea (new behaviour, note on the board).

## Batch 18 Record files card — approved 2026-10-20

Board `pH9PB`, A. Restyle of `files/RecordFilesCard`; same queries, picker, lightbox, describe dialog and remove
flow. Hand-off for the builder:
- Photo grid 3 a row, 92 high; "+N" on the sixth over `--color-overlay`. Hover/focus: interactive ring, round
  white `tag` and `x` buttons stacked top-right (today: tiny 20 buttons at two corners).
- Document lines edge to edge with the 40 file picture line, name, type · size · date, ⋯ `DropdownMenu`
  (Download; Remove from this record in critical). View only keeps ⋯ with Download.
- Being-checked and download-failed messages become the warning / critical notice rows in `files.md`.
- Loading bones replace "Loading files…"; empty, view-only empty and couldn't load as drawn. Couldn't load gains
  a "Try again" that refetches (drawn from the approved Notes card; Jafar approved the board with it).
- Remove pop-up: `ConfirmDialog` with an `unlink` tile; the error line sits above the buttons.

## Batch 17 Caption and labels pop-up — approved 2026-10-20

Board `Y0ECPJ`, A. Restyle of `files/PhotoDescribeDialog` and how `PhotoDescribeForm` sits in it; same query,
controls and save flow. Hand-off for the builder:
- Pop-up: `ui/Dialog` small, tile `photo` grey, hint line file name · record. Photo 200 high, cover, radius 8, border.
- Inside the dialog the form drops its card (border, header tile and title); "Manage labels" moves to a LABELS
  caption row above the tags. The File Manager details panel keeps the card as approved on `K04pQm`.
- The Not saved strip becomes the dialog footer only while changed; saving shows "Saving…" with Cancel disabled.
- Loading bones, couldn't load block, didn't-save line, look-only and nothing-yet as in `files.md`.

## Batch 16 Email From line — approved 2026-10-20

Board `I5mY7I`, B. Restyle of `communications/EmailSenderLabel` only; it keeps today's query, wording and the
four callers (QuoteEmailPreview, InvoiceEmailDialog, ManualEmailDialog, ConversationComposer).
Hand-off for the builder:
- Ready: the sender chip in `chips.md` (mail icon, name, grey address, no angle brackets).
- Long: one line; the address ends in "…" and `ui/Tooltip` shows the full name and address on hover/focus,
  so the chip needs to be focusable (tabindex 0) only when cut off, or always — builder's choice.
- Loading: 240×28 pill bone (replaces "Loading sender…"; keep the words for screen readers).
- Couldn't load: red chip; no address (manual or business wording as today): amber chip.
- In the composer route the chip sits before the arrow; the recipient may truncate, the chip never wraps.

## Batch 14 build — merged 2026-10-20

Rollout: every `ProductsAndServicesBlock` caller now passes `concept` (job, quote, invoice, request pricing,
new quote/request/invoice/job forms, visit pop-up); concept table rules moved off `.job-detail` to
`.pricing-table--concept` / `.pricing-block--concept`. Built: empty two choice tiles, crew work list (prices
hidden) with `IconTile` 56, quote group titles / text lines / tinted add-ons with outlined pill, locked
informative band, foot strips (client eye, invoice lock, eye-off), loading rows, couldn't load, progress
"Due this invoice" box, invoice service-date box (CalendarPicker inside, its own button is the icon), card
tile defaults to quote box (invoices pass receipt/invoice). Light screenshots matched `vsT0H`.
Proof: `docs/evidence/2026-10-20-batch14/README.md`. Light and dark checks cover job, quote, invoice, request,
all four new-record forms, and a real per-visit pop-up. The forms' empty state now uses the two choice tiles;
the narrow visit editor no longer clips unit prices.

## Batch 15 Notes panel — built 2026-10-20

Commit `54d526a1` on `claude/concept-batch14-15`, merged with Batch 14; proof `docs/evidence/2026-10-20-batch15/README.md`.

## Batch 15 Notes panel — approved 2026-10-20

Board `l9ZBWI`, A. Restyle of the compact panel only; every control and the staged-save flow are live today.
Hand-off for the builder:
- Field stays at the card's foot under a hairline: `--color-surface--background--subtle`, 1px border, radius 8,
  padding 4 4 4 12; 14 text; a 32 send square, `--color-interactive` with a white arrow when there is text,
  `--color-inactive--surface` when empty. Focus: 1.5px `--color-interactive` edge on `--color-surface`.
- Notes are the approved bands (`notes.md`), 10 apart, the ⋯ as a 28 quiet icon button at the top right. A pinned
  band is `--color-warning--surface` with a 1px `--color-warning--surface-edge` and a 16 `pin` in `--color-warning`
  before the ⋯.
- Menu as the line menu: 184 wide; Pin/Unpin, Edit, divider, Delete in `--color-critical`.
- Waiting for Save: a status line under the note text (14 icon + 12/600): new note "Not saved yet"
  (`clock`, warning) with a quiet Remove at the right, the band white with a 1px `--color-warning` edge; edited
  note "Edit waiting for Save"; deleted note faded (avatar and author at 50%, text struck in secondary)
  with "Deleted when you save" (`trash`, critical) and a small secondary Undo. Replaces the "Unsaved" and
  "Not saved yet" badges.
- Editing: the field replaces the text inside the band (1.5px interactive edge), small Cancel (secondary) and
  Done (main) at the right.
- Loading: three note-shaped bones. Empty and can write: "No notes yet" 13/600 + one 12 hint line over the field.
  Empty and view only: a 32 inactive tile and "No notes yet". Couldn't load: 32 critical tile, title, one line,
  small secondary Try again (refetches). View only: no field, no ⋯ (⋯ only on notes the person may change).

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

## Batch 31 New job header (board deleted 2026-10-20)

Jafar 2026-10-20: the New job header spans over the side column; it must be one card in the main column like the
Job details record header (C). First board `Yh9QW` (A job facts preview, B title and client inside the header)
was deleted completely at his request after he noticed the client was shown pre-picked. Start again; the drawing
must show how the client is chosen (search box "Search by name or company", result list, Change client, locked
from a request). The New job drawing `zUFDO` is unchanged.

## Batch 39 Weekly hours — approved 2026-10-21

Board `DhRBV`, B · Week planner (A refined day cards deleted). Restyle only: same seven days, Open / Closed
switch, Open 24 hours, up to three periods, Start → End with the length chip, Remove this period, Add another
period, the range error and `disabled`. Look in `inputs.md` → Weekly hours. Hand-off for the builder:
- One list inside the page's card: an hour scale strip on top (DAY, then 12 AM · 6 AM · 12 PM · 6 PM · 12 AM), then
  one row per day with a 1px line above.
- Day column 240: 40 day tile with the short day name (Time colour; inactive grey when closed or can't change),
  day name 15/600, the Open switch (label "Open" in the brand colour, "Closed" quiet) and Open 24 hours under it.
- Hours column: the 24-hour bar (display only, `aria-hidden`), then the periods stacked, each Start → End boxes
  150 wide with no visible Start/End labels (the TimePicker keeps them for screen readers), the length chip and ×;
  Add another period under them. A period that isn't valid yet draws no block.
- `singleColumn` (setup wizard, 640): the day heading row carries Open 24 hours then Open at the right; the bar and
  periods (130 boxes) sit under it.
- Card header on Business hours: Time tile with the clock.

## No-blend shared parts — approved 2026-10-21, waiting to be built

Jafar said yes (2026-10-21) to fixing, at the source, the shared parts that broke guide rule 7, and asked for the
switch's chosen option in brand green. Changed in `concept.pen` and the design skill: client colour family now
sand (`colors.md` → Client colour; the old surface equalled the page colour); secondary, danger, menu and icon
buttons on `--color-interactive-background`, white on coloured tops (`buttons.md`); field boxes sunken on white
cards, white on the page or a coloured top (`inputs.md`); every segmented switch's chosen option brand green
(`inputs.md`); Notes field and empty Files box on `--color-surface--background`. A white top-bar panel was tried and undone:
Jafar kept the top bar on the page colour (2026-10-21). Builder: update `_variables.scss` client tokens and the shared `ui/SegmentedControl`, `ui/Button`,
`ui/Input`, `ui/Select`, Notes and Files parts once (not the top bar); check every screen at 1440 light and dark.

## Switch component — approved 2026-10-21

Jafar approved the switch component board `SnDlF` and asked for every hand-drawn switch to use it: all 34
(Parts, Schedule views and pop-ups, Pickers AM/PM, Price book, New job, Signature pad, Client form) are now
instances, keeping each one's size and direction. Look in `inputs.md` → Segmented switch.
