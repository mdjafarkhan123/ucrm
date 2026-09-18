# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Active part

Part 3 — Customer pays invoice online. Not started.

## Exact next action

Read the contract's Part 3 sections, then plan Part 3 (performance-review design branch applies: webhook
journal + ledger writes). Explain the migration's impact to Jafar before applying it.

## Blockers

Raad LTD is disconnected after the Part 2 gate. Jafar must reconnect a sandbox restricted key in Settings →
Payments before Part 3 can be tested (agent may not paste keys). Stripe Workbench Shell
(`stripe trigger <event>`) works for sandbox events; no local Stripe CLI is installed.

## Pointers

- docs/online-payments-behavior-contract.md
- Part 2 code: src/lib/server/payments/, src/routes/api/webhooks/stripe/ (verifies only; Part 3 journals).
- database.types.ts was hand-merged: `npm run db:types` output drops hand-kept nullable RPC args, so don't
  blindly regenerate.
