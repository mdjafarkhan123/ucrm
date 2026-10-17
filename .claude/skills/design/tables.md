# Tables

> Dependencies: `colors.md`, `borders.md`, `badges.md`, `icon-shapes.md`

## Core Specs

- Container: `--color-surface`, 1px `--color-border`, radius 16, clipped corners.
- Header: `--color-surface--background--subtle`, padding 12 20, labels 11/600 uppercase, 0.6 letter-spacing,
  `--color-text--secondary`; 1px bottom border.
- Rows: padding 14 20, gap 16, 1px bottom border (none on the last row).

## Cells

- First column: 32 avatar (`--color-client--surface`, initials 12/700 `--color-client--onSurface`) or record
  tile, then name (14/600) over address (12 quiet).
- Record column: 24 tile + label.
- Status column: fixed width, pill.
- Money: right-aligned, 14/600 `--color-heading`.

## States

Row hover `--color-surface--hover`; selected `--color-surface--active`.
