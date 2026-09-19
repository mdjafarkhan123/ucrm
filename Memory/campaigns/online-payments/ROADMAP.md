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
3. **Customer pays invoice online** — Done 2026-09-18. Gate passed live in the sandbox: full pay, partial +
   15% tip, overpayment (cash recorded mid-checkout → applied 0 + refund alert), same event delivered 3× →
   one ledger row and one receipt. Not proven live: async bank payments (processing/failed paths) — prove in
   Part 8.
4. **Online quote deposit** — needs 3. Gate: deposit satisfies the quote in test mode.
5. **Refunds, disputes, disconnect safety** — Done 2026-09-19. Gate passed live: in-app refund settles
   pending→succeeded on its own (fresh webhook, ~12s), a dashboard-made refund is picked up with no in-app
   click, a real disputed payment alerts the right team members and links to the right invoice. Found+fixed a
   real bug along the way: `payment_stripe_webhook_events`'s `stripe_event_id` check constraint (from Part 3)
   only allowed a bare `evt_...` id and was silently rejecting every refund confirmation's compound dedup key
   — no refund could ever settle. Fixed in `20261010091000_payment_stripe_webhook_events_refund_key_format.sql`
   and 3 real refunds from before the fix were replayed to correct invoice #7's ledger. Disconnect-safety
   (expiring an open checkout when Stripe is disconnected) is code-complete but not live-tested — deferred by
   Jafar because testing it would require reconnecting Raad LTD's test Stripe key by hand afterward.
6. **Pay-by-app methods** — needs 1; after Stripe per Jafar. Done 2026-09-19 (not committed). Researched:
   Venmo (`venmo.com/u/<handle>?txn=pay&amount=&note=`), Cash App (`cash.app/$<handle>/<amount>`), PayPal.me
   (`paypal.me/<handle>/<amount><CURRENCY>`) all support prefilled deep links; Zelle and Interac e-Transfer have
   no such link anywhere (both are bank-to-bank from the sender's own banking app) so those stay copy-only,
   matching the contract's §6 as already written — no new product decision was needed, only the link formats.
   Data layer live-migrated (`20261011090000_online_payments_pay_by_app_methods.sql`): 6 new
   `organization_settings` columns, Venmo/Zelle/Cash App/e-Transfer added to both invoice and quote-deposit
   recorded methods, `set_organization_payment_settings` extended, and `invoice_online_payment_context` /
   `quote_online_deposit_context` return a `pay_by_app` object independent of Stripe connection (a business
   with no Stripe can still show these — confirmed live: a quote not yet approved, with no Stripe button
   shown, still displayed the pay-by-app box). UI built: Settings → Payments' new "Other ways to pay"
   `SectionBlock` with the 6 inputs (per-field save errors now surface under the right box — added
   `fieldErrors` to `settings/api.ts`'s `saveSection`, a small generalization every settings section's save
   now carries, though only Payments has fields that can fail validation); new shared
   `$lib/components/payments/OtherWaysToPay.svelte` (tappable Venmo/Cash App/PayPal.me, copy-button
   Zelle/e-Transfer/bank transfer); wired into `/i/[token]` and `/q/[token]`'s pay buttons, alongside Stripe
   when connected or alone when it isn't (`Button.svelte` gained an optional `target` prop for the three
   external app links). `svelte-check` 0 errors/warnings project-wide, Prettier clean. Live-verified in the
   browser on Raad LTD (test sandbox): saved all 6 fields, triggered and saw a real field-level validation
   error (bad PayPal.me handle) highlight the right box, then an existing past-due invoice (#11) and a
   freshly created test quote (#39, deposit added, not yet approved) both showed the box with correct
   prefilled amounts/memos in the Venmo/Cash App/PayPal.me links. Clipboard copy itself could not be verified
   through the browser-automation harness (`navigator.clipboard.writeText` hangs under CDP automation,
   unrelated to real browsers) — same proven pattern already used elsewhere in the app
   (`JobWorkReportCard.svelte` etc.), not re-verified here. Test quote #39 ("Pay-by-app verification",
   Greenfield Property Group) was left in Raad LTD from this verification — harmless test clutter, matching
   what's already in that sandbox. Gate met: browser-verified. Nothing committed yet — ask Jafar before
   committing.
7. **Jafar Stripe slice** — needs 2–5. Jafar-panel Part 10 Stripe readiness/health/history/recovery.
   Gate: browser-verified; update jafar-panel Memory.
8. **End-to-end proof** — needs all. Full test-mode journey; guide screenshots. Gate: performance-review
   verification branch; Jafar sign-off.
