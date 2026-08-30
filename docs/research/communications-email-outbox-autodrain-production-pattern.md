# Communications email-outbox automatic drain: production pattern

Research date: 2026-08-29

## Question

How should UCRM automatically drain its transactional email outbox while the app is reached through a
Cloudflare Tunnel and uses managed Supabase, without creating a second queue or making unsupported capacity
claims? How should the same design move later to a supervised VPS worker?

## Recommendation

Keep Postgres as the single durable delivery ledger. For the current deployment, use one **named Supabase
Cron job** to wake the authenticated SvelteKit email-worker route through `pg_net` every minute. Each wake must
be a bounded, idempotent attempt to make progress, not a promise that the queue is empty. When the VPS is
ready, run the same drain function in one supervised worker container and retire the frequent HTTP wake only
after a no-double-run cutover.

This is the transactional-outbox/competing-consumer pattern already present in the repository. PostgreSQL
explicitly documents `SKIP LOCKED` as suitable for avoiding contention among consumers of a queue-like table.
[PostgreSQL `SELECT`](https://www.postgresql.org/docs/17/sql-select.html)

Do not add Redis, BullMQ, or a second email queue for this activation. They would duplicate the existing
Postgres eligibility, retry, deduplication, and recovery state without evidence that the database claim path is
the bottleneck.

## Initial operating envelope

Use these as conservative activation settings to verify, not as capacity claims:

| Control | Initial value | Reason |
| --- | ---: | --- |
| Stable scheduler name | `communications-email-outbox-wake-one-minute` (environment-qualified if multiple environments share monitoring) | A stable identity survives job-id changes and lets monitoring group all runs of this worker. `cron.schedule(name, ...)` is the established named-job primitive. |
| Wake interval | 60 seconds | Gives operational mail a predictable dispatch opportunity while leaving room for a short request to finish. Supabase supports schedules from every second to yearly, but recommends at most eight concurrent jobs and jobs shorter than ten minutes. [Supabase Cron](https://supabase.com/docs/guides/cron) |
| Claim concurrency | 2 | Matches the repository's conservative bounded-drain default and limits simultaneous Brevo, R2, and database work until measured evidence supports more. |
| Maximum claims per wake | 50 | Bounds provider bursts and makes a large backlog yield to the next tick. |
| Drain admission budget | 20 seconds | Stop starting new claims after this point. The current implementation already uses this value. |
| Whole-route deadline | no more than 40 seconds | Includes the last admitted claim, database finalization, and response serialization; every external operation also needs its own shorter timeout. |
| `pg_net` HTTP timeout | 50 seconds | Must be explicit: published Supabase docs and current extension source have differed on the default. It remains above the route deadline and below the next 60-second wake. Verify the installed version in staging. [Supabase `pg_net`](https://supabase.com/docs/guides/database/extensions/pg_net), [`pg_net` SQL source](https://github.com/supabase/pg_net/blob/master/sql/pg_net.sql) |
| Wake lease | approximately 55 seconds | A database-backed singleton lease prevents two HTTP invocations from multiplying the configured concurrency. It expires automatically after a crash and is still shorter than the next normal tick. |

The intended ordering is:

```text
provider/R2 operation timeout < whole route deadline < pg_net timeout < wake interval < stale-claim age
```

Cloudflare's current default proxied origin read timeout is 125 seconds. The proposed route deadline is far
below that limit, but Cloudflare's limit is only an outer guard and must not become the application's work
budget. [Cloudflare error 524](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/)

## Overlap and concurrency

`pg_cron` runs only one instance of a particular database job at once and queues a later occurrence if the
first is still running. That protection does **not** cover this topology: `net.http_post` enqueues asynchronous
work and returns a request ID before the HTTP route finishes. Therefore the cron SQL can finish while the
route is still draining. [`pg_cron` README](https://github.com/citusdata/pg_cron),
[`pg_net` docs](https://supabase.com/docs/guides/database/extensions/pg_net)

Use two layers:

1. Keep the existing atomic `FOR UPDATE SKIP LOCKED` message claim and token-checked finalization. This is the
   correctness boundary if workers compete.
2. Add a short database-backed lease keyed by worker name at route entry. A wake that cannot acquire it should
   return a successful `already_running` result without draining. Do not rely on an in-process boolean because
   it fails across restarts and future replicas. Do not hold a pooled advisory lock across multiple HTTP/RPC
   transactions.

The lease bounds routine concurrency; the message claim still protects correctness if a lease expires during
an unusually slow call.

## Batches, backlog, retry, and idempotency

- Quarantine stale claims once at the start, then claim/send/finalize in two competing slots until the queue is
  idle, 50 claims have been attempted, or the admission budget expires.
- When the cap or budget is reached, return that reason and let the next minute's wake continue. Never turn an
  HTTP request into an unbounded `while queue not empty` loop.
- Alert from Postgres truth: due-row count and oldest-due age globally and by organization. A hot tenant test
  must prove that small tenants are not starved before claiming fairness.
- Keep retry timing in Postgres only. Treat `408`, `429`, and provider `5xx` as retryable and use Brevo's
  `x-sib-ratelimit-remaining` and `x-sib-ratelimit-reset` headers to pace later attempts; do not sleep inside a
  drain slot for a long reset. Brevo recommends using these headers and exponential backoff.
  [Brevo rate-limit headers](https://developers.brevo.com/docs/limit-headers)
- Preserve the stable delivery-intent UUID as Brevo's `idempotencyKey` on an identical retry. Brevo documents
  a 30-minute TTL, so this is defense in depth rather than an exactly-once guarantee. A timeout after possible
  acceptance must remain `submission_unknown` for reconciliation, not be blindly retried.
  [Brevo idempotency](https://developers.brevo.com/docs/heterogenous-versions-batch-emails)
- Before activation, verify that the final retry becomes an explicit terminal/recovery state and that every
  retry time is capped by the intent deadline. The current architecture review identified an indefinite
  `available_at = infinity` final failure as an activation concern; scheduling must not make it less visible.

## Scheduler observability

A returned `pg_net` request ID proves only that the HTTP request was queued. It does not prove that the route
returned success or drained a message. `pg_net` stores `status_code`, `timed_out`, `error_msg`, and response
content in `net._http_response`, and its own documentation says to monitor that table. Responses are unlogged
and retained for six hours by default. [`pg_net` source documentation](https://github.com/supabase/pg_net)

For durable, attributable monitoring, the scheduler wrapper should record a minimal wake ledger containing
the stable worker name, `pg_net` request ID, and dispatch time. A reconciler/view can join recent entries to
`net._http_response` and persist the actual HTTP outcome before the six-hour TTL. This follows `pg_net`'s
official request-tracker wrapper pattern. Do not alert on `cron.job_run_details.status = succeeded` alone: for
an asynchronous HTTP job, it may only mean that Postgres successfully enqueued the request.

Monitor both layers:

- Cron: named job is active; expected ticks exist in `cron.job_run_details`; no repeated scheduler failures.
- HTTP wake: actual `2xx`, `401/403`, `5xx`, `timed_out`, and `error_msg`, plus route result (`idle`,
  `max_claims`, `time_budget`, or `already_running`).
- Queue: due count, oldest due age, processing count, oldest claim age, retry count, cancellation count,
  `submission_unknown` count, and last successful finalize time.
- Provider: latency, HTTP status, rate-limit remaining/reset, and time spent throttled.

Initial alert policy should be tied to the approved operational-delivery objective, not user count. At minimum,
page immediately for authentication failures or a growing `submission_unknown` set; alert after two consecutive
missed/non-`2xx` wakes; and alert when oldest-due age breaches the approved delivery objective. Repeated
`max_claims` or `time_budget` results are backlog-pressure signals to measure before changing concurrency.

## Secrets and route exposure

Store the full worker URL and bearer secret in Supabase Vault, read them at execution time, and keep only
placeholders/names in migrations. Vault stores secret values encrypted on disk and exposes decrypted values
through a view at query time; access to that view must be tightly restricted.
[Supabase Vault](https://supabase.com/docs/guides/database/vault). Supabase's own scheduled-function pattern
uses Cron, `pg_net`, and Vault together.
[Supabase scheduled functions](https://supabase.com/docs/guides/functions/schedule-functions)

The Vault bearer value must match the server-only `COMMUNICATIONS_WORKER_SECRET`. The route should remain POST
only, compare the bearer token safely, return `Cache-Control: no-store`, and never expose the Brevo API key or
Supabase service role. Rotation is: update server secret and Vault secret as one controlled change, verify an
authorized canary, then revoke the old value.

## Staged activation evidence

1. **Preflight:** confirm extensions, named job uniqueness, Vault values, route authorization (`401` without the
   secret), explicit timeouts, and an empty-queue `2xx` whose `pg_net` response is attributable to the stable job.
2. **Single-message canary:** schedule one plain operational email, then one attachment email. Record enqueue,
   wake, claim, Brevo message ID, finalize, webhook, and inbox receipt timestamps.
3. **Failure cases:** prove provider `429`/`5xx`, network timeout, crash after possible acceptance, stale-claim
   quarantine, duplicate wake, invalid bearer, and tunnel outage. Verify no lost outbox row and no blind resend
   of `submission_unknown`.
4. **Bounded backlog:** enqueue a measured multi-tenant burst including one hot tenant. Verify the 50-claim cap,
   two-slot concurrency, next-tick continuation, per-tenant oldest-due age, database connections, R2 latency,
   and Brevo limit headers.
5. **Soak:** run the schedule through at least one full daily operating cycle with dashboards/alerts enabled;
   reconcile wake-ledger outcomes against queue transitions and provider callbacks.
6. **Go/no-go:** activate for normal operational traffic only if rollback is rehearsed (disable the named job),
   unknown outcomes are recoverable, and measured latency/backlog stays inside the approved objective. Evidence
   supports only the exercised workload, not 40,000-user capacity.

## VPS transition

Package the same drain entry point in a dedicated worker service. The worker should use short idle polling with
backoff, the same bounded concurrency and Postgres claims, structured health/progress signals, and graceful
`SIGTERM` handling that stops new claims and gives in-flight finalization a bounded grace period. Configure a
Docker restart policy and healthcheck; Docker recommends restart policies for automatic recovery, and Compose
supports health checks and a `stop_grace_period` before `SIGKILL`.
[Docker restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/),
[Compose services](https://docs.docker.com/reference/compose-file/services/)

Cut over with only one active wake owner: deploy and verify the worker while sends are paused or against an
empty canary lane, disable the one-minute Cron job, start the supervised worker, then resume. Keep a slower Cron
safety wake only if it uses the same database lease and has a tested purpose; otherwise disable it to avoid two
schedulers obscuring worker health.
