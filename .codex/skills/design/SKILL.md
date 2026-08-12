---
name: design
description: UpliftContractor Design skill for AI coding agents
metadata:
    author: Jafar khan
    projectName: Uplift Contractor
    primaryColor: "var(--color-brand)"
    typographyScale: Inter, rem @ 1rem=10px (html 62.5%), Jobber Atlantis 12/14/16/20/24/36/48px — semibold headings, unitless tight line-heights
    spacingScale: "4px base grid: 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64, 80px"
    radiusScale: "6px controls, 8px cards, 12px overlays, nested radii reduced by inner padding."
    scss: src/lib/styles/_variables.scss ($ vars + var(--color-*) theme) + app.scss (base); this skill mirrors them
---

# Design System - Agent Instructions

This skill describes the visual design language for all UI output. Every component, layout, and page should follow the design specs in the module files below. These describe _what the design looks like_ — you choose how to implement the styles.

## Style

A professional dashboard interface with clean grid layouts, data-dense card panels, and a structured information hierarchy optimized for monitoring and management workflows

---

## Before Writing Any Code

1. **Read every module that applies.** For a landing page, read at minimum: `layout.md`, `typography.md`, `colors.md`, `buttons.md`, `cards.md`, `shadows.md`, `radius.md`, `borders.md`. Do NOT write JSX until you have loaded all relevant modules.

---

## Critical Rules

> **This skill documents the LIVE app tokens** in `src/lib/styles/_tokens.scss` + `app.scss`. The `scss/` folder here mirrors them 1:1. When you change a token in the app, update this skill in the same turn (`feedback-sync-tokens-to-skill` rule).

- **Brand color precedence:** When `brand.md` is available, color tokens from `brand.md` overwrite same-name tokens in `colors.md`.

- **Cross-reference modules.** A card containing buttons must satisfy both `cards.md` AND `buttons.md`.

- **Tokens are NOT Tailwind classes.** Colors are semantic CSS custom properties: `var(--color-bg-surface)`, `var(--color-border)`, `var(--color-text-primary)`, `var(--color-brand)`, `var(--success-solid)`, etc. See `colors.md` for the full contract.

- Dark mode is **automatic** via `_theme.scss` (mirrors the app's `dark-theme-tokens` mixin). Never manually swap color values.

- Toggle: set `data-theme="dark"` on `<html>` (explicit in-app choice); OS `prefers-color-scheme` is respected when no explicit choice is set.

- **Every interactive element needs hover, focus, and disabled states** — defined in the relevant module.

- **Use semantic HTML:** proper heading hierarchy (`h1`→`h6`), `<button>` for actions, `<a>` for navigation, ARIA attributes where needed.

## Module Index

### Foundation (read first for any UI work)

- [brand.md](brand.md) — Brand
- [colors.md](colors.md) — Color
- [typography.md](typography.md) — Typography
- [layout.md](layout.md) — Layout
- [radius.md](radius.md) — Radius
- [shadows.md](shadows.md) — Shadow
- [borders.md](borders.md) — Borders

### Core Components

- [buttons.md](buttons.md) — Button
- [button-group.md](button-group.md) — Button Group
- [cards.md](cards.md) — Card
- [inputs.md](inputs.md) — Input
- [alerts.md](alerts.md) — Alert
- [badges.md](badges.md) — Badge
- [lists.md](lists.md) — List
- [avatars.md](avatars.md) — Avatar
- [icon-shapes.md](icon-shapes.md) — Icon Shape
- [accordion.md](accordion.md) — Accordion
- [dropdown.md](dropdown.md) — Dropdown
- [modals.md](modals.md) — Modal
- [tabs.md](tabs.md) — Tabs
- [tables.md](tables.md) — Table
- [pagination.md](pagination.md) — Pagination
- [sidebars.md](sidebars.md) — Sidebar
- [radios-checkboxes-toggle.md](radios-checkboxes-toggle.md) — Radio, Checkbox,
- [tooltips-popovers.md](tooltips-popovers.md) - Tooltips and popovers
- [content.md](content.md) - Content grid and layout system

### CRM-Specific Components

- [status-indicators.md](status-indicators.md) - Job/project status, pipeline stages, priority |
- [stats-cards.md](stats-cards.md) - KPI metric cards, trend indicators, featured stats
- [data-display.md](data-display.md) - Bar charts, gauge/donut, progress bars, timelines
