---
name: design
description: Design system for the CRM's look — brand, colour meaning, type, spacing and component styling, plus what a Pencil design must meet. Use for any screen, component, styling, frontend or Pencil design task.
---

# Design System — Agent Instructions

This skill describes how the CRM looks. Every component, layout and screen follows the modules below. They
describe what the design looks like; you choose how to build it. The approved reference is the Foundation in
`concept.pen` (boards "Colour that means something" and "The parts every screen is built from", approved by
Jafar 2026-10-17).

## Jafar's Design Preferences

Agreed with Jafar on 2026-10-17. Every design, in Pencil or in code, follows all of them.

1. **Premium and modern.** It looks like the work of a top Dribbble product designer: polished, never plain.
2. **Calm and clear.** Clean spacing, clear hierarchy, soft white cards on a warm page, one focal point per
   screen, so a contractor can read it at a glance between jobs.
3. **Contractor first.** Each screen shows what a contractor most needs right now. Every block answers a question
   the contractor has on that screen; remove any block that does not.
4. **Colourful with meaning.** Colour tells you one of three things: the kind of record (request, quote, job,
   invoice, client), the part of the app (schedule, inbox, growth, reviews), or the status (done, waiting, act
   now, planned, draft). Colour is never decoration and never a rainbow. The colour map is in `colors.md`.
5. **Colourful icons across the whole app.** Icons that name a record, a part of the app or a status sit on a
   soft tile in their meaning colour (`icon-shapes.md`). Grey icon tiles look too plain. Action icons (edit,
   delete, copy, share, download, more) stay plain.
6. **Brand green for action.** The main button of each area is brand green `#037741`, with white text. Green
   buttons, not black ones. Light greens appear only in dark mode.
7. **Nothing blends in.** Every element's fill differs from the colour behind it, in light and dark mode.
8. **Built from the app's own colours and sizes** (`src/lib/styles/_variables.scss`). Add a new one only when
   nothing fits.
9. **A new concept, not a touch-up.** New buttons, parts and screens are welcome; a screen's layout and content
   may differ from today's page.
10. **Researched, never copied.** Check what Jobber and other leading products show and leave out on a screen,
    then draw our own look. This research is for just what they show and what not. Not to copy their design
11. **Desktop web app.** Design at 1440px wide; phone layouts wait for the native apps.
12. **Design → review → approve → build.** Jafar approves each screen in Pencil before it is built. If a design
    needs data or behaviour the app does not have, list it for Jafar's decision first.

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
- [layout.md](layout.md) — Layout and spacing
- [radius.md](radius.md) — Radius
- [borders.md](borders.md) — Borders
- [shadows.md](shadows.md) — Shadows
- [icon-shapes.md](icon-shapes.md) — Icon tiles

### Components
- [buttons.md](buttons.md) — Button
- [badges.md](badges.md) — Status pill
- [inputs.md](inputs.md) — Field, checkbox, segmented switch, people pick chips
- [cards.md](cards.md) — Card
- [lists.md](lists.md) — List row
- [tables.md](tables.md) — Table
- [sidebars.md](sidebars.md) — Sidebar
- [top-bar.md](top-bar.md) — Top bar
- [modals.md](modals.md) — Form pop-up, "are you sure?" pop-up, side drawer
- [page-states.md](page-states.md) — Loading, empty, couldn't load

Not yet designed in the concept — use the Classic module until it is: accordion, alerts, avatars, button group,
dropdown, pagination, radios/toggle, tabs, tooltips/popovers.
