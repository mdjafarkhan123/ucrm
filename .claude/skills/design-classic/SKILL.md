---
name: design-classic
description: Classic presentation guidance for existing-app maintenance or explicitly requested Classic screens; reached through the shared design workflow.
---

# Classic Design System — Agent Instructions

This skill describes the live app's current look ("Classic"). Use it to fix or extend screens that have not moved
to the new concept. Every component, layout and screen in Classic follows the modules below. They describe what
the design looks like; you choose how to build it.

## Style

A clean, Jobber-style work app: warm taupe page, white cards, navy text, green actions, and one colour per record
type (request, quote, job, invoice, client).

## Before Writing Any Code

1. **Read every module that applies.** Any screen: `brand.md`, `colors.md`, `typography.md`, `layout.md`,
   `radius.md`, `shadows.md`, `borders.md`, then each component module it uses.
2. **Look at the live screen and its component** in `src/lib/components`. The live look wins over these modules
   when they differ; keep the screen as it is.
3. **For a new Classic layout,** look at the matching image in `Design/` and the closest existing component.

## Critical Rules

- **Tokens come from `src/lib/styles/_variables.scss`.** `token.css` and `token-guide.md` are reference copies;
  check a value against `_variables.scss` before relying on it.
- **Sizes:** the root font is the browser default (1rem = 16px); body text is 14px
  (`--typography--fontSize-base`). Use tokens, not rem maths.
- **Brand colour precedence:** tokens in `brand.md` override same-name tokens in `colors.md`.
- **Dark mode comes from the tokens** (`data-theme`); never swap colours by hand. Check light and dark.
- **Cross-reference modules.** A card with buttons meets `cards.md` and `buttons.md`.
- **Every interactive part** has hover, focus-visible and disabled states.
- **Semantic HTML:** headings in order, `<button>` for actions, `<a>` for navigation, labels on fields.

## Module Index

### Foundations

- [brand.md](brand.md) — Brand
- [colors.md](colors.md) — Colour
- [typography.md](typography.md) — Typography
- [layout.md](layout.md) — Layout
- [radius.md](radius.md) — Radius
- [shadows.md](shadows.md) — Shadow
- [borders.md](borders.md) — Borders

### Components

- [buttons.md](buttons.md) — Button
- [button-group.md](button-group.md) — Button group
- [cards.md](cards.md) — Card
- [section-block.md](section-block.md) — Section block
- [inputs.md](inputs.md) — Input
- [alerts.md](alerts.md) — Alert
- [badges.md](badges.md) — Badge
- [lists.md](lists.md) — List
- [avatars.md](avatars.md) — Avatar
- [icon-shapes.md](icon-shapes.md) — Icon shape
- [accordion.md](accordion.md) — Accordion
- [dropdown.md](dropdown.md) — Dropdown
- [modals.md](modals.md) — Modal
- [tabs.md](tabs.md) — Tabs
- [tables.md](tables.md) — Table
- [pagination.md](pagination.md) — Pagination
- [sidebars.md](sidebars.md) — Sidebar
- [radios-checkboxes-toggle.md](radios-checkboxes-toggle.md) — Radio, checkbox, toggle
- [tooltips-popovers.md](tooltips-popovers.md) — Tooltip, popover
- [content.md](content.md) — Content grid

### CRM Components

- [status-indicators.md](status-indicators.md) — Job and project status, pipeline stages, priority
- [stats-cards.md](stats-cards.md) — KPI cards, trends, featured stats
- Charts and timelines have no module yet; follow the existing implementation.
