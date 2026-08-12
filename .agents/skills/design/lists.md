# Lists

> Dependencies: `colors.md`, `typography.md`, `radius.md`

## Core Specs

- **Root element:** `<ul>` with `--space-base` (16px) horizontal padding, reset margin/padding/list-style
- **Item spacing:** 16px vertical padding (`--space-small`) per item via inner content wrapper
- **Divider:** 1px bottom border (`var(--border-base)` solid `var(--color-border)`) on every item except last
- **Text:** default content uses `--color-text`

## List Icons

- **Size:** 24×24px (`var(--space-large)`)
- **Prevent squishing:** `flex: 0 0 auto` on icon wrapper, `box-sizing: content-box`
- **Spacing:** 8px (`var(--space-small)`) gap between icon and text — from flex alignment, not a margin
- **Active/featured icon:** uses `iconColor` prop mapped to `--color-*` token (icon receives `color` prop from Icon component)
- **Neutral icon:** `--color-icon` (default when no iconColor prop)

## Inactive / Disabled Items

When `isActive={true}` is set on a ListItem, the inner content receives `background-color: var(--color-surface--background)` (taupe tint) to highlight items that need attention.

## Sectioned Lists

- **Section header:** `<div>` wrapper — `position: sticky; top: 0`, padding `var(--space-small) var(--space-base)` (8px 16px), `border-bottom: var(--border-base) solid var(--color-border--section)`
- **Section spacing:** `padding-bottom: 24px (var(--space-large))` between section groups
- **Section title:** Heading level 5, `fontWeight: "bold"`, `size: "large"`

## ListItem Anatomy

```
ul.list                           reset margin/padding, list-style:none
└── li.item:not(:last-child)      1px bottom border: var(--color-border)
    └── button|a (action)         transparent bg, border:none, cursor:pointer
        └── div (content)         padding: var(--space-small) (8px); flex, flex:1
            ├── div (icon)        flex:0 0 auto, 24×24px, box-sizing:content-box
            │   └── Icon          name + iconColor props
            ├── div (info)        flex:1 1 auto, align-self:center, min-width:0
            │   ├── Heading lv5  (title, if present)
            │   ├── span          truncate ellipsis; caption: Text subdued + italic small
            │   └── div (amount)  flex:0 0 auto, text-align:right, bold emphasis (value)
```

## Pattern

Vertical `<ul>` list. Each item is a flex row — icon wrapper (24×24, no-shrink) followed by a content area (8px padding, flex:1). Divider between items via 1px `--color-border` bottom border. Active state: `--color-surface--background` tint on the content area. Section headers stick to top with `--color-border--section` divider.
