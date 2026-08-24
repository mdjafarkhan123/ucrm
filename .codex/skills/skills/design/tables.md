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

## Row activation

A list table whose rows stand for a record opens that record when the row is clicked. Pass `onRowActivate`
to `DataTable` and the row takes `cursor: pointer` and the existing hover tint.

- The first cell also carries a real `<a>` to the same record. That link is the keyboard path and the
  middle-click / open-in-new-tab path; the row click is mouse convenience on top of it.
- Row activation deliberately ignores clicks on controls inside the row — checkbox, actions menu, any link
  or button — and ignores a click that was really a drag to select text.
- The row itself never becomes a tab stop, so keyboard users get one stop per row, not two.
- Wire `onRowActivate` only when its destination exists. A row that looks clickable and goes nowhere is
  worse than a row that does not invite the click.

## Row selection

A `selectable` table puts a checkbox on every row. Always pass `rowLabel` alongside it, returning the name of
the record that row stands for — `rowLabel={(client) => `Select ${client.display_name}`}`. Without it every
checkbox on the page is called "Select row" and a screen reader user cannot tell which one they are ticking.

## Rules

- Wrapper must have horizontal scroll overflow for responsive scrolling
- Last row: omit bottom border to avoid doubling with wrapper border
- Row headers: always `scope="row"` for semantic structure
- Hover on rows is optional
- No arbitrary hex codes — use token colors only
