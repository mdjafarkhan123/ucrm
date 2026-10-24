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

## Settings home

The control room: every setting shows how it is set right now (Pencil: "Batch 63 · Settings home · Approved A",
`PZ8xu`, Jafar 2026-10-22). Full-width page frame, blocks 24 apart.

- **Page header:** the 40 `--color-inactive` settings tile, title and description; at the right a 360 settings
  search box (`inputs.md` search, no key hint).
- **Top row:** the business card fills the left; a 360 column at the right holds the feature card, then the
  balance card, 16 apart. The business card stretches to the column's height.
  - **Business card:** white, 1px `--color-border`, radius 16, clipped. Top padding 24 24 20, gap 16: a 64
    `--color-interactive` logo tile (radius 16, white 30 leaf or the logo), the name `-display` 700 (-0.6) with the
    profile status pill beside it, a 14/500 `--color-text` line under it, and the contact row (16 icons: phone
    `--color-time`, mail `--color-conversation`, web `--color-inactive`; 14/500, 16 apart); Edit profile
    (secondary) at the right. Facts below on `--color-surface--background--subtle` with a 1px line on top,
    padding 0 24: rows of two facts that share the height, a 1px line between rows; each fact a 32 tile in its
    own colour, label `-small` 500 quiet over the value `-base` 600 heading.
  - **Ready for customers:** the screen's one feature card (`cards.md`), padding 20 24, gap 14: an overline
    eyebrow, "10 of 12" `-stat` 700 white with "set up" 14 white 72%, a bar of one 8-high segment per item (3
    apart, done white, left `--color-feature--subtle`), then one row per item left: feature-subtle panel, 1px
    feature border, radius 12, padding 10 12, a 32 outlined icon box, title 14/600 white, arrow-right.
  - **Balance card:** white card, padding 18 20, gap 10: a 32 `--color-conversation` wallet tile, the label 14/600
    heading and a state pill at the right (Enough `success`, Running low `warning`); the amount `-stat` 700 with a
    small secondary Request top-up button at the right; one 14 quiet usage line.
- **Area cards:** three columns 24 apart, cards stacked 24 apart in each column. Each card: white, 1px border,
  radius 16, the Card header (padding 14 16; 40 tile in the area's colour; hint counts settings and what needs
  you), then rows in 6 8 padding. Row: padding 10 8, gap 12, radius 8; a 32 tile in the setting's own meaning
  colour, the name 14/600 heading, the current value 14/500 quiet at the right (or a status pill when it is a
  state: done, waiting), then a 16 chevron-right `--color-icon--secondary`. Hover `--color-surface--hover`.
- **Your account strip:** one white card across the page, padding 14 16, gap 24: a 40 round `--color-heading`
  avatar with "Your account" 16/600 over name and role 14 quiet, then cells divided by a 1px left line: 32 tile,
  name 14/600, value or pill, chevron; desktop alerts end in the on/off switch (`inputs.md`).

## Business profile

A settings page that reads like the business card; each section opens in place on its own Edit (Pencil:
"Batch 64 · Business profile · Approved B", `dw4fp`, Jafar 2026-10-22). Full-width page frame, blocks 24 apart.

- **Top:** the breadcrumb trail (Settings › Business profile, `store`), 14 above the page header: the 40
  `--color-inactive` `store` tile, title and description; at the right a 16 `history` icon and the last change 12/500
  quiet.
- **Business card:** white, 1px border, radius 16, clipped. Identity padding 24 24 22, gap 20: a 72
  `--color-interactive` logo tile (radius 18, white 34 leaf or the logo), the name `-display` 700 (-0.6) with the
  profile pill, a trade line (16 `hard-hat` `--color-job`, trade 14/600 heading, a 4 dot, city 14/500 text), the
  tagline 14 quiet in quotes (line height 1.5, 640 wide), and Edit name and trade (secondary, `pencil`) at the right.
  Under it a `--color-surface--background--subtle` band (1px line on top, padding 12 24, gap 10): "Customers see this
  on" 12/600 quiet, then white pill chips (1px border, padding 4 10 4 6) each with a 20 round tile in the place's
  colour (quotes, invoices, emails and texts, client portal, booking forms) and the name 12/600 heading.
