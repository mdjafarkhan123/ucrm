# Buttons

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `shadows.md`

Pencil: `concept.pen` → Parts board → "Buttons" (kinds, pairs, every state of every kind, sizes, loading), and
the "Switched-on buttons" board (option A).

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
- Background `--color-surface` (white) with a thin 1px `--color-interactive` (brand green) edge; text and icon
  `--color-heading`. The edge, not a grey fill, keeps it apart from a white card or the page (Jafar, 2026-10-21,
  like Jobber).
- Cancel is always a secondary button, left of the action it dismisses (save bar, dialog footer).

### Quiet
- No background or border; text `--color-text`. Only for link-like actions inside a page: Clear filters, Skip for
  now, Show more.

### Danger
- Secondary look with a 1px `--color-destructive` edge and `--color-destructive` text and icon. Opens the confirm step for a destructive action.

### Danger · confirm
- Background `--color-destructive`; text and icon `--color-surface`. Only the final button of a confirm dialog
  ("Delete job").

### More menu
- Secondary look, label then a 16px `chevron-down` in `--color-icon`; padding 0 10 0 14, gap 6. Opens a menu of
  the area's less-used actions.

### Icon button
- 36×36 (40×40 in the top bar), radius 8, the secondary look (white, thin brand-green edge); 16–18 icon in `--color-icon`. Needs an `aria-label`.

### Pencil button
- The icon button holding a 16 `pencil`, at small (32) or base (36) size; it opens a block for editing beside a
  heading or at the end of a row. Its label is the accessible name and the hover tip. All states as the icon
  button (approved 2026-10-19).

### Switched on
- A white bordered button that works like a light switch (Unscheduled, Map, Filters) stays on while its panel
  shows or its filter is set: border, label and icon `--color-interactive`, background stays `--color-surface`.
- Hover and pressed: border, label and icon `--color-interactive--hover`; pressed adds a soft inner shadow.
- Number bubble after the label: 20 high, padding 0 7, pill corners, 12/600. Off: `--color-inactive--surface`
  with `--color-heading` text. On: `--color-interactive` with `--color-surface` text (`--color-interactive--hover`
  on hover).

### Joined group
- Two to four white buttons that belong together (‹ Today ›; Map | Filters) share one box: height 36,
  `--color-surface`, 1px `--color-border--interactive`, radius 8, `--shadow-button`, clip. Inside, each button has
  no border, shadow or radius, and a 1px `--color-border--interactive` line separates them. Pencil: Schedule
  toolbar.

## States

Every kind has all six states.

| State | Main / Danger · confirm | White kinds (secondary, danger, menu, icon) | Quiet |
|---|---|---|---|
| Hover | `--color-interactive--hover` / `--color-destructive--hover` | `--color-surface--hover` and edge `--color-interactive--hover`; danger uses `--color-critical-surface` and a `--color-destructive` border | `--color-surface--hover` |
| Pressed | Hover colour with a soft inner shadow | `--color-surface--active`, edge `--color-interactive--hover`, no shadow; danger keeps its hover look without shadow | `--color-surface--active` |
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
