# Page states

> Dependencies: `colors.md`, `icon-shapes.md`, `buttons.md`

Pencil: `concept.pen` → Pop-ups board → "Loading, empty and couldn't load". Each state sits inside the card or
area that would hold the content; it has no border of its own.

## Loading

- Row-shaped shapes where the rows will be, in `--color-border` with a soft shimmer to
  `--color-surface--background--subtle`. Each row: padding 12 16, gap 14; a 32 square (radius 8), two lines
  (10 and 8 high, 8 apart, different lengths per row), and a 56×20 shape at the right. Rows sit in 8 padding.
- A block placeholder for a whole card uses radius 16.

## Empty

- Centred, padding 32 40, gap 12: a 40 tile in the page's record or section colour, the title 20/600 (-0.2),
  one line 14 `--color-text--secondary` at most 320 wide, then the one main action 4 lower.
- An empty section inside a card keeps its one quiet line instead.

## Couldn't load

- Same layout as Empty with a `--color-critical` tile (alert-triangle), plain words, and a secondary
  "Try again" button with the refresh icon.
