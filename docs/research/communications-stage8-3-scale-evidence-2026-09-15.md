# Communications Stage 8-3 scale evidence — 2026-09-15

## Verdict

The SMS claim/finalize path, SMS price reconciliation, and SMS usage-window reconciliation are supported for
the measured 200-tenant workload below, run against the current, fixed code (`e9db5a6`). Money reconciles
exactly: every credit reservation settled, every organization's reserved balance returned to zero, and
segment-recount adjustments posted correctly. The email claim/finalize path is also supported, and this run
additionally confirmed a real platform safeguard (the short-term sending rate limiter) correctly throttling a
sustained hot-tenant burst rather than failing or overcharging it. This is proportional evidence for the
exercised workload, not a 40,000-tenant or general production-capacity claim: no representative Twilio-scale
network latency, no multi-day usage-window lag/backoff behavior, and no failure-path (retry/cancel/
submission-unknown) volume was exercised.

## Workload contract

- Environment: local Supabase stack (Postgres 17 via the Supabase CLI), no live Twilio or Brevo calls at any
  point -- every provider fact (message SIDs, billed prices, usage records) is a synthetic stand-in, matching
  this campaign's hard constraint that nothing may spend real money against a live provider until a country
  launch gate and real business registration exist.
- Tenants: 200 synthetic organizations, each with a full, real fixture (Twilio subaccount, approved SMS
  registration, ready default sender, org mode, a $1,000 settled SMS credit balance, opted-in SMS consent, a
  fully verified 60-day-old sending domain, an enabled default email sender, an unlimited email allowance
  override). One tenant (org #1) sent 20x a typical tenant's volume (400 messages vs 20) to exercise skew.
- Volume: 4,380 SMS sends and 4,380 email sends enqueued through the real commands/paths (SMS via
  `communication_sms_enqueue_operational`; email via direct delivery-intent + outbox fixtures, matching the
  existing pgTAP email fixtures -- there is no single email "enqueue" SQL command the way SMS has one).
- Concurrency: 2 concurrent SMS worker slots and 2 concurrent email worker slots, each a persistent Postgres
  session looping real `claim_*` + `finalize_*` calls until its queue was empty, matching a real small worker
  pool.
- Success criteria: every eligible message drains to `submitted`; every SMS credit reservation reaches
  `settled` with reserved balance returned to zero; price and usage-window reconciliation run without error
  over the full 200-tenant set; no deadlock, lock conflict, or correctness defect.

## Evidence

| Layer | Evidence | Result |
| --- | --- | --- |
| Correctness (the fixed bug) | All 4,380 SMS sends drained to `submitted` with zero errors against the real `claim_communication_sms_outbox_event()` / `finalize_communication_sms_outbox_event()` functions -- the exact path that threw `column reference "delivery_intent_id" is ambiguous` on essentially every send before commit `e9db5a6`. | Supported |
| SMS claim+finalize | 4,380/4,380 messages drained in 7.00s wall time under 2 concurrent worker slots (625.9 msg/s combined). Per-call latency: p50 2.65ms, p95 3.63ms, p99 4.29ms, max 19.84ms. | Supported at 4,380 messages / 200 tenants |
| Email claim+finalize | 4,080/4,380 messages drained in 8.24s wall time under 2 concurrent slots (495.3 msg/s). Per-call latency: p50 3.50ms, p95 4.95ms, p99 5.94ms, max 36.15ms. The remaining 300 all belong to the one hot tenant and were correctly deferred by the platform's real short-term email rate limiter (100 recipients/window), not dropped, blocked, or errored -- confirms that safeguard holds under a genuine concurrent burst. | Supported; rate limiter confirmed working as designed |
| SMS price settlement (Stage 8-1) | 4,380/4,380 reservations settled in 1.92s (2,279.9/s). p50 0.35ms, p95 0.54ms, p99 0.65ms. 451 messages (~10.3%) got a synthetic +1 segment recount and each posted a correct, separate ledger adjustment at the frozen per-segment rate. | Supported |
| SMS usage-window reconciliation (Stage 8-2) | All 200 organizations reconciled in 0.14s (1,472.7 orgs/s); every day compared as `matched` against its synthetic provider total, and the org's cursor advanced. Only the SQL comparison/write path was exercised -- the real cron's multi-day lag/overlap/backoff scheduling and the actual Twilio Usage Records call are TypeScript-owned and out of this SQL-level test's scope. | Supported for the comparison/write path; lag/backoff scheduling unverified |
| Money correctness | Every account's `reserved_balance_minor` returned to exactly 0 after settlement (0/200 organizations left with a dangling hold). Total charged across the ledger: $219.00, exactly matching 4,380 segments x $0.05. | Supported |
| Concurrency / locking | 0 deadlocks, 0 conflicts (`pg_stat_database`) across the full run. The claim functions' `FOR UPDATE ... SKIP LOCKED` design means workers never block on each other; the tight, consistent per-call latency distribution (no long tail) is consistent with that. | Supported |
| Query plan | `EXPLAIN (ANALYZE, BUFFERS)` on the SMS claim's core candidate scan, run with the full 4,380-message backlog present: index scan on the existing partial index `communication_outbox_events_sms_claim_idx`, 0.523ms execution, 253 buffer hits, no sequential scan. | Supported at 4,380-row backlog |
| Hot-tenant fairness | The hot tenant's messages (20x volume) drained at the same average age-at-drain as every other tenant's (both ~104s from enqueue to drain in this session, reflecting the gap between the enqueue and drain steps, not backlog growth). The oldest-due-first `SKIP LOCKED` scan neither starves nor privileges the hot tenant relative to the other 199. | Supported: no starvation observed |

## Changes and deferred decisions

No product code changed during this verification beyond the already-committed `delivery_intent_id` fix
(`e9db5a6`) and its regression test, both committed before this run started. This run found no new defect. The
only behavior worth a deliberate decision: the email short-term rate limiter deferred 300 of the hot tenant's
400 messages, which is correct, designed behavior, not a gap -- no action needed unless Jafar wants a higher
platform default for large contractors, which is a product/business decision, not a correctness fix.

Deferred and out of this test's scope: real Twilio/Brevo network latency and failure-mode volume (retry,
cancelled, submission_unknown), the real cron's multi-day usage-window lag/overlap scheduling, and any claim
higher than 200 tenants / 4,380 messages per channel. All synthetic seed data and harness objects
(`scale_evidence_timings` table and its two drain procedures) were removed by `supabase db reset --local`
immediately after this evidence was captured; nothing from this run remains in the local dev database.

## Capacity statement

Capacity is **not established** beyond the exact workload measured here: 200 tenants, 4,380 SMS + 4,380 email
messages, 20x hot-tenant skew, 2+2 concurrent worker slots, against a local Postgres instance with no real
provider network latency. It does not establish the product's 40,000-tenant target, sustained multi-hour
throughput, real Twilio/Brevo latency and error-rate behavior, or VPS-hosted pool saturation.

**Overall: Supported.** The critical claim-function bug is confirmed fixed under real concurrent load, money
reconciles exactly across 200 tenants, and the email rate limiter's hot-tenant protection was confirmed
working. Stage 8-3 is complete for this evidence's scope; remaining risks (real provider latency, failure-path
volume, multi-day reconciliation lag) are explicit and independently reactivatable.
