# Contractor design concept

## Summary

A real redesign of the contractor app, not a restyle. We research what the best products show and leave out on
each main screen, design one new concept in Pencil, prove it on a few pilot screens, and then roll it out to the
whole app at once. Contractors should see the few things they need most on every screen, in a design that feels
premium, calm and clear. Colour is used to mean something.

## Problem and audience

Today's screens grew one by one: some blocks are filler, and the look was never designed as one system.
Contractors and their office staff open the app between jobs and want to see what needs them right now.

## First version

- Research findings (what leading products show and omit per screen), kept in `docs/research/`.
- One approved design concept in `classic.pen`: colour rules, type, spacing, shell, core parts.
- Pilot screens approved by Jafar: Home, Jobs list, Job details.
- Whole-app rollout in one switch, with one shared look: no old styles, no leftover code, Control Room included.

## Experience target

- Premium, polished, modern, clear and calm, in the spirit of strong Dribbble product work.
- Each screen answers "what does a contractor most need to see here?" No vague or useless blocks.
- Colourful where colour matters: record type, section or status, never decoration or a rainbow. Brand green
  stays the app's `#037741`.
- Desktop web app. No phone-size design work.
- Research shows what products show and leave out. It never means copying a design.

## Not doing

- Copying any product's design — research is for understanding what works.
- Phone layouts — this is a desktop web app.
- New features or behaviour — design changes the look only; ideas for behaviour go to Jafar as suggestions.

## Still unclear

- Which screens count as "necessary" beyond the three pilots, and their order.
- Whether today's "App look" screens in `classic.pen` are kept as a starting point or replaced.

## Sources and design decisions

- Work already built on branch `claude/jobs-list-app-look` (2026-10-16): new shell, shared list parts
  (record list card, card table, filter chips, attention card, money card), Jobs list, Job details, Clients,
  Requests, Quotes, Invoices lists. Its shared-parts structure carries over to any new look. Not merged to
  main while the concept is undecided.
- Decision 2026-10-16 (Jafar): one look everywhere, Control Room included; old styles get deleted, not kept.
