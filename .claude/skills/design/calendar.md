# Calendar

> Dependencies: `colors.md`, `badges.md`, `buttons.md`, `typography.md`

Pencil: `concept.pen` → "Concept · Schedule · Week · Owner · 1440" and "Concept · Schedule · Day · Owner · 1440"
(both approved by Jafar 2026-10-19).

## Page

- No page header: the calendar card fills the content area's full height under the top bar (page padding 8 top,
  32 sides, none at the foot).
- One white card, radius 16, 1px `--color-border`: toolbar, day headings, Anytime row, hour grid, colour key.

## Toolbar

- Padding 14 20, gap 8, 1px `--color-border` underneath.
- Left: a joined group ‹ | Today | › (`buttons.md`), then the range 20/700 heading with a 16 chevron-down.
- Right: Month / Week / Day segmented switch (chosen icon `--color-time`), a 1×24 divider, Unscheduled
  (switched-on look only while its drawer is open, `buttons.md`), then a joined group Map | Filters | •••.

## Grid

- Hours column 66 wide, labels 11/500 `--color-text--secondary` at the top right of each hour.
- 64 per hour, 7 AM–7 PM; hour lines 1px `--color-border`; day columns split by 1px `--color-border`.
- Day heading: weekday 11/600 uppercase (0.6 spacing) `--color-text--secondary`, date 20/700 heading, item count
  12/500 quiet at the right; under it, small filled pills for "2 late" (`--color-critical`) and "1 unassigned"
  (`--color-warning`).
- Today: weekday `--color-interactive`, date 15/700 white in a 30 `--color-interactive` circle, 3px
  `--color-interactive` line under the heading, column and Anytime cell on `--color-surface--background--subtle`.
- Closed day: white with 1px `--color-border` diagonal stripes, 12 apart; "Closed" in place of the count.
- Now: a 1px `--color-interactive` line across the open days and 3px on today, both behind the cards; a 10 dot at
  today's left edge; a `--color-interactive` pill in the hours column with the time 11/600 white.

## Cards

- Inset 4 from the column sides, 2 from the hour lines; radius 8; padding 6 8 (5 8 on one-hour cards); clip.
- Fill: the kind of work's `--surface` (visit `--color-job`, assessment `--color-request`, event `--color-event`,
  task `--color-task`). No border, no shadow.
- Top row: 14 type icon in the record colour (event uses `--color-event--onSurface`), the time 12/600 in the
  record `--onSurface`, gap 4. The time is always shown.
- Client 13/600 `--color-heading`, job 12/500 `--color-text` under it, line height 1.25; tasks and events show
  their title in the client style. One-hour cards put client and job on one line, 4 apart.
- Foot: people circles at the left (24, `--color-heading`, white initials 11/700, 2px ring in the card fill, 2
  apart) and the status pill at the right.
- Late: 4px `--color-critical` left edge plus an outlined "Late" pill. Unassigned: outlined "Unassigned" pill only,
  no edge. Outlined pill: white, 1px status-main edge, padding 3 8, 5 dot, 11/600 `--onSurface`.
- Completed (any kind): `--color-surface--active`, 1px `--color-border--interactive`, icon
  `--color-icon--secondary`, time, client and job `--color-text--secondary` and crossed out, no people circles,
  and a filled "Completed" pill (`--color-success--surface`, 11 check, 11/600) at the foot.
- Two or more at once: they share the column width side by side, 4 apart, padding 6 6, start time only.
- Hover: 1px edge in the record colour and a soft shadow (0 4 12 `--color-heading` at 12%).

## Anytime row

- 64 high, items 6 from the cell edges and 4 apart: 24 high, radius 6, padding 0 8, gap 6, the kind's surface,
  14 type icon, title 12/600 `--color-heading`. A late item adds the 4px red edge and its pill on a second line.

## Colour key

- At the card's foot, padding 12 20, 1px `--color-border` above: kind tiles (18) with labels 12/500, a divider, the
  Late / Unassigned / Completed pills, and a short `--color-interactive` line labelled "Now".

## Day view

- Same page, card, toolbar (Day chosen; the range reads "Wednesday, Oct 21, 2026") and colour key as Week.
- Columns: people 208 and Anytime 140, each with a 1px `--color-border` right edge; then the hours, 64 wide each,
  7 AM–7 PM, so the whole working day shows without sideways scrolling.
- Head row 76 high: the day summary at the left (weekday, today circle, item count, "late" and "unassigned"
  pills as in a Week day heading), "ANYTIME" 11/600 uppercase, then hour labels 11/500 quiet, 6 right of each
  hour line, with a short tick between hours. The now pill sits above the labels with a 2px stem.
- One row per person, Unassigned first; rows 96 high (lanes 88 plus 8), 1px `--color-border` underneath.
  Work that overlaps opens a second lane and the row grows. Hour lines run down every row.
- People cell, padding 14 16, gap 12: a 32 `--color-heading` circle with white initials 12/700 (Unassigned: a 32
  `--color-warning` icon tile with user-x), the name 14/600, then the item count 12/500 quiet with the booked
  hours 12/600 heading at the right, and a 4 high bar (`--color-border` track, `--color-time` fill) for hours
  booked against the working day.
- Day off: a plain "Day off" pill (moon icon) in place of the count, and the Anytime cell and hours hatched like
  a closed day.
- Cards sit 6 from the row edges and 2 from the hour lines, 84 high. No people circles: the row says who. A visit
  shared with others shows in each person's row with a 20 circle and "With Jake" 11/600 in the record
  `--onSurface`. Cards under two hours wide show the start time only.
- The now line is 2px `--color-interactive`, down every row behind the cards.
- Anytime cell: padding 6, pills 4 apart as in the Week Anytime row.
