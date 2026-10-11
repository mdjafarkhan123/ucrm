# Borders

## Width Scale

Use the border-width tokens to keep edge thickness consistent across components.

| Token | Use |
| --- | --- |
| `var(--border-base)` | Default borders and dividers |
| `var(--border-thick)` | Stronger separation or emphasis |
| `var(--border-thicker)` | Heavy structural separation |
| `var(--border-thickest)` | Exceptional high-weight separation |

Use `solid` borders by default. Reserve other styles, such as `dashed`, for
specific affordances such as file dropzones.

The base width is appropriate for most use cases. Use a thicker token only when
the border communicates a stronger structural boundary or closes an already
divided section.

## Color Tokens

| Token | Use |
| --- | --- |
| `var(--color-border)` | Default borders on cards, lists, tables, menus, and containers |
| `var(--color-border--interactive)` | Borders on inputs, buttons, and other interactive controls |
| `var(--color-border--section)` | List sections, table headers, and other content that is further subsectioned |

Do not use color as the only way to convey meaning. Pair important states with
text, icons, labels, or other accessible cues.

## Focus

Focus is not a wider border. Preserve the control's normal border width and use
`var(--shadow-focus)` for the focus indicator. Keep the border color governed by
the component's semantic token, such as `var(--color-border--interactive)` for
form fields.

## Usage by Component

| Context | Width | Color |
| --- | --- | --- |
| Inputs, selects, and textareas | `var(--border-base)` | `var(--color-border--interactive)` |
| Secondary or outlined buttons | `var(--border-base)` | `var(--color-border--interactive)` |
| Cards and containers | `var(--border-base)` | `var(--color-border)` |
| Table and list item separators | `var(--border-base)` | `var(--color-border)` |
| Section boundaries and table headers | `var(--border-thick)` when stronger separation is needed | `var(--color-border--section)` |
| Dropdown menus and modal boundaries | `var(--border-base)` | `var(--color-border)` |

Use the Divider component for full-width content separation. Dividers should not
add their own surrounding spacing; place them within the relevant content layout.
