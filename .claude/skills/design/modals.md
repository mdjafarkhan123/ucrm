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