- **Section cards:** Contact and Time zone and currency side by side (same height), then Where you work across the
  page. Closed: the Card header with Edit (secondary, `pencil`), then fact rows edge to edge (padding 14 20, gap 12,
  1px line between): a 32 tile in the fact's meaning colour, label 12/500 quiet over the value 14/600 heading; a
  state sits at the right as a pill (Not confirmed `warning`, Street hidden `inactive`, Locked `inactive` with a 12
  lock) with Confirm (small secondary) beside it. A reason goes in a subtle footer band (1px line on top, padding 12
  20, a 14 `--color-informative` info icon, 12/500 quiet).
- **Open section:** the same card with a 1.5px `--color-interactive` edge and a soft lift (0 8 24, heading 8%);
  header without Edit, the body padding 20 gap 16 with the fields (`inputs.md`), and a footer bar
  (`--color-surface--background--subtle`, 1px line on top, padding 12 20, gap 8): a 12/500 quiet hint, Cancel
  (secondary) and Save (main, `check`, named for the section). The business card opens with the logo column at the
  left (logo over a 12/600 `--color-interactive` "Logo in Branding" link with arrow-up-right).
- **Where you work:** the map panel at the left (520, `--color-surface--background--subtle`, 1px line at its right,
  pale `--color-surface` roads): the service-area ring (`--color-client--surface`, 1.5px `--color-client` edge), an
  inner `--surface-edge` circle, a 32 round `--color-client` base pin with a white house and a 2px white edge, a
  white distance chip (12/600) and a white place label (12/500 quiet). Facts or the open fields at the right.
- **Someone saved first:** the open card's edge turns 1.5px `--color-critical`; a `critical` notice strip (`notices.md`,
  `users` icon) names who changed it and when; the footer hint says your changes are kept, with See their version
  (secondary, `git-compare`) and Save.
- **Staff who can't change it:** every section closed, no Edit or Confirm; an `informative` notice strip with a lock
  under the page header says who can change it.

## Branding

