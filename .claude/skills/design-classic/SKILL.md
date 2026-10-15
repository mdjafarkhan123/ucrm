---
name: design-classic
description: Classic presentation guidance for existing-app maintenance or explicitly requested Classic screens; reached through the shared design workflow.
---

# Classic design

Read [shared design](../design/SKILL.md) for workflow, engineering and screen checks. These modules are
Classic-only: use the relevant modules together (for example, cards and their buttons). `brand.md`
owns same-name brand token precedence. Existing screens and verified implementation take precedence
over stale reference claims; preserve actual appearance rather than restyling to match an old document.
For new Classic layouts, inspect matching `Design/*.jpg` references and existing components, then follow
approved product behaviour. Blueprint images do not override working permissions or save behaviour.

## Recovery and reconciliation

Recovered from pre-Botanical tree `75d6d48432a4e846941e6b9c88d3ffd7db1f6026` on 2026-10-11.
Visual modules are retained; Botanical shell additions now live in its own skill. Historical entry-point
claims about `html { font-size: 62.5% }`, a `_tokens.scss` source and a mirrored `scss/` directory were
stale. Verified sources are `src/lib/styles/_variables.scss` and `app.scss`: the root is **100%**, normally
16px per rem at browser defaults, while the body base token is **14px**. Respect user text scaling.
Use actual CSS tokens/computed styles; never convert using the old 10px-per-rem assumption.
`token.css` and `token-guide.md` are reference snapshots, not runtime imports; reconcile against live
sources before changing values. Update affected guidance with approved token changes.

Classic dark colours come from the live variables file's dark-theme mixin and root `data-theme` handling.
Keep the existing explicit choice/OS preference behaviour and verify affected light/dark states.

## Approved new Classic look

Jafar approved the new Classic direction on 2026-10-13. For each redesigned part in
`docs/classic-theme-redesign-behavior-contract.md`, use the reference screens in `classic.pen` and the
token values, colour meanings and component recipe in `docs/classic-theme-redesign-design-recipe.md`.
Read the campaign plan's platform scope before drawing screens or applying the shared screen check.
`src/lib/styles/_classic-theme-tokens.scss` exposes those values as `--classic2-*` only while the Classic
frame is active; menus and dialogs inherit them from the document root. Use these tokens for new Classic
work. The older module values below describe the live parts that have not yet reached their build step.
Check the relevant approved Pencil frame before restyling one of those parts.

## Module Index

### Foundations

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
- [section-block.md](section-block.md) — Section Block
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
- Charts and timelines — inspect existing implementation; no dedicated Classic module exists.
