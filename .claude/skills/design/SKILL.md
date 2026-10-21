---
name: design
description: Design system for the CRM's look — brand, colour meaning, type, spacing and component styling, plus what a Pencil design must meet. Use for any screen, component, styling, frontend or Pencil design task.
---

# Design System — Agent Instructions

This skill describes how the CRM looks. Every component, layout and screen follows the modules below. They
describe what the design looks like; you choose how to build it. The approved reference is the Foundation in
`concept.pen` (boards "Colour that means something" and "The parts every screen is built from", approved by
Jafar 2026-10-17).

## Jafar design preferences for pencil design
- [guide.md](guide.md) - Pencil app design preferences

## Before Writing Any Code

1. **Read every module that applies.** Any screen: `brand.md`, `colors.md`, `typography.md`, `layout.md`,
   `radius.md`, `borders.md`, `shadows.md`, `icon-shapes.md`, then each component module it uses.
2. **Screens not yet moved to the concept** keep their live look: use [design-classic](../design-classic/SKILL.md).

## Critical Rules

- **Tokens only.** Every value maps to a token in `src/lib/styles/_variables.scss` (Pencil uses the same names
  without `--`, except text sizes: Pencil `font-size-label` is `--typography--fontSize-label`). A new token goes into Pencil, code and these modules in the same commit.
- **Cross-reference modules.** A card with buttons meets `cards.md` and `buttons.md`.
- **Dark mode comes from the tokens;** never swap colours by hand.
- **Every interactive part** has hover, focus-visible, active and disabled states.
- **Semantic HTML:** headings in order, `<button>` for actions, `<a>` for navigation, labels on fields.

## Pencil Design Requirements

- Draw in `concept.pen` from its Foundation parts and token names, following every preference above.
- Working in Pencil (opening the file, saving, recording Jafar's approval): read
  [Pencil workflow](../../../docs/pencil-workflow.md).

## Module Index

### Foundation (read first for any UI work)
- [brand.md](brand.md) — Brand
- [colors.md](colors.md) — Colour
- [typography.md](typography.md) — Typography
- [layout.md](layout.md) — Layout and spacing, sign-in screens, setup steps, booking page
- [radius.md](radius.md) — Radius
- [borders.md](borders.md) — Borders
- [shadows.md](shadows.md) — Shadows
- [icon-shapes.md](icon-shapes.md) — Icon tiles

### Components
- [buttons.md](buttons.md) — Button
- [badges.md](badges.md) — Status pill
- [inputs.md](inputs.md) — Field, money and quantity boxes, checkbox, radio choice, on/off switch, segmented switch, people pick chips, message sheet, questions on a public form, weekly hours, signature pad
- [chips.md](chips.md) — Filter chip, tag, tag picker, multi-choice filter chip, date range chip, sender chip, channel pill
- [avatars.md](avatars.md) — Avatar
- [tabs.md](tabs.md) — Tabs
- [cards.md](cards.md) — Card, number card, side card rows, totals card, automatic follow-up card
- [files.md](files.md) — Photo viewer, file picture, photo box, upload list, files card, record files card, files waiting to save, add files pop-up, photo labels pop-up, photo details, caption and labels pop-up, files on a message
- [notes.md](notes.md) — Notes card, author line, note text, note files, note box on a new record, activity feed
- [price-book.md](price-book.md) — Search list under a line's name, new item pop-up, Price book drawer
- [lists.md](lists.md) — List row, Load more footer
- [tables.md](tables.md) — Table
- [sidebars.md](sidebars.md) — Sidebar
- [top-bar.md](top-bar.md) — Top bar
- [modals.md](modals.md) — Form pop-up, "are you sure?" pop-up, side drawer, pop-over, email preview pop-up, communication settings pop-up, customer group pop-up, profile photo pop-up
- [page-states.md](page-states.md) — Loading, empty, couldn't load
- [notices.md](notices.md) — Notice strip, form error card
- [calendar.md](calendar.md) — Schedule calendar: toolbar, grid, cards, now line
- [time-clock.md](time-clock.md) — Work timer: ticking time, running clock, Start and Stop, your timer panel, visit row clock

Not yet designed in the concept — use the Classic module until it is: accordion, dropdown, pagination,
tooltips.
