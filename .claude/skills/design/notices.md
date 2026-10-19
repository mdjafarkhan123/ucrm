# Notice strip

> Dependencies: `colors.md`, `radius.md`, `icon-shapes.md`, `buttons.md`

A message that stays in place until its cause is fixed, on a page or inside a card or pop-up.

## Core Specs

- Fill `--color-<tone>--surface`; no border; radius 16; padding 12; gap 12; items centred.
- Left: a 32 white tile (`--color-surface`, radius 8) with a 16 icon in `--color-<tone>`; the yellow family
  uses `--color-warning--onSurface`.
- Message: 14/500, line height 1.45, `--color-<tone>--onSurface`, fills the width.
- Right: at most one secondary button (`buttons.md`) when there is something to do. No close button.

## Tones

| Meaning | Tone | Icon |
|---|---|---|
| Good to know | `informative` | info |
| Done | `success` | circle-check |
| Needs a look | `warning` | triangle-alert |
| Something failed | `critical` | circle-alert |

## Form error card

At the top of a create or edit form; after a failed save it scrolls into view and takes focus (Pencil: board
"Load more, form errors, edit button, number cards", approved 2026-10-19).

- White card, 1.5px `--color-critical` edge, radius 16, clipped.
- Head: `--color-critical--surface`, padding 12 14, gap 12. A 32 tile filled `--color-critical` with a 16
  white `triangle-alert`; the title 14/600 ("2 things to fix before saving", or "This job wasn't saved") over a
  12 hint ("Your other changes are kept.", or what to try), both `--color-critical--onSurface`.
- One row per field to fix: padding 10 14, gap 10, 1px `--color-border` line above. A 20 round number
  (`--color-critical--surface`, 11/700 `--color-critical--onSurface`), the field name 13/600 heading over what to
  do 12 quiet, and a 16 `arrow-down-right` `--color-icon--secondary` at the right.
- Row hover `--color-surface--hover`, arrow `--color-heading`. Focus on the card: the 2px `--color-focus` ring.
