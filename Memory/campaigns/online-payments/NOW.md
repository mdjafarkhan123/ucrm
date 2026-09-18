# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Status

Part 4 — Online quote deposit — DONE and browser-verified 2026-09-18 on Raad LTD (quote #31): approved+signed
as customer, paid the $118.36 deposit with Stripe's sandbox Link test card, deposit showed "Received" and the
quote flipped to "Ready for job", and the office/finance bell alert rendered
("Deposit paid online on quote #31 · 118.36 USD received through Stripe") and opened the right quote.
`npm run check` (0 errors) and Prettier both clean on touched files. Supabase advisors: only the pre-existing
baseline (104x `rls_enabled_no_policy` INFO, including the expected `payment_stripe_checkouts` one).

**Not yet committed to git** — all Part 3 + Part 4 work is still uncommitted working-tree changes.

## Exact next action

Ask Jafar whether to commit Part 3 + Part 4 now (single commit or split), then decide the next online-payments
part (Venmo/Zelle/Cash App/e-Transfer instructions) or close the campaign if nothing else is scoped.

## Pointers

- docs/online-payments-behavior-contract.md
- Part 4 code: `src/lib/server/payments/quote-deposit-checkout.ts`,
  `src/lib/server/payments/stripe-checkout-events.ts`,
  `src/routes/api/public/quotes/[token]/checkout/+server.ts`,
  `src/lib/components/quotes/CustomerQuoteDepositPayment.svelte`,
  `supabase/migrations/20261009090000_online_quote_deposit_payments.sql` (applied to dev DB).
- 71 pre-existing server unit test failures (quotes, settings-business, team resend) predate commit 9d581a6;
  not caused by this campaign.
