# Contractor design concept

## Summary

A new design concept for the whole contractor app. It is drawn in Pencil (`concept.pen`) from the app's own
colours, sizes and spacing, then each screen goes **design → review → approve → build** (Jafar, 2026-10-17).
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
   with `-surface` and `-on-surface`, plus `radius-circle`. The sidebar follows the work order Requests → Quotes →
   Jobs → Invoices, as Jobber does.
2. **Pilot screens**, one per session, each approved: Home, Jobs list, Job details.
3. **Every other screen**, each approved. Once a pattern is approved, several screens may be drawn in parallel
   by helper agents, each reviewed against the brief before Jafar sees it.
4. **Build.** Approved screens are built through shared parts. New variables go into
   `src/lib/styles/_variables.scss` and the design skill in the same commit as Pencil. When every screen uses the
   concept, the old look and its unused code are deleted.

## Experience target

The target is "Jafar's Design Preferences" in the [design skill](../.claude/skills/design/SKILL.md).

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

- How the concept reaches users: the whole app switches at once, or screen by screen. Decide before building.
- Whether money cards stay light in dark mode (Jafar's App-look decision of 2026-10-16) in the concept.
- The "Changes requested" colour on Quotes.

## Sources and design decisions

- Colour meanings follow Jobber's own design system (Atlantis), whose record colours the app already uses:
  `.claude/skills/design-classic/colors.md` § Workflow colors.
- Coloured icons used sparingly to show meaning: Apple Human Interface Guidelines, Sidebars — "fixed colors can
  help clarify the meaning of an icon" (https://developer.apple.com/design/human-interface-guidelines/sidebars).
- Decision 2026-10-17 (Jafar): concept work starts now with the simple flow; Phase A screens already built stay.
- Decision 2026-10-17 (Jafar): Foundation boards approved.
- Decision 2026-10-17 (Jafar): the Foundation's off-scale sizes become new tokens — text 11, 13, 32; tile
  corners 6 and 10; card padding 20 — added to `concept.pen` and the design skill, and to `_variables.scss`
  with the first screen that uses them.
- Decision 2026-10-17 (Jafar): complete the button set — every state for every kind, three sizes, a confirm-red
  button, a More menu button and a faint raised look — and every button that waits on the server shows loading,
  in the app whether or not a screen has a Pencil design. Loading follows GitHub Primer and Shopify Polaris: the
  spinner replaces the icon (or the label, keeping the width) and blocks a second press. The Pencil drawing awaits
  Jafar's review.
- Decision 2026-10-17 (Jafar): keep two sets of styling modules for now — `design` (concept) and
  `design-classic` (live look) — until rollout; revisit then.
