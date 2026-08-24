# Content & Grid System

> Dependencies: `layout.md`, `typography.md`

## Containers

| Type                       | Max width  | Horizontal padding |
| -------------------------- | ---------- | ------------------ |
| App content (with sidebar) | Full width | 24–32px            |
| Reading / forms            | 640px      | —                  |
| Narrow (confirm dialogs)   | 480px      | —                  |

## Grid System

Flexible grid.

| Context             | Gap         | Columns (mobile → desktop) |
| ------------------- | ----------- | -------------------------- |
| KPI stat cards      | 16px → 24px | 2 → 4                      |
| Dashboard panels    | 24px        | 1 → 2 → 3                  |
| Compact widgets     | 16px        | variable                   |
| Full-width sections | 0           | 1                          |

### Responsive Columns

| Breakpoint            | Columns |
| --------------------- | ------- |
| Mobile (default)      | 1–2     |
| Small/Tablet (≥640px) | 2–4     |
| Desktop (≥1024px)     | 3–12    |

Full support for 6, 7, 8, 9+ column grids where needed.

## Breakpoints

| Name        | Width  |
| ----------- | ------ |
| Small       | 640px  |
| Medium      | 768px  |
| Large       | 1024px |
| Extra large | 1280px |
| 2XL         | 1536px |

## Rules

- Always design Desktop-first
- Use layout shifts (stack → row) at md and lg breakpoints
- Lists: 24px indentation, 8px vertical item gap
- Body copy: 16px, var(--typography--lineHeight-large) line-height, max-width 65ch
- Interactive links: `var(--color-brand)` color, underline, hover → no underline
- All interactive links follow brand underline/hover protocol
