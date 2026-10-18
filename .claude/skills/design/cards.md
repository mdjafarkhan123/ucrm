# Cards

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `icon-shapes.md`, `typography.md`

## Core Specs

- Background `--color-surface`; 1px `--color-border`; radius 16; padding 20 (`--space-medium`); gap 16; no shadow.

## Anatomy (stat card)

1. Header: 32 tile + title 14/600 + quiet open icon (arrow-up-right) at the right.
2. One big number, 32 (`--typography--fontSize-stat`)/700 `--color-heading`.
3. Footer: a status pill and a 13px quiet line ("across 9 invoices").

## States

- Static: no hover.
- Clickable: hover `--color-surface--hover`, pointer cursor.

## Rules

- One job per card: one number or one list, one action.
- Cards in a row share the same height.
