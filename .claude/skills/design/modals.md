# Pop-ups

> Dependencies: `colors.md`, `radius.md`, `shadows.md`, `icon-shapes.md`, `buttons.md`

Pencil: `concept.pen` → "Concept · Foundation · Pop-ups · 1440". Three patterns: the form pop-up, the
"are you sure?" pop-up and the side drawer. Pop-ups that decide money, sending or scheduling get their own
drawing.

## Shared

- White (`--color-surface`), 1px `--color-border`, radius 16 (`--radius-large`), `--shadow-base`; the page
  behind is dimmed with `--color-overlay`.
- Tiles follow the colour map: the record or part of the app the pop-up is about (`icon-shapes.md`, 40 tile).

## Form pop-up

- Widths: small 400, default 600, medium 640, large 940.
- Header: 40 tile, title 20/600 (-0.2) with an optional 12 quiet line under it, the × as a white icon button
  at the right; padding 16 16 16 20, gap 12, a 1px `--color-border` line underneath. No tile when the pop-up
  has no icon.
- Body: padding 20; fields 16 apart.
- Footer: `--color-surface--background--subtle` with a top line, padding 16 20, gap 8. Cancel (secondary) then
  the green main button at the right; a secondary action may sit at the far left.

## "Are you sure?" pop-up

- 480 wide, padding 24, gap 16, no ×.
- Heading: 40 tile then the title 20/600, gap 14. Message 14 `--color-text`, line height 1.5.
- Actions at the right, 8 apart, 8 extra above them: Cancel (secondary) then the named action.
- Tile by kind: danger `--color-critical` (danger · confirm button); go ahead, the record you end up with
  (green main button); warning `--color-warning` ("Go back" / "Complete anyway"); notice, the record it is about
  or `--color-informative`, with one button.

## Side drawer

- 480 wide, full height, floating 12 from the window's top, right and bottom edges.
- Header as the form pop-up. Body padding 20, blocks 20 apart. Footer as the form pop-up's.

## Pop-over

The small card that opens beside the button you clicked (`ui/Popover`: Send later in the inbox, a document's
History, Add on the sales calendar), approved 2026-10-20 on board `e18rX` (B). Lighter than the Visit pop-up,
which keeps its own approved look.

- Card: `--color-surface`, 1px `--color-border`, radius 12, a soft shadow (0 1 4, black 10%), clipped.
- Top band in the meaning colour's `--surface` (e.g. `--color-conversation--surface` for Send later), padding
  12 12 12 14, gap 10: a 32 white tile (radius 8, 1px `--surface-edge`, 16 icon in the meaning colour), the title
  16/600 heading, and a 28 quiet × with its icon in the meaning `--onSurface`.
- Body padding 16, gap 14; fields and buttons are the normal ones (a main button full width when it is the one
  action).
- A 16×10 arrow in `--color-surface` with the `--color-border` edge points at the button that opened it.
- Loading: row-shaped bones in the body; couldn't load: the page-states small error with Try again.

## Email preview pop-up

The rendered marketing email (board `l62Og`, A, Jafar 2026-10-20): from a template's Preview, Preview while
writing, and inline in a campaign's Review step (same body inside the Message card, no pop-up chrome).

- Large pop-up (940). Header: 40 tile in `--color-growth` (`mail`), the template or campaign name, a 12 quiet line
  "Email preview · what customers will see". No footer.
- Body padding 20, gap 16: the segmented switch Desktop (`monitor`) / Mobile (`smartphone`), the chosen icon in
  `--color-growth`.
- Under it a well: `--color-surface--background--subtle`, 1px `--color-border`, radius 8, padding 28 0, the
  email centred in it (600 on Desktop, 375 on Mobile) on white with a 1px edge, radius 4; the well scrolls.
- The email keeps its own light colours in dark mode.
- Loading: an email-shaped bone (bar, image block, heading, lines, button) on white in the well. Couldn't load:
  the page-states error with Try again.

## Communication settings pop-up

A client's automatic-message ticks (board `DXj9z` Part 2, A, Jafar 2026-10-20).

- Large pop-up (940). Header: 40 tile in `--color-conversation` (`bell-ring`), "Communication settings", 12 quiet
  line "Automatic messages this client gets". Footer: Done (main) at the right.
- Body padding 4 20 20: one row per group, padding 18 0, a hairline between groups. Left 240: a 32 tile in the
  group's record colour (quote `file-text`, job `hammer`, review `star`) and the group name 15/700 heading. Right:
  the ticks 16 apart, each the approved checkbox with label and description.
