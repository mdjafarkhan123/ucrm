# Fields

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `typography.md`

## Core Specs

- Label above the box: 13/600 `--color-heading`, 6 gap. A must-fill field adds a red `*` (13/700
  `--color-critical`) 4 after the label.
- Box: height 40, padding 0 12, radius 8, `--color-surface`, 1px `--color-border--interactive`.
- Value 14 `--color-heading`; placeholder `--color-text--secondary`.
- A word or icon in front (`$`, phone): 14/500 word or 16 icon in `--color-text--secondary` /
  `--color-icon--secondary`, 8 before the value.
- Small: 36 high, value 13, for tight spots (quantities, line items).

## Variants

- **Select:** chevron-down icon at the right, `--color-icon--secondary`.
- **Search:** search icon at the left. Once something is typed, a 24 clear button at the right: × 14
  `--color-icon` on `--color-surface--hover`, radius 6. The ⌘K hint (12/600 on `--color-surface--background`,
  radius 4) is only in the top bar's search. Inside a table's header: 38 high, 1px `--color-border`, 13/500.
- **Select with a word in front (filters):** an optional 16 icon, then the word 14/500 `--color-text--secondary`,
  then the value 14/600 heading ("Status · All").
- **Big text box:** 96 high (three lines), padding 10 12, line height 1.45, grows when dragged. With a letter
  limit, a 12/500 `--color-text--secondary` count under the right corner ("408 left"); over the limit it turns
  12/600 `--color-critical` ("12 too many").
- **Money:** the currency sign in its own block at the front: 40 wide (36 small), the field's full height,
  `--color-surface--background--subtle`, the sign 14/600 heading, a 1px `--color-border--interactive` line
  after it. The amount sits at the right, 14/600 heading (placeholder `0.00` regular `--color-text--secondary`),
  with thousands commas once the box is left ("1,250.00"). The sign follows the business's currency.
- **Quantity stepper:** 36 high, padding 3, gap 2. A 28 square − button and + button, radius 6,
  `--color-surface--hover` with a 14 icon `--color-icon` (hover `--color-surface--active`); the number centred
  between them, 13/600 heading. − is greyed (`--color-disabled` icon) at 1.
- **Error:** 1.5px `--color-critical` border; under it a 14px circle-alert icon and a 12px message in
  `--color-critical` that says what to fix.

## States

Hover: border `--color-border--interactive--hover`. Focus (typing, or a dropdown open): `--shadow-focus`.
Disabled: `--color-disabled--secondary` background, value and icons `--color-disabled`.
Text boxes, big text boxes and search share the hover edge and retain their typing focus while pressed.
A closed dropdown pressed state uses `--color-surface--active` and the hover edge, then opens the list.
Search clear: hover uses `--color-surface--active`; pressed adds a 1px hover edge.
Dropdown errors use the shared error border and a corrective message below the box.

## Dropdown list

- Opens 4 under the box, as wide as it: `--color-surface`, 1px `--color-border`, radius 16, padding 8, 2
  between lines, `--shadow-base`. The box's chevron turns up.
- Line: 36 high, padding 0 10, radius 8, 14 `--color-heading`. Mouse over: `--color-surface--hover`. Chosen:
  600 with a 16 check in `--color-interactive` at the right. Pressed: `--color-surface--active`.
  Can't be picked: `--color-disabled`.

## Checkbox

- An 18 box, radius 4 (`--radius-small`), 1px `--color-border--interactive`, white. Ticked: `--color-interactive`
  fill and edge with a white 12 check.
- 10 gap to the text: the label 14/600 `--color-heading`, an optional 12 `--color-text--secondary` description
  under it, 2 apart. Hover: edge `--color-interactive`. Focus: `--shadow-focus` on the box.

## Radio choice

- One pick from a short list whose words are too long for a segmented switch. Two forms.
- **Plain:** the question 14/600 heading, 8 above; options side by side 16 apart, wrapping. Option: an 18
  circle, 10 gap, the label 14 `--color-text` (chosen: `--color-heading`).
- **Tiles** (Setup questions, "This visit only" / "This and later visits"): a 13/600 heading question above, 8
  gap; tiles 8 apart. Tile: white, 1px `--color-border`, radius 8, padding 10 12, gap 10, aligned to the top; the
  circle, then the label 13/600 heading with an optional 12 quiet hint under it.