A studio: the logo and colour at the left, a live picture of what customers see at the right (Pencil: "Batch 65 ·
Branding · Approved A", `FjLSw`, Jafar 2026-10-22). Full-width page frame, blocks 24 apart.

- **Top:** the breadcrumb trail (Settings › Branding, `palette`) and page header as on Business profile, with the
  40 `--color-inactive` `palette` tile and the last change at the right.
- **Columns:** a 520 controls column and the preview column filling the rest, 24 apart.
- **Logo card:** Card header (`image`, inactive), body padding 20 gap 16. A 196 stage
  (`--color-surface--background--subtle`, 1px border, radius 12) holding a 320×128 white paper sheet (radius 8, a
  soft 0 1 2 and 0 6 16 shadow) with the logo centred; the paper stays white in dark mode. "Small sizes": white
  pill chips (1px border, padding 4 12 4 4) with the logo at 32, 28 and 24 and the place 12/600. Actions under a
  1px line: Replace logo (secondary, `upload`), Remove (danger), the file hint 12/500 quiet at the right.
- **Logo states:** the stage carries the state. No logo yet: a 1.5px `--color-border--interactive` edge, a 32
  inactive `image-plus` tile, one 12 quiet line, Upload logo. New logo: `warning` pill "Not saved yet". Saved: an
  `informative` "Being checked" pill, the spinner and a 12 quiet line. Removed: the paper at 40% opacity, a
  `critical` pill "Removed on Save", Undo (secondary, `rotate-ccw`).
- **Brand colour card:** Card header (`palette`, inactive). A 76 swatch (radius 14, 1px border) with a 24 white
  pipette badge at its bottom right, the Colour code field and Reset to default (secondary, `rotate-ccw`) in one
  row aligned to the bottom. Quick picks: 32 rings (padding 3, 1px border; chosen 2px `--color-heading`) around
  the colour. Then a `success` notice strip when white words read clearly on the colour, `warning` when they don't.
- **Preview card:** Card header (`eye`, informative) with "Nothing is sent until you save". The 3-choice segmented
  switch (Quote page, Shared files, Website chat), then a subtle stage (radius 12, padding 24 40) holding the
  customer page: white, radius 10, a soft 0 2 4 and 0 12 28 shadow, a grey browser bar, the 4-high brand-colour
  line, the logo top and the page with its main button in the brand colour. The customer page keeps its own light
  colours in dark mode. Under it, 24 tiles with 12/600 labels name what uses the brand. A white team note card
  (32 inactive `panel-left` tile) says the sidebar shows the logo too.
- **Save bar:** floats centred at the bottom once something changes: 720 wide, white, 1px border, radius 12,
  `--shadow-high`, padding 10 10 10 16: a 32 `warning` `pencil-line` tile, the change count 14/600 over what
  changed 12/500 quiet, Cancel (secondary) and Save branding (main, `check`).
- **Someone saved first:** a `critical` notice strip (`users`) under the page header says who saved and when; the
  save bar's tile turns `critical` `git-compare`, the title says the changes weren't saved, and Cancel becomes See
  their version (secondary, `git-compare`).
- **Staff who can't change it:** an `informative` notice strip with a lock under the page header; no Replace,
  Remove, Reset, quick picks or save bar; the colour code field shows the disabled look; the preview still works.

## Number paperwork

The documents a country asks for before a texting number can be bought there (Pencil: "Communications · Number
paperwork · Approved", `A0URqF`, Jafar 2026-10-22). Texting parts use `--color-conversation`.

- **List page:** full-width page frame. The breadcrumb trail (Settings › Phone & SMS › Number paperwork,
  `file-check`) and page header (40 conversation `file-check` tile; New paperwork, main, `file-plus`). Then the list
  card filling the left and a 360 side column, 24 apart.
  - **List card:** Card header (`files`, hint "4 sets · 1 needs a fix"), an uppercase 12 head row on
    `--color-surface--background--subtle`, rows padding 14 20 with a 1px line between: a 32 round flag, the country
    and kind 14/600 over "Business · sent Oct 18" 12/500 quiet, a 140 numbers column (14 icon, 12 text: a number in
    heading with a conversation `phone`, or "None yet" quiet with `hourglass`), a 130 status column (Draft
    `inactive`, Under review `warning`, Approved `success`, Needs a fix `critical`), then `chevron-right`.
  - **Needs a fix row:** sits first, filled `--color-critical--surface`, its meta in `--onSurface`. Under it a white
    box (radius 12, 1px critical `--surface-edge`, padding 12 14): a 32 critical tile (`file-x`), what's wrong 14/600
    over the reason 12 quiet, and Fix and send again (small secondary, `file-pen`).
  - Foot band (subtle, 1px line on top, padding 12 20): a 14 informative `info` and one 12/500 quiet line.
  - **Side cards:** How it works (informative `route`): numbered 28 informative circles joined by a 2px
    `--surface-edge` line, title 14/600 over a 12 quiet hint. Details we reuse (client `building-2`): fact rows
    (32 tile, label 12/500 quiet over value 14/600) and a subtle foot band with a 13/600 `--color-interactive` link.
- **New paperwork:** the setup-steps frame (760 column): breadcrumb ending in New paperwork, header with the save
  state and Save draft, the step track (Country and kind, Business details, Documents, Check and send), one step
  card in conversation tiles, the footer bar (Back, "Step 2 of 4 · saved as you type", Continue).
  - **Business details:** two radio tiles (A business, Just me), then groups (1px line on top, 16/600 title, 12
    quiet hint), fields two to a row. The chosen address is a radio card with a 1.5px `--color-interactive` edge,
    a 32 client `map-pin` tile and a success pill.
  - **Documents:** one box per document (white, radius 12, 1px border, padding 16): 32 tile, name 14/600 over what
    it must show 12 quiet, a state pill (Needed `warning`, 64% `informative`, Checking `warning`, Didn't upload
    `critical`, Added `success`); "What counts" chips (28 high, subtle, 1px border, a 14 success `check`); the file
    box (`files.md` upload look) or the file line (subtle, radius 8, the 40 progress ring around a 32 round tile). A
    lock notice strip (`informative`) says files stay private.
  - **Check and send:** fact rows with a quiet Change, "WHAT HAPPENS NEXT" boxes as on the Add number pop-up, a
    `success` notice strip that paperwork is free, Send for review (main, `send`).
- **Opened set:** the flag (40) beside the title, a large status pill. A status card: a band in the status
  `--surface` (40 white tile, 16/600 title and 12 line in `--onSurface`) with the action at the right; Needs a fix
  adds a 1.5px `--color-critical` edge and the form-error rows below. Then What you sent (the Check rows; the row
  to fix filled `--color-critical--surface` with Replace).
- **States:** list empty, loading and couldn't load use page states inside the list card. Sending: the button's
  spinner, Back dimmed. Sent: a centred card with a 40 success `send` tile, "Sent for review" 24/700, Back to paperwork.

## Number readiness

Whether each texting number can text yet, on Phone & SMS (Pencil: "Communications · Number readiness · Approved
B", `NbWfA`, Jafar 2026-10-22). Texting parts use `--color-conversation`.

- **Page:** the breadcrumb trail (Settings › Phone & SMS), the page header (40 conversation `phone` tile; Number
  paperwork secondary `file-check`, Add number main `plus`), then a summary card, the number cards two to a row
  (24 apart), and one 12/500 quiet foot line with a 14 informative `info`.
- **Summary card:** white, padding 24, gap 32. Left: a 40 conversation `message-circle` tile beside "CAN YOU
  TEXT YET?" 12/600 uppercase quiet; the count at 34/700 heading ("2 of 4", "All 3") beside its words 16/600;
  one 14 quiet line naming what needs you, or "Nothing needs you"; a bar of one 10-high round segment per number
  in its status colour, 4 apart; a legend of 8 dots and 12/500 quiet counts. Right: a 440 subtle box (radius 12,
  1px border, padding 14 16), "WHERE YOU CAN TEXT", one row per country (24 round flag, name 14/600, status
  pill: Ready `success`, Setting up `warning`), then a 13/600 `--color-interactive` link with `plus`.
- **Number card:** white, radius 16, 1px border; Action needed and Texting paused take a 1.5px
  `--color-critical` edge. Top (padding 20, gap 18): a 40 round flag, the name 16/600 (a plain-label Default tag
  with `star` beside it) over the number, country and kind 12/500 quiet, and the ⋯ icon button. The journey on a
  subtle box (radius 12, padding 14 12): four 104-wide steps (Bought, Paperwork, Approval, Texting), each a 28
  circle over its name 12/600 and a 12/500 quiet hint, joined by 2px lines (`--color-success--surface-edge`
  between done steps, `--color-border` after). Circles: done `success` `check`, waiting `warning` `hourglass`
  (`loader` while connecting), your turn `informative` `pencil`, failed `critical` `x`, not yet white with a
  border and its number. Then the ability chips (28 high, white, 1px border, 14 conversation icon, 12/600).
- **Status band:** the card's foot in the status `--surface`, padding 14 20, gap 12: a 32 white tile (status
  `--surface-edge` edge, 16 icon), the title 14/600 over one 12/500 line, both in `--onSurface`, and at most one
  small secondary button at the right. Statuses: Business details needed `informative` (`building-2`), Under
  review `warning` (`hourglass`), Action needed `critical` (`file-x`), Ready to text `success`
  (`circle-check`), Getting your number ready `warning` (`loader`), Texting paused `critical` (`circle-pause`).
- **Renewal strip** (Pencil: "Communications · Monthly number renewal · Approved B", `QiDBX`, Jafar 2026-10-23):
  between the card's top and its status band, full width, a 1px line on top, padding 14 20, gap 12. A head row
  (gap 16): a 32 white tile (16 icon), an uppercase 12/600 eyebrow over the date and price 14/600, and at most one
  small secondary button (Add money, `wallet`) at the right. Under it a meter: 12/600 words at the left and 12/500
  at the right over an 8-high round bar. Paid: `--color-surface--background--subtle` with a `--color-border`
  line, conversation `refresh-cw`, "RENEWS", the bar full in `--color-success` ("Balance $4.60 covers it"). Balance
  too low: the warning family (`wallet`, "RENEWS IN 3 DAYS"), the bar filled in `--color-warning` as far as the
  balance covers the price ("$0.40 of $1.15 · short by $0.75"). Couldn't renew: the critical family
  (`calendar-x`, "UNPAID SINCE NOV 2", "Add $0.75"), the bar becomes 14 day blocks 4 apart, used days in
  `--color-critical` ("9 of 14 days left · released Nov 16"); the card takes the 1.5px critical edge, the Texting
  step a critical `pause` circle with "Paused", and the band reads Sending paused (`circle-pause`). Released: the
  subtle strip with `phone-off`, "RELEASED", the date and a quiet "Your conversations are kept." line, no meter; the
  journey at 45%, no ability chips or Default tag, the Texting step an inactive `x` with "Ended", and an
  `inactive` band "Number released" with Add number (`plus`).
- **Card actions:** the ⋯ opens the action menu (276) with Rename and Make default; Make default is disabled
  (`--color-disabled`) with a 12 quiet hint until the number can text. Renaming puts a 36 field with a 1.5px
  `--color-interactive` edge in place of the name, with Cancel and Save name (small main, `check`).
- **States:** loading shows shapes for the summary and each card (the band as a subtle strip); no numbers and
  couldn't load use page states in a white card (conversation `phone` with Add number; critical with Try again).

## Toll-free business details

The guided form opened from a toll-free number's Add business details button (Pencil: "Communications · Toll-free
business details · Approved A", `SCpaW`, Jafar 2026-10-23). Use the number-paperwork setup frame: a 760-wide
column, breadcrumb and page header, four-step track, one white step card, and its Back / saved-state / Continue
footer. The steps are Business, Texting, Proof of consent, and Check and send. Texting parts use
`--color-conversation`.

- **Business:** prefilled fields follow the number-paperwork Business details card, with a quiet helper line.
- **Texting:** one card groups the purpose, how customers agree, estimated volume, consent explanation, two
  sample texts and optional policy links. Use the shared white fields and 96-high text boxes; the examples sit
  side by side.
- **Proof:** one card with an `informative` hint strip, then a subtle 160-high picture box with a conversation
  `image-plus` icon, upload label and up-to-five-pictures hint. A quiet foot line sits below the box.
- **Check and send:** a `success`-surface review area with a plain approval explanation, Save draft secondary and
  Send for review main.
- **States:** a progress bar appears in the picture box during upload. A failed upload uses a `critical` icon
  tile and Try again; Send uses the shared button spinner. Under review uses a `success` tile and Back to numbers;
  a rejected check uses a `critical` tile, the reason and Fix and send again.

## Texting setup (Control Room)

Uplift's hand work so businesses can text, and the price list (Pencil: "Communications · Uplift texting setup ·
Approved mix (B + A's table)", `v6Jtu`, Jafar 2026-10-22, with every state). Texting parts use `--color-conversation`.

- **Page:** Platform Operations › Texting setup in the Control Room sidebar (`message-square-text`, a count of tasks).
  Page header (40 conversation tile; Open Twilio secondary `external-link`), four number cards (`cards.md`: To do
  `informative`, Waiting on Twilio `warning`, Countries live `success`, Country with no price `warning`), a tab strip
  on a white capsule (To do, Waiting on Twilio, Countries & prices, Businesses, each with its count), then the work
  area: a 380 queue card and the task panel filling the rest, 24 apart, both full height.
- **Queue card:** head (16/600 title, "Oldest first" 13/500 quiet with `arrow-down-up`), rows padding 14 16 with a
  1px line under each: a 32 round flag, the task 14/600 over the business and when 12/500 quiet, a 24 kind chip
  (`--color-conversation--surface`, 12 icon, 12/600 `--onSurface`: Twilio permission `globe`, Price `tag`, Opt-out
  words `message-square-off`), `chevron-right`. The open task: `--color-surface--active` with a 3px
  `--color-interactive` bar down its left edge and a green chevron. A subtle foot band with a 14 informative `info`.
- **Task panel:** head padding 20 24 (40 flag, title 20/700 with a status pill, a 14 quiet line; Open the business as a
  small secondary). Steps padding 16 0 with a 1px line between: a 28 circle (done `success` `check` with a quiet
  title and "Done" 12/600 `--color-success--onSurface`; your turn filled `--color-informative` with a white `pencil`;
  not yet white with a border and its number), title 14/600 over a 13 quiet line. The Twilio step adds a subtle box
  (radius 12, 1px border, padding 12 14): a 32 informative `key-round` tile, the account 13/600 over where to go
  12/500 quiet, Copy ID and Open in Twilio (small secondary). The last step holds the "I did it" checkbox. A
  HISTORY block (12/600 uppercase quiet; rows with a 24 tile, 13/500 text, 12 quiet time). Foot (subtle, 1px line on
  top, padding 16 24): Can't turn on (danger, `ban`) at the left, a 12 quiet hint and the main button at the right,
  at 45% until the box is ticked; saving shows its spinner ("Marking…") with the rest at 45%.
- **Unpaid number task** (`QiDBX`): a queue row with the `wallet` kind chip "Unpaid number"; the panel head takes a
  critical pill ("Unpaid · released in 9 days"). The body (padding 24, gap 20): a subtle facts box (12/500 quiet
  labels over 14/600 values, 24 apart; the amount short in `--color-critical--onSurface`), the HISTORY block, and
  an informative notice strip saying the task closes by itself. No steps and no foot.
- **Price task:** a subtle box of Twilio's costs (12/500 quiet labels over 14/600 values, 24 apart), money boxes two
  to a row each with its margin as a 12 hint (`--color-success--onSurface` 600 when the margin is back on target),
  a locked subtle box for what a country doesn't offer, Starts as the segmented switch (Now, On a date) with a
  date box. **Opt-out task:** groups (1px line on top) with 28 word chips (subtle, 1px border, 12/600) and the reply
  line (14 `corner-down-right`, 13 text, 14 `copy`).
- **Results:** done and "a teammate did it first" replace the panel with a centred page state (40 `success`
  `circle-check` / `informative` `user-check`) and Next task (main, `arrow-right`). Can't turn on is a 600 form pop-up
  with a critical `ban` tile, a reason select, a big text box of what the business sees, and Close request (danger ·
  confirm).
- **Waiting on Twilio:** a list card, head with Check now (small secondary, `rotate-cw`; checking shows its spinner
  and "Asking Twilio…"); rows with a 32 tile, title 14/600 over 12/500 quiet, a status pill. A turned-down row is
  filled `--color-critical--surface` with a white pill.
- **Countries & prices tab:** one card: Card header (40 conversation `badge-dollar-sign`; a 240 search box, Check
  Twilio prices secondary, Add a country main); a warning notice strip when Twilio's price moved, with Review price;
  the uppercase 12 head row on subtle; rows padding 14 20: 32 flag with the country 14/600 over its number kind,
  then Twilio cost 13/500 `--color-text`, their price 14/700 with "a segment" 12 quiet (or Set price, small
  secondary), margin 13/600 (a fallen margin in `--color-warning--onSurface` with `trending-down`), picture and
  number prices 13/500 (not offered in quiet), businesses 13/600, a status pill (Live `success`, No price `warning`,
  Off `inactive`) and the 32 ⋯ button. A price starting later adds an informative chip under the price ("$0.10 from
  Nov 1", `calendar-clock`). Change price is a 640 form pop-up: the flag in the header, the Twilio costs box, money
  boxes with margins, Starts, and an informative notice strip that sent texts keep their price.
- **States:** loading shows queue rows and panel shapes; nothing to do is a page state with a 40 `success`
  `circle-check`; couldn't load uses the critical page state with Try again. The price list uses the same states.

## A business's Texting view (Control Room)

On a business's Communications tab, Texting chosen on the segmented switch (Email, Texting, Website chat), under the
business header card with its page tabs (same board, `v6Jtu`).

- Two side cards side by side: Texting mode (40 `success` `power` tile; an On pill in the header; fact rows of
  what the package allows, what the business chose and Uplift's override; a subtle foot with a 12 quiet line and
  Change) and Twilio account (40 `informative` `key-round`; fact rows with a 14 `copy` on IDs; a subtle foot link
  "Open this account in Twilio" 13/600 `--color-interactive` with `external-link`). Changing the mode puts the
  override select and a required reason field in the card, with Cancel and Save mode in the foot.
- Then the countries card at full width: Card header (40 conversation `globe`; Add a country small secondary), the
  uppercase 12 head row on subtle, rows padding 14 20: 32 flag with the country 14/600 over when it was asked 12/500
  quiet; the Twilio permission (16 icon: `check` `--color-success`, `hourglass` `--color-warning--onSurface`,
  `circle-off` quiet) with its state 13/600 over who and when 12/500 quiet; the price 13/600 over the picture price
  12/500 quiet (or the warning "No price yet" chip); a status pill (Ready `success`, Setting up `warning`, Off
  `inactive`); and Open task (small secondary, `arrow-right`) on a row waiting on Uplift, otherwise the 32 ⋯. A
  subtle foot band with a 14 informative `info`.
- The ⋯ menu (276): See it in Twilio, Show its history, and Turn off for the business on the danger strip, which asks
  first in the "are you sure?" pop-up with a required reason.
- **States:** loading shows Loading rows in the card; only the home country shows its row and one 14 quiet line;
  couldn't load is the critical page state inside the card.

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

## Website chat widget

The chat a visitor opens on the contractor's own website (Pencil: "Batch 66 · Website chat widget · Approved B",
`yyWfm`, Jafar 2026-10-22). It wears the business's brand colour from Branding (shown as `brand` below), never
`--color-interactive`, and keeps its light colours on every website and in dark mode. White words on `brand`.

- **Launcher:** bottom right or left, 24 from the edges. Closed: a 52 pill, padding 0 22 0 18, `brand`, a 22
  `message-circle` and "Message us" 16/600; a brand-coloured glow (0 8 20 `brand` at 35%) and 0 2 4. Open: a 52
  circle with a 22 `chevron-down`. The panel sits 16 above it.
- **Teaser:** a 300 white speech bubble (radius 20 20 4 20, padding 14 16 16, gap 8, 0 12 30 shadow and a 1 hairline
  ring): a 24 logo mark with the business name 12/700, then the teaser line 16/500 heading. A 28 round white key ×
  sits above it at the right.
- **Panel:** 392 wide, radius 24, clipped, `--color-surface--background--subtle`, 1px `--color-border`, a 0 20 48
  shadow at 18% and 0 2 6 at 8%.
- **Welcome top:** a 232 `brand` gradient (to a darker step) with a soft white glow at the top right; the logo on a
  44 white tile (radius 12, a 32 logo mark) and a 32 close (white 15%, radius 10, 16 ×); the business name 14/600
  white 82% over the greeting 24/700 white (-0.5).
- **Card:** overlaps the top, 12 from the panel's sides: white, radius 20, 1px border, a 0 4 14 shadow, padding
  18, gap 14. "Your message" (label 14/600) and an 84 big text box first; then "How should we reply?" with "Phone
  or email" 12 quiet at the right, over one joined contact box (radius 10, 1px `--color-border--interactive`) of
  44 rows split by hairlines: name (`user-round`), phone (a 32 country button on `--color-surface--background--subtle`,
  radius 8: flag, dial code 14/600, 14 chevron), email (`mail`, "Email (optional)"). The "Text me about my request"
  agreement sits in a `--color-surface--background--subtle` box (radius 12, padding 12) with the brand-filled
  checkbox, label 14/600 and the fine print 12 quiet; it shows once a phone number is typed. Send: 48 high, radius
  14, `brand`, "Send message" 16/600 at the left and a 32 arrow-right well (white 18%, radius 10) at the right.
- **Footer:** centred, padding 14 16: a 12 lock, "Privacy policy" 12/600 underlined, a dot, "Powered by
  <business>" 12 quiet.
- **Form states:** Send at 45% until the form is complete. A mistake turns the contact box (or message box) edge
  1.5px `--color-critical`, adds a 16 `circle-alert` at the row's right and a 12 `--color-critical` line under the
  box that says how to fix it. Couldn't send: a `--color-critical--surface` note (1px edge, radius 10, padding 10
  12, 16 `circle-alert`, 14/500 `--onSurface`) above Send. Sending: Send at 85% with a white 18 spinner and
  "Sending…". Loading: shimmer shapes (page-states rule) in the card's layout.
- **Country list:** under the country button, 260 wide, white, radius 12, padding 6, a 0 12 28 shadow: a
  36 search box, then 36 rows (flag, name 14/500, dial 12/600 quiet); the chosen row `--color-surface--hover`, 600
  name and a 14 brand check. The country button gets a 1.5px `--color-interactive` edge while open.
- **Chat:** the top turns white and slim (padding 14 14 14 16, hairline under it): a 40 logo mark (radius 12), the
  business 16/700 over "We'll reply right here" 12 quiet, and a 32 close on `--color-surface--background--subtle`.
  White thread, padding 14 16 16. "Load earlier messages" 12/600 with a 14 arrow-up and the time line 12/500 quiet,
  centred. Business messages: `--color-surface--background--subtle` bubbles (radius 18 18 18 6, padding 10 14,
  14 heading, up to 272 wide), a 24 logo mark beside the last one of a run, the name and time 12 quiet under it.
  Visitor messages: `brand` bubbles at the right (radius 18 18 6 18), white words, time 12 quiet under. Not sent: an
  18 `circle-alert` before the bubble and "Not sent · Tap to retry" 12/600 `--color-critical`, retry underlined.
  Message box: a 48 pill (white, 1px `--color-border--interactive`, padding 0 6 0 18) with a 36 `brand` circle send
  holding a white 18 arrow-up.
- **Ended:** the message box gives way to a `--color-surface--background--subtle` card (radius 16, padding 18,
  centred, gap 12): a 40 inactive `message-circle-x` tile, "This conversation has ended." 14/600, and a 44 `brand`
  "Start a new conversation" button (radius 12, `message-circle-plus`).
- **Not available or not set up:** the welcome top stays; the card holds a 48 inactive `message-circle-off` tile
  and the message 14/600; no footer.

## Recently deleted page

Deleted clients waiting out their 30 days (`concept.pen` board `Wf0tP`, "Recently Deleted page · Approved B",
Jafar 2026-10-24, with every state). Full page frame with Clients current in the sidebar.

- **Top:** the breadcrumb (Clients › `trash-2` Recently deleted), the page header with a 40 client `trash-2` tile
  and no buttons, then a toolbar: search (300), the Deleted by filter chip, and at the right a 14/500 quiet count
  ("6 deleted clients · 15 invoices kept").
- **Columns:** main column plus the 360 side column. Main holds two section cards, 24 apart: "Deleted for good this
  week" (critical `alarm-clock` tile, a critical count pill) for clients with 3 days or fewer, then "Can still be
  restored" (client `rotate-ccw` tile, an inactive count pill). A card with nobody in it is hidden.
- **Row** (edge to edge, padding 16 20, gap 16, a hairline above): a 48 days ring (track `--color-border`, the arc
  for the days left out of 30 from the top, clockwise; `--color-critical` in the urgent card, `--color-client`
  otherwise; the number 16/700 over "days" 12 quiet), then the name 14/600 with "Deleted <date> by <member>" 14
  quiet beside it, and under them count pills of what comes back (pill corners, padding 3 9 3 7, a 1px
  `--surface-edge`, a 12 record icon, 12/600 `--onSurface`; "Only the client record" 12 quiet when there is
  nothing). At the right "GOES FOR GOOD" 12/600 quiet over the date 14/600 (critical `--onSurface` and the
  weekday in the urgent card), a small secondary Restore (client `rotate-ccw`) and the 32 ⋯ button.
- **Side column:** "How the 30 days work" (client `hourglass`): three steps, a 28 circle (1px client
  `--surface-edge`; the last critical) on a 2 wide edge-colour line, the when 14/600 over 12 quiet. "Always kept"
  (invoice `shield-check`): rows with a 32 tile (invoice `receipt`; conversation `message-circle-off`), title
  14/600 over a 12 quiet why, then a small secondary "See kept invoices" (`arrow-up-right`) under a hairline.
- **Picking several:** a tick box takes the ring's place on hover; once one is ticked every row shows it and
  picked rows fill `--color-surface--active`. A floating bar (white, radius 12, `--shadow-high`, padding 10 10 10
  16): a 24 `--color-interactive` count circle, "2 clients picked" 14/600, Clear (quiet), Restore 2 (main).
- **⋯ menu** (`inputs.md` action menu): Restore, then on the danger strip Delete permanently now (`shield-x`),
  which opens the Delete permanently pop-up (`modals.md`).
- **Restoring:** the spinner takes Restore's icon, ⋯ at 45%. Toasts as in `modals.md` § Delete client pop-ups:
  success `rotate-ccw` "<name> is back" with Open client; many, "<n> clients are back"; failed, critical
  `circle-alert` with Try again.
- **Same phone or email pop-up:** default pop-up (600), 40 client `users` tile, "Another <name> is in Clients", 12
  quiet "Same phone number: …". Body: the intro 14 quiet; two cards side by side (radius 12, 1px `--surface-edge`,
  clipped) with a top band (client `rotate-ccw` "Coming back"; informative `user-check` "Already in Clients"),
  then a 28 avatar, name 14/600 over 12 quiet, and count pills; then radio tiles (`inputs.md`): Restore and merge
  them (chosen) / Restore as a separate client. Footer: Cancel, Restore and merge (main, `git-merge`).
- **States** (`page-states.md`), in the main column's place: empty (client `trash-2`, "Nothing deleted in the last
  30 days", Back to Clients); loading (header shapes and bone rows with a 48 round bone and an 80×32 button bone);
  couldn't load (critical, Try again); search with no match (client `search`, Clear search as a quiet button).