- Not sending: under the description, a strip `--color-warning--surface`, radius 8, padding 6 10, a 14
  `circle-pause` in `--color-warning`, "Not sending ·" 12/600 `--color-warning--onSurface`, then the Automations
  link 12/600 `--color-interactive` underlined (people who can't manage Automations get the words instead).
- Foot: the consent note on `--color-surface--background--subtle`, 1px `--color-border`, radius 10, padding 12 14,
  a 16 `shield-check` in `--color-growth`, words 12 secondary.
- Do not disturb: a warning notice strip (`moon`) at the top and every group row at 50%. No marketing: an
  informative notice strip (`megaphone-off`), rows unchanged.

## Customer group pop-up

Marketing's New / Edit customer group (board `PLExJ`, B, Jafar 2026-10-21). Same fields, conditions and words
as the live app.

- Large pop-up (940). Header: 40 tile in `--color-growth` (`users`), the title. Footer: Cancel, then Save group
  (Save changes when editing).
- Body splits in two: the form at the left (padding 20, gap 20) and a 300 recipients panel at the right, full
  height, `--color-growth--surface` with a 1px `--surface-edge` line on its left.
- Form: Name and Description, then "Match customers who" (16 `funnel` in `--color-growth`, 16/600 title, 12 quiet
  hint) over one list box: white, 1px `--color-border`, radius 12, clipped.
- Condition row: padding 12 8 12 14, gap 12, a hairline under it. Left 172: a 24 tile in the colour of what the
  condition checks (client things `--color-client`; lead source `--color-request` `inbox`; services, work type and
  last completed Job `--color-job`; upcoming work `--color-time`; always include `--color-success` `user-plus`;
  always exclude `--color-critical` `user-x`) and the label 13/600 heading. Right: the condition's controls, 36
  high. Last: a 32 quiet trash icon `--color-icon-secondary` (red on hover).
- Picked values: a 28 chip, white, 1px `--color-border--interactive`, radius 8, padding 0 4 0 10, the value 13/500
  heading and a 20 × (radius 6). Tags keep the tag look. Add / Add tag: a quiet 28 button, 14 `plus` and 13/600 in
  `--color-interactive`.
- The list box ends in a `--color-surface--background--subtle` band with "Add a condition…" as a quiet green
  button (16 `circle-plus`, 14 chevron); it opens the dropdown list, each line with its condition's 24 tile.
- No conditions: one row with a 16 `users` in `--color-growth` and the live sentence, then the band.
- Recipients panel (padding 20, gap 16): a 32 white tile (`users`, `--color-growth`), "Recipients" 16/600 and the
  12 hint in `--color-growth--onSurface`. A white card (radius 12, 1px `--surface-edge`, padding 16): eligible
  count 40/700 (-1) with an 18 `mail-check` in `--color-success`, "Eligible to receive email" 13/600
  `--color-success--onSurface`; under a hairline, Match the rules (`users`) and Excluded (`user-minus`) 13 with
  figures 14/700, then each exclusion reason 12 quiet with its count 12/600, indented 24.
- View customers (Hide customers when open): a full-width secondary button. The list opens in the panel under the
  counts: the filter select, white rows (name 13/600, email 12 quiet, an excluded customer's reason as a grey
  pill), Load more as a quiet button.
- Counting: bones in `--color-growth--surface-edge` inside the white card. Couldn't count / couldn't load: the
  small error (critical tile, words, Try again) in a white card. Nothing found: one 12 quiet line in a white card.
- Search picker and type-and-add box open the dropdown list (`inputs.md`); typing "Searching…", "Start typing to
  search.", "No matches for “…”." and the red "Could not search. Try again." are 13 lines in the list. The
  type-and-add pop-over is 280 wide, radius 12: a text box, the suggestions, "Press Enter to add." 12 quiet.
- Name missing: the field error. Someone else changed the group: a critical notice strip at the top of the form.

## Profile photo pop-up

Your own photo, from the top bar's account menu and Settings (board `n2ujB`, B, Jafar 2026-10-21). Same steps and
words as the live app.

- Medium pop-up (640). Header: 40 tile in `--color-inactive` (`user-round`), "Profile photo", 12 quiet line "Shown
  next to your name across the app". Footer: Remove (danger, `trash-2`) at the far left when there is a photo, then
  Choose new photo (Choose a photo when there is none) as the main button with `image`. While moving: Back
  (secondary) then Save photo (main, `check`).
- Body splits in two, 420 high. Left, a 320 studio: `--color-photo-studio` with a soft white glow from the upper
  middle (white 12% → 0), padding 24, gap 18, everything centred. Right, the preview panel:
  `--color-surface--background--subtle`, a 1px `--color-border` line on its left, padding 20, gap 12.
- Your photo: a 176 avatar with a 4 white ring and a deep shadow (0 10 28, black 35%); under it the hint 13 white
  72%, centred, 200 wide. No photo yet: the initials 52/600 in the person's avatar family (`avatars.md`).
- Moving and zooming: the hint on top, then the 240 crop square (radius 12): the photo, black 50% outside the
  circle, a 2px white 90% circle edge. Under it the 240 zoom row: 18 `zoom-out` and `zoom-in` in white 72%, a 4 high
  white 22% track, its filled part `--color-interactive`, a 16 white handle with a 2px `--color-interactive` ring.
  Then Choose a different photo as a quiet button, 13/600 white.
- Preview panel: "How your teammates see you" 14/600 heading and a 12 quiet line ("Your photo across the app";
  while moving, "Follows your photo as you move and zoom"). Three white cards (radius 12, 1px `--color-border`,
  padding 12, gap 10), each opening with a 14 icon and a 12/600 quiet label:
  - Top bar (`panel-top`, `--color-inactive`): a search box and the account chip (32 avatar, first name 13/600,
    `chevron-down`).
  - Schedule (`calendar-days`, `--color-time`): a visit on `--color-job--surface` with a 3px `--color-job` left
    edge, title 13/600 and time 12 in `--color-job--onSurface`, the 24 avatar at the right.
  - Inbox (`message-circle`, `--color-conversation`): a client's 32 initials avatar, name 13/600, last message 12
    quiet, the 24 assigned avatar at the right.
  The previews show the crop as it moves and have no controls.
- Saving: Save photo spins, Back is disabled, the zoom row and Choose a different photo drop to 45%. Removing:
  Remove spins in red, Choose new photo is disabled.
- Not a photo / couldn't save: a strip at the left of the footer, `--color-critical--surface`, 1px edge, radius 8,
  padding 7 12, a 16 `circle-alert` in `--color-critical` and the live words 13/500 `--color-critical--onSurface`.
  After a failed save the crop stays.
- Dark mode: the studio keeps its colour; everything else follows the tokens.

## Merge clients pop-up

Picking the client to keep and the duplicate, then merging (board `XddjD`, A, Jafar 2026-10-21). Same words,
moves, rules, warnings and blockers as the live app.

- Large pop-up (940). Header: 40 tile in `--color-client` (`git-merge`), "Merge clients". Footer: at the left a
  16 `trash-2` and "… will be deleted. This can't be undone." 13/600 `--color-critical` (shown once the preview
  has loaded); Cancel, then Merge clients as the danger · confirm button with `git-merge`.
- Body padding 20, gap 20: the intro 14 secondary, then From → To in one row. Left the duplicate card, right the
  client to keep, each radius 12 with a 1px `--surface-edge`, clipped: a top band in the meaning `--surface`
  (duplicate `--color-critical`, `trash-2`; keep `--color-client`, `user-check`), padding 10 14, a 24 white tile
  and the live label 13/600 `--onSurface`; under it, padding 14, the client search box 44 high on
  `--color-surface--background` with a 28 initials avatar, the name 14/500 and `chevron-down`.
- Between the cards, 96 wide: a 40 round `--color-client--surface` circle with a 20 `arrow-right` in
  `--color-client`, and Swap under it as a quiet small button (`arrow-left-right`).
- Review under a hairline, padding 20 0 0, gap 14: "MOVES TO …" 12/600 uppercase quiet; the moves as tiles, five
  to a row, each `--color-surface--background--subtle`, 1px `--color-border`, radius 12, padding 12, gap 10: a 32
  tile in the record's colour (property `house` client, request, quote, job, invoice, payment `credit-card`
  invoice, messages `message-circle` and email `mail` conversation, notes `sticky-note` inactive, phone `phone`
  time, contacts `users` client, files `file` informative, tags `tag` inactive), the count 18/700 heading and
  the kind 12/500 quiet. Then the two rules 13, each with a 16 icon (`user-check` client, `receipt` invoice), and
  each warning as a warning notice strip (`notices.md`).
