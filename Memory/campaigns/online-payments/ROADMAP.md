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
   what's already in that sandbox. Gate met: browser-verified. Committed `eb98c42`.
7. **Jafar Stripe slice** — needs 2–5. Done 2026-09-19, committed `4081c09`. A read-only "Stripe connection
   health" card in the organization Communications tab (account identity, live/test mode, last-checked time,
   sanitized health badge, manual "Recheck now"), backed by the existing `stripe-connection.ts` readiness
   module. No connect/disconnect controls for Jafar: the key is contractor-owned and never reaches the
   platform owner, so there's nothing to recover on that side — visibility plus recheck is the complete,
   intentionally narrower scope for this provider (docs/jafar-completion-contract.md). Browser-verified live
   on Raad LTD's sandbox connection: card loaded real status, "Recheck now" updated `last_checked_at` live.
   jafar-panel Memory updated.
8. **End-to-end proof** — needs all. In progress, paused by Jafar 2026-09-20. Full test-mode journey; guide
   screenshots. Gate: performance-review verification branch; Jafar sign-off.
   Proven live on Raad LTD's sandbox so far: quote #40 ($1,320, 25% deposit) sent by real email; customer page
   showed the test-mode banner and the pay-by-app box; approved + signed; **$330 deposit paid by card through
   Stripe**, confirmed by exactly one `checkout.session.completed` (`evt_1UHY35R5t9sA1JBVRibrSxqE`, outcome
   `paid`), recorded as a `quote_deposit_events` row with method `stripe_card` and the payment-intent
   reference — **Part 4's gate passed live**. Quote → job #23 → **invoice #27** ($1,200) raised and issued.
   Still unproven: invoice card payment + tip, automatic receipt, and Part 3's two async bank paths
   (`processing` → succeeded, `async_payment_failed`). Guide screenshots and the verification write-up not
   started.
   Environment note: the Claude Chrome extension has no permission for `checkout.stripe.com`, so the agent
   cannot fill Stripe's form; Jafar paid the deposit by hand. Resolve before the remaining payments.
9. **Quote deposit reaches the invoice** — surfaced by Part 8, pre-existing and method-independent. Jafar
   approved 2026-09-20: follow Jobber's unallocated → applied lifecycle, applied automatically at billing.
   - **9a automatic application** — Done 2026-09-20, committed `5eee391`. `create_invoice_from_work` now
     credits the deposit paid on the quote behind the billed work, capped at what the bill owes; no table or
     column changes, because the ledger, the available-credit helper and the invoice display already existed.
     12 pgTAP assertions green (`supabase/tests/database/quote_deposit_applied_when_work_is_billed.sql`).
     Gate met. Not yet seen in the browser — job #20 (quote #36, $3,510 deposit, no invoice yet) is the live
     proof waiting to be billed.
   - **9b leftover credit is spendable by hand** — needs 9a. Jobber's invoice **Deposits (Add Deposit)** row
     (`jobber-05-invoices-payments.md` §174): leftover client credit goes onto any of that client's invoices.
     `public.apply_client_payment` already does this in the database and is reachable from no route or screen;
     the work is an `/api/*` route plus the dialog. Gate: browser-verified on a real leftover credit.
     Known live case: invoice #27 is fully paid while quote #40's $330 deposit sits unspent — it needs 9b (or
     a refund) to settle, and is why 9b should land before a first paying client.
