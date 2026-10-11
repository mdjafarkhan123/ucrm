# Layout & Spacing

Its a desktop web app. Mobile priority is not first

## Spacing Tokens

Spacing is expressed with the `--space-*` token scale. Use tokens, never raw values, for any layout measure.

| Token                 | Value |
| --------------------- | ----- |
| `--space-minuscule`   | 1px   |
| `--space-smallest`    | 2px   |
| `--space-smaller`     | 4px   |
| `--space-small`       | 8px   |
| `--space-slim`        | 12px  |
| `--space-base`        | 16px  |
| `--space-large`       | 24px  |
| `--space-larger`      | 32px  |
| `--space-largest`     | 48px  |
| `--space-extravagant` | 64px  |

## Proximity rule

The closer two elements are related, the tighter the spacing between them:

| Relationship                              | Token                 | Value |
| ----------------------------------------- | --------------------- | ----- |
| Separate sibling items in a row           | `--space-small`       | 8px   |
| Optical adjustment (not standard)         | `--space-smaller`     | 4px   |
| Icon ↔ label inside a control             | `--space-smaller`     | 4px   |
| Chips in a selection group                | `--space-small`       | 8px   |
| When `small` feels tight, `base` too much | `--space-slim`        | 12px  |
| Default gap in content containers         | `--space-base`        | 16px  |
| Parent-level containers                   | `--space-large`       | 24px  |
| Distinguish two groups                    | `--space-larger`      | 32px  |
| Content-rich hierarchy                    | `--space-largest`     | 48px  |
| Low-density / hero sections               | `--space-extravagant` | 64px  |

- Smallest allowed on desktop: `--space-smallest` (2px)
- `--space-minuscule` (1px) is reserved for one-off optical fixes, never grid rhythm

## Layout Rhythm Reference

| Context                      | Token                 | Value |
| ---------------------------- | --------------------- | ----- |
| Section vertical padding     | `--space-extravagant` | 64px  |
| Section header → content     | `--space-largest`     | 48px  |
| Heading → paragraph          | `--space-base`        | 16px  |
| Container horizontal padding | `--space-large`       | 24px  |
| Flex/grid row gap            | `--space-base`        | 16px  |
| Card grid gap (desktop)      | `--space-large`       | 24px  |
| Card grid gap (mobile)       | `--space-base`        | 16px  |
| Wide component grid gap      | `--space-larger`      | 32px  |
| Column layout gap            | `--space-largest`     | 48px  |

## Breakpoints

| Name        | Width    | Media query                                  |
| ----------- | -------- | -------------------------------------------- |
| Extra small | < 490px  | `@custom-media --small-screens-and-below`    |
| Small       | ≥ 490px  | `@custom-media --small-screens-and-up`       |
| Medium      | ≥ 768px  | `@custom-media --medium-screens-and-up`      |
| Large       | ≥ 1080px | `@custom-media --large-screens-and-up`       |
| Extra large | ≥ 1440px | `@custom-media --extra-large-screens-and-up` |

Responsive slots: `xs` (0), `sm` (490), `md` (768), `lg` (1080), `xl` (1440).

## Container

CRM sections are **full width** (`width: 100%`), not capped. Every major section wraps content in a full-bleed container with horizontal padding `var(--space-large)` (24px).

Breakpoint rules:

- Mobile: padding drops to `var(--space-base)` (16px)
- Medium and up: padding is `var(--space-large)` (24px)

Only narrow, reading-focused blocks (forms, confirm dialogs) cap their width — reading `max-width: 640px`, dialogs `max-width: 480px`.

## Page Widths

| Page type       | Max width | Use for                                   |
| --------------- | --------- | ----------------------------------------- |
| Fill            | 100%      | Dashboards, data tables, calendars        |
| Standard        | 1280px    | Multi-column "show" layouts               |
| Narrow          | single-column | Forms, single-column content          |

## Content Composition Order

Inside each section follow:

1. Heading (`h1`–`h3`)
2. Leading paragraph
3. Normal paragraph(s)
4. Lists, CTA links, or component grids

Separate items with `--space-base` (16px); separate groups with `--space-largest` (48px).

## Section Pattern

Each section has:

- Vertical padding `var(--space-extravagant)` (64px)
- A background that alternates between `--color-surface--background` and `--color-surface--background--subtle`
- A full-width container (`width: 100%`, padding `var(--space-large)`)
- A section header with bottom margin `var(--space-largest)` (48px)
- Section content below, gap `var(--space-larger)` (32px)

## Motion & Animation

- Prefer CSS-native `transition` / `animation` / `@keyframes`
- Use timing tokens: `--timing-quick` (0.1s) for micro-interactions, `--timing-base` (0.2s) for standard, `--timing-slow` (0.3s)+ for larger/orchestrated moments
- Prioritize high-impact orchestrated moments over scattered micro-interactions. A single well-sequenced page-load animation using staggered `animation-delay` delivers more perceived quality than many isolated effects.
- Reserve scroll-triggered and hover transitions for moments that reinforce hierarchy or reward attention.

## Backgrounds & Visual Depth

- Default to clean, flat solid backgrounds (`--color-surface`, `--color-surface--background`) suited to data-dense dashboard layouts
- Use subtle `--color-border` separators and `--shadow-base` card elevation for hierarchy — avoid gradient meshes, noise textures, or decorative overlays
- Every visual treatment must serve a purpose (grouping, separation, status). No ornamental effects competing with data readability

## Must

- All sections: consistent `var(--space-extravagant)` (64px) vertical padding
- All containers: full width, `var(--space-large)` horizontal padding
- Section headers: `var(--space-largest)` (48px) bottom margin
- Consistent vertical rhythm (via `--space-*` tokens), no crowded sections
- Layouts readable and properly spaced on both desktop (≥ 1080px) and mobile (< 490px)
