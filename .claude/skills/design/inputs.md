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