- Opened from a client page: the duplicate box shows "Search by name or company", no review, Merge clients
  disabled. Same client: the duplicate box gets a `--color-critical` edge and "Choose a different client." 12/500
  red with a 14 `circle-alert`. Checking: the live line 13 quiet and five bone tiles (`--color-border` bones).
  Couldn't check / blocked: a critical notice strip (`circle-alert` / `ban`) with the live words; when blocked
  the moves stay and Merge clients is disabled. Nothing to move: the live line replaces the tiles. Merging: the
  spinner takes the merge icon's place, Cancel is disabled.

## Collect payment pop-up

Recording money received and applying it to a client's bills, and Fix payment (board `b5ZAe`, A, Jafar
2026-10-21). Same fields, words and buttons as the live app; Payment method stays a dropdown.

- Large pop-up (940). Header: 40 tile in `--color-invoice` (`credit-card`), "Collect payment" ("Fix payment"),
  a 12 quiet line naming the invoice and client ("Invoice #1042 · Sarah Lee"; Fix: "$1,500.00 payment · Sarah
  Lee"). Footer: Cancel, Save and email receipt (secondary, `mail`), Collect payment (main, `check`). Fix: no
  receipt button; Save corrected payment.
- Body splits in two. Left, the payment (padding 20, gap 16): Amount received as a 56 high money box (sign block
  48 wide, sign 18/600, amount 24/700 -0.4 at the right); Payment method (16 `landmark` in `--color-invoice`)
  and Payment date (16 `calendar-days` in `--color-time`) side by side; Reference # (16 `hash`); Details as a
  big text box. Fix: the live intro line 14 quiet on top, and "Why is it being fixed? (optional)" last.
- Right, a 400 panel, `--color-invoice--surface` with a 1px `--surface-edge` line on its left, padding 20, gap 12:
  a 32 white tile (`receipt`) and "Apply to invoices" 16/600; one white card per bill (radius 12, 1px
  `--color-invoice--surface-edge`, padding 12 12 12 14, gap 12): the checkbox, "Invoice #1042" 14/600 over the
  live line 12 quiet ("This invoice · owes $1,250.00", "Due Oct 3 · owes $480.00"), and when ticked a 120 small
  money box; a ticked card's edge is 1.5px `--color-invoice`.
- Foot card (white, radius 12, padding 14, gap 12): an 8 high bar, the applied part `--color-invoice` and the
  credit part `--color-client`, 3 apart, radius 4; then "Applied" and "Kept as client credit" 13/500 with 8 dots
  in those colours and their amounts 14/700 at the right. No credit: the bar is all blue and the credit line goes.
- Other bills loading: a bone card under the pinned bill. Amount missing: the big box gets the field error ("Enter
  how much was paid."). Over what a bill owes: the card's edge and its box turn `--color-critical`, the live
  error under its words. Couldn't save: a critical notice strip at the foot of the left side, fields kept.
  Saving: only the pressed button spins; the other two are disabled.

## Notification bell pop-up

The panel under the top bar's bell (`layout/NotificationBell`, used by the team bell and Jafar's bell; board
`FGYzU`, B, Jafar 2026-10-21). Same behaviour as live; only Jafar's bell has the foot.

- Panel 440 wide, at most 640 tall (or 80% of the window), `--color-surface`, 1px `--color-border`, radius 16,
  shadow 0 12 32 black 14%, clipped; a 16×10 `--color-surface` arrow points at the bell. The list scrolls; the
  header and foot stay.
- Header padding 20 16 14 20: "Notifications" 20/700 (-0.3) over a 13 quiet summary with 8 dots ("5 unread" with
  an `--color-interactive` dot · "2 need you" with a `--color-critical` dot; none unread: a 14 `circle-check` in
  `--color-success` and "All caught up"). At the right, Mark all read as a small secondary button (16
  `check-check` in `--color-interactive`), shown only while something is unread, then a 32 quiet ×.
- Needs you (padding 4 16 16): a 14 `triangle-alert` `--color-critical` and "NEEDS YOU" 12/600 (0.6) quiet; then
  each unread alert with an orange or red tone as a card: radius 12, padding 12, gap 12, `--color-<tone>--surface`
  with its 1px `--surface-edge` (tone `critical` or `warning`); a 36 white tile (radius 9) with the record's 18
  icon in the record colour; title 14/600, detail 13, time 12 at 80%, all `--color-<tone>--onSurface`; a 16
  chevron-right. Once read it leaves the cards for the timeline. A 1px `--color-border` line under the section.
- Latest (padding 14 16 8): "LATEST" label, then a timeline row per alert, newest first (padding 0 8 0 4, gap
  12, radius 10): the time 12 right-aligned in a 60 column (unread 600 heading; a read alert with a tone keeps
  its time 600 in the tone colour); a rail with the 32 record tile and a 2 wide `--color-border` line down to the
  next row; title 14 (unread 600 heading, read 500 `--color-text`) over detail 13 quiet, 2 lines at most, 16
  below. Unread: a 10 `--color-interactive` dot with a 2 `--color-surface` ring on the tile's top-right corner
  (a read alert with a tone: the dot in the tone colour).
- Record tiles by alert: inquiry and customer reply `--color-request` (`inbox`, `reply`), quote
  `--color-quote` (`file-check`), invoice and payment `--color-invoice` (`credit-card`, `receipt`), message
  `--color-conversation` (`message-circle`), schedule and timer `--color-time` (`calendar-days`, `timer`),
  feedback `--color-review` (`star`), pipeline task or mention `--color-growth` (`square-check`, `at-sign`).
- Jafar's foot: `--color-surface--background--subtle`, 1px `--color-border` line above, padding 12 16 16, a full
  width secondary "View all notifications" with a 16 `arrow-right` in `--color-interactive`.
- Row hover `--color-surface--hover`; focus `--shadow-focus`.
- Loading: timeline bones (a 36×8 time, the 32 tile, 10 and 8 lines); no Mark all read. Empty: page-states
  empty in the business grey with a `bell` tile, "No notifications yet" 16/600 and the live line. Couldn't load:
  the same with the critical tile, "Notifications couldn't load" and a secondary Try again (`refresh-cw`).
  Marking all read: the button spins and can't be pressed. Mark all read failed: a critical notice strip
  (`notices.md`) under the header, everything stays unread.

## Edit visit pop-up

One visit of a job (`jobs/JobVisitDialog`), from a Job page's visits and from Schedule (board `PbkWT`, B, Jafar
2026-10-21). Same fields, rules, words and buttons as the live app, with two approved changes: one three-way
switch replaces the Schedule later and Anytime ticks, and the no-day error ends "or choose Later".

