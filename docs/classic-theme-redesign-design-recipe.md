# Classic theme redesign — design recipe

How to design and build screens for the [Classic theme redesign](classic-theme-redesign-behavior-contract.md)
so every page matches the **reference screen**: `Job details · Claude concept · Job cockpit · 1440` (frame
`oNoOG`) in `classic.pen`. The plan's § Design principles say _what_ a page should do; this recipe says _how_
it looks and how the work is done. When the reference screen and this recipe disagree, the reference screen
wins and this recipe is corrected — except the font, which is Inter whatever the screen shows.

Status: proposed with the job concept (2026-10-13). When Part 2 adds the new tokens and Jafar approves the
family, swap the raw values below for their token names. When the first version is built, this recipe moves
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
6. **Fix and repeat** until a fresh round finds nothing — at most three rounds — then fit the screen frame's
   height to its content.
7. **Hand over.** Tell Jafar the screen names, what each shows and which parts are new; ask him to press
   Ctrl+S in Pencil, then commit `classic.pen` from the main folder.

## Page

- Screen 1440 wide; page background `#F3F2EE`; 12 padding; sidebar and content column 16 apart.
- Content column stacks top bar, breadcrumb row and body, 20 apart. Body: main column fills, right rail 344
  wide, 20 apart; main and rail cards stack 20 and 16 apart.
- Breadcrumb row: parent link 13/500 green (`$color-interactive`), chevron 14, current record 13/500
  secondary; right side "Updated just now" 12 secondary after a 6px green dot.
- Font: Inter (Jafar, 2026-10-13). Icons: Lucide in Pencil, the matching Tabler icon in code.

## Cards and rows

- Card: white (`$color-surface`), 20 corner, 1px inner border `#E4E2DC`, two shadows — y1 blur 2
  `#032B3A0A` and y12 blur 32 `#032B3A0D` — clipped. One surface style for every card; colour lives in
  status pills, avatars and icons only.
- Card header: padding 20/24 in the main column, 18/20/14/20 in the rail. Title 17/700 (rail 16/700),
  letter-spacing −0.2, `$color-heading`; subtitle 13/500 (rail 12/500) secondary, phrased as a useful fact
  ("2 of 4 complete · last visit Wed, Oct 15"). Optional count chip: 12/600 secondary on
  `$color-surface-background-subtle`, pill, 2/8 padding. Header actions sit right: a green ghost link, then
  one bordered secondary button.
- Rows: 1px top divider `#ECEAE5`; padding 16/24 for rich rows, 14/24 for list rows, 12/20 in the rail.
- Table head: 10/24 padding on `$color-surface-background-subtle` with top and bottom dividers; labels
  11/600 uppercase, letter-spacing 0.6, secondary. Numbers right-aligned; totals in a 300-wide block at the
  right, the grand total 14/700 label and 18/700 value above a divider.
- Footer strip: `$color-surface-background-subtle`, 12/24 padding, a 12/500 secondary summary left and a
  13/600 green "Show all →" link right.
- Tabs inside a card: labels 14/600 (inactive secondary), each followed by a value chip; the active tab has a
  2px green underline and a `$color-job-surface` chip.

## Header card

- Padding 24/28/0/28. Row 1: status pill (record-type surface colour, pill, 5/10/5/8 padding, 7px dot,
  12/600) + record number 12/600 letter-spacing 0.6 secondary + 3px dot + record kind 12/500. Right side: a
  40×40 history icon button and a 40-high "More ⌄" button, both radius 12 with a border, then the one green
  primary button (40 high, radius 12, 0/16 padding, white 18 icon + 14/600 label, shadow y4 blur 12
  `#03774133`) named for the record's next step.
- Title 32/700, letter-spacing −0.8, line height 1.15, 18 below row 1.
- Meta row: 28px client avatar + name 14/600; then icon-15 + 14/500 secondary facts 16 apart; quick contact
  buttons right — 34px circles on `$color-surface-background-subtle` with a border.
- Lifecycle track: five equal steps, 6 apart, 24 above and below. Bar 6px pill — done
  `$color-interactive`, current `$color-surface-active` with a `$color-brand` portion, upcoming
  `$color-surface-active`. Label 13/600 (upcoming secondary) with a check-13 icon when done or a 7px brand dot
  when current; sub-line 12/500 secondary, green for the current step.
- Key facts strip: top divider, padding 18/0/22; four equal facts with 1px dividers and 20 side padding;
  each a 36px radius-10 icon tile on `$color-surface-background-subtle`, label 12/500 secondary, value
  14/600 heading. Pick facts that live nowhere else on the page.

## Lists of dated work

- Date tile 52×56, radius 12, bordered: weekday 10/700 letter-spacing 0.6 secondary, day 20/700. Today's tile
  is filled `$color-interactive` with white day and `#D7F5E5` weekday.
- Text: title 15/600, time line 13/500 secondary, note line 12/500 with a 13 icon. Today's row has a
  `#F5FAF6` tint and a green 600 live note ("Clocked in 8:04 AM · on site 2h 16m").
- Crew avatars 30px, overlapping by 5, each with a 2px outer stroke in the row's background colour.
- Status pills in a 124-wide column: done = `$color-success-surface` + check; now = `$color-interactive`
  filled, white text + radio icon; scheduled = `$color-inactive-surface` + calendar-clock.
- Row action: a borderless 36px button with a secondary chevron (pencil for editable future rows), the same
  on every row.

## Right rail

Order: money first, then wrap-up, then reference — profit, close-out, billing, instructions, photos and
files, notes. Rail cards follow § Cards and rows, except:

- **Profit:** `$color-surface-reverse`, padding 24, gap 20, shadow y16 blur 40 `#032B3A33`. Eyebrow 11/700
  letter-spacing 1 `#A9B7BC` with a "Team only" lock chip on `#FFFFFF14`; figure 40/700 white,
  letter-spacing −1.2, beside a `$color-brand` margin pill with dark 12/700 text; split bar 10 high, 3 apart,
  radius 3 — labor `#3B9AE8`, expenses `#F0A44B`, profit `#84CC16` — and a legend of 13/500 `#C7D2D6`
  labels, 12 `#84979F` percentages and 13/600 white values.
- **Close-out:** a 52px ring (track `$color-surface-active`, progress `$color-interactive`, inner radius
  0.78, count in the middle) beside the title. Each item: a 24px state circle — done filled green with a
  white check, waiting subtle with an hourglass, to-do a 1.5 outline — label 14/600, state 12/500, and a
  30-high radius-8 bordered action button when the user can act.
- **Photos:** a three-column grid of 92-high radius-12 tiles, 8 apart; the last tile carries a
  `#032B3A99` overlay with "+N" 18/700 white. Files follow as rows with a 34px coloured file-type tile.
- **Notes:** 28px avatar, author 13/600 and time 12/500 on one line, text 13/500 at line height 1.5; a
  40-high radius-12 composer on `$color-surface-background-subtle` with a 28px green send button.

## Avatars and colour pairs

Initials avatars use an existing surface/on-surface pair per person — `$color-informative-*`,
`$color-request-*`, `$color-quote-*` — so the same person keeps the same colour across the page.
