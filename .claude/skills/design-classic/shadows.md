# Shadows & Elevation

Exactly four elevation shadows exist. No other shadow tokens are defined — the `shadow-2xs…shadow-2xl` scale does not exist. Everything else is a `--shadow-focus` ring for interactive controls.

| Token            | CSS value                                                                     |
| ---------------- | ----------------------------------------------------------------------------- |
| `--shadow-low`   | `0px 1px 2px rgba(0, 0, 0, 0.25), 0px 0px 2px rgba(0, 0, 0, 0.1)`             |
| `--shadow-base`  | `0px 1px 4px 0px rgba(0, 0, 0, 0.1), 0px 4px 12px 0px rgba(0, 0, 0, 0.05)`    |
| `--shadow-high`  | `0px 16px 16px 0px rgba(0, 0, 0, 0.075), 0px 0px 8px 0px rgba(0, 0, 0, 0.05)` |
| `--shadow-focus` | `0px 0px 0px 2px var(--color-surface), 0px 0px 0px 4px var(--color-focus)`    |

Shadows always carry a slight y-axis offset — the implied light source sits above the head of the viewer. The higher an element sits, the broader its shadow spreads (diffusion) and the lighter it gets.

## Elevation Stack (Z-index)

Shadows signal depth on the z-axis; `z-index` positions it. Used order:

| Token                    | Value | Used by                                                                                    |
| ------------------------ | ----- | ------------------------------------------------------------------------------------------ |
| `--elevation-default`    | 0     | Content on the surface plane                                                               |
| `--elevation-base`       | 1     | Sticky/floating in-content layers (sticky headers, LightBox controls)                      |
| `--elevation-menu`       | 6     | Row-level action menus, FilterPicker overlay, DataList/DataTable actions                   |
| `--elevation-datepicker` | 6     | Reserved for date picker calendars (adjacent to menus)                                     |
| `--elevation-modal`      | 1001  | Main `Menu`, Select/Combobox/Autocomplete popups, BottomSheet, SideDrawer, Modal, LightBox |
| `--elevation-tooltip`    | 1002  | Tooltip, Popover portals, autocomplete/clear helpers                                       |
| `--elevation-toast`      | 1003  | Toast notifications                                                                        |

## Component Mapping

| Shadow token     | Use it for                                                                                                                                                                                                                                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--shadow-low`   | Slight lift, still near the surface — non-interactive Cards that sit overtop other content. Low elements are NOT "gliding" surfaces.                                                                                                                                                                                  |
| `--shadow-base`  | Most normal case: floating containers over related content that are interactive — Menu, Popover, Select / MultiSelect / Autocomplete / Combobox dropdown lists, Chip dismissible menu, contextual action menus, Filter picker, Data grid row actions, BrowserBottomSheet, Gallery "show more", Sidebar (`hasShadow`). |
| `--shadow-high`  | Elements that break the plane of the view, typically fixed position — Modal & other composed dialog popups, Toast, Card at `elevation="high"`.                                                                                                                                                                        |
| `--shadow-focus` | Focus ring (NOT an elevation). Interactive controls in the `focus-visible` state — Button, Chip, Checkbox, RadioGroup, Switch, SegmentedControl, InputNumber, formatFile/grid rows, Select trigger, Menu action, Link.                                                                                                |

## Rules

- Use only `--shadow-low`, `--shadow-base`, `--shadow-high`, and `--shadow-focus`. Never compose custom `box-shadow` values.
- `--shadow-focus` is a focus/ring shadow only — it is never an elevation shadow.
- Never stack multiple shadow tokens on one element; pick a single level.
- Elevation steps are semantic and intentional — the element's depth (what it should float over) decides the level, not a "bigger = fancier" scale.
- Cards default to the surface plane with **no** shadow (`elevation="none"`). Add `low` only when a card floats over other cards (e.g. carousel). `base`/`high` also exist for Cards.
- Interactively elevate (e.g. Card hover) only when the elevation itself is the affordance — do not step Card elevation for hover.
- Apply `data-elevation="elevated"` to floating layers (Menu, popovers, pickers) so dark mode recomputes their surface color to match the elevation.
- `--shadow-focus` ring order: `2px var(--color-surface)` gap, then `4px var(--color-focus)` ring outside it.
