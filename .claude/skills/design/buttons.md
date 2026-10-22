# Buttons

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `shadows.md`

Pencil: `concept.pen` → Parts board → "Buttons" (kinds, pairs, every state of every kind, sizes, loading), the
"Switched-on buttons" board (option A), and Batch 62 `SU6gO` (white buttons in place, light and dark).

## Core Specs

- Height 36, padding 0 14, radius 8, gap 8; label 14/600; optional 16px icon before the label.
- Main and danger-confirm buttons are slightly raised: `--shadow-button--raised`. White buttons (secondary,
  danger, menu, icon, joined groups) are raised white keys: `--shadow-button--key`. Quiet buttons have no shadow.

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
- A raised white key with no drawn line: background a top-to-bottom shade from `--color-surface--key` to
  `--color-surface--hover`, `--shadow-button--key`; text `--color-heading`, icon `--color-icon`. The shadow ring,
  not a line or a grey fill, keeps it apart from a white card or the page. In dark mode the key is lighter than
  what it sits on, with a faint top highlight (Jafar, 2026-10-22, Batch 62 B; replaces the brand-green edge).
  Green stays for the main button and a switched-on button.
- Cancel is always a secondary button, left of the action it dismisses (save bar, dialog footer).

### Quiet
- No background or border; text `--color-text`. Only for link-like actions inside a page: Clear filters, Skip for
  now, Show more.

### Danger
- Secondary look (raised white key, no line) with `--color-destructive` text and icon. Opens the confirm step for a
  destructive action.

### Danger · confirm
- Background `--color-destructive`; text and icon `--color-surface`. Only the final button of a confirm dialog
  ("Delete job").

### More menu
- Secondary look, label then a 16px `chevron-down` in `--color-icon`; padding 0 10 0 14, gap 6. Opens a menu of
  the area's less-used actions.

### Icon button
- 36×36 (40×40 in the top bar), radius 8, the secondary look (raised white key); 16–18 icon in `--color-icon`. Needs
  an `aria-label`.

### Pencil button
- The icon button holding a 16 `pencil`, at small (32) or base (36) size; it opens a block for editing beside a
  heading or at the end of a row. Its label is the accessible name and the hover tip. All states as the icon
  button (approved 2026-10-19).

### Switched on
- A white button that works like a light switch (Unscheduled, Map, Filters) stays on while its panel shows or its
  filter is set: it keeps the raised key and adds a 1px `--color-interactive` border; label and icon
  `--color-interactive`. Inside a joined group only the label and icon turn green.
- Hover and pressed: border, label and icon `--color-interactive--hover`; pressed adds a soft inner shadow.
- Number bubble after the label: 20 high, padding 0 7, pill corners, 12/600. Off: `--color-inactive--surface`
  with `--color-heading` text. On: `--color-interactive` with `--color-surface` text (`--color-interactive--hover`
  on hover).

### Joined group
- Two to four white buttons that belong together (‹ Today ›; Map | Filters) share one raised key: height 36,
  the secondary background, `--shadow-button--key`, radius 8, clip. Inside, each button has no border, shadow or
  radius, and a 1px `--color-border` line separates them. Pencil: Schedule toolbar.

## States

Every kind has all six states.

| State | Main / Danger · confirm | White kinds (secondary, danger, menu, icon) | Quiet |
|---|---|---|---|
| Hover | `--color-interactive--hover` / `--color-destructive--hover` | `--color-surface--key-hover`, `--shadow-button--key-hover` (lifts); danger uses `--color-critical-surface` | `--color-surface--hover` |
| Pressed | Hover colour with a soft inner shadow | `--color-surface--key-pressed`, `--shadow-button--key-pressed` (sinks in); danger keeps `--color-critical-surface` | `--color-surface--active` |
| Focus | `--shadow-focus`: 2px gap, then a 2px `--color-focus` ring | same | same |
| Disabled | Background `--color-disabled--secondary`, text and icon `--color-disabled`, no shadow | same | text `--color-disabled` |
| Loading | see below | see below | see below |

## Loading

Every button supports loading. A button whose action waits on the server shows it from the moment it is pressed
until the work finishes.

- A 16px spinner (a ring in the button's text colour, its track at 25%) takes the icon's place. The label and
  the button's own colour stay, so the user still sees what is happening.
- A button with no icon hides its label and centres the spinner; its width stays the same.
- The button cannot be pressed again while loading, and carries `aria-busy="true"`.
- Buttons that only open a dialog or another page act instantly. A More menu spins only while its options load.
