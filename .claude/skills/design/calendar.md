# Calendar

> Dependencies: `colors.md`, `badges.md`, `buttons.md`, `typography.md`

Pencil: `concept.pen` → "Concept · Schedule · Week · Owner · 1440", "Concept · Schedule · Day · Owner · 1440" and
"Concept · Schedule · Month · Owner · 1440" (all approved by Jafar 2026-10-19). Every Schedule pop-up is on one
board, "Concept · Schedule · Pop-ups · 1440".

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

## Month view

- Same page, card and toolbar (Month chosen; the range reads "October 2026"). The colour key leaves out "Now".
- Weekday row 36 high, 1px `--color-border` underneath: names 12/700 uppercase (0.6 spacing) `--color-text`,
  padding 0 12. Today's weekday is `--color-interactive` with a 3px
  `--color-interactive` line along the row's foot.
- Six week rows of equal height (154), 1px `--color-border` between rows and between days; the grid keeps its
  height and scrolls on short screens rather than squeezing.
- Date cell, padding 8, gap 4: the date 13/700 heading at the left (the 1st of a month reads "Nov 1"), the item
  count 11/500 quiet at the right ("Closed" on a closed day). Under it, only when needed, the filled "late" and
  "unassigned" pills from the Week day heading.
- Today: a floating tile inside the cell, 4 in from the grid lines: white, radius 10, 1px `--color-interactive`
  edge, a soft green shadow (0 6 16 brand green at 14%) over a hairline one (0 1 2 `--color-heading` at 8%),
  padding 4. The date is 12/700 white in a 24 `--color-interactive` circle. No tint on the cell.
- Closed day: the Week view's diagonal stripes across the cell.
- Days from the months either side: date 13/500 `--color-text--secondary`; their items, pills and "+ N more" at
  60% opacity.
- Items, 3 at most, 3 apart: 22 high, radius 6, padding 0 6, gap 5, the kind's surface, 12 type icon in the
  record colour, start time 11/600 in the record `--onSurface` (Anytime items have none), then the client 11/600
  heading (tasks and events show their title). Text that does not fit ends in "…".
- Late item: 3px `--color-critical` left edge. Unassigned item: a 6 `--color-warning` dot at the right end.
  Completed item: `--color-surface--active`, 1px `--color-border--interactive`, icon `--color-icon-secondary`,
  time and name `--color-text--secondary` and crossed out.
- More than three: "+ N more" 11/600 `--color-interactive` under the items.

## Visit pop-up

- Opens 10 beside the chosen card, which keeps its hover look while open. No arrow; the page is not dimmed.
- 368 wide, white, 1px `--color-border`, radius 16, `--shadow-base`, clip.
- Header as the form pop-up (`modals.md`): 40 tile in the record colour, the client 20/600 (-0.2) with the small
  status pill beside it, the work 12 quiet under it, and a 32 × icon button.
- Body, padding 20, gap 16. Facts 14 apart: a 32 tile (When and Team `--color-time`, Where `--color-client`), the
  label 12 quiet over the value 13/600 heading. Team shows the people circles (24, 2 apart) before the names; nobody
  assigned shows the value in `--color-warning--onSurface`.
- Timer panel: `--color-surface--background--subtle`, 1px `--color-border`, radius 8, padding 12 12 12 14; "Your
  timer" 13/600 with a 12 quiet state line, and a small secondary "Start timer" (play icon) at the right.
- Actions: small main "Mark complete" (check) and small secondary "Reschedule", sharing the width, 8 apart.
- Footer: `--color-surface--background--subtle` with a top line, padding 8 12: "Open job #" with an arrow-up-right
  at the left and "Move to Unscheduled" at the right, both small quiet buttons.

- Quote visit pop-up: the same frame with a `--color-request` tile (inbox); facts Client (`--color-client`), When,
  Team, Where; the timer panel; no actions; the footer holds only "Open request".
- Event pop-up: a `--color-event` tile (calendar-days, icon `--onSurface`), no status pill unless completed; facts
  When and Details (text-align-start, `--color-event` tile; value 13/400 `--color-text`, line height 1.45); actions
  Mark complete (fills the row), Edit (secondary, pencil) and Delete (danger, trash); no footer.

- Move visit: the same frame; 40 `--color-time` tile (calendar-sync), "Move visit" with "client · work" under it.
  Body gap 16: a change panel (`--color-surface--background--subtle`, 1px `--color-border`, radius 8) with rows
  padding 10 14 split by a line, label 12 quiet in a 56 column, "Now" 13/400 `--color-text`, "Move to" 13/600
  heading; each warning on `--color-warning--surface`, radius 8, padding 10 12, a 16 triangle-alert in
  `--color-warning` and 13/500 `--onSurface`; the repeat question as a radio choice (`inputs.md`); the Notify
  customer checkbox. Footer as the form pop-up's, padding 12 16, small Cancel then small "Save move" (check).

## Day list

- Opens from "+ N more" beside the Month date; picking an item opens its pop-up in the same place.
- 368 wide, the visit pop-up's frame. Header: 40 `--color-time` tile (calendar-days), the date 20/600 (-0.2)
  ("Wednesday, October 21"), under it the item count 12 quiet and the small filled "late" / "unassigned" pills.
- List padding 12, rows 6 apart, every item in reading order. A row is a compact Week card: the kind's surface,
  radius 8, padding 8 10; top row (20 high) the 14 type icon, time 12/600 `--onSurface` ("Anytime" when none) and
  the status pill at the right (outlined Late / Unassigned, filled Completed); then the client 13/600 heading with
  the work 12/500 `--color-text` beside it. Completed rows take the Week card's completed look.
