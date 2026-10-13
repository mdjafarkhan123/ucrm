# Classic theme redesign — design recipe

How to design and build screens for the [Classic theme redesign](classic-theme-redesign-behavior-contract.md)
so every page matches the **reference screen**: `Job details · Claude concept · Job cockpit · 1440` (frame
`oNoOG`) in `classic.pen`. The plan's § Design principles say _what_ a page should do; this recipe says _how_
it looks and how the work is done. When the reference screen and this recipe disagree, the reference screen
wins and this recipe is corrected.

Family screens so far: the job reference, `Quote details · Classic redesign · 1440` and `Invoice details ·
Classic redesign · 1440`, side by side in `classic.pen`.

Status: proposed with the job concept (2026-10-13). Colours, corners and shadows are named tokens on the
Classic design-system page in `classic.pen` (§ Color › Record pages and cards, Featured card; § Spacing &
shape › Corners, Elevation), each with its light and dark value; the dark copy of that page shows the dark
values. Draw with the token names below, never raw values. When the first version is built, this recipe moves
into the `design-classic` skill.

## Working method

1. **Know the page's real content.** Read the page's `+page.svelte` and list every section, rail card and
   conditional block it renders. Done when each section on your list maps to a place in the design, or to a
   menu, tab or hover reveal. Every feature you draw exists in that code or in the plan's § Approved
   additions.
2. **Start from the reference screen.** Copy its shell (sidebar and top bar instances) and the parts you need
   from frame `oNoOG`, then change content. Draw a new part only when no existing part fits, and give it the
   same card, row and type rules below.
3. **Fill it with a realistic, busy record.** One believable contractor scenario with real names, dates,
   amounts that add up, and work in progress — the state an owner sees most days. Empty states come after
   the busy state is approved.
4. **Build section by section,** checking Pencil's layout problems (`ctx.problems`) after each one.
   Pencil `execute` globals do not survive between calls; carry node ids forward as literals.
5. **Critique like a picky designer.** Export the whole frame with `Export(..., "png", ..., {scale:1})`, crop
   it into halves with `magick`, and read each half at full size. Hunt for: clipped or wrapped-badly text,
   misalignment, overlapping parts, one row styled differently from its siblings, the same fact shown twice,
   invented features, wording that differs from the app (it says "Labor"), and colour used for decoration.
   Check dark mode once per screen: set the frame's `theme` to `{mode:"dark"}`, export, set it back.
6. **Fix and repeat** until a fresh round finds nothing — at most three rounds — then fit the screen frame's
   height to its content.
7. **Hand over.** Tell Jafar the screen names, what each shows and which parts are new; ask him to press
   Ctrl+S in Pencil, then commit `classic.pen` from the main folder.

## Page

- Screen 1440 wide; page background `$color-surface-page`; 12 padding; sidebar and content column 16 apart.
- Content column stacks top bar, breadcrumb row and body, 20 apart. Body: main column fills, right rail 344
  wide, 20 apart; main and rail cards stack 20 and 16 apart.
- Breadcrumb row: parent link 13/500 green (`$color-interactive`), chevron 14, current record 13/500
  secondary; right side "Updated just now" 12 secondary after a 6px green dot.
- Font: Inter, `$font-family` (Jafar, 2026-10-13). Icons: Lucide in Pencil, the matching Tabler icon in code.

## Cards and rows

- Card: `$color-surface`, `$radius-card` (20), 1px inner border `$color-border-card`, **shadow-card** — two
  shadows, y1 blur 2 `$color-shadow-card-near` and y12 blur 32 `$color-shadow-card-far` — clipped. The
  design-system Card part carries this look. One surface style for every card; colour lives in status pills,
  avatars and icons only.
- Card header: padding 20/24 in the main column, 18/20/14/20 in the rail. Title 17/700 (rail 16/700),
  letter-spacing −0.2, `$color-heading`; subtitle 13/500 (rail 12/500) secondary, phrased as a useful fact
  ("2 of 4 complete · last visit Wed, Oct 15"). Optional count chip: 12/600 secondary on
  `$color-surface-background-subtle`, `$radius-pill`, 2/8 padding. Header actions sit right: a green ghost
  link, then one bordered secondary button.
- Rows: 1px top divider `$color-border-divider`; padding 16/24 for rich rows, 14/24 for list rows, 12/20 in
  the rail.
- Table head: 10/24 padding on `$color-surface-background-subtle` with top and bottom dividers; labels
  11/600 uppercase, letter-spacing 0.6, secondary. Numbers right-aligned; totals in a 300-wide block at the
  right, the grand total 14/700 label and 18/700 value above a divider.
- Footer strip: `$color-surface-background-subtle`, 12/24 padding, a 12/500 secondary summary left and a
  13/600 green "Show all →" link right.
- Tabs inside a card: labels 14/600 (inactive secondary), each followed by a value chip; the active tab has a
  2px green underline and a `$color-job-surface` chip. Used for the job's Work log and the invoice's History
  (Payments, Edits).
