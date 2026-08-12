# Sidebars

> Dependencies: `colors.md`, `radius.md`, `typography.md`, `badges.md`, `alerts.md`

## Core Specs

- Background: `var(--color-surface--background)`
- Right border: `var(--border-base)` solid `var(--color-border)` (for left-sidebar); left border for right-sidebar
- Width: 256px

## Anatomy

### Outer Container

Hidden on mobile, visible at small breakpoint. Needs a toggle/trigger for mobile.

### Inner Wrapper

- Full height, vertical scroll overflow
- Padding: `var(--space-slim)` horizontal (12px), `var(--space-base)` vertical (16px)

### Navigation List

- Vertical spacing: `var(--space-small)` (8px) between items
- Font weight: medium

### Navigation Item

- Layout: flex, vertically centered
- Padding: `var(--space-small)` horizontal (8px), `var(--space-small)` vertical (8px)
- Text: `var(--color-heading)`
- Radius: `var(--radius-base)` (8px)
- Hover: `var(--color-surface--hover)` background
- Transition: `all var(--timing-base) ease-out`
- Icon: 20x20px, `var(--color-icon)`, hover → `var(--color-heading)`, 75ms transition
- Label: `var(--space-slim)` (12px) left margin from icon

### Active Item

- Background: `var(--color-surface--active)`
- Text: `var(--color-interactive)`
- Active indicator: 3px left border `var(--color-brand)` (see `borders.md`)

### Separator

- Padding-top: `var(--space-base)` (16px); Margin-top: `var(--space-base)` (16px)
- Top border: `var(--border-base)` solid `var(--color-border)`
- Vertical spacing below: `var(--space-small)` (8px)

### Bottom CTA / Card

- Padding: `var(--space-base)` (16px)
- Margin-top: `var(--space-large)` (24px)
- Radius: `var(--radius-base)` (8px)
- Background: `var(--color-interactive--background--subtle--hover)`
- Can also use any alert variant from `alerts.md`

## Rules

- Responsive: hidden on mobile with a trigger mechanism
- Icons: 20x20px, `var(--color-icon)` (hover: `var(--color-heading)`)
- Multi-level menus: indent with 44px left padding
- Spacing follows 8px grid
- Only neutral, brand, or status tokens — no arbitrary colors