# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Status

Part 5 — Refunds, disputes, disconnect safety — Done 2026-09-19, live-verified. See ROADMAP.md Part 5 for
what was proven and the real bug found+fixed (a check constraint was silently blocking every refund
confirmation). Disconnect-safety alone stays code-complete/not-live-tested; Jafar deferred it rather than
reconnect Raad LTD's test Stripe key by hand.

Not yet committed to git: this part's 3 migrations (all already applied live to the dev Supabase project) plus
`StripeRefundDialog.svelte` and `stripe-refunds.ts` from earlier this campaign. `git status --short` shows the
full file list.

## Exact next action

Ask Jafar: commit Part 5 now, or keep going first? Then start Part 6 (pay-by-app methods) per ROADMAP.md —
research how top apps present Venmo/Cash App/PayPal/Zelle/e-Transfer links before building.

## Pointers

- docs/online-payments-behavior-contract.md §5–§6.
- Stripe CLI: `/tmp/claude-1000/.../scratchpad/stripe` (copy forward each new session — `stripe config --list`
  confirms it's still logged into the right sandbox, no re-login needed).
