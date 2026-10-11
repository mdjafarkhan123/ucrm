# Border Radius

The radius scale is a fixed set of corner sizes in `_variables.scss`. Pick from this scale — never invent values.

| Token             | Value | Default usage                                                              |
| ----------------- | ----- | -------------------------------------------------------------------------- |
| `--radius-small`  | 4px   | Checkboxes, menu item cells, small controls, nested elements               |
| `--radius-base`   | 8px   | Default surface radius — buttons, cards, inputs, modals, toolbar, dropdown |
| `--radius-large`  | 16px  | Softer variants, e.g. labels (InlineLabel small/base), selection chips     |
| `--radius-larger` | 24px  | Large labels, elements that expect an extra-smooth corner                  |
| `--radius-circle` | 100%  | Circles only — avatars, radio options, switch pip, toggles                 |

## How each token is used

### `--radius-small` (4px)

- Checkboxes and small interactive controls.
- Menu item cells that sit on a base-radius container.
- Anything nested inside a base-radius container, or smaller than the base, uses the small corner.

### `--radius-base` (8px)

The system default. Every surface with a defined edge uses it:

- Buttons, cards, input fields, modal dialogs, menus.
- The four field corner tokens (`--public-field--top-left-radius`, etc.) all resolve to `--radius-base`.
- `--modal--border-radius` resolves to `--radius-base`.

### `--radius-large` (16px) & `--radius-larger` (24px)

Use sparingly — reserved for elements where a smoother corner reads better, e.g. inline labels and auto-complete chips. Don't reach for these on standard surfaces.

### `--radius-circle` (100%)

For genuinely circular shapes only: avatars, radio options, toggle pips, indicator dots. Never used as a generic "big radius".

## Hardcoded corners (not tokens)

Some components hardcode their own corner size:

| Component   | Value                          |
| ----------- | ------------------------------ |
| StatusLabel | 12px (0.75rem)                 |
| Chip        | 20px                           |
| ProgressBar | `calc(height / 2)` — full pill |

## Rules

- `--radius-base` (8px) is the default for any surface with edges.
- Round unless the element truly is circular — `--radius-circle` is reserved for shapes.
- Nested elements inside a rounded container fall back to `--radius-small`.
- Larger corners (16/24px) are for specialty elements, not default surfaces.
- Never use arbitrary radius values outside this scale.
- Radius must be consistent within each component family.
