# Contractor design concept

## Summary

Two phases, in this order. **Phase A — finish today's design:** every screen already designed in Pencil
(`classic.pen`, "App look") is built in the app, and the shared parts are updated so each change reaches every
page. Screens with no design yet are designed in the same look and built. Then the old code is deleted, so one
look and no leftovers remain. **Phase B — the new design concept:** a real redesign, researched and designed
like the best product teams, applied across the whole app. Phase B starts only when Phase A is complete.

## Problem and audience

Screens grew one by one and the look was never one system. Contractors and office staff open the app between
jobs and want to see what needs them right now. Phase A makes today's look consistent and removes old code so
Phase B has a clean base.

## First version

**Phase A**
- Every designed screen built: Home, Schedule (all states), Inbox, Settings, and the Quote, Request, Invoice,
  Client and Payment detail pages. Already built on branch `claude/jobs-list-app-look`: shell, Jobs, Clients,
  Requests, Quotes, Invoices lists, Job details.
- Screens with no Pencil design (Timesheets, Pipeline, Files, Marketing, Reviews, Reports) designed in the same
  look, approved by Jafar, then built.
- Shared parts become the only look (table, filter chips, load more, page header, shell), Control Room
  included. Old styles and unused options deleted. Docs and design skills updated to match.

**Phase B**
- Research findings in `docs/research/`: what leading products show and omit per screen.
- One approved concept in Pencil: colour rules, type, spacing, shell, core parts.
- Pilot screens approved (Home, Jobs list, Job details), then the whole app rolled out, in the shared parts.

## Experience target

- Premium, polished, modern, clear and calm, in the spirit of strong Dribbble product work.
- Each screen shows what a contractor most needs to see. No vague or useless blocks.
- Colourful where colour matters: record type, section or status, to add meaning and improve the look. Never
  decoration, never a rainbow. Brand green stays `#037741`.
- Desktop web app. No phone-size design work.
- Research only shows what products show and leave out. It never means copying a design.
- **Phase B is a new concept, not a polish of today's pages.** Layout, grouping and the content of each screen
  can differ from the live page, as the Pencil Job details already differs from the live one. The test is what
  a contractor most needs on that screen, not what the page has today.

## Not doing

- Copying any product's design.
- Phone layouts.
- Phase A adds no new features or behaviour: it changes the look only.
- Phase B may rearrange screens and change what each shows. When the concept needs data or behaviour the app
  lacks, list it for Jafar's decision before building; never build it silently.
- Phase B work before Phase A is complete (Jafar, 2026-10-16).

## Still unclear

- Whether to merge Phase A to main in steps or all at once.
- The order of the undesigned screens.
- Open Phase A questions from the list builds: dark mode of the money card, "Changes requested" colour,
  whether data-less design pieces (Quotes totals, Client book, Job lifecycle strip) get built or trimmed.

## Sources and design decisions

- Built so far (2026-10-16): branch `claude/jobs-list-app-look`, worktree `.worktrees/jobs-list-app-look`.
- Decision 2026-10-16 (Jafar): one look everywhere, Control Room included; old styles deleted, not kept.
- Decision 2026-10-16 (Jafar): Needs attention tiles filter their list.
