# Tabs

> Dependencies: `colors.md`, `typography.md`, `shadows.md`

## Core Specs

- Split one record's content into groups opened one at a time; never for moving between pages.
- Strip: `--color-surface--background`, pill corners, padding 4, 4 between tabs, the full width of its card;
  inside the card's padding (16 20). The open tab's content starts 20 below the strip.
- Tab: pill corners, label 600 `--color-text--secondary`, an optional count 8 after it. Page tabs: label 16,
  padding 8 14. Tabs inside a card: label 14, padding 6 12.
- Count: pill corners, padding 2 7, 12/600, `--color-surface--background--subtle` with
  `--color-text--secondary`. Money that came in: `--color-success--surface` with `--color-success--onSurface`.

## States

- Open: `--color-surface`, 1px `--color-border--interactive`, `--shadow-button`, label `--color-heading`; its
  plain count turns `--color-interactive` with `--color-text--reverse` figures (a money-in count keeps its green).
- Hover: `--color-surface--hover`, label `--color-heading`. Focus: 2px `--color-focus` ring around the tab.
- Unlike the segmented switch (a short bordered track inside a form), tabs run the card's full width and keep
  their counts.
