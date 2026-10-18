# Fields

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `typography.md`

## Core Specs

- Label above the box: 13/600 `--color-heading`, 6 gap.
- Box: height 40, padding 0 12, radius 8, `--color-surface`, 1px `--color-border--interactive`.
- Value 14 `--color-heading`; placeholder `--color-text--secondary`.

## Variants

- **Select:** chevron-down icon at the right, `--color-icon--secondary`.
- **Search:** search icon at the left; optional ⌘K key hint (11/600 on `--color-surface--background`, radius 4).
- **Error:** 1.5px `--color-critical` border; under it a 14px circle-alert icon and a 12px message in
  `--color-critical` that says what to fix.

## States

Hover: border `--color-border--section`. Focus: `--shadow-focus`. Disabled: `--color-disabled--secondary`
background.

## Checkbox

- An 18 box, radius 4 (`--radius-small`), 1px `--color-border--interactive`, white. Ticked: `--color-interactive`
  fill and edge with a white 12 check.
- 10 gap to the text: the label 14/600 `--color-heading`, an optional 12 `--color-text--secondary` description
  under it, 2 apart. Hover: edge `--color-interactive`. Focus: `--shadow-focus` on the box.

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
