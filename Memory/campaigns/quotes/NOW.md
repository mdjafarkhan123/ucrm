# Quotes: Current Checkpoint

## Goal

Build trustworthy proposals from creation through customer decision, deposit readiness, Pipeline outcome, and terminal Job handoff.

## Current state

Parts 1–6 are closed. Part 7 was completed through the sales-pipeline campaign. Part M (money-permission
lockdown) closed 2026-08-31: database, routes, and route specs all agree, with the full unit suite green.

Only Part 8 remains. Its command half shipped with Jobs Part 5 on 2026-09-01:
`public.convert_quote_to_job` (migration `20260901002848`) and `POST /api/quotes/:id/convert-to-job` copy the
approved version's selected scope into Job-owned lines, make the Quote terminally `converted`, and return the
first Job again for a retry. `quotes.convert` is seeded for owner/admin/office/sales (`20260901003013`).

## Exact next action

Finish Part 8's screen half: the Convert to job control on Quote detail, gated on `quotes.convert` and
`public.quote_ready_for_job`, plus the final audit and manual pass. Wait for the Jobs detail page (jobs
campaign Part 8) before deciding where the button sends the person.

## Blockers

Email delivery remains owned by Communications; online payment processing remains owned by Payments.

## Essential pointers

- docs/quote-behavior-contract.md § Staff permissions — where the two money permissions are enforced
- supabase/tests/database/quote_money_lockdown.sql — the assertions that define the money rule

## Completion gate

Part 8 provides one idempotent Job conversion and the final audit/manual without weakening immutable Quote
history.
