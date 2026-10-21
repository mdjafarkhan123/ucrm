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

- A create page keeps its form blocks as separate cards 24 apart in the main column, beside a 360 right
  rail. The first card contains the page title; it stays within the main column rather than spanning the rail.
- **Floating save bar** at the foot, over the page: white, 1px `--color-border`, radius 16, padding 12 12 12 20,
  `--shadow-high`. Left: an 8 `--color-warning` dot, "New job · not saved yet" 14/600 heading, then a 12 quiet
  hint saying what else the save does ("Sarah gets the booking email when you save"). Right: Cancel (secondary)
  then the main button with a check icon.
- **Shared create form**, approved B by Jafar 2026-10-20 (Pencil: "Create form header · Approved B", `NhVGQ`;
  reusable "Create form · Shared work-record header" `OjBZG`, shown on `m4ibfF`, `pM2Vf` and New request `el2At`). One card for Request, Quote, Job
  and Invoice, built like the Record header: white, 1px `--color-border`, radius 16, clipped.
- **Coloured top:** the record type's `--color-<record>--surface`, a 1px `--color-<record>--surface-edge` line
  under it, padding 20 24 22, rows 18 apart. Heading row: a 40 white tile (edge `--color-<record>--surface-edge`,
  icon in the record colour), 14 gap to "New request / quote / job / invoice" (24/700, -0.5, heading) over a
  one-line description (14, `--color-<record>--onSurface`), 2 apart. Then the Title field full width (Invoice:
  Subject).
- **White part:** padding 20 24 24, items 24 apart, aligned to the bottom. The client picker fills the left;
  the record's own fact sits on the right, 208 wide. Required labels keep their red star. Conditional property
  controls stay under the client picker.
- **Record fact tile**, read-only, never a field box: 63 high, `--color-surface--background--subtle`, radius 8,
  padding 0 12, gap 10; a 32 tile (radius 8, 1px edge) then the label 12/500 quiet over the value 14/600 heading,
  4 apart. Request: Time calendar tile, "Requested on", the date. Quote, Job, Invoice: a `#` tile in the record
  colour, "Quote # / Job # / Invoice #", "Given when you save".
- **New job page**, approved A by Jafar 2026-10-20 (Pencil: "Batch 32 · New job page · Approved A", `q6Ffc`):
  the shared create form, then separate section cards in Jobber's order: Visits, Billing, Products and services;
  rail: the shared money summary card (`cards.md`). Visits card: Card header (Time tile, "1 visit · first on …",
  Create visits), body padding 20 gap 16: the Schedule segmented switch; the open visit in a radius 12 panel with
  a 1px `--color-time--surface-edge` edge, its head on `--color-time--surface` (44 `--color-time` date tile with
  weekday 12/600 over the day 16/700 in white; "Visit 1" 14/600 over the day and time 12 in
  `--color-time--onSurface`; who is going at the right 12/500 `--color-time--onSurface`, or "Nobody assigned yet"
  quiet; a chevron), body padding 16 gap 16: Visit title, Day · Start → End on one row, Anytime and Schedule
  later checkboxes side by side, Instructions with its count, Who is going chips, Remove visit (danger, small).
  Notify customer closes the card under a 1px line. Billing: Card header (Invoice receipt tile) and its checkbox.
- **New quote page**, approved A by Jafar 2026-10-21 (Pencil: "Batch 34 · New quote page · Approved A", `OzXHh`):
  the shared create form in quote pink, then separate cards: Introduction, Products and services, Client message,
  Contract disclaimer. An optional part not yet added is a slim card (padding 14 20, gap 14): a 40 quote tile,
  the title 16/600 beside an "Optional" tag (pill, `--color-surface--background--subtle`, 1px `--color-border`,
  12/500 quiet), a 12 quiet hint under it, and a small secondary "Add …" button at the right. Products and
  services: under the start choices, small secondary Add text and Add heading buttons; then a Client view row
  (1px line above, padding 12 20: an 18 eye in `--color-client`, "Client view" 14/600, a 12 quiet summary of what
  the client sees, a quiet green "Change" at the right) above the Quote subtotal foot. Contract disclaimer: Card
  header (file-check tile), a writing box and a foot with a 12 quiet hint and the count. Rail: the Batch 24
  totals card, one Discount and tax card, Notes, Attachments.
