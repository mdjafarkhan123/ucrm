# Icon Shapes

> Dependencies: `colors.md`, `radius.md`
> There is no separate "icon shape" component — every icon ships as a single glyph with three sizes and a `--color-*` fill. Colored icon containers are a layout rule I enforce via radius tokens, never a wrapper component of their own.

## Core Specs

- **Sizes:** `small` 16×16, `base` 24×24 (default), `large` 32×32.
- **Sizing medium:** the icon `svg` is inline-block; `width`/`height` come from
  the size token; the `viewBox` holds the glyph's intrinsic paths.
- **Shapes when wrapping an icon in a colored tile** (sidebar, module headers,
  empty states):
    - Circle: `--radius-circle` (100%)
    - Rounded square: `--radius-base` (8px)
- **Centering is mandatory:** `display: inline-flex; align-items: center;
justify-content: center`.

## Sizes

| Size | Container       | Icon    | Icon size |
| ---- | --------------- | ------- | --------- |
| XS   | 24×24           | 16×16px | small     |
| SM   | 32×32           | 24×24px | base      |
| MD   | 40×40 (literal) | 24×24px | base      |
| LG   | 48×48           | 32×32px | large     |
| XL   | 56×56 (literal) | 32×32px | large     |

- Container widths map to `--space-large` (24px), `--space-larger` (32px),
  `--space-largest` (48px). 40px and 56px are literal
- Icon size governs legibility; the container does not.

## Color Variants

### Brand

- Background: `var(--color-interactive--background--subtle--hover)`
- Icon color: `var(--color-interactive--subtle)`

### Gray

- Background: `var(--color-surface--background)`
- Icon color: `var(--color-icon)`

### Danger

- Background: `var(--color-critical--surface)`
- Icon color: `var(--color-critical)`

### Success

- Background: `var(--color-success--surface)`
- Icon color: `var(--color-success)`

### Warning

- Background: `var(--color-warning--surface)`
- Icon color: `var(--color-warning)`

### Info

- Background: `var(--color-informative--surface)`
- Icon color: `var(--color-informative)`
