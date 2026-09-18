# Online Payments: Roadmap

Goal: contractors get paid online with the least possible setup. Customers pay invoices and quote deposits by
card through the contractor's own Stripe account, and see the contractor's Venmo/Zelle/Cash App/e-Transfer
details. Money always goes straight to the contractor.

Product truth: docs/online-payments-behavior-contract.md (approved 2026-09-18, incl. its 4 decisions).

## Approved direction (Jafar, 2026-09-18)

- Stripe Connect / Stripe Apps one-click is impossible: both need a platform-owned Stripe account, and Jafar is in
  Bangladesh. Chosen: contractor-owned Stripe via ONE pasted restricted key; UCRM creates the webhook endpoint
  through the API (the create response returns its signing secret). No documented prefilled key-creation link.
- Setup must be as easy as possible; plain-English guide plus assisted setup (Jafar via UltraViewer).
- Keep docs/jafar-completion-contract.md "Provider and CRM-dependent controls" rules. Reuse the AES-GCM keyring
  pattern in src/lib/server/communications/twilio-credential-crypto.ts.
- Schema, RLS, and money changes in this campaign are approved in principle; explain each migration's impact
  in plain English when it lands.
- Jafar: Stripe first; pay-by-app (Venmo etc.) after Stripe, "best way, most professional, so they love it".

## Parts

1. **Payments behavior contract** — Done 2026-09-18 (approved).
2. **Stripe connection** — Done 2026-09-18. Gate passed live with a sandbox restricted key: connect, check,
   signed test event 200, replace and disconnect remove their Stripe endpoints; key stored only encrypted.
3. **Customer pays invoice online** — Next; needs 2. Public invoice Pay button (partial + tips per contract) →
   Stripe Checkout → verified webhook → journaled, idempotent ledger receipt, async bank payments, overpayment
   guard, receipt email, notification, cache invalidation. Gate: test card pays once despite webhook retries.
4. **Online quote deposit** — needs 3. Gate: deposit satisfies the quote in test mode.
5. **Refunds, disputes, disconnect safety** — needs 3. In-app refund, dashboard refunds reflected, dispute
   alerts, stop sessions on disconnect/suspension. Gate: test refund reflected once.
6. **Pay-by-app methods** — needs 1; after Stripe per Jafar. Research first how top apps present these
   (Venmo/Cash App/PayPal links prefilled with amount+note where supported, QR codes, copy buttons, Zelle and
   e-Transfer instructions); add Venmo, Zelle, Cash App, e-Transfer to recorded methods. Gate: browser verified.
7. **Jafar Stripe slice** — needs 2–5. Jafar-panel Part 10 Stripe readiness/health/history/recovery.
   Gate: browser-verified; update jafar-panel Memory.
8. **End-to-end proof** — needs all. Full test-mode journey; guide screenshots. Gate: performance-review
   verification branch; Jafar sign-off.
