# Cards

> Dependencies: `colors.md`, `radius.md`, `shadows.md`, `typography.md`

## Core Specs

- **Background:** neutral-primary-soft
- **Border:** 1px, border-default color
- **Radius:** 8px (base)
- **Shadow:** shadow-xs

## Card Heading

- Desktop: 20px, medium weight, heading color
- Mobile: 16px, medium weight, heading color
- **Max font size: 20px** — card headings must never exceed 20px regardless of heading level or breakpoint.
- Never skip heading levels — the page hierarchy must logically arrive at the card heading level.

## States

### Static Card (no interactivity)
- Background: neutral-primary-soft
- Border: 1px, border-default
- Radius: 8px
- Shadow: shadow-xs
- No hover styles. Non-interactive cards must NOT have hover background changes.

### Interactive Card (clickable)
- Same base styles as static card
- Hover: neutral-secondary-medium background
- Transition: colors
- Cursor: pointer

## Rules

- Background: neutral-primary-soft
- Border: 1px, border-default
- Radius: 8px
- Shadow: shadow-xs
- Interactive hover: neutral-secondary-medium background
- Non-interactive: no hover styles
