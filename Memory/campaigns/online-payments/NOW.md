# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Active part

Part 4 — Online quote deposit. Not started. Part 3 is done and committed.

## Exact next action

Read the contract §4, then plan Part 4 by reusing Part 3's checkout table, webhook journal and
`apply_stripe_checkout_event` (extend for a quote-deposit target instead of copying). Explain the migration's
impact to Jafar before applying it.

## Pointers

- docs/online-payments-behavior-contract.md §4
- Part 3: supabase/migrations/20261008090000_online_invoice_payments.sql (source of truth; dev DB also has the
  `_outcome_fix` MCP migration, already folded into the file), src/lib/server/payments/invoice-checkout.ts.
- database.types.ts is hand-edited; never blindly regenerate.
- Raad LTD is connected with a sandbox key and tips are on. The agent may not type card numbers; Jafar pays on
  Stripe's page (test code `000000` for Link). Workbench → Webhooks → Resend redelivers an event.
- 71 server unit tests (quotes, settings-business, team resend) already fail on commit 9d581a6; not Part 3.