- Large pop-up (940), always. Header: 40 tile in `--color-job` (`calendar-cog`), "Edit visit", a 12 quiet line
  with the job title (a per-visit billed job adds " · billed per visit"). A recurring job puts a small pill beside
  the title: `--color-informative--surface`, padding 3 9, a 12 `repeat` and "Recurring" 12/600 `--onSurface`.
- Body splits in two. Left, the When panel, 340 wide, `--color-time--surface` with a 1px `--surface-edge` line on
  its right, padding 20, gap 16: a 32 white tile (`calendar-clock`, `--color-time`) and "When" 16/600; the date
  card; the switch; Day of the visit; Time.
- Date card: white, radius 12, 1px `--color-time--surface-edge`, padding 14, gap 14. A 56×60 date tile in
  `--color-time`, radius 12: month 12/700 (0.8) white 80%, day 24/700 white. Then the weekday 18/700 heading over
  a 14 `clock-3` in `--color-time` and the hours with their length 13/500 `--color-text` ("8:00 AM – 12:00 PM · 4
  hrs"). It reads back what is picked as it changes.
- Switch (`inputs.md` segmented switch, full width): Set a time (`clock-3`) · Anytime (`sun`) · Later
  (`calendar-off`). Anytime: hours line "Anytime that day" with `sun`, Time hidden. Later: the tile turns
  `--color-time--surface` with a 24 `calendar-off`, "No date yet" and the live hint 13; Day and Time hidden.
- Right, the details (padding 20, gap 16): Visit title, Instructions for this visit (big text box), Who is going
  chips. A recurring job opens with an informative notice strip ("Changes here affect this visit only…").
- What this visit bills (per-visit billing only), under Who is going: a group box like Book work's First visit
  (radius 16, 1px `--color-border`, subtle head with a 24 `--color-invoice` tile `receipt` and 14/600 title).
  Body padding 16, gap 10: 12/600 quiet column names (Name · Quantity · Unit price · Total), then one row per line,
  36 high boxes, the name box with the line's 14 icon in `--color-job`, a changed quantity with a 1.5px
  `--color-interactive` edge, the total 14/600 at the right. Foot on `--color-surface--background--subtle` with a
  top line: "Use the job’s lines again" as a quiet green button at the left (only when the visit has its own
  lines), "This visit" 14/600 quiet and the amount 18/700 at the right.
- Its states: loading, bone rows (`page-states.md`), no foot; couldn't load, a critical strip (radius 8, padding
  10 12, 16 icon, 13/500 `--onSurface`) with the live words; fixed (invoiced or completed), an informative strip
  with `lock` and the live words, the boxes on `--color-surface--background--subtle` with `--color-border`, no
  reset button; going back to the job's lines, an informative strip (`rotate-ccw`) and a quiet "Keep this visit’s
  own lines"; can't see prices, names and quantities only, no price columns and no foot.
- Footer: Notify customer (the approved checkbox with its live hint) fills the left; Cancel, then Save and update
  future visits (secondary, 16 `calendar-sync` in `--color-time`; recurring jobs, hidden when Later), then Save visit
  (main, `check`).
