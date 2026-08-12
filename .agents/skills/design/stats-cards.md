# Stats Cards

> CRM-specific. Dependencies: `cards.md`, `colors.md`, `typography.md`, `badges.md`

Stats cards (KPI cards) appear in the dashboard header row and on module summary pages. They display a primary metric, trend indicator, and optional supporting context.

---

## Anatomy

```
┌─────────────────────────────────────────┐
│  Label text             [↗ Arrow icon]  │
│                                         │
│  44                                     │  ← Primary value
│                                         │
│  ↑ 8%  Increased from last month       │  ← Trend line
└─────────────────────────────────────────┘
```

---

## Variants

### Standard Stat Card
- Base card styles from `cards.md`
- Padding: `$space-5` (20px)
- **Label:** `$fs-body`/`var(--text-body)` (14px), `var(--color-text-secondary)`, medium
- **Value:** 44px (near `$fs-display` 48px / `$fs-h1` 36px), semibold, `var(--color-text-primary)` *(see Typography — Numeric Data)*
- **Supporting context:** 14px / `var(--typography--fontSize-base)`, `var(--color-text--secondary)`, regular
- **Trend:** 13px (~`$fs-caption`), medium + icon 14×14px
- **Dashboard article variant:** when the stat card is rendered as an `<article>` in the owner dashboard, use no shadow while retaining the border, radius, and surface treatment.
- **Link icon (↗):** `$space-5` (20px) ghost button, top-right, `var(--color-text-secondary)` → `var(--color-text-primary)` on hover

### Featured Stat Card (Primary KPI — brand green background)
Use for the most important metric on the page (e.g., Total Projects, Total Revenue).
- Background: `var(--color-brand)` (theme-aware — light/dark automatically via token)
- Border: transparent
- Shadow: `$shadow-sm`
- **Label:** `$fs-body`/`var(--text-body)` (14px), `var(--color-text-on-brand-soft)`, medium
- **Value:** 44px (near `$fs-display` 48px / `$fs-h1` 36px), semibold, white
- **Trend text:** 13px (~`$fs-caption`), `var(--color-text-on-brand-soft)`
- **Supporting context:** 14px / `var(--typography--fontSize-base)`, `var(--color-text--reverse--secondary)`, regular
- **Trend icon:** white
- **Link icon:** white, 50% opacity → full on hover

### Compact Stat Card
For tighter grids (e.g., inline summary rows within module pages):
- Padding: `$space-4` (16px)
- Value: `$fs-h2`/`var(--text-h2)` (24px), semibold, `var(--color-text-primary)`
- Label: 13px (~`$fs-caption`), `var(--color-text-secondary)`
- No trend line

### Mini Stat (Inline / Widget)
For sidebar widgets or inline summary bars:
- No card border, no shadow (borderless)
- Value: `$fs-h3`/`var(--text-h3)` (20px), semibold, `var(--color-text-primary)`
- Label: `$fs-caption`/`var(--text-caption)` (12px), `var(--color-text-muted)`
- Stacked: value on top, label below

---

## Trend Indicator

Shows change vs prior period (last month / last week).

| Direction | Icon | Text color | Icon color |
|---|---|---|---|
| Up positive | ↑ arrow | `var(--success-solid)` | `var(--success-text)` |
| Down negative | ↓ arrow | `var(--danger-solid)` | `var(--danger-text)` |
| Neutral | → arrow | `var(--color-text-secondary)` | `var(--color-text-secondary)` |
| Up negative (cost) | ↑ arrow | `var(--danger-solid)` | `var(--danger-text)` |

Format: `↑ 8% · Increased from last month` or `↓ 3% · 2 fewer than last week`

Trend area:
- Flex row, 4px gap
- Icon + percentage: colored per direction
- Description text: `var(--color-text-secondary)` (or `var(--color-text-on-brand-subtle)` on featured card)

---

## Dashboard Stats Row Layout

Four stat cards in a row, `$space-6` (24px) gap:
- Card 1: **Featured** (brand green bg) — primary metric e.g. Total Jobs
- Cards 2–4: **Standard** — secondary metrics e.g. Active, Completed, Pending

Responsive: 2 columns on tablet, 4 on desktop. Featured card can span 2 cols on mobile.

---

## CRM KPI Examples

| Module | Primary KPI | Secondary KPIs |
|---|---|---|
| Dashboard | Total Projects | Active · Completed · Pending |
| Clients | Total Clients | Active · New This Month · At Risk |
| Invoices | Total Revenue | Outstanding · Overdue · Paid This Month |
| Time Tracking | Total Hours (month) | Billable · Non-Billable · This Week |
| Team | Team Members | Active · Subcontractors · Utilization % |

---

## Rules

- Maximum one Featured card per stats row
- Never use Featured card style for anything other than the primary KPI
- Value text must always be the largest element in the card (44px desktop, 30px mobile)
- Trend direction color must be semantically accurate (up cost = danger, not success)
- Always include aria-label on the link icon describing where it navigates
