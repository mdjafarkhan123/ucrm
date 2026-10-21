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

## Page loading

What fills the content area while the next page's screen arrives (Pencil: "Batch 48 · Page loading · Approved
A", `x8nYl`, Jafar 2026-10-21). The sidebar and top bar stay; grey shapes take the layout of the page being
opened, built from the page frame, cards and Loading rows above, so nothing moves when the page arrives.

- **Shapes:** on a card, `--color-border` shimmering to `--color-surface--background--subtle`; on the page
  colour, `--color-border--interactive` shimmering to `--color-border`. Text lines 8–12 high (radius 4), titles
  18–26 high (radius 5–6), tiles their real size and radius, pills full round, buttons 36–40 high (radius 8).
- **List page:** the page header (40 tile, a 120×24 title over a 380×12 line, a 36 More and a 112×40 button at
  the right), four number cards (32 tile and a short line, a 28 high number, an 8 line), then the table card:
  Card header shapes, the head row on `--color-surface--background--subtle`, and Loading rows (each also with
  two short value lines before the 56×20 pill).
- **Record page:** the breadcrumb capsule (24 circle and two step lines), then the two columns. Record header
  card: its top on `--color-surface--background--subtle` (40 tile, pill, the four action shapes at the right, a
  320×26 title), the client line (36 circle, name line, three contact lines), four facts, and the track band
  with five 32 step tiles. Then section cards (Card header shapes and Loading rows); the side column holds the
  money card, Notes and Files as side cards with their header shapes.
- **Create pages and others** follow the same rule from their own frame (`layout.md`).
