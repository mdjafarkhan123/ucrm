# Cards

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `icon-shapes.md`, `typography.md`

## Core Specs

- Background `--color-surface`; 1px `--color-border`; radius 16; no shadow.
- **Title area:** every white card with a title starts with the one shared **Card header** part (Pencil:
  "Card header" on the Parts board), so a change to it reaches every card (Jafar, 2026-10-18): a 40 icon tile in
  the card's meaning colour, the title 20/600 (`--typography--fontSize-larger`, -0.2), an optional 12 quiet hint
  under it, the card's actions at the right, padding 16 20 (`--space-base` `--space-medium`; 14 16 in a narrow
  right column), and a full-width 1px `--color-border` line underneath. The body below has padding 20
  (`--space-medium`) and gap 16. A table head right under the header supplies that line itself.

## Section card and side card

- **Section card** (a block of a page): the Card header, then a body with padding 20 and gap 16.
  - Facts: rows of label (13/500 `--color-text-secondary`, 140 wide) and value (14/500 `--color-heading`),
    padding 10 0, a 1px `--color-border` line between rows.
  - List: rows run edge to edge, padding 14 20, a 1px line between rows, no body padding.
  - A group inside a card is never a second card: a 1px `--color-border` line above, 16 space, a 16/600 title
    and a 12/500 quiet hint, then its fields 12 below.
- **Side card** (in the 360 side column): the same, with the header padding 14 16 and body padding 16. A count
  goes in the hint line ("3 tags · used to filter clients").
- The header tile's colour is what the card is about: a record, or a part of the app (`colors.md`).

## Anatomy (stat card)

1. Header: 32 tile + title 14/600 + quiet open icon (arrow-up-right) at the right.
2. One big number, 32 (`--typography--fontSize-stat`)/700 `--color-heading`.
3. Footer: a status pill and a 13px quiet line ("across 9 invoices").

## Feature card

- The one card a screen leads with (Home: greeting, day summary and day clock). At most one per screen; never on a
  card full of record tiles or status pills.
- Linear gradient `--color-feature--start` → `--color-feature--end`, plus a radial `--color-feature--glow` at the
  top right; no border; radius 16; padding 24 32.
- Text `--color-feature--text` (title 28/700 `--typography--fontSize-display`, -0.6) and
  `--color-feature--text--secondary`. Panels inside: `--color-feature--subtle` with 1px `--color-feature--border`,
  radius 16; their icons white. A white secondary button sits on it unchanged.

## Status tiles (overview card)

- The clickable tiles in a list's overview card (Jobs "Needs attention"): white, 1px `--color-border`, radius 16,
  padding 14 12, gap 12, 8 apart inside 16 card padding.
- Top row: a 32 icon tile in the status colour (`icon-shapes.md`; the yellow family uses its `--onSurface` icon)
  and a 16 arrow-right at the right. Then the count 32/700, the label 13/600 heading, the hint 12 quiet.
- Hover: `--color-surface--hover`, border `--color-border--interactive--hover`. Picked: 2px inner
  `--color-interactive` ring. An act-now tile with a count is filled `--color-critical--surface`, its icon tile
  white and its text `--color-critical--onSurface`.
- The feature card beside it: a 32 tile (`--color-feature--subtle`, 1px `--color-feature--border`, white
  icon) before an 12/600 uppercase eyebrow; the figure 28/700 under it; the second figure or the legend rows in a
  `--color-feature--subtle` panel (1px `--color-feature--border`, radius 8, padding 12 16) at the card's foot.
- Money on the feature card beside it: money in is white, money still to come white 72%, overdue
  `--color-feature--alert`; a figure pill is white with `--color-feature--start` text.

## Number card

A row of counts (campaign sending results, automations); a card may open the list behind its number (Pencil:
board "Load more, form errors, edit button, number cards", approved 2026-10-19).

- White, 1px `--color-border`, radius 16, padding 16 16 14, gap 12; cards in a row 16 apart, same height.
- Top row, gap 12: a 40 tile in the card's status colour (`icon-shapes.md`), then the number 26/700 (-0.6)
  `--color-heading` over its label 13/600 in the status `--onSurface` colour. A card that opens a list adds a
  16 `arrow-right` `--color-icon--secondary` at the right.
- Note under it on a band: `--color-surface--background`, radius 8, padding 8 10; text 12/500
  `--color-text-secondary`.
- Colour is the status: waiting `warning`, planned `informative`, done `success`, act now `critical`,
  stopped or draft `inactive`.
- Link hover: `--color-surface--hover`, border `--color-border--interactive--hover`, arrow `--color-heading`.
  Focus: the 2px `--color-focus` ring.

## States

- Static: no hover.
- Clickable: hover `--color-surface--hover`, pointer cursor.

## Rules

- One job per card: one number or one list, one action.
- Cards in a row share the same height.
