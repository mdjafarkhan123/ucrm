# Sales Pipeline: Current Checkpoint

## Goal

Build one contractor-friendly commercial board from Request through Quote, copying Jobber's current Sales
Pipeline. Request, Assessment, and Quote remain operational truth; the Pipeline projects them and adds
accountable commercial follow-up.

## Status: paused

Parts 1–4 are closed. Part 4C (Sales Outcomes tiles/report) shipped and closed 2026-08-19 — see
`parts/04-won-lost-reopen-outcomes.md` for what it verified. Part 5 (Quote stages, drag, automatic Won) has
no placeholder dependency and cannot start until the Quotes campaign establishes real Quote truth. There is
no exact next action in this campaign right now.

## Resume trigger

Resume Part 5 once the Quotes campaign is far enough along that Quote creation, approval, and change-request
states are real. At that point: read `ROADMAP.md` for Part 5's dependencies, create its packet from the
approved behavior contract's Quote-stage sections, and follow the same tour-Jobber-first, propose-then-build
flow every other part used.

## Current truth

- Parts 1–4 are closed. The approved behavior is authoritative in `docs/sales-pipeline-behavior-contract.md`.
- Part 4 shipped the full outcome engine: `pipeline_mark_opportunity_lost` / `pipeline_reopen_opportunity`
  (4A), the card's `Mark as lost` action and both write routes (4B), and the Won/Lost tiles plus the
  `/pipeline/outcomes` Sales Outcomes report with Reopen as its only UI entry point (4C).
- The Request detail page's Archive/Bring back toggle is gone; Lost and Reopen (via the Sales Outcomes
  report) are the only ways a Request is archived or restored — a DB trigger enforces this.
- `SidePanel` (the Opportunity Brief) is a true modal; the board is not interactive behind an open Brief.
- Board state remains URL-derived throughout. `src/lib/pipeline/filters.ts` (board) and
  `src/lib/pipeline/outcomes.ts` (Sales Outcomes report) hold the two URL vocabularies.
- The embedded activity timeline and all Schedule work stay deferred.

## Blockers

Part 5 blocked on the Quotes campaign (not yet started).

## Protected work

Keep Requests, Assessments, and the closed Pipeline Parts 1–4 stable. Never author Pipeline stage fields from
application code. No placeholder Quote or Schedule domain.

## Required pointers

- `docs/sales-pipeline-behavior-contract.md` and `CONTEXT.md`
- `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1–4.6.2
- `Memory/campaigns/sales-pipeline/ROADMAP.md` for full part history and standing decisions
- `Memory/campaigns/sales-pipeline/parts/04-won-lost-reopen-outcomes.md` for everything Part 4 shipped
- `Memory/deferred/INDEX.md` for the activity/Schedule deferrals and the rate-limit debt

## Active-part completion gate

Not applicable while paused. Part 4's gate (outcome transitions atomic, reasoned, permission-safe, idempotent,
preserved in history/reporting) is met — see ROADMAP.md.
