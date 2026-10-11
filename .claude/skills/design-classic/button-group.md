# Button Groups

> Dependencies: `buttons.md`, `borders.md`, `colors.md`, `radius.md`

## Core Specs

- **Wrapper:** inline-flex, `var(--radius-base)` radius, shadow-xs
- **Children overlap:** `calc(-1 * var(--border-base))` left margin on all except first button
- **Buttons inside the group must NOT have individual shadows.** Only the wrapper has a shadow.

## Anatomy

### Wrapper

- Display: inline-flex
- Radius: `var(--radius-base)`
- Shadow: shadow-xs

### First Button

- `var(--radius-base)` radius on inline-start side only, 0 on inline-end

### Middle Button(s)

- No radius (0 on all corners)

### Last Button

- `var(--radius-base)` radius on inline-end side only, 0 on inline-start

### All buttons except first

- `calc(-1 * var(--border-base))` left margin to overlap borders

## Rules

- Buttons inside groups follow all styles from `buttons.md` (background, border, focus rings) except individual shadows
- Icon-only buttons: 16x16px icon, match height of text buttons