- **New invoice page**, approved A by Jafar 2026-10-21 (Pencil: "Batch 36 · New invoice page · Approved A", `EBLIe`):
  the shared create form in invoice colour (Subject, client, Invoice #), then separate cards: Products and
  services, Terms & dates. Products and services: Card header (package tile in invoice colour), each line open in
  the editor with its optional Service date box on the line's bottom row beside the kind pill, the Add row, and
  the Invoice subtotal foot. Terms & dates: Card header (calendar tile), body padding 20 gap 16, three equal
  columns on one row: Invoice date field with a 12 quiet "Today if left blank." hint; Payment terms select; Due
  date as a read-only 40 high tile (`--color-surface--background--subtle`, radius 8, padding 0 12, gap 10: a 16
  calendar-check icon in `--color-invoice`, the date 14/600 heading, "in 14 days" 12 quiet) with a 12 quiet hint;
  Custom date swaps the tile for a date field. Rail: the shared money summary card (`cards.md`), Attachments.
- Invoice dates and payment terms keep their existing Terms & dates card. Each page keeps its existing cards
  and right-sidebar contents. Client creation is outside this shared form's approval.

## Setup steps

A step-by-step page such as an import (Pencil: "Batch 29 · Import steps", approved A 2026-10-20). One 760
column, centred, blocks 24 apart: the page header, the step track, then one card for the current step.

- **Step track:** a white card (radius 16, 1px `--color-border`, padding 14 20), steps 12 apart joined by 2px
  lines that fill the space (`--color-success` behind a finished step, `--color-border` ahead). Step: a 32 tile
  (radius 8), then the label 13/600 heading over a 12 quiet hint. Finished: `--color-success--surface` tile
  with a check. Current: `--color-interactive` tile, white icon, label 700. Ahead: `--color-surface--background--subtle`
  tile, 1px `--color-border`, `--color-icon--secondary` icon, label quiet.
- **Step card:** the Card header (tile in the page's colour), a body with padding 20 and gap 16, and the pop-up
  footer bar: Back (secondary, arrow-left) at the left, a quiet 12 hint or nothing, and the main button at the right.
- **File box:** `--color-surface--background`, 1.5px `--color-border--interactive`, radius 16, padding 28 20,
  centred: a 40 `--color-success` spreadsheet tile, "Choose a CSV file or drag it here" 14/600 heading, the row cap
  12 quiet. Under it a 13/600 `--color-interactive` link with a download icon to the sample file.
- **Column matching:** rows edge to edge under an uppercase 12 head row (`--color-surface--background--subtle`).
  Row padding 12 20, gap 12: your column 14/600 heading over samples 12 quiet (240 wide), a 16 arrow-right
  (`--color-success` when matched, `--color-warning--onSurface` when not), the field box (40 high; matched starts with
  a 16 `--color-success` circle-check), then "Don't overwrite" (checkbox, 45% opacity when the column isn't
  matched). An unmatched row fills `--color-warning--surface`, its box edge 1.5px `--color-warning`, with a small
  "Pick one" warning pill under the samples.
- **Review:** four count cards in a row (white, radius 16, padding 16, gap 10): a 32 tile in the kind's colour
  (new: page colour, updates `--color-informative`, skipped `--color-inactive`, attention `--color-warning`), the
  number 32/700 heading, the label 13/500 quiet. Then notice strips: attention `warning`, "Nothing gets sent"
  `informative` with shield-check.

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

## Sign-in screens

The Jafar panel's sign-in, join, forgot-password and new-password screens (Pencil: board `Y0A1Z`, approved
B · Split screen 2026-10-20).

- The 1440 screen on `--color-surface`, 12 inset, split in two equal halves.
- Left: the deep-green brand panel (the screen's one feature card, `cards.md`), radius 20, padding 56,
  content spread top to bottom: the mark (40 tile on `--color-feature--subtle`, 1px `--color-feature--border`,
  white leaf) and "Uplift" 18/700; in the middle an "UPLIFT TEAM" pill (lock-keyhole, feature-subtle), "The
  control room" 48/700 (-1.2) and one 16 line in `--color-feature--text--secondary`. The same on every screen.
- Right: plain `--color-surface`, the form column 400 wide centred, no card, gap 20: title 28/700 (-0.6), intro
  15 quiet, fields 44 high, 16 apart; the main button full width, 44 high, 15 label; Back to sign in a quiet
  button; "Forgot password?" a 13/600 `--color-interactive` link at the right under the password.
- Messages: a 48 tile above the title — done `--color-success` (mail-check, circle-check), expired
  `--color-warning` (link-2-off, timer-off). A sign-in error is a `--color-critical--surface` box (1px
  `--surface-edge`, radius 8, padding 10 12, circle-alert, 13/500 `--onSurface` text) above the button.

## Booking page

The public page a prospect uses to book a call (Pencil: "Batch 30 · Booking a call", approved A 2026-10-20).
On `--color-surface--background`, padding 40 0, centred, 28 apart: the brand (a 32 `--color-interactive` tile,
radius 9, white 16 leaf, then "Uplift" 18/700 heading), then one card.

- **Card:** white, 1px `--color-border`, radius 20, a soft shadow (0 8 24, heading colour at 6%), clipped; 1080
  wide with the call's summary, 560 wide for a settled state.
- **Summary** (left, 340, 1px line at its right, padding 32 28, gap 24): a 44 round avatar
  (`--color-time--surface`, initials 14/700 `--color-time--onSurface`) with the host 14/600 over "Uplift" 12 quiet;
  the call's name 28/700 (-0.6) and its description 14 `--color-text` (line height 1.5); then, under a 1px line,
  fact rows (32 tile, label 12/500 quiet over the value 14/600): length `--color-time` clock, how
  `--color-conversation` video or phone. The chosen time joins them as a `--color-time--surface` box (1px edge,
  radius 12, padding 12 14): a white 32 tile with `calendar-check`, the time and date 14/600 and the zone 12, in
  `--onSurface`.
- **Steps** (right, padding 32 32 28, gap 24): the step title 20/700. Choosing: the month and a 240 times column,
  32 apart.
  - Month: the heading 16/700 with ‹ › as 36 icon buttons; weekday heads 12/600 uppercase quiet; days are 44
    circles. Open: white, 1.5px `--color-border--interactive`, number 14/700 heading, a 4 `--color-interactive` dot
    under it. Chosen: `--color-interactive` fill, white number. Closed: no fill, number `--color-disabled`. Today
    carries a 4 quiet dot. Under the month: a 16 globe, "Times in … time" 13 quiet and "Change" 13/600
    `--color-interactive`, underlined.
  - Times: the day 16/700, then buttons 44 high, 8 apart, full width: white, 1px `--color-border--interactive`,
    radius 8, time 14/600 `--color-interactive`. Hover: 1.5px `--color-interactive` edge, `--color-surface--hover`,
    and a 16 arrow-right after the time.
  - Details: the back button (quiet, arrow-left) above the title; fields two per row, 16 apart, 44 high; the note
    box; a footer under a 1px line with the security check at the left and the large main button at the right.
- **Settled states** (booked, request sent, link not working): a white top, padding 40 40 28, centred, gap 14: a 56
  white-edged tile (radius 16, 28 icon) in the status colour (done `--color-success`, waiting `--color-warning`,
  closed `--color-inactive`), the title 24/700 (-0.5), the message 15 quiet (line height 1.5). Then the facts under a
  1px line, padding 8 28: rows of a 40 tile (when `--color-time` calendar, how `--color-conversation`), label 12/500
  quiet, the value 14/600; the join link 13/600 `--color-interactive` with external-link; a pending link line 13
  quiet. The foot band (`--color-surface--background--subtle`, 1px line on top, padding 14 28): a 16 mail icon and
  the change-or-cancel hint 13 quiet.