- Circle: white, 1px `--color-border--interactive`. Chosen: a 5px `--color-interactive` ring around a white centre;
  a chosen tile's edge is 1.5px `--color-interactive`.
- Hover: circle (and tile) edge `--color-interactive`; a tile also fills `--color-surface--hover`. Focus: 2px
  `--color-focus` ring around the option or tile. Can't change: circle `--color-disabled--secondary` fill with a
  `--color-disabled` edge or ring, words `--color-disabled`; a tile fills `--color-disabled--secondary` with a
  1px `--color-border` edge.

## On/off switch

- For a setting that takes effect straight away; a checkbox stays for choices counted when a form is saved.
- Track 44×24, pill corners, padding 0 3. Off: `--color-border--interactive` (hover
  `--color-border--interactive--hover`). On: `--color-interactive` (hover `--color-interactive--hover`).
- Knob: an 18 `--color-surface` circle, shadow 0 1 2 `--color-heading` 20% plus 0 2 6 at 10%. On, it slides
  right and holds an 11 check in the track's colour. No icons in the track.
- Focus: 2px `--color-focus` ring, 2 outside the track. Can't change, off: track
  `--color-surface--background--subtle` with a 1px `--color-border--interactive` edge, knob `--color-disabled`, no
  shadow. Can't change, on: track `--color-disabled`, knob `--color-surface--background`, check `--color-disabled`.
- Settings row: the words at the left (label 14/600 heading, description 12 `--color-text--secondary`, 2 apart),
  the switch at the right; rows padding 14 0, a 1px `--color-border` line between them.

## Segmented switch

- For two to four choices of one kind (One-off / Recurring, Ends after / Ends on). Field label above, 6 gap.
- Track: `--color-surface--background--subtle`, 1px `--color-border`, radius 8, padding 3, 2 between options.
- Option: 32 high, padding 0 14, radius 6, 13/600; an optional 16 icon 6 before the label. Not chosen: text
  `--color-text--secondary`, icon `--color-icon--secondary`, no fill. Chosen: white, 1px
  `--color-border--interactive`, `--shadow-button`, text `--color-heading`, icon in the meaning colour of the
  section (e.g. `--color-time` on Visits).

## People pick chips

- "Who is going": one round chip per person, 8 apart, wrapping. Height 36, padding 0 12 0 6, gap 8, pill
  corners, white, `--shadow-button`; a 24 avatar with a 2px white ring, the name 13/600, a 16 state icon last.
- Not picked: 1px `--color-border--interactive`, name `--color-heading`, `circle-plus` in `--color-icon--secondary`.
- Picked: 1.5px `--color-interactive` edge, name and `circle-check` in `--color-interactive`.
- Hover: `--color-surface--hover`. Focus: `--shadow-focus`. Each chip is a checkbox to assistive technology.

## Day picker

- Picks one or many days on a month (Create visits). In a box: 1px `--color-border`, radius 12, padding 12, rows
  6 apart. Header: 32 icon buttons ‹ › either side of the month 15/600 heading, centred.
- Weekday names 12/600 uppercase (0.6 spacing) `--color-text--secondary`; the week starts on the business's
  week-start day. Day cells share the width, 40 high, 4 apart, each a 36 circle with the date 13/500 heading.
- Today: 1.5px `--color-interactive` ring, date 13/700 `--color-interactive`. Picked: `--color-interactive` fill,
  date 13/700 white. Past days that cannot be picked: date `--color-disabled`. Days outside the month are blank.

## Message sheet

The email and text an automation sends (Settings → Automation), approved 2026-10-20 on board `qf1uu` (email A,
text A). One sheet, like a mail app; the step card around it keeps its number and a `--color-conversation` tile.

- Sheet: `--color-surface`, 1px `--color-border--interactive`, radius 8, clipped. Email: a 44 subject row (padding 0 12, gap 10, the
  label "Subject" 13/600 quiet with a critical `*`, the value 14/600 heading), a 1px hairline, then the message
  (padding 12, label "Message" 13/600 quiet, body 14 heading). Text: the message only.
- Values bar at the sheet's foot: `--color-surface--background--subtle`, padding 8 12, gap 8, a 1px hairline
  above: 14 `braces` in `--color-conversation`, "Insert" 12/600 quiet, the value chips 6 apart, and the
  letters-left count 12/500 quiet at the right.
