# Color Tokens

Every color used by a component must come from a semantic CSS custom property:

```css
color: var(--color-text);
background: var(--color-surface);
border-color: var(--color-border);
```

Use semantic tokens in component code. The base palette exists only to define
semantic tokens and must not be used directly. Semantic tokens automatically
respond to the active theme.

## Token patterns

Status and workflow colors use three related tokens:

| Suffix | Use |
| --- | --- |
| none | Main color for labels, icons, filters, and indicators |
| `--surface` | Background tint behind the status |
| `--onSurface` | Text or icon placed on the status surface |

## Brand

| Token | Light value | Dark value | Use |
| --- | --- | --- | --- |
| `--color-brand` | `var(--color-base-lime--500)` | `var(--color-base-lime--500)` | Brand visual language and brand accents |
| `--color-brand--highlight` | `#85eb00` | `#85eb00` | Bright highlight; use sparingly |

## Status

| Token | Light value | Dark value | Meaning |
| --- | --- | --- | --- |
| `--color-critical` | `var(--color-base-red--600)` | `var(--color-base-red--500)` | Action required to unblock the user |
| `--color-critical--surface` | `var(--color-base-red--200)` | `var(--color-base-red--900)` | Critical status background |
| `--color-critical--onSurface` | `var(--color-base-red--800)` | `var(--color-base-red--300)` | Text/icon on a critical surface |
| `--color-warning` | `var(--color-base-yellow--400)` | `var(--color-base-yellow--400)` | Action may be required |
| `--color-warning--surface` | `var(--color-base-yellow--200)` | `var(--color-base-yellow--700)` | Warning status background |
| `--color-warning--onSurface` | `var(--color-base-yellow--700)` | `var(--color-base-yellow--200)` | Text/icon on a warning surface |
| `--color-success` | `var(--color-base-green--600)` | `var(--color-base-green--500)` | Successful completion; no action required |
| `--color-success--surface` | `var(--color-base-green--200)` | `var(--color-base-green--800)` | Success status background |
| `--color-success--onSurface` | `var(--color-base-green--800)` | `var(--color-base-green--300)` | Text/icon on a success surface |
| `--color-informative` | `var(--color-base-lightBlue--500)` | `var(--color-base-lightBlue--600)` | Helpful information; no action required |
| `--color-informative--surface` | `var(--color-base-lightBlue--200)` | `var(--color-base-lightBlue--800)` | Informative status background |
| `--color-informative--onSurface` | `var(--color-base-lightBlue--700)` | `var(--color-base-lightBlue--300)` | Text/icon on an informative surface |
| `--color-inactive` | `var(--color-base-blue--700)` | `var(--color-base-blue--500)` | Not part of an active workflow |
| `--color-inactive--surface` | `var(--color-base-blue--200)` | `var(--color-base-blue--700)` | Inactive status background |
| `--color-inactive--onSurface` | `var(--color-base-blue--900)` | `var(--color-base-blue--200)` | Text/icon on an inactive surface |

Do not use color as the only way to communicate status. Pair it with text,
icons, labels, or accessible descriptions.

## Interactions

| Token | Light value | Dark value | Use |
| --- | --- | --- | --- |
| `--color-interactive` | `var(--color-base-green--600)` | `#8acc33` | Default interactive and CTA color |
| `--color-interactive--hover` | `var(--color-base-green--700)` | `#a1d65c` | Hover state of the default interactive color |
| `--color-interactive--subtle` | `var(--color-base-blue--800)` | `var(--color-base-blue--200)` | Less prominent actions and navigation icons |
| `--color-interactive--subtle--hover` | `var(--color-base-blue--900)` | `var(--color-base-blue--100)` | Hover state for subtle interaction |
| `--color-interactive--background` | `var(--color-base-taupe--300)` | `var(--color-base-blue--700)` | Interactive background separated from its surface |
| `--color-interactive--background--hover` | `var(--color-base-taupe--400)` | `var(--color-base-blue--600)` | Hover state of an interactive background |
| `--color-interactive--background--subtle--hover` | `var(--color-base-green--200)` | `var(--color-base-green--800)` | Subtle interactive background hover |
| `--color-destructive` | `var(--color-base-red--600)` | `var(--color-base-red--500)` | Interaction that destroys or removes data |
| `--color-destructive--hover` | `var(--color-base-red--700)` | `var(--color-base-red--400)` | Hover state of a destructive action |
| `--color-disabled` | `var(--color-base-grey--500)` | `var(--color-base-grey--500)` | Disabled text, icons, or controls |
| `--color-disabled--secondary` | `var(--color-base-grey--200)` | `var(--color-base-grey--700)` | Secondary disabled color, such as a control background |
| `--color-focus` | `var(--color-base-blue--500)` | `var(--color-base-blue--500)` | Focus ring color; use through `--shadow-focus` |