- Errors (checked on Save): the Day or Time box gets the field error with the live words; with an empty day the
  date tile turns `--color-time--surface` with "—" and "?" and the weekday reads "Pick a day" quiet. Couldn't save:
  a critical notice strip at the top of the details, fields kept. Saving: the pressed save buttons spin together,
  Cancel is disabled.

## Billing setup pop-up

From the Billing card on a job page (`jobs/JobBillingCard`; board `aJGHA`, B, Jafar 2026-10-21 "ok continue" to the
suggested picks). Same boxes, words and buttons as the live app.

- Medium pop-up (640). Header: 40 tile in `--color-invoice` (`receipt`), "Billing setup", a 12 quiet line "Job #1042 ·
  title". Footer: Cancel, then Save billing (main, `check`); Save billing is off until something changes.
- Body splits in two. Left, the form (padding 20, gap 16): "How is this work priced?" select, with under it a
  read-back strip (radius 12, `--color-invoice--surface`, 1px `--surface-edge`, padding 10 12, a 24 white
  `badge-dollar-sign` tile, 14/600 `--onSurface`: "$4,373.36 for the whole job", "… per completed visit", "… each
  billing period, whatever the visit count"); then "When should we be reminded to invoice?" select. A one-off job's
  price box has one choice, so it shows disabled with a `lock` in place of the chevron.
- Right, a 330 "Three decisions" panel: `--color-invoice--surface`, 1px `--surface-edge` line on its left, padding 20,
  gap 12; a 32 white tile (`list-ordered`) and the title 16/600. Three white cards (radius 12, 1px `--surface-edge`,
  padding 12 12 12 14, gap 10): Price (`badge-dollar-sign`, number 1) and Invoice reminder (`bell`, number 2) read the
  two choices back (the reminder adds "A reminder for your team, nothing goes to the client."); Collect the money
  (`credit-card` in `--color-icon--secondary`, a grey "Not set here" pill, 80% opacity) says "Lives with Payments.
  Nothing here charges a client."
- Without money access the read-back and the amount in the card are left out. Saving: Save billing spins, Cancel and
  both boxes go disabled grey. Couldn't save: a critical notice strip (`notices.md`) tops the form with the live words.

## Payment schedule pop-up

Add or Edit payment schedule, from the Billing card of a one-off job (`jobs/JobPaymentScheduleDialog`; board
`aJGHA`, B, Jafar 2026-10-21). Same boxes, words, rules and buttons as the live app.

- Large pop-up (940). Header: 40 tile in `--color-invoice` (`layers`), "Add a payment schedule" or "Edit payment
  schedule", the job line. Footer: at the left Remove schedule (danger, `trash-2`; only on a saved schedule with no
  invoiced stage); Cancel, then Save schedule (main, `check`).
- Body splits in two. Left, the stages (padding 20, gap 16): the live intro 14 secondary, the "How is each stage
  set?" switch full width (Amounts `banknote` / Percentages `percent`, `inputs.md`), then one list box (radius 12,
  1px `--color-border`, clipped): a `--color-surface--background--subtle` row of 12/600 quiet column names, one row
  per stage (padding 10 8 10 14, gap 12, a hairline above), and an Add stage band (`--color-surface--background--subtle`,
  a quiet green `circle-plus` button). Amounts mode: Stage box · money box 150 (sign block 36) · a 32 quiet
  `trash-2` (red on hover). Percentages mode: Stage box · Percent box 110 with a `%` · the stage's amount 14/600
  right-aligned in 100 · the trash. Boxes are 36 high.
- Right, a 340 panel: `--color-invoice--surface`, 1px `--surface-edge` line on its left, padding 20, gap 12; a
  32 white tile (`receipt`) and "Job total" 16/600. One white card (radius 12, padding 16, gap 14): the job total
  40/700 (-1); an 8 high bar, one part per stage in `--color-invoice` at 100%, 70%, 45% (then 30%, 20%), 3 apart,
  radius 4, the unassigned rest in `--color-border`; a legend line per stage (8 dot, name 13/500, amount 14/700);
  under a hairline "Left to assign" with its amount, 14/700: `circle-check` and `--color-success` at $0.00, or
  `triangle-alert` and `--color-warning` otherwise.
- Stage already invoiced: its boxes are disabled grey with an informative "Invoiced" pill in the trash's place (all
  rows give that trailing space 84), the other switch choice shows the can't-pick look, an informative notice strip
  (`notices.md`) under the switch gives the live reason, and Remove schedule is gone.
- Stages do not add up and Couldn't save: a critical notice strip tops the left side with the live words; the strip
  clears when anything is edited. Saving: the Save button spins, everything else goes disabled grey.
- First schedule: two blank stages, no Remove schedule; the whole total is left to assign.

## Add an invoice reminder pop-up

From the reminders inside the Billing card (`jobs/JobRemindersCard`; board `aJGHA`, A, Jafar 2026-10-21). A reminder
for the team, never a message to the client.

- Small pop-up (400). Header: 40 tile in `--color-invoice` (`bell-plus`), "Add an invoice reminder", the job
  line. Footer: Cancel, then Add reminder (main, `plus`), off until a day is picked.
- Body padding 20, gap 16: "Remind our team on" date box (a quiet "Pick a day" until chosen), "Note (optional)" box
  (placeholder "e.g. bill with the March statement", 200 letters), then an informative notice strip with the live
  sentence ("This is a reminder for your own team on the date you pick — nothing is sent to the client.").
- Saving: Add reminder spins, Cancel goes disabled grey. Couldn't save: a critical notice strip at the top of the body
  with the server's words; the day and note stay.


## Plan details pop-up and plan price

