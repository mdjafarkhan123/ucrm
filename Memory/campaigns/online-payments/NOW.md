# Online Payments: Current Checkpoint

Goal: contractors get paid online (Stripe card via one pasted key; later Venmo/Zelle/Cash App/e-Transfer) with
the easiest possible setup. Contract approved 2026-09-18.

## Status

Parts 1–7, 9a and 9b done and committed. Part 8 (end-to-end proof) is still paused mid-run. Details in the
roadmap.

## Exact next action

**Part 8 remainder** — needs Jafar at the keyboard to pay Stripe checkouts:

- First bill job #20 (quote #36, $3,510 deposit, no invoice yet) in the browser to see 9a work on real data.
- Then prove Part 3's two unproven async bank paths (`processing` → succeeded, and `async_payment_failed`) on
  a new test invoice — first check whether Stripe's page offers bank (ACH) in this sandbox.
- Then the guide screenshots and the performance-review verification write-up.

## Blockers

- The Claude Chrome extension has no permission for `checkout.stripe.com`, so the agent cannot fill Stripe's
  payment form; Jafar fills and pays each remaining checkout (worked for #27).
- The browser screenshot tool times out while a ⋮ menu or an open Select list is showing, though the app is
  fine. Drive the page with `javascript_tool` instead; to get a customer link, hook
  `navigator.clipboard.writeText` and click the menu item.
- Bank (ACH) payments may not be switched on in the sandbox. Check what Stripe's payment page offers before
  asking Jafar to change anything in his own Stripe account.

## Pointers

- docs/online-payments-behavior-contract.md §3 (invoice), §4 (deposit), §6 (pay-by-app).
- Database tests run against the remote project as one transaction that is rolled back; members cannot call
  `private.*`, so assert those helpers under `set local role postgres`.
- Customer links: quote/invoice ⋮ → **Copy customer link**. No email send needed. Greenfield Property Group's
  email is now `dev.jafarkhan+part8@gmail.com` so test sends stop bouncing off `.example.com`.
- Greenfield still has $260.86 of unspent deposits (quotes #34 and #31) and invoice
  #28 owes $270 — handy for further Add deposit checks.
- The Stripe CLI is not needed — webhooks reach the app through the real Cloudflare Tunnel endpoint.
