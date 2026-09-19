# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Status

Part 6 (pay-by-app methods) — Done and committed `eb98c42` 2026-09-19.

## Exact next action

Start Part 7 (Jafar Stripe slice) — needs Parts 2-5, which are done. Read
`Memory/campaigns/jafar-panel/NOW.md` first since Part 7 extends jafar-panel Part 10's Stripe
readiness/health/history/recovery work there.

## Pointers

- docs/online-payments-behavior-contract.md §6.
- Stripe CLI: `/tmp/claude-1000/.../scratchpad/stripe` (copy forward each new session — `stripe config --list`
  confirms it's still logged into the right sandbox, no re-login needed).
