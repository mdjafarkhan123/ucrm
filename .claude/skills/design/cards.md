# Cards

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `icon-shapes.md`, `typography.md`

## Core Specs

- Background `--color-surface`; 1px `--color-border`; radius 16; padding 20 (`--space-medium`); gap 16; no shadow.

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
  icon) before an 11/600 uppercase eyebrow; the figure 28/700 under it; the second figure or the legend rows in a
  `--color-feature--subtle` panel (1px `--color-feature--border`, radius 8, padding 12 16) at the card's foot.
- Money on the feature card beside it: money in is white, money still to come white 72%, overdue
  `--color-feature--alert`; a figure pill is white with `--color-feature--start` text.

## States

- Static: no hover.
- Clickable: hover `--color-surface--hover`, pointer cursor.

## Rules

- One job per card: one number or one list, one action.
- Cards in a row share the same height.
