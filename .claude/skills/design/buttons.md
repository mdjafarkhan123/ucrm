# Buttons

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `shadows.md`

Pencil: `concept.pen` → Parts board → "Buttons" (kinds, pairs, every state of every kind, sizes, loading).

## Core Specs

- Height 36, padding 0 14, radius 8, gap 8; label 14/600; optional 16px icon before the label.
- Main and danger-confirm buttons are slightly raised: `--shadow-button--raised`. White buttons (secondary,
  danger, menu, icon) sit on `--shadow-button`. Quiet buttons have no shadow.

## Sizes

| Size | Height | Padding | Label | Icon | Use for |
|---|---|---|---|---|---|
| Small | 32 | 0 12, gap 6 | 13/600 | 16 | Buttons inside rows and busy cards |
| Base | 36 | 0 14, gap 8 | 14/600 | 16 | Everywhere else (default) |
| Large | 44 | 0 18, gap 8 | 16/600 | 18 | Sign-in, setup and client-facing pages |

An icon button is square at the size's height.

## Variants

### Main
- Background `--color-interactive`; text and icon `--color-surface`. One per area.

### Secondary
- Background `--color-surface`; 1px `--color-border--interactive`; text and icon `--color-heading`.
- Cancel is always a secondary button, left of the action it dismisses (save bar, dialog footer).

### Quiet
- No background or border; text `--color-text`. Only for link-like actions inside a page: Clear filters, Skip for
  now, Show more.

### Danger
- Secondary look with `--color-destructive` text and icon. Opens the confirm step for a destructive action.

### Danger · confirm
- Background `--color-destructive`; text and icon `--color-surface`. Only the final button of a confirm dialog
  ("Delete job").

### More menu
- Secondary look, label then a 16px `chevron-down` in `--color-icon`; padding 0 10 0 14, gap 6. Opens a menu of
  the area's less-used actions.

### Icon button
- 36×36 (40×40 in the top bar), radius 8, white, bordered; 16–18 icon in `--color-icon`. Needs an `aria-label`.

## States

Every kind has all six states.

| State | Main / Danger · confirm | White kinds (secondary, danger, menu, icon) | Quiet |
|---|---|---|---|
| Hover | `--color-interactive--hover` / `--color-destructive--hover` | `--color-surface--hover` and border `--color-border--interactive--hover`; danger uses `--color-critical-surface` and a `--color-destructive` border | `--color-surface--hover` |
| Pressed | Hover colour with a soft inner shadow | `--color-surface--active`, border `--color-border--interactive--hover`, no shadow; danger keeps its hover look without shadow | `--color-surface--active` |
| Focus | `--shadow-focus`: 2px gap, then a 2px `--color-focus` ring | same | same |
| Disabled | Background `--color-disabled--secondary`, text and icon `--color-disabled`, no shadow | same, border `--color-disabled--secondary` | text `--color-disabled` |
| Loading | see below | see below | see below |

## Loading

Every button supports loading. A button whose action waits on the server shows it from the moment it is pressed
until the work finishes.

- A 16px spinner (a ring in the button's text colour, its track at 25%) takes the icon's place. The label and
  the button's own colour stay, so the user still sees what is happening.
- A button with no icon hides its label and centres the spinner; its width stays the same.
- The button cannot be pressed again while loading, and carries `aria-busy="true"`.
- Buttons that only open a dialog or another page act instantly. A More menu spins only while its options load.
