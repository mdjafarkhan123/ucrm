# Tooltips & Popovers

> Dependencies: `colors.md`, `radius.md`, `shadows.md`

## Tooltips

### Core Specs

- Surface: `var(--color-surface--reverse)` — adapts automatically to the active theme
- Text: `var(--color-text--reverse)`
- Font: `var(--typography--fontSize-small)` (12px), weight 500, line-height `var(--typography--lineHeight-base)` (1.25)
- Padding: `var(--space-small)` vertical, `calc(var(--space-small) + var(--space-smaller))` horizontal (8px / 12px)
- Radius: `var(--radius-base)` (8px)
- Max-width: 250px
- Elevation: `var(--elevation-tooltip)` (z-index 1002)
- No border, no shadow
- Gap to activator: `var(--space-small)` (8px), via wrapper padding on the facing side
- Arrow inset: `calc(-1 * var(--space-smaller))` (-4px)
- Fade-in: opacity 0 → 1, ease-out, 150ms, delayed 300ms
- `pointer-events: none` on the wrapper

### Surface Behaviour

- Default: dark surface (`--color-surface--reverse`), reverse text — the surface and text both invert in the opposite theme
- No border on any variant

## Popovers

### Core Specs

- Background: `var(--color-surface)`
- Radius: `var(--radius-base)` (8px)
- Shadow: `--shadow-base`
- Border: `var(--border-base)` solid `var(--color-border)`
- Width: `max-content`, max-width: 350px (`--popover--width`)
- Position offset (gap from activator): 10px
- z-index: `var(--elevation-tooltip)` (1002)
- Font: `var(--typography--fontSize-base)` (14px), line-height normal
- No entrance transition (rendered conditionally)

### Header / Title

- Layout: flex, `space-between`, center-aligned
- Padding: `var(--popover--padding)` (`var(--space-base)`, 16px)
- No background, no bottom border — the header inherits the container surface
- Dismiss button padding: `calc(var(--base-unit) / 4)` (4px, aligned end)

### Body / Content

- Content padding: `var(--popover-content-base-padding)` (`--space-base`, 16px), applied as `--public-content--padding`
- Typography: `--color-text`, `--typography--fontSize-base` (14px)

## Arrows

### Tooltip

- Size: 8x8px (`--tooltip--arrow-size`)
- Rotated 45°; fill matches the tooltip surface

### Popover

- Size: `var(--base-unit)` (16px)
- Border: `var(--border-base)` solid `var(--color-border)`
- Tip via `clip-path`; positioned `-7px` into the pocket; background inherits container
- Rotation per placement (top/bottom/left/right)

## Rules

- Tooltips: radius `var(--radius-base)`, `--color-surface--reverse` surface, reverse text, no border/shadow
- Popovers: radius `var(--radius-base)`, `--color-surface`, `--shadow-base`, `--border-base` border
- Both render at `var(--elevation-tooltip)`
- Arrows match parent surface (tooltip) or inherit container + border (popover)