# Filter Chips, Tags and Sender Chip

> Dependencies: `colors.md`, `inputs.md` (dropdown list), `radius.md`

## Filter chip

- Sits above a list (in a list card's toolbar, beside the search box). Height 36, padding 0 10 0 12, gap 6,
  radius `--radius-base`, `--color-surface`, 1px `--color-border--interactive`, `--shadow-button`.
- Inside: a 16 icon `--color-icon`, the name 14/500 `--color-text`, a 1×16 `--color-border--interactive`
  line, the value 14/600 heading, a 16 chevron `--color-icon`.
- Name only (a chip that shows nothing until used): the name 14/600 heading, no line or value.
- Filtering: 1.5px `--color-interactive` edge, icon `--color-interactive`; the chevron gives way to a 24 clear
  button (radius 6, `--color-surface--hover`, × 14 `--color-icon`), padding right 6.
- A sort chip always shows its value and is never marked as filtering.
- Open: the focus ring and an up chevron; the list follows `inputs.md`'s dropdown list, 240 wide. A status
  filter's lines start with an 8 dot in the status colour.
- Hover: `--color-surface--hover`, edge `--color-border--interactive--hover`. Focus: 2px `--color-focus` ring.
  Disabled: `--color-disabled--secondary`, everything `--color-disabled`, no shadow.

## Tag

- A pill in the tag's own colour family: 28 high, padding 0 4 0 10, gap 6, `--surface` fill, no edge; a 13 tag
  icon in the main colour, the name 12/600 `--onSurface`, then a 20 round remove button with an 12 × in
  `--onSurface` (hover: the button fills `--surface`, darker). Look-only: no remove button, padding 0 10.
- The tag icon is what tells a tag from a status pill, which carries a dot.
- Tag colours: the business picks one of ten — Grey `--color-inactive`, Red `--color-critical`, Orange
  `--color-request`, Yellow `--color-review`, Green `--color-job`, Teal `--color-conversation`, Blue
  `--color-invoice`, Indigo `--color-time`, Purple `--color-growth`, Pink `--color-quote`.

## Tag picker

- Tags 8 apart, wrapping, then an "Add tag" pill: 28 high, padding 0 12 0 9, 1px `--color-border--interactive`,
  a 14 tag icon `--color-icon--secondary`, 12/600 `--color-text--secondary`. Hover: `--color-interactive` edge,
  icon green, `--color-surface--hover`. Focus: 2px `--color-focus` ring.
- The list: 280 wide, `--color-surface`, 1px `--color-border`, radius 16, padding 8, gap 6, `--shadow-base`. A
  36 search box at the top; lines 36 high with an 18 checkbox, a 14 tag icon in the tag's colour and the name
  14 heading (picked: 600). Hover: `--color-surface--hover`.
- Nothing found: 13 `--color-text--secondary` ("No matching tags.").
- Create: under a 1px `--color-border` line, a `--color-surface--hover` block: 16 circle-plus
  `--color-interactive`, "Create tag “Snow”" 14/600 heading; under it ten 16 colour dots (the picked one 12
  inside a 1.5px heading ring) and a 12 quiet hint. The next unused colour is picked for you.
- Changing a colour: a hovered line shows a 28 "⋯" button (radius 6, `--color-surface--active`) that opens a
  200-wide colour list beside it: "COLOUR" caption, 32 lines with a 14 dot and the name, the current one 600
  with a green check.
- Error: 14 circle-alert and a 12 `--color-critical` message under the search box.

## Sender chip

The "From" value in an email preview and the inbox composer's From → To line (board `I5mY7I`, Jafar
2026-10-20).

- A look-only pill: 28 high, padding 0 12 0 8, gap 6, `--radius-circle`, `--color-conversation--surface`, 1px
  `--color-conversation--surface-edge`; a 14 mail icon `--color-conversation`, the name 13/600
  `--color-conversation--onSurface`, the address 13/400 `--color-text--secondary`. No angle brackets.
- Stays one line. A long address ends in "…"; hover or keyboard focus shows the full name and address in
  the shared tooltip.
- Loading: a 240×28 pill-shaped bone in `--color-border`.
- Couldn't load: the same pill in `--color-critical--surface` with its `--surface-edge`, a 14 circle-alert
  `--color-critical`, the message 13/600 `--color-critical--onSurface`.
- No address yet: the same pill in `--color-warning--surface` with its `--surface-edge`, a 14 triangle-alert
  `--color-warning`, the message 13/600 `--color-warning--onSurface`.
