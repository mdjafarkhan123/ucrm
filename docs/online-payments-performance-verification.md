# Online Payments: Performance Verification

Verified 2026-09-20 against the live test setup (Raad LTD, Stripe sandbox). Method:
`.claude/skills/performance-review/references/verify.md`. Read-only review; no code or schema changed.

```text
Performance Verification – Online payments (Parts 2–9)
Workload contract : Assumed, not measured. Per business: tens of Pay clicks and webhook events a day, at most
                    a few hundred open/processing checkouts. Target: no request does work that grows with the
                    total number of businesses, and nothing on the customer's path is slower than Stripe itself.
Layers reviewed   : public Pay routes, Stripe webhook route, database lookups, Stripe API calls, disconnect

Layer                          | Evidence                                                                                                   | Result
-------------------------------|------------------------------------------------------------------------------------------------------------|-------
Correctness first              | Live proofs 2026-09-18..20: same event x3 -> one ledger row; card, bank success, bank failure, refund,    | ✅
                               | dispute, deposit, billing credit all landed once. pgTAP suites green per part.                             |
Public Pay routes (invoice,    | Two rate limits per request (per address 20/10min, per link 10/10min), run in parallel. Body is Zod-       | ✅
quote)                         | checked before any database or Stripe work. Per click: 1 locked database call, 1 Stripe call, 1 update.     |
Webhook route                  | 1 connection lookup by primary key, 1 signature check, 1 small update, 1 apply call. No loops. Bad         | ✅
                               | signature costs 1 lookup; the connection id is an unguessable uuid, so it is not a cheap flood target.      |
Database lookups               | Every lookup the payment paths make has an index (listed below). Live table sizes are tiny (15 checkouts,  | ⚠️
                               | 19 webhook events, 6 refunds) so query plans show nothing at scale; the index match is a reasoned bound.   |
Stripe waterfall               | Webhook money events add 1 extra Stripe read (which payment method was used). It fails soft to "Online    | ✅
                               | payment". Redelivery repeats that read: bounded by Stripe's retries, harmless.                              |
Disconnect                     | Expires open checkouts one by one. Runs once per disconnect, only over that business's open checkouts.     | ✅
Browser side                   | Pay pages load one small context call; the Stripe page is Stripe's own. No new heavy dependency.            | ✅

Indexes checked (all present): checkout by id, by session id, by payment intent, by invoice, by quote, by
payment event; refund by Stripe refund id and by checkout; webhook journal by (business, event id); connection
by business and by id.

Changes made       : none
Unverified/deferred:
- Query plans at scale: the tables are too small to show real plans. Reason: no realistic data volume exists.
  Impact: low, every lookup is an exact key match. Next decision: re-run EXPLAIN in the production-like load
  rehearsal that the launch gate already requires.
- Webhook journal (payment_stripe_webhook_events) has no clean-up. One small row per event, so growth is slow;
  no owner assigned. Decide a retention rule at the launch gate, not now.
- The webhook route has no rate limit of its own. Only Stripe-signed traffic does real work; unsigned traffic
  costs one key lookup. No owner assigned; revisit with the network-security review at the launch gate.
- No load test was run and none is required for this ordinary payment CRUD; the routes are not fan-out paths.
Capacity statement : not established. No concurrency test was run; the numbers above are reasoned bounds and
                     the live single-user proofs only.
Overall            : ⚠️ Partially verified (nothing blocks; the gaps are unmeasurable until there is real volume)
```