The "View details" pop-up on Get started (`packages/PackageDetails`) and the price on each plan card and the plan's
own page (`packages/PackagePrice`). Approved B by Jafar 2026-10-22 (Pencil: "Batch 57 · Plan details and price ·
Approved B", `S4I7i`).

- **Pop-up:** large (940). Header: a 40 brand tile (`--color-interactive` fill, white `package`), the plan name, its
  promise as the hint. Footer: Close (secondary), then "Choose <plan>" or "Keep this package" (main, `check`).
- **Body:** padding 20 24 24, blocks 24 apart. A section head is a 32 tile, the title 16/600 and an optional 12 quiet
  hint, 12 above its content.
  - **Hero:** the screen's feature card (`cards.md`), padding 24 24 24 28, gap 28. Left: a feature-subtle 32 tile
    (`sparkles`), "What you get" 20/700, then each highlight as a white 18 `circle-check` and 14/500 white words, 14
    apart. Right, 300 wide: a feature-subtle panel (1px feature border, radius 16, padding 20, gap 12): "MONTHLY ·
    SELECTED" 12/600 white 72%, the price part on green (pill white with `--color-feature--start` words, figures
    white, the old price and period white 72%), its note band feature-subtle.
  - **Services we deliver** (Growth `briefcase-business`, "Uplift does this work for you."): one tile per service in a
    row, 12 apart, the same height: `--color-surface--background`, radius 12, padding 16, gap 10; a 40 tile in the
    service's section colour (website Growth `globe`, Google profile Review `map-pin`, reviews Review `star`, calls
    and texting Conversation `phone`, marketing Growth `megaphone`), the name 14/600, the description 14 quiet.
  - **In the app** beside **Limits** (280), 16 apart, each a `--color-surface--background` box (radius 12, padding
    16, gap 14) with an inactive section head. In the app: the extra features two to a row, 8 apart, in white boxes
    (radius 8, padding 12, gap 10, the same height per row): a 32 tile in the feature's section colour, the name 14/600
    over the description 12 quiet; then "INCLUDED IN EVERY PACKAGE" 12/600 quiet and the basics as white chips (1px
    `--color-border`, pill corners, padding 4 10, 14/500 heading). Limits: one white box per allowance (radius 8,
    padding 10 12): the number 28/700 (-0.6) over its words 14/500 quiet ("Unlimited" when it has no cap), then a 14
    `refresh-cw` and the monthly-reset line 12 quiet when an amount resets.
  - **Price and payment** (Invoice `credit-card`, "Prices are in US dollars."): each billing the plan offers as a white
    tile side by side, 12 apart (radius 12, padding 16, gap 10, 1px `--color-border`): "MONTHLY"/"YEARLY" 12/600
    quiet; the chosen one has a 1.5px `--color-interactive` edge and a 14 `check` with "Selected" 14/600
    `--color-interactive` at the right. Under them a "HOW PAYING WORKS" box (`--color-invoice--surface`, 1px
    `--surface-edge`, radius 12, padding 16, gap 12): three white step boxes in a row (radius 8, padding 12, gap 10):
    a 28 `--color-invoice` circle with the white number, the title 14/600 over 12 quiet words — "You apply" / "Pick a
    package and send this form.", "We send payment instructions" / "You pay us directly, outside the app.", "Your
    account starts" / "Once the first payment arrives." Then the prepaid-balance line 12 `--onSurface`.
  - **Not included:** a strip at the end (`--color-inactive--surface`, radius 16, padding 12, gap 12): a white 32
    tile with `circle-minus`, "Not included" 14/600 over the words 14/500, in `--onSurface`.
