# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Status

Part 9a done and committed (`5eee391`): billing a job now credits the deposit paid on its quote. Part 8
(end-to-end proof) is still paused mid-run. Parts 1–7 done. Details in the roadmap.

## Exact next action

Ask Jafar which comes first, then do it:

- **Part 9b** — Jobber's invoice **Deposits (Add Deposit)** row so leftover client credit can be spent by
  hand. `public.apply_client_payment` already does it in the database and no route or screen reaches it, so
  the work is one `/api/*` route plus a dialog. Load the `design` and `bits-ui` skills. Invoice #27 is the
  live case: it is fully paid while quote #40's $330 deposit sits unspent.
- **Part 8 remainder** — first bill job #20 (quote #36, $3,510 deposit, no invoice yet) in the browser to see
  9a work on real data. Then prove Part 3's two unproven async bank paths (`processing` → succeeded, and
  `async_payment_failed`) on a new test invoice — first check whether Stripe's page offers bank (ACH) in this
  sandbox. Then the guide screenshots and the performance-review verification write-up.

## Blockers

- The Claude Chrome extension has no permission for `checkout.stripe.com`, so the agent cannot fill Stripe's
  payment form; Jafar fills and pays each remaining checkout (worked for #27).
- The browser screenshot tool times out while a ⋮ menu is open, though the app is fine. Drive the page with
  `javascript_tool` instead; to get a customer link, hook `navigator.clipboard.writeText` and click the menu item.
- Bank (ACH) payments may not be switched on in the sandbox. Check what Stripe's payment page offers before
  asking Jafar to change anything in his own Stripe account.

## Pointers

- docs/online-payments-behavior-contract.md §3 (invoice), §4 (deposit), §6 (pay-by-app).
- Database tests run against the remote project as one transaction that is rolled back; members cannot call
  `private.*`, so assert those helpers under `set local role postgres`.
- Customer links: quote/invoice ⋮ → **Copy customer link**. No email send needed. Greenfield Property Group's
  email is now `dev.jafarkhan+part8@gmail.com` so test sends stop bouncing off `.example.com`.
- The Stripe CLI is not needed — webhooks reach the app through the real Cloudflare Tunnel endpoint. Its
  stored key has expired anyway and re-login needs Jafar's browser confirmation.
