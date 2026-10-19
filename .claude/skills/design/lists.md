# List Rows

> Dependencies: `icon-shapes.md`, `badges.md`, `typography.md`

## Core Specs

- Inside a card with padding 8; each row padding 12 16, gap 14, radius 8.
- Order: 32 record tile → title (14/600 heading) over meta (12 quiet) → status pill in a 160 column → date
  (13 quiet, right-aligned, 150 wide) → amount (14/600 heading, right-aligned, 90 wide) → chevron-right
  (16, `--color-icon--secondary`).

## States

Hover `--color-surface--hover`; focus `--shadow-focus`.

## Load more footer

The foot of a record list card (Pencil: board "Load more, form errors, edit button, number cards", approved
2026-10-19).

- A full-width bar on `--color-surface--background--subtle`, padding 10 12 10 16, gap 10, items centred, below
  the last row's 1px `--color-border` line.
- More to load: "Showing 25 jobs" 12/500 `--color-text-secondary` at the left; at the right a small secondary
  button (`buttons.md`, 32 high) with a 16 `chevrons-down` in the list's record colour and "Show 25 more".
  Loading: the button's spinner takes the icon's place.
- All loaded: a 24 tile (`--color-success--surface`, `check` in `--color-success`) then "All 48 jobs are
  showing" 12/500 `--color-heading`.
- Search needs more letters: the same with an `--color-informative` tile and `search` icon, and the message
  ("Many clients match. Type more of the name to see the rest.").
