# Notes

> Dependencies: `colors.md`, `avatars.md`, `files.md`, `buttons.md`, `cards.md`

Pencil: `concept.pen` → board "Notes and attachments" (`KuOmH`), approved 2026-10-19.

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
