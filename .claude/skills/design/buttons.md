# Buttons

> Dependencies: `colors.md`, `radius.md`, `borders.md`

## Core Specs

- Height 36, padding 0 14, radius 8, gap 8; label 14/600; optional 16px icon before the label.

## Variants

### Main
- Background `--color-interactive`; text and icon `--color-surface`.
- Hover `--color-interactive--hover`. One per area.

### Secondary
- Background `--color-surface`; 1px `--color-border--interactive`; text `--color-heading`.

### Quiet
- No background or border; text `--color-text`. For Cancel and low-weight actions.

### Danger
- Secondary look with `--color-destructive` text and icon.

### Icon button
- 36×36 (40×40 in the top bar), radius 8, white, bordered; 16–18 icon in `--color-icon`.

## States

| State | Look |
|---|---|
| Hover | Darker background (main) or `--color-surface--hover` |
| Focus | 2px `--color-focus` ring outside |
| Disabled | Background `--color-disabled--secondary`, text and icon `--color-disabled` |
