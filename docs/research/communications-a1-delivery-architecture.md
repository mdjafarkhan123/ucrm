# Communications A1 email-delivery architecture

Research date: 2026-08-28

## Question

Should A1 activate the existing email outbox with a Redis/BullMQ sending engine, or use the existing
Postgres queue with a Supabase-scheduled, bounded worker loop?

## Verdict

Use the existing Postgres outbox as the only durable queue and run a **bounded competing-consumer drain**.
For the current remote-Supabase deployment, Supabase Cron should wake the authenticated SvelteKit worker
route through `pg_net`. When the app moves to an always-on VPS, the same drain can run continuously in a
supervised Docker worker and Cron can become a slower safety wake-up or be disabled.

Do **not** add Redis, BullMQ, or Supabase Queues in A1. Redis would be a second delivery ledger that needs an
outbox-to-Redis relay, missed-enqueue reconciliation, persistence and monitoring. If BullMQ is reduced to a
repeating “wake the Postgres drain” job, it adds no useful behavior over Cron. If it owns one job per email,
it duplicates the retry, delay, deduplication and recovery state that Postgres already owns.

This verdict applies to operational email only. Registered-user count does not establish send throughput.
The missing workload facts are simultaneous sending organizations, peak accepted recipients per second,
tenant skew, provider latency, attachment bytes, and the Brevo account's actual quota. Marketing is a later,
separate lane and may use Brevo's campaign/batch primitives rather than this per-recipient transactional path.

## What already exists

The repository is not choosing a queue from scratch:

- The [delivery foundation](../../supabase/migrations/20260823080419_communications_email_delivery_foundation.sql)
  creates one outbox row per intent, a due-row partial index, a unique logical-send key, and an atomic
  `FOR UPDATE SKIP LOCKED` claim.
- The [current claim policy](../../supabase/migrations/20260908100000_communications_retry_deadlines.sql)
  rechecks expiry, organization state, recipient, suppression, sender/domain health, warm-up, short-term
  tenant limits, provider capacity, and allowance before returning a claim token.
- [Finalization and stale-claim quarantine](../../supabase/migrations/20260824100947_communications_email_capacity_claim.sql)
  make repeated finalization with the same token safe, record usage once, defer transient failures, and move
  an abandoned provider outcome to `submission_unknown` rather than blindly resend it.
- The [email worker](../../src/lib/server/communications/email-worker.ts) and
  [forward worker](../../src/lib/server/communications/forward-worker.ts) already perform the external R2 and
  Brevo work outside the claim transaction. Only their HTTP routes are stubbed, and each module currently
  handles one claim per call.
- The [transactional webhook route](../../src/routes/api/webhooks/brevo/transactional/+server.ts) authenticates,
  stores the raw callback with a uniqueness key, and returns success for duplicates; SQL later projects
  delivery outcomes and suppressions.

This is already the standard transactional-outbox boundary: Postgres owns eligibility and history; a worker
owns slow external I/O; claim and finalize are separate short transactions.

## Architecture comparison

