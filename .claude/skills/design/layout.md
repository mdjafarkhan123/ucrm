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
- **On-site assessment panel**, approved A by Jafar 2026-10-21 (Pencil: "Batch 46 · On-site assessment panel ·
  Approved A", `PLgAR`): what Book a visit opens, on New request and on a saved request page. It stays inside its
  white card under the Card header (Time tile, truck icon). Body padding 20 gap 16 holds the open visit exactly like
  the New job open visit panel above: radius 12 panel, 1px `--color-time--surface-edge`, head on
  `--color-time--surface` (44 `--color-time` day tile, or a white tile with a 20 calendar-clock in `--color-time`
  when there is no day; "Assessment" 14/600 over the day and time or "No day yet" 12 `--color-time--onSurface`;
  who is going at the right, or "Nobody assigned yet" quiet), no chevron. Panel body padding 16 gap 16: Day ·
  Start → End on one row (hidden with Schedule later; Start and End hidden with Anytime), Anytime and Schedule
  later checkboxes side by side (only Schedule later while it is ticked), Instructions with its count, Who is going
  people pick chips, then Remove visit (danger, small). Notify customer closes the card under a 1px line (dated
  visits only). A saved request's panel ends in a 1px-topped actions row: Remove visit left; Cancel and Save visit
  (main, check icon) right. Errors: the field's error border plus a 12 `--color-critical` line with a 14
  circle-alert under the row; team loading, couldn't load and nobody else are one 13/500 line with a 16 icon under
  "Who is going".
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
- **New client page**, approved A by Jafar 2026-10-21 (Pencil: "Batch 42 · Client form · Approved A", `fJ8Mx`;
  the same page edits a client from the client page's ⋯ menu). First card: the coloured top in client sand
  (40 white `user-round` tile, "New client" or "Edit <name>", a 14 `--color-client--onSurface` line), then the
  Client type (Person / Company) and Status (Lead / Customer) segmented switches 24 apart; under it the white
  part, padding 20 24 24, gap 16: "Primary details" 16/600, fields two per row, 16 apart; email, phone, billing
  email and company carry a 16 front icon in `--color-conversation`, `--color-time`, `--color-invoice`,
  `--color-client`. Billing email is full width with its 12 quiet hint; Communication setting is a select with a
  Configure button (`settings` in `--color-conversation`). A similar client is a warning notice strip at the
  card's foot; an exact match is the critical strip and the matched field gets the error edge. Then the
  Client address card (Card header, `map-pin` client tile, the optional hint), fields two per row. Rail: Lead
  source, Tags (count in the hint), Notes, Attachments, all with client tiles. Save bar: Cancel, Save & create
  another, Save client. Edit: no address card, Notes or Attachments, no Save & create another; Lead can't be
  picked for a customer, with a 12 hint under Status.
- Invoice dates and payment terms keep their existing Terms & dates card. Each page keeps its existing cards
  and right-sidebar contents. The client form has its own first card (above).

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
- **New campaign**, approved A by Jafar 2026-10-21 (Pencil: "Batch 51 · New campaign · Goal step · Approved A",
  `t0L1xo`): the setup-steps frame in the Growth colour. Above the header, the breadcrumb trail ("Campaigns ›
  New campaign", megaphone on the current step). Header: a 40 `--color-growth` megaphone tile; at the right the
  save state (16 `cloud-check` `--color-success`, 12/500 quiet "All changes saved") then Save draft (secondary,
  `save`). The step track stacks each step: the 32 tile over the label and hint, centred, steps 112 wide, the 2px
  lines level with the tiles. Goal step card: Card header (Growth `target` tile), body gap 20: the goals as radio
  tiles two to a row, 12 apart (white, radius 12, 1px `--color-border`, padding 16, gap 14: a 40 Growth tile, the
  title 14/600 over the description 12 quiet, the 18 circle at the top right; chosen 1.5px `--color-interactive`
  edge), then the name field; the footer bar holds the hint and Continue (main, arrow-right).
- **New campaign · Customers step**, approved B by Jafar 2026-10-21 (Pencil: "Batch 53 · New campaign ·
  Customers step · Approved B", `RPlkr`). The step track shows Goal finished and Customers current. Card header:
  Growth `users` tile. Body (padding 20, gap 20):
  - Picker row: the Customer group select box, then New group (secondary, `plus`) at its right, bottoms level.
  - Rule chips: "Matches customers who" 12/500 quiet, then one chip per rule, 8 apart (28 high,
    `--color-surface--background--subtle`, 1px `--color-border`, radius 8, padding 0 10, gap 6): a 14 icon in the
    colour of what the rule checks (as the customer group pop-up) and the words 12/500 heading.
  - Audience meter: `--color-growth--surface`, 1px `--surface-edge`, radius 16, padding 20, gap 14. Top: a 40
    white tile with a 20 `mail-check` in `--color-success`, the count `-stat` 700 (-1), "customers will get this
    email" 14/600 heading over "out of N who match the group's rules" 12 `--color-growth--onSurface`. Then a 10
    high bar (white track, radius 5, 2 gap): the "will get it" share `--color-success`, the rest `--color-inactive`.
    Then the key: 8 dots with "N will get it" and "N left out" 12/500.
  - Why N are left out: 14/600 title over a 12 quiet hint, View customers (secondary, `eye`; Hide customers with
    `eye-off`) at the right. One list box (white, 1px `--color-border`, radius 12, clipped), a row per reason
    (padding 12 16, gap 12, hairline between): a 28 tile (radius 8; a reason the owner can fix in `--color-warning`,
    the rest `--color-inactive`), the reason 14/500 over a 12 quiet tip, the count 14/700 at the right.
  - Customer list (open): "Customers in this group" 14/600 with the filter select (200) at the right, then a list
    box of rows (padding 10 16): name 14/600 over email 12 quiet; at the right an excluded customer's reason as a
    grey pill, others a 14 `mail-check` with "Will get it" 12/500 `--color-success--onSurface`. Load more in a
    `--color-surface--background--subtle` footer.
  - Footer: Back, the hint "N customers will get this email." (empty while loading), Continue.
  - States: loading groups (bones for every block, the meter as one radius-16 block); counting (meter bones in
    `--color-growth--surface-edge`, hint "Counting who will get this email…"); no groups (Empty, Growth tile, New
    group main); couldn't load (`page-states.md`, Try again).
- **New campaign · Email step**, approved B by Jafar 2026-10-21 (Pencil: "Batch 54 · New campaign · Email step ·
  Approved B", `Nuydc`). For this step the column widens to 1092 (header and step track stretch with it); the
  track shows Goal and Customers finished, Email current. Card header: Growth `mail` tile. The body splits in two,
  the same height:
  - Editor (left, 440, padding 20, gap 20, 1px `--color-border` line on its right): Subject line and Preview text
    fields (label row with a 12/500 quiet "N left" at the right). Inside the box at the right a 28 square Variable
    button (radius 6, `--color-surface--background--subtle`, 1px `--color-border`, 14 `braces` `--color-growth`;
    open: `--color-growth` fill, white icon). A variable shows in the text as a tag: 24 high, padding 0 8, radius 6,
    `--color-growth--surface`, 1px `--surface-edge`, 12 `braces` and the name 12/600 `--color-growth--onSurface`.
  - Blocks: a hairline, then "Blocks" 16/600 with "N of 30" 14/500 quiet at the right. One row per block, 6 apart
    (`--color-surface--background--subtle`, 1px `--color-border`, radius 10, padding 8 12 8 8, gap 10): a 32
    Growth tile with the type's icon (image `image`, heading `heading`, text `pilcrow`, button
    `mouse-pointer-click`, divider `separator-horizontal`, service summary `list-checks`), the type 14/600, a short
    summary 14 quiet. The open block is white with a 1.5px `--color-growth` edge, padding 8 8 12 8: a filled
    `--color-growth` tile with a white icon, the type 14/700, then Move up / Move down as a joined group (32) and
    Remove (32 icon button, `--color-destructive` edge and `trash-2`); under it the block's fields, then the
    Variable button (28, Growth surface, `braces` and "Variable" 12/600) with the letter count at the right.
  - Add a block: a full-width secondary button (`plus`). Its menu opens above it when there is no room below,
    radius 16, padding 8: rows 48 high with a 32 Growth tile, the type 14/600 over a 12 quiet hint.
  - Live preview (right): `--color-surface--background--subtle`, padding 20 24 24, gap 16, centred. Toolbar: the
    Desktop (`monitor`) / Mobile (`smartphone`) switch, then at the right a pill (28 high, radius 14, white, 1px
    `--color-border`): an 8 `--color-success` dot and "Updates as you type" 12/600; while re-rendering a 16
    spinner and "Updating…", the last render staying in place. Then the inbox row (600 wide, white, radius 10,
    1px `--color-border`, padding 12 14): a 36 round `--color-interactive` avatar with the business initial, the
    sender 14/700 with the time at the right, the subject 14/600, the preview text 14 quiet. Then the email as in
    the email preview pop-up (`modals.md`); the block being edited has a 2px `--color-growth` outline (radius 6, 8
    outside the block) and at its top right a `--color-growth` tag (radius 6 6 0 0, 22 high) with the white type
    icon and "Text · editing" 12/600.
  - Footer: Back, the hint "Variables fill in with each customer's own details.", Continue.
  - States: no blocks (a quiet box "No blocks yet" with one line; the preview shows the business bar, a
    placeholder "Your blocks show here" and the footer); first preview loading (the email bone, pill "Loading the
    preview…"); couldn't render (page-states error with Try again, pill hidden); couldn't save (the form error card
    at the top of the editor, its hint the reason); photo block (photo box `files.md`: uploading, too big with the
    field error); 30 blocks (Add a block disabled).
- **New campaign · Delivery step**, approved B by Jafar 2026-10-21 (Pencil: "Batch 55 · New campaign · Delivery
  step · Approved B", `DWtO4`). Column back to 760; the track shows Goal, Customers and Email finished, Delivery
  current with the hint "Button and replies". Card header: Growth `route` tile. Body (padding 20, gap 20):
  - Email path: `--color-growth--surface`, 1px `--surface-edge`, radius 16, padding 20, gap 14. Head: 16 `route`
    `--color-growth` and "The path one email takes" 14/600 `--color-growth--onSurface`. Then four stops in a row, 6
    apart with a 16 `chevron-right` `--color-growth` between: each white, radius 12, 1px `--color-border`, padding
    14, 124 high, gap 10. Top: a 32 tile in the stop's colour, at the right a 20 round number (subtle fill, 1px
    border, 12/600 quiet). Then the label 12/500 quiet, the value 14/600 heading, a 12 quiet line. Stops: Sent from
    (`--color-conversation`, `mail`, the sender's name), Reaches (Growth `users`, the customer group), They press
    (`--color-informative`, `mouse-pointer-click`; the value is the email button: `--color-informative` fill,
    radius 6, padding 6 12, white 12/700 words), It opens (form: `--color-request` `clipboard-list`, the form name,
    "becomes a request"; website: `--color-informative` `globe`; phone: `--color-time` `phone`).
  - "Where should the button take them?" 16/600 over a 12 quiet hint, then one row per destination, 12 apart
    (white, radius 12, 1px `--color-border`, padding 14 16): radio 18, a 32 tile in the destination's colour, the
    title 14/600 over a 12 quiet detail, and at the right "Button:" 12 quiet with the button's words 12/600. Chosen:
    1.5px `--color-interactive` edge; under its row (indented 74) the Form select with Open form (secondary,
    `external-link`), or for the website a read-only line (40 high, subtle fill, `globe`, the address, "from your
    business profile" 12 quiet) with Open website. Can't pick: 55% opacity, off radio, the reason as the detail.
  - Two mini cards side by side (subtle fill, radius 12, 1px border, padding 14, gap 12): a white 32 tile, the label
    12/500 quiet, the value 14/600, a 12 quiet line, a 20 `circle-check` `--color-success`. Replies
    (`--color-conversation`, `inbox`: "Land in your shared Inbox") and Your plan (Growth `gauge`: the allowance).
  - Footer: Back, the hint "Nothing sends yet — you send or schedule it on the next step.", Continue.
  - States: nothing picked (stops 3 and 4 on the subtle fill with a 1px `--color-border--interactive` edge, grey
    tiles, "Not picked yet"); Continue with nothing picked (form error card at the top of the body); no verified
    sender (stop 1 with a 1.5px `--color-warning` edge, `--color-warning--surface` tile with `mail-x`, "No sender
    yet", and a warning notice strip under the path with Set up a sender); loading (the path box with white stop
    bones, then bones for the head, three rows and the two mini cards); couldn't load (`page-states.md`, Try again).
- **New campaign · Review step**, approved B by Jafar 2026-10-21 (Pencil: "Batch 56 · New campaign · Review step ·
  Approved B", `qCDG0`). The column widens to 1092 as on the Email step; the track shows Goal to Delivery finished,
  Review current. Card header: Growth `list-checks` tile, "Review before you send". The body splits in two:
  - Email (left): the Email step's preview well and toolbar, the pill reading "Shown with Sarah's details" (8
    `--color-success` dot), no editing outline; the email as in the email preview pop-up (`modals.md`).
  - Launch panel (right, 440, white, padding 20, gap 20, 1px `--color-border` line on its left):
    - The Customers step's audience meter (count, "customers will get this email", the bar and its key).
    - "Who, from whom, and where it leads" 16/600, then one list box (1px `--color-border`, radius 12, clipped),
      a row per fact (padding 12 14, gap 12, hairline between): a 32 tile, the label 12/500 quiet over the value
      14/600 and an optional 12 quiet line. Goal (Growth `target`), Customer group (Growth `users`, its rules), From
      (`--color-conversation` `mail`, the address and "replies land in your Inbox"), The button
      (`--color-informative` `mouse-pointer-click`, its words and where it opens, a 32 `external-link` icon button),
      Your plan (Growth `gauge`).
    - "When should it send?" 16/600, then two radio tiles 10 apart (white, radius 12, 1px `--color-border`, padding
      12 14, gap 12): the 18 radio, a 32 tile (chosen: Growth; not chosen: subtle fill, `--color-icon--secondary`),
      the title 14/600 over a 12 quiet hint. Send now (`send`), Schedule for later (`calendar-clock`). Chosen: 1.5px
      `--color-interactive` edge; the chosen Schedule tile holds Day to send and Time (40 boxes, 10 apart) and a
      14 `globe` with the business time zone 12 quiet.
    - The informative notice strip "Sent email can't be recalled…".
    - Actions, 10 apart: the large main button full width (44, `rocket`, "Send to N customers"; scheduled:
      `calendar-check`, "Schedule for <day> at <time>"), then a full-width secondary "Send a test email to yourself"
      (`mail-search`). A test result sits under them: a radius-8 box, padding 8 12, a 16 icon and 12/500 words, in
      `--color-success` (`mail-check`) or `--color-critical` (`mail-x`).
  - Footer: Back and the hint "Nothing sends until you press Send."; no main button (it is in the panel).
  - States: staff member (no When block or test button; a subtle box with an `--color-inactive` `lock` tile, "Ready
    for the owner to send" and why); sending (the main button's spinner); couldn't send (critical notice strip above
    the actions); needs a fix (the row on `--color-warning--surface` with a white tile, `--onSurface` icon and words
    and a 20 `triangle-alert`; a warning notice strip; the main button disabled); loading (the email bone,
    "Loading the preview…", a meter bone in `--color-growth--surface-edge`, list bones); couldn't load
    (`page-states.md`, Try again).

## Record pages

- A record page (client, request, quote, job, invoice, payment) uses the two-column frame: main column of cards,
  a 336 side column, 24 apart. All six open with the same header card; only its data changes (below).
- Editing on a record page brings up the same floating save bar as a create page: status dot then the state
  (14/600 heading) and a 12 quiet hint; Cancel (secondary) then Save changes (main, check icon). Dot by state:
  editing with nothing changed `--color-inactive` and Save disabled; changed or saving `--color-warning` (Save
  shows its spinner, Cancel disabled); couldn't save `--color-critical` with the hint in
  `--color-critical--onSurface` 600 (Pencil: "Record page frame", approved 2026-10-20).

## Record header

One card for all six records (Pencil: "Record header · C · White top", approved 2026-10-20, white top approved
2026-10-21). White, 1px `--color-border`, radius 16, clipped. Drawn 840 wide, the page's main column.

- **Top:** white like the rest of the card, with a 1px line under it; no record colour and no status stripe, so
  the status pill always shows in its own colour (Jafar, 2026-10-21). Padding 20 24, rows 16 apart.
  - Row: a 40 record tile (radius 10, `--color-<record>--surface` with its edge, 20 icon in the record colour;
    payment uses the invoice family), the large status pill, then the actions at the right, 8 apart: pencil and
    history as 36 icon buttons, More, then the main button. No record info line (number, version, dates).
  - Title `-display`, 700, -0.6, `--color-heading`. Renaming puts the field in its place.
- **Client line** padding 16 24, 1px line under it, 14 gap: a 44 round avatar (`--color-client--surface`, initials
  `-small` 600 `--color-client--onSurface`), the name `-large` 600 over the contact row (`-base` 500 `--color-text`,
  20 apart, 8 between icon and text): 16 map-pin `--color-client`, phone `--color-time`, mail
  `--color-conversation`. The address opens in Google Maps and gives way first. No call / text / email buttons.
  The client page puts its address (18 pin, `-base` 500 heading) here, with Message and Request a review at the
  right.
- **Facts:** padding 20 24, up to four facts in one row, 12 apart; each takes the room its words need and the
  spare room goes between them, with a 1px `--color-border` line and 12 inset before each fact after the first.
  Each: a 40 tile at the left (radius 10, 20 icon, the fact's own colour family), 10 gap, then the label
  `-small` 500 `--color-text--secondary` over the value `-base` 600 heading, 4 apart. When the row is too
  narrow (the live main column is 771 wide at 1440) only a long value (over 14 characters, such as an email)
  ends in "…", with its full text on hover; labels and short values stay whole. A missing value says what it
  waits for in `--color-text--secondary`.
- **Foot:** the Request → Paid track (padding 12 24, `--color-surface--background--subtle`, 1px line on top;
  32 step tiles, label `-label` 600, 700 on the current step, sub `-overline` quiet, 2px joining lines) or the
  client's tab band (`tabs.md`).

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
