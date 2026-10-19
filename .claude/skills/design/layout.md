# Layout

> Dependencies: `sidebars.md`, `top-bar.md`

## Shell

- Sidebar 248 wide on the left; top bar 64 high across the content; content on `--color-surface--background`.
- Desktop web, designed at 1440px wide.

## Page header

- A 40 icon tile in the page's record or section colour, then the title (24/700, -0.5) with the description
  (14, `--color-text--secondary`) under it; no eyebrow. Actions sit at the right, centred: a More menu, then
  the main button.

## Page frame

- No white sheet: the page sits on `--color-surface--background` and each block on it is its own card
  (`cards.md`). Padding 32, 8 under the top bar; cards 24 apart.
- Widths: full (lists, calendars; capped at 1280), two columns (main column plus a 360 side column, 24 apart;
  record and create pages), narrow (one 640 column, centred; short forms and setup steps).
- A page whose content is not in cards yet keeps one white card around it (radius 16, 1px `--color-border`)
  until its own screen is redesigned.

## Breadcrumb trail

- Above the page header, 14 apart. One white capsule: `--color-surface`, 1px `--color-border`, pill corners,
  padding 4, steps 2 apart.
- Step: pill corners, padding 6 12, 14 icon `--color-icon-secondary` then the label 13/500
  `--color-text-secondary`. The first step starts with a 24 round `--color-heading` circle holding a white
  14 arrow-left (padding 4 12 4 4).
- Between steps a 16 chevron-right `--color-icon-secondary`.
- The page you are on: `--color-surface--background` fill, icon and label `--color-heading`, label 600; not a
  link.
- Hover: the step fills `--color-surface--hover`, label `--color-heading`. Focus: 2px `--color-focus` ring
  around the step.

## Create pages

- A create page (New job) has the page header, the form's blocks as separate cards 24 apart in the main column,
  and a 360 rail whose card stays in view while the form scrolls.
- **Floating save bar** at the foot, over the page: white, 1px `--color-border`, radius 16, padding 12 12 12 20,
  `--shadow-high`. Left: an 8 `--color-warning` dot, "New job · not saved yet" 14/600 heading, then a 12 quiet
  hint saying what else the save does ("Sarah gets the booking email when you save"). Right: Cancel (secondary)
  then the main button with a check icon.
- A record number given on save shows as a pill at the right of the page header: white, 1px `--color-border`,
  pill corners, padding 6 12 6 6; a 24 round tile in the record colour, "Job #" 12/600 heading, then
  "Given when you save" 12 quiet.

## Spacing

Tokens on a 4px grid: `--space-smaller` 4, `--space-small` 8, `--space-slim` 12, `--space-base` 16,
`--space-medium` 20, `--space-large` 24, `--space-larger` 32, `--space-largest` 48. (`--space-medium` is
for card padding.)

| Where | Value |
|---|---|
| Page padding | 32 |
| Gap between cards | 16–24 |
| Card padding | 20 (`--space-medium`)–24 |
| Inside a row | 12–14 gap, 12×16 padding |

## Rules

- Line up columns (status, date, amount) across rows.
