# Fields

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `typography.md`

## Core Specs

- Label above the box: 13/600 `--color-heading`, 6 gap.
- Box: height 40, padding 0 12, radius 8, `--color-surface`, 1px `--color-border--interactive`.
- Value 14 `--color-heading`; placeholder `--color-text--secondary`.

## Variants

- **Select:** chevron-down icon at the right, `--color-icon--secondary`.
- **Search:** search icon at the left; optional ⌘K key hint (11/600 on `--color-surface--background`, radius 4).
- **Error:** 1.5px `--color-critical` border; under it a 14px circle-alert icon and a 12px message in
  `--color-critical` that says what to fix.

## States

Hover: border `--color-border--section`. Focus: `--shadow-focus`. Disabled: `--color-disabled--secondary`
background.
