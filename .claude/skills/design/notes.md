# Notes

> Dependencies: `colors.md`, `avatars.md`, `files.md`, `buttons.md`, `cards.md`

Pencil: `concept.pen` → board "Notes and attachments" (`KuOmH`), approved 2026-10-19; the Notes panel around
the notes → board "Notes panel · menu and states" (`l9ZBWI`), approved 2026-10-20; the note box on new
records → board "Writing boxes" (`qf1uu`, B), approved 2026-10-20.

## Notes card

- A side or section card (`cards.md`) with a 40 `--color-conversation` tile (`notebook-pen`); notes are team talk.
- Each note: `--color-surface--background` band, radius 8, padding 12, gap 12; a 32 avatar, then the author line,
  the note text and its files, 6 apart.

## Author line

- A 32 avatar (`avatars.md`), 8 gap, then the name 13/600 `--color-heading` over the time 12
  `--color-text--secondary`, 1 apart.
- An edited note: an "Edited" tag 6 after the name: `--color-inactive--surface`, radius 4, padding 1 5,
  12/600 `--color-inactive--onSurface`.
- Hovering the time shows the exact date and time in a dark tip: `--color-surface--reverse`, radius 6,
  padding 5 8, 12/500 `--color-text--reverse`.

## Note text

- 14/400 `--color-text`, line height 1.5; line breaks kept, long words wrap.
- A mention: a chip in `--color-conversation--surface`, radius 4, padding 1 4, the name 600
  `--color-conversation--onSurface`. Emphasis only, never a link, so never green.

## Note files

- 8 under the text. Photos first, 8 apart: 96×72 tiles, radius 8, 1px `--color-border`, photo filling (cover).
  Hover: 1.5px `--color-interactive` edge.
- Files after, as chips 8 apart that wrap: `--color-surface`, 1px `--color-border`, radius 8, padding 6 10 6 6,
  gap 10; a 32 file picture (`files.md`, small sheet with its type tab), the name 13/600 heading over the size 12
  quiet, then a 16 `download` in `--color-icon--secondary`. Long names truncate.
- Still being checked: a photo tile is `--color-warning--surface` with an 18 `clock` in `--color-warning`; a chip
  uses the same box as its picture, "Being checked" in `--color-warning--onSurface`, and no download.

## Notes panel

- The Notes card's body: note bands 10 apart, padding 16; the note field at the foot under a 1px
  `--color-border` hairline, padding 12 16 16.
- Note field: `--color-surface--background--subtle`, 1px `--color-border`, radius 8, padding 4 4 4 12, gap 8;
  text 14, placeholder `--color-text--secondary`. Focused: `--color-surface` with a 1.5px `--color-interactive`
  edge. A 32 send square at the right, radius 8, a 16 `arrow-up`: `--color-interactive` with a white arrow when
  there is text, `--color-inactive--surface` with an `--color-inactive--onSurface` arrow when empty.
- ⋯ on a note: a 28 quiet square, radius 8, 16 `ellipsis` in `--color-icon--secondary`; pressed
  `--color-surface--active`. Its menu is the line menu look (`price-book.md`), 184 wide; Delete in
  `--color-critical`.
- Pinned note: band `--color-warning--surface` with a 1px `--color-warning--surface-edge`, and a 16 `pin` in
  `--color-warning` before the ⋯.
- Waiting for Save: a status line under the text, a 14 icon and 12/600 words 6 apart. New note: white band with a
  1px `--color-warning` edge, `clock` + "Not saved yet" in warning, a quiet small Remove at the right. Edited:
  `clock` + "Edit waiting for Save". Deleted: avatar and author at 50%, the text struck through in
  `--color-text--secondary`, `trash` + "Deleted when you save" in critical, a small secondary Undo at the right.
- Editing: the text becomes a box with a 1.5px `--color-interactive` edge, padding 8 12; small Cancel (secondary)
  and Done (main) 8 apart at the right below it.
- Loading: three note-shaped bones (a 32 circle, a 96×10 line and two 8-high lines in `--color-border`).
- Empty: "No notes yet" 13/600 heading over one 12 quiet hint line, centred over the field; with no field, a 32
  inactive tile above the words. Couldn't load: a 32 critical tile (`triangle-alert`), the title, one quiet line
  and a small secondary Try again.

## Note box on a new record

The Notes card on a new client, request, quote or job (the note saves with the record), approved 2026-10-20 on
board `qf1uu` (B). The Notes panel's field, grown taller, so a note looks the same before and after Save.

- The Notes card (`cards.md` header, conversation tile, hint "Only your team sees this · saves with the client"),
  body padding 16.
- Field: `--color-surface--background`, 1px `--color-border`, radius 8, padding 12 12 10 12, gap 10;
  three lines of text 14, placeholder `--color-text--secondary`. Hover `--color-surface--hover` with a
  `--color-border--interactive--hover` edge. Typing:
  `--color-surface` with the 1.5px `--color-interactive` edge.
- Inside the field's foot, 8 below the text: a 14 `lock` in `--color-conversation` and "Team only" 12/600
  `--color-conversation--onSurface`, 6 apart; at the right the letters-left count 12/500 quiet ("500 left"),
  quiet even when nearly full.
- Couldn't save: 1.5px `--color-critical` edge, and the error line 12 `--color-critical` under the field.

## Activity feed

The history of a client, request or quote in a 360 side card, "Client history" (Pencil: board `gZ6rR`,
approved A · Timeline 2026-10-20).

- Side card with the Card header: `--color-client` tile with `history`, "Newest first" hint, quiet Close.
- Day label: a pill (padding 3 8, `--color-surface--background`, 1px `--color-border`, 12/600 uppercase quiet,
  0.6 spacing) then a 1px `--color-border` rule filling the row; 10 below it.
- Each event, gap 12: a 28 rail with a round 28 marker (`--color-<meaning>--surface`, 1px `--surface-edge`,
  14 icon in `--color-<meaning>`), and a 2px `--color-border` line down to the next marker in the same day.
  Text: summary 14/500 heading, then 6 below the author line (24 avatar, name 12/600, "·", "2h ago" 12 quiet);
  16 under each event except the day's last.
- Meaning colour: quote events `--color-quote`, client events `--color-client`, review events
  `--color-review`, notes `--color-conversation`, tags and files `--color-inactive`, anything else
  `--color-inactive` with `history`. The client: `--color-client` avatar with `user-round`; Automatic:
  `--color-inactive` avatar with `zap`.
- Loading: a day pill shape, then rows of a 28 circle and two lines (`page-states.md`). Nothing yet and
  Couldn't load (with Try again) follow `page-states.md` with the `--color-client` tile.