- **Plan price** (on a white card): an optional pill on top (success, `badge-percent` "50% off for 3 months" for an
  intro offer, `piggy-bank` "Save $498 · 17%" for a yearly saving; never both); one line, 6 apart: the price 28/700
  (-0.6; 48 on the plan's own page), the old price struck through and the period, 14 quiet; then a grey note band
  (`--color-surface--background`, radius 8, padding 8 10): "Then $249 a month" or "That's $207.50 a month" 14/600
  heading over an optional 12 quiet line ("Paid upfront", "Join by <date> to get it."). No offer or saving: the price
  line alone.

## Mark as lost pop-up

A Pipeline card's Mark as lost and Outcomes' Lost reason (`pipeline/MarkOpportunityLostDialog`). Approved A by
Jafar 2026-10-22 (Pencil: "Batch 59 · Mark as lost pop-up · Approved A", `o0HfC`).

- Default form pop-up (600). Header: 40 tile in the card's record colour (request `inbox`, quote `file-text`), the
  title ("Mark as lost" or "Lost reason"), the hint "Request · <card name> · <client>" ("Quote #318 · …" on a quote).
- Body, fields 16 apart. Mark as lost: a warning notice strip (`notices.md`, `triangle-alert`) saying what happens to
  a request or a quote. Lost reason: "What the customer said" first when they declined in their own words
  (`--color-surface--background`, a 3px `--color-border` line at the left, radius 8, padding 12 14; a 12/600 quiet
  label over the words 14 `--color-text`, line height 1.5), then a 14 lock and "Only your team sees this reason…"
  12/500 quiet.
- Reason (optional) is the dropdown (`inputs.md`); a retired reason reads "<name> (retired)". Note is the big text
  box, 96 high, with "52 / 1,000" 12/500 quiet at the right under it; with "Other" its label reads
  "Note (required for “Other”)".
- Footer: Cancel, then Mark as lost (danger · confirm, `circle-x`) or Save reason (main, `check`).
- Reasons loading: the dropdown disabled with "Loading reasons…". "Other" without a note: Mark as lost disabled.
  Saving: the spinner takes the button's icon; Cancel and × disabled. Couldn't save: a critical notice strip at the
  top of the body with the server's words; the reason and note stay.

## Add number pop-up

Buying a texting number in three steps (`concept.pen` board `qaFQf`, "Add number pop-up · Approved B", Jafar
2026-10-22, with option A's number list in step 2).

- Large pop-up (940). Header: 40 tile in `--color-conversation` (`phone`), "Add number", the hint "A new number for
  texting your customers". Footer: "Step 2 of 3" 12/500 quiet at the left; Cancel or Back (`arrow-left`), then
  Continue (`arrow-right`), "Buy for $2.00" (`shopping-cart`) or "Start paperwork" (`file-plus`).
- Body splits in two. Left, a 260 step rail: `--color-conversation--surface`, a 1px `--surface-edge` line on its
  right, padding 16, gap 6; "3 STEPS" 12/600 `--onSurface`; each step padding 10, radius 10: a 28 circle (done:
  `--color-conversation` fill with a white `check`; current: white with a 1.5px `--color-conversation` edge and its
  number; next: white, 1px `--surface-edge`), the title 14/600 over the choice made 12 `--onSurface` ("You are
  here", "Next"). The current step is a white row with a 1px `--surface-edge`. At the foot a white card (radius 12,
  padding 14): "MONTHLY PRICE" 12/600 quiet, the price 20/700 with "a month" 12 quiet, one 12 quiet line.
- Right pane padding 24, gap 18; a heading 16/600 over a 14 quiet line.
- **Step 1:** the country picker (360), then "What kind of number?" as three equal tiles (white, 1px
  `--color-border`, radius 12, padding 16, gap 10): a 32 conversation tile, the name 16/600, a radio at the right
  (chosen: a 22 green circle with a white `check` and a 1.5px `--color-interactive` tile edge), the description 14
  quiet, three 24 ability squares (`message-square`, `image`, `phone` on `--color-conversation--surface`), "From
  $2.00" 14/700 with "a month", and a need band (radius 8, padding 8 10, 14 icon, 12/600 words) in its status
  tone: informative for a registration needed after buying, warning for paperwork before buying. A kind the country
  can't text from: `--color-surface--background--subtle`, 80% opacity, an inactive tile, a disabled radio, "—" and an
  inactive band with `ban`.
- **Step 2:** the search box (220) and the Picture messages and Calls checkboxes in one row, then the list: a
  radius 12 card, a head row on `--color-surface--background--subtle` ("8 NUMBERS FOR 512 · AUSTIN AREA" and
  "Price per month", 12/600 quiet), rows padding 10 12, gap 14, radius 8: radio, the number 14/600 over "City ·
  Local" 12 quiet, ability pills in a 250 column (24 high, `--color-conversation--surface`, 13 icon, 12/600; one it
  lacks is `--color-surface--background--subtle` with `minus` and struck-through words), the price 14/600 with
  "/month" in a 110 column. The chosen row is white with a 1.5px `--color-interactive` edge. Foot: "Showing 5 of 8"
  and a quiet "Show other numbers".
- **Step 3:** the bill card (radius 12): a `--color-conversation--surface` band with a 40 white tile, the number
  24/700 (-0.5), "Austin, TX · Local number" 14/500 `--onSurface` and white ability pills; then lines padding 11 0
  with hairlines: Paperwork (a success "Not needed in the US" or warning "Needed first" pill), Today or "When you
  buy" (700), Every month after, Setup charge, Paid from. Under it "WHAT HAPPENS NEXT": three equal
  `--color-surface--background--subtle` boxes (radius 12, padding 12) with a 24 status tile, a 14/600 title and a 12
  quiet line, `chevron-right` between them.
- States: searching, the list's loading rows; no numbers, and the phone company unreachable, the page-states
  empty and couldn't-load layouts inside the list card, Continue disabled; a country with nothing to text from,
  every kind greyed, a warning notice strip, Continue disabled; buying, the button's spinner, Back and × disabled;
  connection dropped, an informative notice strip with a spinner tile at the top and "Checking…"; bought, a 40
  success tile, "<number> is yours" 24/700, the charge line, a warning notice strip that it can't text yet, and
  "Register your business" as the main button beside Done.

## Text another country pop-up

A business asks Uplift to switch on texting to another country, from "Text customers in another country" under
WHERE YOU CAN TEXT (`concept.pen` board `xGLYB`, "Text customers in another country · Approved A", Jafar
2026-10-23, with every state). Texting parts use `--color-conversation`.

- Default form pop-up (600). Header: 40 conversation `globe` tile, "Text customers in another country", a 12 quiet
  hint. Footer: Cancel, then the main button with `send`; at 45% until a country is picked.
- Body, blocks 20 apart, each under a 12/600 uppercase quiet head. **Country box** (44 high): a 24 round flag, the
  name 14/600, the dialling code 12/600 quiet, `chevron-down`. Its open list (radius 12, padding 6, soft shadow) has
  a focused search box (1.5px `--color-interactive` edge) above two groups: already on or asked for (rows at 60%,
  each with its status pill) and new countries (20 flag, name, price 14/600 with "a text" 12 quiet; the chosen row
  `--color-surface--active` with a green `check`).
- **What it costs:** three equal subtle boxes (radius 12, 1px border, padding 12 14): a 14 conversation icon and
  12/500 quiet label over the value 16/700 with a 12 quiet unit. Not set yet reads "Price coming" in quiet.
- **Which number texts them:** a band (radius 12, padding 12 14) with a 32 white tile, title 14/600 over a 12/500
  line, all in the status `--onSurface`: warning `smartphone` when a number is needed, success `circle-check` when
  one already can.
- **What happens next:** three steps in a row, `chevron-right` between: a 28 round status tile (informative `send`,
  warning `hourglass`, success `circle-check`), title 12/600 over a 12 quiet line.
- **States:** loading, the box on subtle with "Loading countries…" and a spinner; asking, the button's spinner
  with Cancel, × and the box at 45%; couldn't ask, a critical notice strip at the top of the body; asked, a
  centred result (40 success tile, the title 24/700, a Setting up pill, a 14 quiet line, the number band, Done);
  no match, a centred empty state in the list (32 subtle `search-x` tile, 14/600 title, 12 quiet line).

## Delete client pop-ups

Delete client, delete permanently, the receipt and Download client data (`concept.pen` board `WEpOG`, "Customer
delete pop-ups · Approved B", Jafar 2026-10-24, with every state). Danger parts use `--color-critical`; the client
panel uses `--color-client`.

- **Delete client:** large pop-up (940). Header: 40 critical `trash-2` tile, "Delete <name>?", a 12 quiet line
  ("Client since Mar 2024 · 1 property"; many: "12 picked on the Clients list · 2 left out"). Footer: at the left a
  quiet red button (16 `shield-x`, 14/600 `--color-critical`, 14 `chevron-right`) for the permanent delete, hidden
  without that permission and for many clients; Cancel, then Delete client (danger main, `trash-2`).
- Body splits in two, no padding. Left (padding 20, gap 14): a 16 critical `trash-2` with "Goes with <name>"
  16/600, then one list box (radius 12, 1px `--color-border`, clipped), a row per kind (padding 10 14, gap 12, a
  hairline above): a 28 tile in the record's colour (request `inbox`, quote `file-text`, job `hammer`, messages
  `message-circle` conversation, notes `sticky-note` inactive, files `file` informative, review request `star`
  review, opportunity `target` growth, property `house` client), the kind 14/500 and the count 14/700 at the right.
- Right, a 360 panel, `--color-client--surface` with a 1px `--surface-edge` line on its left, padding 20, gap 14: a
  16 `shield-check` with "What stays" 16/600; white cards (radius 12, 1px `--surface-edge`, padding 12 14, gap 12),
  a 32 tile, title 14/600 over a 12 quiet why (invoices `receipt` invoice; a "stop texting" choice
  `message-circle-off` conversation, only when there is one). Then "WHAT HAPPENS NEXT" 12/600 `--onSurface` and
  three steps: a 28 white circle (1px `--surface-edge`, 14 icon) on a 2 wide `--surface-edge` line, the when 14/600
  over a 12 line in `--onSurface` (`eye-off` Today, `rotate-ccw` Until <date>; the last, `trash-2` "Deleted for
  good", in `--color-critical`).
- **Many clients:** the same pop-up with totals; clients with open money are named in a warning notice strip
  (`circle-dollar-sign`) under the heading.
- **Money still open:** default pop-up (600), 40 warning `circle-dollar-sign` tile, "<name> can't be deleted yet".
  A 14 quiet intro, then one list box, a row per open item: a 32 invoice tile (`receipt`, `credit-card`, `wallet`),
  the item 14/600 · the amount 14/600 `--color-warning--onSurface`, the way to settle 12 quiet, and an Open
  secondary button (`arrow-up-right`). Footer: one main button, Got it.
- **Delete permanently:** default pop-up (600), 40 critical `shield-x` tile, "Delete <name> permanently", 12 quiet
  "Because they asked us to delete their information". Body: a critical notice strip (`triangle-alert`) that it
  can't be undone; "DELETED NOW" 12/600 quiet over pill chips (subtle fill, 1px border, padding 4 10 4 4, a 22
  round tile in the record colour with a 12 icon, words 12/600 heading); a 16 invoice `receipt` with the kept line
  14; the field "Type <name> to confirm" (the name 14/700 `--color-critical`), a green `circle-check` in the box
  once it matches, a 12 quiet hint. Footer: Back (quiet) at the left; Cancel, Delete permanently (danger main,
  `shield-x`) at 45% until the name matches.
- **Receipt:** default pop-up (600), 40 success `circle-check` tile, "<name> was deleted", 12 quiet "Permanently ·
  <date and time> · by <member>". Body: one paper card (subtle fill, 1px border, radius 12, padding 4 16) with two
  sections 14 apart, split by a 1px `--color-border--interactive` line: "DELETED" (14 critical `trash-2`), lines
  14 with counts 14/600 at the right; "KEPT, AND WHY" (14 invoice `shield-check`), the item 14/600 in a 200 column
  beside its why 14 quiet. Footer: Copy receipt (secondary, `copy`), Done (main, `check`).
- **Download client data:** default pop-up (600), 40 client `download` tile, "Download <name>'s data". "WHAT'S IN
  THE FILE" then subtle boxes two to a row (radius 12, 1px border, padding 12, gap 10): a 32 record tile, the part
  14/600 over a 12 quiet detail, a 16 `circle-check` in `--color-success`. Then a 16 quiet `circle-minus` with the
  left-out line 14 quiet, and an informative notice strip (`clock-3`). Footer: Cancel, Prepare download (main,
  `download`).
- **Toasts** (bottom right, 420): white, radius 12, 1px border, shadow 0 12 32 black 14%, padding 12 12 12 14, gap
  12: a 36 tile (preparing: the spinner in a client tile; ready: success `file-archive`; failed: critical
  `circle-alert`), title 14/600 over a 12 quiet line, an optional main button (Download), a 28 quiet ×. The bell
  shows the ready file as a client `download` row.
- **States:** counting, bone rows in the list and a bone card in the panel, Delete client and the red link at 45%;
  couldn't count, a critical notice strip with Try again in place of the list, the panel says only "Invoices and
  payments always stay."; deleting, the pressed button's spinner with Cancel, × and the link at 45% (permanent:
  the box goes subtle); couldn't delete, a critical notice strip above the list, counts kept.