When an interactive color is used as a filled background, use
`var(--color-surface)` for the label/icon unless a more specific contrast token
is defined.

## Surfaces and overlays

| Token | Light value | Dark value | Use |
| --- | --- | --- | --- |
| `--color-surface` | `var(--color-white)` | `var(--color-base-blue--900)` | Default element surface: cards, fields, and controls |
| `--color-surface--hover` | `var(--color-base-taupe--200)` | `var(--color-base-blue--800)` | Hovered surface |
| `--color-surface--active` | `var(--color-base-taupe--300)` | `var(--color-base-blue--700)` | Pressed or active surface |
| `--color-surface--background` | `var(--color-base-taupe--200)` | `var(--color-base-blue--1000)` | Receded page or section background |
| `--color-surface--background--hover` | `var(--color-base-taupe--300)` | `var(--color-base-blue--800)` | Hovered receded background |
| `--color-surface--background--subtle` | `var(--color-base-taupe--100)` | `var(--color-base-blue--800)` | Background distinct from the main surface |
| `--color-surface--background--subtle--hover` | `var(--color-base-taupe--300)` | `var(--color-base-blue--600)` | Hovered subtle background |
| `--color-surface--reverse` | `var(--color-base-blue--900)` | `var(--color-base-taupe--200)` | Strong-contrast reversed surface |
| `--color-overlay` | `rgba(var(--color-black--rgb), 0.32)` | `rgba(var(--color-black--rgb), 0.6)` | Mask behind foreground actions such as modals |
| `--color-overlay--dimmed` | `rgba(var(--color-white--rgb), 0.6)` | `rgba(var(--color-black--rgb), 0.4)` | Indicates inactivity or waiting |

## Text and icons

| Token | Light value | Dark value | Use |
| --- | --- | --- | --- |
| `--color-heading` | `var(--color-base-blue--900)` | `var(--color-base-blue--100)` | High-contrast headings |
| `--color-text` | `var(--color-base-blue--800)` | `var(--color-base-blue--200)` | Default body text |
| `--color-text--secondary` | `var(--color-base-blue--700)` | `var(--color-base-blue--400)` | Less important text when primary text is present |
| `--color-text--reverse` | `var(--color-white)` | `var(--color-base-blue--700)` | Text on a reversed surface |
| `--color-text--reverse--secondary` | `var(--color-base-blue--300)` | `var(--color-base-blue--900)` | Secondary text on a reversed surface |
| `--color-icon` | `var(--color-base-blue--800)` | `var(--color-base-blue--200)` | Default icon color |
| `--color-icon--secondary` | `var(--color-base-blue--500)` | `var(--color-base-blue--600)` | Less prominent icon color |

Do not use brand, status, or accent colors for long-form body copy.

## Borders

| Token | Light value | Dark value | Use |
| --- | --- | --- | --- |
| `--color-border` | `var(--color-base-blue--300)` | `var(--color-base-blue--700)` | Default subtle definition between elements |
| `--color-border--interactive` | `var(--color-base-blue--300)` | `var(--color-base-blue--500)` | Interactive borders requiring accessible contrast |
| `--color-border--section` | `var(--color-base-blue--900)` | `var(--color-base-blue--400)` | Table headers, list sections, and stronger dividers |

## Workflow colors

