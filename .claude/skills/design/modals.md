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