- Products and services: the app's wording — card title "Products and services", columns Line item,
  Quantity, Unit price, Total. Add-ons carry a neutral pill ("Recommended add-on") beside the name. The
  totals block holds every money row — subtotal, discount, tax, record total — so discount and tax need no
  rail cards of their own. A locked block says why in a footer strip (lock icon + the app's message).
- Text sections (introduction, client message, disclaimer) are compact cards of 14/500 text at line height
  1.55; related ones share one card as labelled rows.

## Buttons

- Buttons are `$radius-control` (12); the design-system Button part carries it. 40 high in headers, 36 in
  card headers, 30 high with `$radius-base` (8) for small row actions.
- The one green primary button adds **shadow-primary** (y4 blur 12 `$color-shadow-primary`), white
  (`$color-surface`) 18 icon and 14/600 label, 0/16 padding. No other button has a shadow.

## Header card

- Padding 24/28/0/28. Row 1: status pill (record-type surface colour, `$radius-pill`, 5/10/5/8 padding, 7px
  dot, 12/600) + record number 12/600 letter-spacing 0.6 secondary + 3px dot + record kind 12/500. Right
  side: a 40×40 history icon button and a 40-high "More ⌄" button, both bordered, then the one green primary
  button (§ Buttons) named for the record's next step.
- Title 32/700, letter-spacing −0.8, line height 1.15, 18 below row 1.
- Meta row: 28px client avatar + name 14/600; then icon-15 + 14/500 secondary facts 16 apart; quick contact
  buttons right — 34px circles on `$color-surface-background-subtle` with a `$color-border-card` border.
- Lifecycle track: the same five steps on every work record — Request, Quote, Job, Invoice, Paid — each page
  lighting its own; a done step's sub-line says when ("Approved Sep 28"), the current one what it waits on
  ("Waiting on David", "Due in 7 days"). Five equal steps, 6 apart, 24 above and below. Bar 6px pill — done
  `$color-interactive`, current `$color-surface-active` with a `$color-brand` portion, upcoming
  `$color-surface-active`. Label 13/600 (upcoming secondary) with a check-13 icon when done or a 7px brand dot
  when current; sub-line 12/500 secondary, green for the current step.
- Key facts strip: top divider, padding 18/0/22; four equal facts with 1px dividers and 20 side padding;
  each a 36px `$radius-control` icon tile on `$color-surface-background-subtle`, label 12/500 secondary,
  value 14/600 heading. Pick facts that live nowhere else on the page, plus the record total. When the facts
  can be edited (an invoice's terms and dates), the strip ends with a 32px bordered pencil button instead of
  a separate section.

## Lists of dated work

- Date tile 52×56, `$radius-control`, bordered: weekday 10/700 letter-spacing 0.6 secondary, day 20/700.
  Today's tile is filled `$color-interactive` with a `$color-surface` day and `$color-on-interactive-secondary`
  weekday.
- Text: title 15/600, time line 13/500 secondary, note line 12/500 with a 13 icon. Today's row has a
  `$color-surface-current` tint and a green 600 live note ("Clocked in 8:04 AM · on site 2h 16m").
- Crew avatars 30px, overlapping by 5, each with a 2px outer stroke in the row's background colour
  (`$color-surface`, or `$color-surface-current` on today's row).
- Status pills in a 124-wide column: done = `$color-success-surface` + check; now = `$color-interactive`
  filled, `$color-surface` text + radio icon; scheduled = `$color-inactive-surface` + calendar-clock.
- Row action: a borderless 36px button with a secondary chevron (pencil for editable future rows), the same
  on every row.

## Right rail

Order: money first, then wrap-up, then reference — profit, close-out, billing, instructions, photos and
files, notes. Photos and files always sit in the rail. Each work record has one featured card: job and
quote show profit (team only; the quote's split is Cost and Estimated profit), the invoice shows Balance due
(Paid and Balance split, `$color-brand` and `$color-feature-muted`, plus the client account balance). Rail
cards follow § Cards and rows, except:

- **Profit (featured card):** `$color-feature-surface` — dark in both modes — padding 24, gap 20,
  **shadow-feature** (y16 blur 40 `$color-shadow-feature`). Eyebrow 11/700 letter-spacing 1
  `$color-feature-eyebrow` with a "Team only" lock chip on `$color-feature-chip`; figure 40/700
  `$color-feature-text`, letter-spacing −1.2, beside a `$color-brand` margin pill with 12/700
  `$color-feature-on-brand` text; split bar 10 high, 3 apart, `$radius-small` — labor `$color-profit-labor`,
  expenses `$color-profit-expenses`, profit `$color-profit-margin` — and a legend of 13/500
  `$color-feature-label` labels, 12 `$color-feature-muted` percentages and 13/600 `$color-feature-text`
  values. One featured card per page at most.
- **Close-out:** a 52px ring (track `$color-surface-active`, progress `$color-interactive`, inner radius
  0.78, count in the middle) beside the title. Each item: a 24px state circle — done filled green with a
  white check, waiting subtle with an hourglass, to-do a 1.5 outline — label 14/600, state 12/500, and a
  30-high `$radius-base` bordered action button when the user can act.
- **Photos:** a three-column grid of 92-high `$radius-control` tiles, 8 apart; the last tile carries a
  `$color-overlay-photo` overlay with "+N" 18/700 `$color-feature-text`. Files follow as rows with a 34px
  coloured file-type tile.
- **Notes:** 28px avatar, author 13/600 and time 12/500 on one line, text 13/500 at line height 1.5; a
  40-high `$radius-control` composer on `$color-surface-background-subtle` with a 28px green send button.

## Avatars and colour pairs

Initials avatars use an existing surface/on-surface pair per person — `$color-informative-*`,
`$color-request-*`, `$color-quote-*` — so the same person keeps the same colour across the page.
