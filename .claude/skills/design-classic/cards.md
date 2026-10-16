# Cards

> Dependencies: `colors.md`, `radius.md`,  `typography.md`

## Core Specs

- **Background:** `var(--color-surface)`
- **Border:** 1px solid `var(--color-border)`
- **Radius:** `var(--radius-base)` = 8px

Dashboard metric cards rendered as semantic `<article>` elements may omit the shadow when a flatter summary treatment is explicitly approved for that surface.

## Card Heading

- Desktop: 20px, medium weight, heading color
- Mobile: 16px, medium weight, heading color
- **Max font size: 20px** — card headings must never exceed 20px regardless of heading level or breakpoint.
- Never skip heading levels — the page hierarchy must logically arrive at the card heading level.

## States

### Static Card (no interactivity)

- Background: var(--color-surface)
- Border: 1px, border-default
- Radius: 8px
- No hover styles. Non-interactive cards must NOT have hover background changes.

### Interactive Card (clickable)

- Same base styles as static card
- Hover: neutral-secondary-medium background
- Transition: colors
- Cursor: pointer

## Rules

- Background: neutral-primary-soft
- Border: 1px, var(--color-border)
- Radius: 8px
- Interactive hover: neutral-secondary-medium background
- Non-interactive: no hover styles