- Value chip: 28 high, pill, white, 1px `--color-border--interactive`, `--shadow-button`, padding 0 12 0 9, gap 6, a 14 icon in
  `--color-conversation`, label 12/600 heading. Hover `--color-surface--hover`; focus `--shadow-focus`;
  pressed `--color-surface--active`. It inserts the value at the cursor, as today.
- Typing: a 2px `--color-focus` ring 4 outside the sheet, radius 12. Under the sheet, one 12
  quiet hint line ("Values in {{ }} are swapped for the real details when it sends").
- Unknown value or can't save: 1.5px `--color-critical` edge, the error line 12 `--color-critical` under the sheet.
- Text only, cost meter under the sheet: `--color-surface--background`, radius 8, 44 high, three facts 8
  apart, each a 24 white tile with its icon in `--color-conversation` and the fact 13/600 heading with a 12
  quiet word: characters · segments · estimated cost ("estimated from (555) 201-4417"). Estimating…: the facts
  after characters become "Estimating…" quiet; no texting number yet: one 12 quiet line instead.
- Send from stays a normal select (`Field · select`) with its hint; when the numbers couldn't load it is disabled
  with the hint in `--color-warning--onSurface`. The optional text inside "Reply by text or email" has two values
  and no Send from.

## Questions on a public form

A business's own questions as a customer answers them (board `Y3od0z`, B, Jafar 2026-10-20).

- One card per question, 12 apart inside the white form card: `--color-surface--background--subtle`, 1px
  `--color-border`, radius 14, padding 16, gap 12.
- Head: a 28 number tile (radius 8) in `--color-request--surface` with a 1px `--surface-edge` and the number
  13/700 `--color-request--onSurface`; 12 to the label 14/600 heading with the red `*`, the help line 12 secondary
  under it.
- Text, long text, number and dropdown use the approved boxes.
- Choices are tap tiles 8 apart: 44 high, padding 0 12, gap 10, radius 10, white, 1px
  `--color-border--interactive`, `--shadow-button`; the approved checkbox or circle, the label 14/500 heading.
  Picked: 1.5px `--color-interactive` edge and 600 label. Tick several stack; pick one and Yes / No sit side by
  side. Yes / No add a 24 tile (`thumbs-up`, `thumbs-down`): `--color-inactive--surface` with an
  `--color-inactive` icon, picked `--color-success--surface` with an `--color-success` icon.
- Hover: `--color-surface--hover` with a `--color-interactive` edge. Focus: 2px `--color-focus` ring.
- Photo questions use the page's approved upload box.

## Weekly hours

A business's normal week (Settings → Business hours, the setup wizard), approved B on board `DhRBV`
(Jafar 2026-10-21). One list inside the card, a day per row.

- Hour scale strip under the Card header: `--color-surface--background--subtle`, padding 10 20, "DAY" (12/600
  uppercase, 0.7 spacing, quiet) over the day column, then 12 AM · 6 AM · 12 PM · 6 PM · 12 AM spread across the bar
  column, 12/600 quiet.
- Day row: padding 16 20, gap 24, a 1px `--color-border` line above. Day column 240: a 40 tile (radius 10) with
  the short day name 12/700 in `--color-time--surface` / `--surface-edge` / `--onSurface`, 12 to the day name
  15/600 heading; closed or can't change, the tile is `--color-inactive` and a closed day's name is quiet. Under
  them, 52 in, the on/off switches 10 apart: Open (label in `--color-interactive`; "Closed" quiet) and Open 24 hours.
- Day bar: 32 high, radius 8, `--color-surface--background--subtle`, 1px `--color-border`, a 1px `--color-border`
  line at 6, 12 and 18 hours. Each open period is a block 24 high, 2 in from its edges, radius 6, `--color-time`
  with its range 12/600 in `--color-surface` ("8:00 AM – 5:00 PM"; shorter "7–11 AM" in a narrow block). Open 24
  hours fills the bar. A closed day's bar stays empty. Can't change: blocks `--color-disabled`.
- Under the bar, 12 apart: the periods 10 apart, each Start → End time boxes 150 wide with no visible labels, the
  length chip and a 32 × icon button (hover: `--color-surface--hover`, × in `--color-critical`); then a small
  secondary "Add another period" with a plus. The range error follows the time box rules.
- One column (640): the day heading row has Open 24 hours, then Open, at the right; the bar and periods (130
  boxes) sit under it.
