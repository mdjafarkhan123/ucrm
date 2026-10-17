---
name: design
description: Design system for the CRM's look — brand, colour meaning, type, spacing and component styling, plus what a Pencil design must meet. Use for any screen, component, styling, frontend or Pencil design task.
---

# Design System — Agent Instructions

This skill describes how the CRM looks. Every component, layout and screen follows the modules below. They
describe what the design looks like; you choose how to build it. The approved reference is the Foundation in
`concept.pen` (boards "Colour that means something" and "The parts every screen is built from", approved by
Jafar 2026-10-17).

## Style

A premium, calm product for contractors: clean spacing, clear hierarchy, soft white cards on a warm page, and
colour that names what each thing is. Each screen shows what a contractor most needs right now.

## Before Writing Any Code

1. **Read every module that applies.** Any screen: `brand.md`, `colors.md`, `typography.md`, `layout.md`,
   `radius.md`, `borders.md`, `shadows.md`, `icon-shapes.md`, then each component module it uses.
2. **Screens not yet moved to the concept** keep their live look: use [design-classic](../design-classic/SKILL.md).

## Critical Rules

- **Tokens only.** Every value maps to a token in `src/lib/styles/_variables.scss` (Pencil uses the same names
  without `--`). Add a token only when none fits, in Pencil, code and these modules in the same commit.
- **Colour means something.** It names a kind of record, a part of the app, or a status (`colors.md`).
- **One green action** per area (`buttons.md`).
- **Cross-reference modules.** A card with buttons meets `cards.md` and `buttons.md`.
- **Dark mode comes from the tokens.** Every fill differs from the colour behind it, in light and dark.
- **Every interactive part** has hover, focus-visible, active and disabled states.
- **Semantic HTML:** headings in order, `<button>` for actions, `<a>` for navigation, labels on fields.

## Pencil Design Requirements

- Draw in `concept.pen` at 1440px wide, from its Foundation parts and token names.
- Research what Jobber and other leading products show and leave out on that screen; draw our own look.
- Layout and content may differ from today's page; the test is what a contractor most needs there.
- List any data or behaviour the design needs that the app lacks, for Jafar's decision.
- Jafar approves each screen before it is built. Steps: [Pencil workflow](../../../docs/pencil-workflow.md).

## Module Index

### Foundation (read first for any UI work)
- [brand.md](brand.md) — Brand
- [colors.md](colors.md) — Colour
- [typography.md](typography.md) — Typography
- [layout.md](layout.md) — Layout and spacing
- [radius.md](radius.md) — Radius
- [borders.md](borders.md) — Borders
- [shadows.md](shadows.md) — Shadows
- [icon-shapes.md](icon-shapes.md) — Icon tiles

### Components
- [buttons.md](buttons.md) — Button
- [badges.md](badges.md) — Status pill
- [inputs.md](inputs.md) — Field
- [cards.md](cards.md) — Card
- [lists.md](lists.md) — List row
- [tables.md](tables.md) — Table
- [sidebars.md](sidebars.md) — Sidebar
- [top-bar.md](top-bar.md) — Top bar

Not yet designed in the concept — use the Classic module until it is: accordion, alerts, avatars, button group,
dropdown, modals, pagination, radios/checkboxes/toggle, tabs, tooltips/popovers.