| Concern | Existing Postgres outbox + bounded drain | Redis/BullMQ in front of the outbox |
| --- | --- | --- |
| Durability | One authoritative record, already backed by constraints, history and recovery UI. | Requires a relay and reconciliation because a Postgres commit and Redis enqueue cannot be one transaction. Redis durability also has to be operated: Redis says RDB snapshots may lose the latest minutes, while default once-per-second AOF may lose about one second; it recommends RDB+AOF when PostgreSQL-like data safety is wanted. [Redis persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/) |
| Atomic claim | Already implemented with `SKIP LOCKED` and claim tokens. More workers can safely compete. | BullMQ safely assigns jobs, but the worker must still claim Postgres because Postgres owns current eligibility and allowance. The Redis lease does not replace the database claim. |
| Retry/backoff | Already encoded once in `available_at`, attempt count, expiry, and terminal/unknown states. | BullMQ supports fixed/exponential backoff and jitter, but enabling it would create two retry clocks unless BullMQ merely wakes the database. [BullMQ retries](https://docs.bullmq.io/guide/retrying-failing-jobs) |
| Duplicate risk | Enqueue and finalize are locally idempotent. The unavoidable provider-call/finalize gap is quarantined as unknown. | BullMQ describes worst-case delivery as at least once, and a stalled job is put back in waiting and may run again. Its own guidance requires idempotent, atomic jobs. [BullMQ overview](https://docs.bullmq.io/), [stalled jobs](https://docs.bullmq.io/guide/workers/stalled-jobs), [idempotent jobs](https://docs.bullmq.io/patterns/idempotent-jobs) |
| Deduplication | Unique logical send and one outbox row per intent remain for the life of the business record. | A custom BullMQ job ID blocks a duplicate only while that job remains in the queue; after removal, the same ID can be added again. [BullMQ job IDs](https://docs.bullmq.io/guide/jobs/job-ids) |
| Rate limiting | Current provider/tenant policy remains in the authoritative claim. Brevo's response headers can tune global submission pacing. | BullMQ OSS has a global queue limiter, but per-customer group keys were removed in v3. Independent group rate limits/concurrency are BullMQ Pro features, so Redis OSS does not solve tenant fairness. [BullMQ rate limiting](https://docs.bullmq.io/guide/rate-limiting), [Pro group rate limiting](https://docs.bullmq.io/bullmq-pro/groups/rate-limiting), [Pro group concurrency](https://docs.bullmq.io/bullmq-pro/groups/concurrency) |
| Recovery/visibility | The product's delivery history, unknown state, suppressions, and Platform Owner recovery queue all read Postgres directly. | BullMQ can export queue-state metrics to Prometheus, but those metrics would describe the secondary wake-up queue, not necessarily the authoritative email state. [BullMQ Prometheus metrics](https://docs.bullmq.io/guide/metrics/prometheus) |
| Operational cost | One scheduler, the existing database, and the application worker. | Adds a package, Redis connections, persistence/backups, worker lifecycle, queue cleanup, alerts, relay repair, and divergence runbooks before it improves a measured bottleneck. |

Supabase Queues is also unnecessary here. It is a Postgres-native pull queue with visibility-timeout delivery,
but Supabase's own consumer example leaves a failed message in the queue so a later invocation reads it again.
That is useful queue behavior, not exactly-once execution of an external email send. Migrating would duplicate
the richer application outbox and policy already present. [Supabase Queues](https://supabase.com/docs/guides/queues),
[Queue consumer example](https://supabase.com/docs/guides/queues/consuming-messages-with-edge-functions),
[Queues API](https://supabase.com/docs/guides/queues/api). It would also add version-sensitive delay behavior;
Supabase's changelog records a pgmq 1.4.4-to-1.5.1 delay change that temporarily halted upgrades.
[Supabase breaking-change changelog](https://supabase.com/changelog?types=breaking-change)

## Recommended A1 path

```text
application transaction -> Postgres intent + outbox
Supabase Cron wake-up -> authenticated bounded drain -> atomic Postgres claim
-> R2 attachment read -> Brevo submit -> token-checked Postgres finalize
Brevo callback -> authenticate + persist -> idempotent SQL projection -> history/suppression
```

1. Un-stub both internal routes and have each call a bounded drain, not an unbounded request loop. Quarantine
   stale claims once per drain, then run a small fixed number of asynchronous claim/send/finalize slots until
   the queue is idle, a maximum claim count is reached, or a time budget expires. Keep the maximum below the
   HTTP timeout and below the wake interval so routine invocations do not overlap.
2. Wake the routes with the repo's existing Vault + `pg_cron` + `net.http_post` convention. Supabase Cron can
   run from every second to yearly, records runs in `cron.job_run_details`, recommends no more than eight
   concurrent jobs, and recommends jobs finish within ten minutes. `pg_net` is asynchronous and currently
   beta; its POST default timeout is two seconds and responses are retained for six hours, so A1 must set an
   explicit timeout and monitor the HTTP result rather than treating a returned request ID as a successful
   drain. [Supabase Cron](https://supabase.com/docs/guides/cron),
   [`pg_net`](https://supabase.com/docs/guides/database/extensions/pg_net). `pg_cron` runs only one instance of
   a given database job at once, although an asynchronous `pg_net` call returns before the remote handler is
   necessarily finished; the route's own time bound is therefore still required.
   [`pg_cron` source project](https://github.com/citusdata/pg_cron)
3. On VPS deployment, call the same drain from a supervised long-running Node worker with idle polling
   backoff, graceful shutdown, and bounded concurrency. Do not fork a second delivery implementation.
4. Keep Postgres as the sole owner of retry timing. Brevo returns `429` with limit/remaining/reset headers and
   tells clients to use them for retry pacing. Capture those headers, pause new provider submissions until the
   reset, and finalize each claimed item through the existing database retry path.
   [Brevo rate-limit headers](https://developers.brevo.com/docs/limit-headers),
   [Brevo API limits](https://developers.brevo.com/docs/api-limits)

Initial concurrency is a conservative configuration to verify, not a capacity claim. Choose it from the live
Brevo response headers and measured request latency. Increasing worker count before that evidence only creates
larger provider bursts and more simultaneous database/R2 work.

## Correctness points A1 must close

### Provider idempotency and unknown outcomes

Brevo documents an `idempotencyKey` UUID in the email's `headers` map. Reusing the key for an identical retry
prevents a second processing within its documented 30-minute TTL. Use the delivery-intent UUID as the stable
key and keep the existing UCRM tag for webhook correlation.
[Brevo idempotency](https://developers.brevo.com/docs/heterogenous-versions-batch-emails)

That TTL is defense in depth, not an exactly-once guarantee. A timeout after provider acceptance can still be
ambiguous, especially after the TTL. Keep `submission_unknown` non-retryable until a provider callback or an
operator reconciles it. Never let BullMQ, Cron, or a worker restart blindly resubmit an unknown outcome.

The provider request also needs an explicit abort timeout. Otherwise a hung request consumes a worker slot and
eventually becomes a stale claim without a controlled outcome.

The existing database retry sequence should remain authoritative, but A1 should verify that every retry time is
capped by the intent's `expires_at` and that the final attempt becomes an explicit terminal/recovery state. The
current finalizer can set `available_at = infinity` after its retry ladder, which bypasses the later expiry check;
activation should not leave an indefinite failed row whose intended deadline can never run.

### Tenant fairness

The 100-recipient/10-minute organization rule is rate control and bounds the size of a hot tenant's burst; it is
not strict fair scheduling. Both the current global FIFO claim and BullMQ OSS FIFO can let one tenant occupy all
worker slots until that burst is claimed. Redis therefore does not justify the roadmap's fairness assumption.

For A1's operational-only workload, do not build a general multi-lane scheduler without a latency requirement.
Instead, measure oldest-due age by organization in a skew test (one hot tenant plus many one-message tenants).
If other tenants miss the approved operational-delivery target, change the Postgres candidate selection or add a
per-tenant in-flight bound. A3 must use a distinct marketing lane regardless, so a campaign can never enter the
operational FIFO.

### Webhooks, bounces and suppressions

Brevo exposes sent, delivered, deferred, soft/hard bounce, spam, invalid, blocked, error and unsubscribe events,
and supports bearer-token webhook authentication. The current route and raw-event dedupe align with those
primitives. [Brevo transactional webhooks](https://developers.brevo.com/docs/transactional-webhooks),
[secure webhooks](https://developers.brevo.com/docs/secured-webhooks)

One current failure response is unsafe: Brevo documents that any webhook `5xx` stops retrying and discards the
event, while `429` remains retryable. If durable callback insertion fails transiently, return `429` (and log/alert)
rather than the current `500`; return `2xx` only after the raw event is durable. Brevo retries an unresponsive or
`429` endpoint four times at 10 minutes, 1 hour, 2 hours and 8 hours.
[Brevo webhook retry mechanism](https://developers.brevo.com/docs/retry-mechanism)

## Recovery and verification evidence

A1 should expose or alert on Postgres truth, not just process logs:

- due backlog count and oldest due age globally and by organization;
- processing count, oldest claim age, quarantined/unknown count, retry/cancel/submitted rates;
- worker wake result and last successful claim/finalize time;
- Brevo latency, HTTP status, remaining/reset limit headers, and time spent rate-limited;
- unprocessed callback count/oldest age, duplicate callback count, and bounce-to-suppression latency.

Verification must cover:

1. one plain email and one attachment email reaching a real inbox with the expected From/Reply-To;
2. a burst spread across tenants plus a 100-recipient hot tenant, recording queue age and database connections;
3. a provider `429`, timeout before acceptance, crash after acceptance/before finalize, and stale-claim quarantine;
4. duplicate and out-of-order delivered/hard-bounce callbacks, suppression before the next eligible send, and a
   simulated callback persistence failure that receives Brevo-compatible retry treatment;
5. scheduler/tunnel downtime followed by recovery with no lost outbox row and no automatic resend of an unknown;
6. the forward worker and the Platform Owner recovery queue.

These tests establish behavior at the exercised burst and configured concurrency only. They do not establish
capacity for 40,000 users; that claim requires measured production-like send rate, tenant skew, provider latency,
database/R2 load, and backlog-drain time.

## A1 scope boundary

Include worker activation, bounded draining, schedule/daemon lifecycle, explicit provider timeouts, Brevo
idempotency, database-owned retry/deadline correctness, callback durability, bounce/suppression proof,
forwarding, and operational metrics/recovery.

Exclude Redis/BullMQ, pgmq migration, SMS, Automation, marketing tables or lanes, campaign recipient batching,
provider-native marketing campaigns, a generic workflow engine, and any untested throughput claim. Revisit a
Redis dispatch layer only when measurements show the Postgres claim/wake path—not Brevo quota, R2, or tenant
policy—is the bottleneck, and only with an explicit relay/reconciliation design.
