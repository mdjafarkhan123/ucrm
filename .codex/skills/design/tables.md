# Tables

> Dependencies: `colors.md`, `radius.md`

## Wrapper

- Horizontal scroll overflow
- Background: var(--color-surface)
- Radius: 8px var(--radius-base)
- Border: 1px, var(--color-border)

## Table Element

- Full width, left-aligned text (right-aligned for RTL)
- Font: 14px, var(--color-text)

## Table Head

- Font: 14px, var(--color-text), bold weight
- Background: var(--color-surface--background--subtle)
- Bottom border: border-default
- Cell padding: 24px horizontal, 12px vertical

## Table Body

- Row background: var(--color-surface)
- Row bottom border: border-default (omit on last row to avoid doubling with wrapper border)
- Row hover: var(--color-surface-hover) (optional)
- Row header: bold weight, text color, no-wrap
- Cell padding: 24px horizontal, 16px vertical

## Rules

- Wrapper must have horizontal scroll overflow for responsive scrolling
- Last row: omit bottom border to avoid doubling with wrapper border
- Row headers: always `scope="row"` for semantic structure
- Hover on rows is optional
- No arbitrary hex codes — use token colors only
