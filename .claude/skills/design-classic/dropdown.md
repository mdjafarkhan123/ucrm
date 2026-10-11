# Dropdown

> Dependencies: `colors.md`, `radius.md`, `shadows.md`, `inputs.md`

## Core Specs

### Chevron Icon

- Size: 16x16px
- Spacing: 6px left margin, -2px right margin
- Color: inherits from trigger button

### Menu Container

- Background: var(--color-surface)
- Border: 1px, var(--color-border)
- Radius: 8px, (--radius-base)
- Shadow:8px, --shadow-base
- Z-index: --elevation-modal

### Menu List

- Padding: 8px
- Font: 14px, body color, medium weight

### Menu Item

- Layout: inline-flex, vertically centered, full width
- Padding: 8px horizontal, 8px vertical
- Radius: 8px (--radius-base)
- Hover: background --color-surface-hover, heading text
- Transition: colors, 150ms

## Trigger Sizes

| Size  | Font size | Horizontal padding | Vertical padding |
| ----- | --------- | ------------------ | ---------------- |
| Small | 14px      | 12px               | 8px              |
| Base  | 14px      | 16px               | 10px             |
| Large | 16px      | 20px               | 12px             |

## Icon-only Trigger

- Padding: 8px
- Min size: 44x44px
- Icon: 20x20px

## Variants

### Default

- Menu width: 176px, items have 8px radius

### With Divider

- Top border (border-default) between child groups, skip first group

### With Header

- Header padding: 16px horizontal, 12px vertical
- Bottom border: border-default
- Name: heading color, 14px, semibold weight
- Email: body-subtle color, 14px, truncated

### With Icons

- Icon before label: 16x16px, 8px right margin, body color
- On hover, icon color changes to heading

### With Checkbox / Radio

- Inputs: 16x16px, 4px radius, focus ring in brand-soft
- Helper text: 12px, body-subtle color, 2px top margin

### With Search

- Search input at top of menu following `inputs.md` specs
- Left icon: 12px left padding, input 36px left padding

### Scrollable

- Max height: 192px, vertical scroll overflow

## States

| State            | Appearance                                                   |
| ---------------- | ------------------------------------------------------------ |
| Focused trigger  | no outline, 2px brand ring                                   |
| Hover item       | --color-surface-hover background, heading text               |
| Active/open item | --color-surface-active background, heading text              |
| Disabled item    | --color-disabled text, not-allowed cursor, no pointer events |

## Filter chip (toolbar filters)

A filter that sits in a toolbar row beside a search box uses `ui/FilterChip.svelte`, never a full-width
`Select` in a hand-made pill. It follows the Stripe and Linear pattern:

- The chip is only as wide as its own words. Its open list is as wide as its longest option.
- Resting (the value that means "not filtering"): the filter's name and a chevron, border
  `--color-border--interactive`, background `--color-surface`.
- Filtering: name in secondary text, value in semibold, border `--color-interactive`, background
  `--color-surface--active`, and a cross in place of the chevron that puts the filter back to rest.
- A control that always has an answer (a sort order) leaves `restValue` out: it shows its value and never
  highlights.
- Height 44px, radius `--radius-base`, so it lines up with `SearchInput` and `SegmentedControl`.

A filter panel that drops open under a list's search box still uses `FilterBar` + `FilterField`.
