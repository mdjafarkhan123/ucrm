# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Status

Part 7 (Jafar Stripe slice) — Done and committed `4081c09` 2026-09-19.

## Exact next action

Start Part 8 (end-to-end proof) — needs all prior parts, which are done. Full test-mode journey plus guide
screenshots; gate is the performance-review verification branch and Jafar sign-off.

## Pointers

- docs/online-payments-behavior-contract.md §6.
- Stripe CLI: `/tmp/claude-1000/.../scratchpad/stripe` (copy forward each new session — `stripe config --list`
  confirms it's still logged into the right sandbox, no re-login needed).
