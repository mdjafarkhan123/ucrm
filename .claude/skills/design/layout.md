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

## Record pages

- A record page (client, request, quote, job, invoice, payment) uses the two-column frame: main column of cards,
  a 336 side column, 24 apart. All six open with the same header card; only its data changes (below).
- Editing on a record page brings up the same floating save bar as a create page: status dot then the state
  (14/600 heading) and a 12 quiet hint; Cancel (secondary) then Save changes (main, check icon). Dot by state:
  editing with nothing changed `--color-inactive` and Save disabled; changed or saving `--color-warning` (Save
  shows its spinner, Cancel disabled); couldn't save `--color-critical` with the hint in
  `--color-critical--onSurface` 600 (Pencil: "Record page frame", approved 2026-10-20).

## Record header

One card for all six records (Pencil: "Record header · C", approved 2026-10-20). White, 1px `--color-border`,
radius 16, clipped.

- **Coloured top:** the record type's `--color-<record>--surface` (request peach, quote pink, job green, invoice
  and payment blue, client taupe), never the status's. Padding 20 24 22, rows 14 apart.
  - Row: a 40 white tile (radius 10, 20 icon in the record colour), the status pill on white, then the actions
    at the right, 8 apart: pencil and history as 36 white icon buttons, More, then the main button. No record
    info line (number, version, dates).
  - Title 26/700, -0.6, `--color-heading`. Renaming puts the field in its place.
- **Client line** on white, padding 16 24, 1px line under it: a 36 round avatar (`--color-client--surface`,
  initials 12/600 `--color-client--onSurface`), the name 14/600 over the contact row (13/500 `--color-text`,
  16 apart): 14 map-pin `--color-client`, phone `--color-time`, mail `--color-conversation`. The address opens in
  Google Maps and gives way first. No call / text / email buttons. The client page puts its address (16 pin,
  14/500 heading) here, with Message and Request a review at the right.
- **Facts:** padding 16 24 20, up to four even columns, 16 inset and a 1px `--color-border` line between them.
  Each: a 20 tile (radius 5, 12 icon, the fact's own colour family) and label 12/500 `--color-text--secondary`,
  6 over the value 14/600 heading. A missing value says what it waits for in `--color-text--secondary`.
- **Foot:** the Request → Paid track (padding 12 24, `--color-surface--background--subtle`, 1px line on top;
  32 step tiles, label 13/600, 700 on the current step, sub 12 quiet, 2px joining lines) or the client's tab
  band (`tabs.md`).

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