Use workflow colors only on elements directly related to the corresponding
workflow item. Every item follows the main, surface, and on-surface pattern.

| Token family | Light main / surface / on-surface | Dark main / surface / on-surface |
| --- | --- | --- |
| `--color-request` | `var(--color-base-orange--600)` / `var(--color-base-orange--200)` / `var(--color-base-orange--800)` | `var(--color-base-orange--500)` / `var(--color-base-orange--800)` / `var(--color-base-orange--300)` |
| `--color-quote` | `var(--color-base-pink--700)` / `var(--color-base-pink--200)` / `var(--color-base-pink--800)` | `var(--color-base-pink--500)` / `var(--color-base-pink--800)` / `var(--color-base-pink--300)` |
| `--color-job` | `var(--color-base-green--600)` / `var(--color-base-green--200)` / `var(--color-base-green--700)` | `var(--color-base-green--500)` / `var(--color-base-green--800)` / `var(--color-base-green--200)` |
| `--color-visit` | Alias of `--color-job` | Alias of `--color-job` |
| `--color-invoice` | `var(--color-base-lightBlue--700)` / `var(--color-base-lightBlue--200)` / `var(--color-base-lightBlue--800)` | `var(--color-base-lightBlue--500)` / `var(--color-base-lightBlue--800)` / `var(--color-base-lightBlue--300)` |
| `--color-payments` | Alias of `--color-invoice` | Alias of `--color-invoice` |
| `--color-task` | `var(--color-base-lightBlue--800)` / `var(--color-base-blue--200)` / `var(--color-base-blue--800)` | `var(--color-base-blue--500)` / `var(--color-base-blue--700)` / `var(--color-base-blue--300)` |
| `--color-event` | `var(--color-base-yellow--400)` / `var(--color-base-yellow--200)` / `var(--color-base-yellow--700)` | `var(--color-base-yellow--400)` / `var(--color-base-yellow--700)` / `var(--color-base-yellow--200)` |
| `--color-client` | `var(--color-base-taupe--700)` / `var(--color-base-taupe--200)` / `var(--color-base-taupe--800)` | `var(--color-base-blue--200)` / `var(--color-base-blue--800)` / `var(--color-base-blue--300)` |

## Data visualization

Use categorical tokens to distinguish unrelated chart series. They respond to
the active theme and should be preferred over base colors.

| Token | Light value | Dark value |
| --- | --- | --- |
| `--color-dataViz--categorical--1` | `var(--color-base-purple--700)` | `var(--color-base-purple--500)` |
| `--color-dataViz--categorical--1--subtle` | `var(--color-base-purple--500)` | `var(--color-base-purple--600)` |
| `--color-dataViz--categorical--1--bold` | `var(--color-base-purple--800)` | `var(--color-base-purple--300)` |
| `--color-dataViz--categorical--2` | `var(--color-base-teal--500)` | `var(--color-base-teal--500)` |
| `--color-dataViz--categorical--3` | `var(--color-base-orange--500)` | `var(--color-base-orange--500)` |

## Utility tokens

| Token | Value | Use |
| --- | --- | --- |
| `--color-white` | `rgba(var(--color-white--rgb), 1)` | Pure white |
| `--color-black` | `rgba(var(--color-black--rgb), 1)` | Pure black |
| `--color-base-white` | Alias of `--color-white` | Palette primitive |
| `--color-base-black` | Alias of `--color-black` | Palette primitive |

## Base palette

Base colors are raw primitives and do not respond to semantic theme changes.
Do not use them directly in component code. The available ramps are:

`grey`, `taupe`, `red`, `green`, `blue`, `yellow`, `lime`, `lightBlue`,
`pink`, `orange`, `teal`, and `purple`, each from `--100` through `--1000`.

## Prohibited

- Do not use raw hex, RGB, or RGBA values in component code.
- Do not manually swap light and dark values in components.
- Do not use brand or accent backgrounds for large layout surfaces except for a deliberate hero or campaign area.
- Do not use accent colors for body copy or navigation text.
- Do not use a status color without an accompanying semantic cue such as text, an icon, or an accessible label.
