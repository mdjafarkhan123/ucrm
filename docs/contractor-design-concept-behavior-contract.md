# Contractor design concept

## Summary

A new design concept for the whole app: every staff page, every customer page and email, login and sign-up,
and Jafar's admin panel last. It is drawn in Pencil (`concept.pen`) from the app's own
colours, sizes and spacing, then each screen goes **design → review → approve → build**.
New buttons, parts and screens are allowed; the look follows
the [design skill](../.claude/skills/design/SKILL.md) (Style, Critical Rules, Pencil Design Requirements and its
modules), which every agent reads before designing.

## Problem and audience

Screens grew one by one and the look was never one system, and today's look reads plain. Contractors and office
staff open the app between jobs and want to see what needs them right now, in a product that feels premium.

## First version

1. **Foundation — approved 2026-10-17.** Two boards in `concept.pen`: "Colour that means something" (record,
   section and status colours, the colourful-icon rule) and "The parts every screen is built from" (buttons,
   status pills, icon tiles, fields, cards, list rows, table, sidebar, top bar, dark preview). Four new colour
   families were added from shades the app already has: `color-time` (Schedule, Timesheets),
   `color-conversation` (Inbox), `color-growth` (Pipeline, Marketing, Reports), `color-review` (Reviews), each
   with `-surface` and `-on-surface`, plus `radius-circle`. The sidebar keeps the live app's groups (Overview, Customers,
   Work & Money, Growth; Jafar 2026-10-18).
2. **Pilot screens**, one per session, each approved: Home, Jobs list, Job details.
3. **Everything else, most necessary first**, each approved. A **redesign checklist** holds every piece of the
   app, built from the code rather than from memory: every page file (`src/routes/**/+page.svelte`) and every
   component file (`src/lib/components/**/*.svelte`), plus customer emails and error pages. Each piece carries
   two ticks, Pencil and Built, and each tick has a "waiting" step. A coverage check proves nothing is missing.
   The order, by tier:
   1. Shared parts and pop-up patterns: every part used on more than one page.
   2. Daily pages: the app's daily list in `src/routes/(app)/+layout.svelte`, with their record and "new" pages.
   3. What customers and new businesses see: customer pages, customer emails, login and sign-up.
   4. Weekly tools: the remaining staff work pages.
   5. Growth.
   6. Set up once: Settings and Setup.
   7. Jafar's admin panel.

   Every pop-up is on the checklist. Simple ones follow a drawn pattern (form pop-up, "are you sure?" pop-up,
   side drawer). Pop-ups that carry money, sending or scheduling decisions get their own drawing, and Jafar may
   move any pop-up between the two. Once a pattern is approved, several screens may be drawn in parallel by
   helper agents, each reviewed against the brief before Jafar sees it.
4. **Build.** Screen by screen (Jafar, 2026-10-18): an approved screen is built soon after its approval, so the
   app mixes old and new looks until every screen is done. Approved screens are built through shared parts. Once an approved shared part is built, its new appearance applies everywhere that component is used, including pages awaiting their own redesign (Jafar, 2026-10-19). New variables go into
   `src/lib/styles/_variables.scss` and the design skill in the same commit as Pencil. When every screen uses the
   concept, the old look and its unused code are deleted.

## Experience target

The target is "Jafar's Design Preferences" in the [design skill](../.claude/skills/design/SKILL.md). Must read before you start designing in pencil.

## Not doing

- Copying any product's design.
- Phone layouts (the native apps come later).
- Building a screen before Jafar approves its Pencil design.
- New data or behaviour built silently: a design that needs it lists it for Jafar's decision first.

## Earlier work (Phase A, before 2026-10-17)

The first plan finished today's "App look" before starting a concept. Built and on main: shell, Jobs, Clients,
Requests, Quotes and Invoices lists, the six record pages, Home, Inbox, 25 Settings pages, and Schedule. Stopped
on 2026-10-17: drawing the undesigned screens (Timesheets, Pipeline, Files, Marketing, Reviews, Reports) in the
App look, and a separate old-code cleanup. Both now happen inside the concept. `classic.pen` keeps the App-look
designs as the record of the live app.

## Still unclear

- Whether money cards stay light in dark mode (Jafar's App-look decision of 2026-10-16) in the concept.
- The "Changes requested" colour on Quotes.

## Sources and design decisions
