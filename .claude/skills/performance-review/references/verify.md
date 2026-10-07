# Performance Verification

Verify the coherent changed path once all affected layers exist. This is an evidence review, not a requirement to
touch every layer or install monitoring, caching, or load-testing tools. Preserve correctness and authorization
while optimizing.

## 1. Reconstruct the contract and scope

Read the approved design verdict when one exists. Otherwise state the growth variable, expected workload, and
delivery/correctness target from available requirements; label assumptions. Inspect the current implementation
and any relevant diff or history when present, then trace the actual path end to end. List only affected layers.

A registered-user count is not a workload. A capacity claim needs the exercised concurrency, request/event mix,
data shape, duration, environment, and success criteria.

**Done when:** the review has a bounded path, workload, baseline or target, and complete affected-layer list.

## 2. Establish correctness first

Run the narrow correctness checks for the path before interpreting performance evidence. Confirm tenant isolation,
authorization, ordering, consistency, retries/idempotency, and failure behavior relevant to the change. A faster
incorrect result is a block.

If the task is review-only, report findings without editing. If fixes are authorized, make only in-scope confirmed
fixes. Schema, RLS, permissions, packages, infrastructure, and external services still require their normal gates
and approvals.

## 3. Collect proportional evidence

Apply every relevant section below and omit the rest. Compare with an existing baseline or stated target when
available; do not invent a universal threshold.

### Database and data access

- Identify the exact queries/RPCs, call count, projection, expected cardinality, tenant/RLS predicates, ordering,
  and maximum result size. Detect N+1 and repeated reads by counting round trips, not by assuming connection use.
- Verify pagination remains deterministic and bounded at the expected depth. Deep offset cost can justify keyset
  pagination; shallow or random-access use can justify offset.
- Check each relevant index against the actual predicate, join, order, referential action, and data distribution.
  Account for redundant indexes and write/storage cost. A foreign key or RLS column is a reason to inspect, not an
  automatic index mandate.
- For material reads, use `EXPLAIN (ANALYZE, BUFFERS)` with representative data when execution is safe; use plain
  `EXPLAIN` for unsafe writes. Read actual versus estimated rows, loops, buffers, sorts/spills, and elapsed time.
  A sequential scan or nested loop is not a defect when it is cheapest for the observed cardinality.
- Test live aggregates first. Recommend maintained counters, read models, or materialization only when evidence
  misses the workload and freshness/repair/write trade-offs are acceptable.
- Determine whether the path uses the Supabase Data API/PostgREST or an application Postgres driver before reviewing
  pooling. For a driver, verify the current deployment’s persistent/transient connection mode, pool budget,
  transaction/session requirements, timeouts, and saturation; never prescribe a port from file type alone.

Load Supabase Postgres best practices for Postgres diagnosis or any SQL/schema/RLS/index fix, then read its relevant
rule files. Do not change RLS semantics for speed.

### API, algorithms, and dependencies

- Count database and external calls, including calls inside loops. Run independent I/O concurrently only when
  downstream capacity, ordering, rate limits, transactions, and memory make it safe.
- Measure response/request bytes and serialization work; verify user-controlled input and list/bulk output are
  bounded.
- Check time and peak-memory complexity against the maximum growing input. Look for nested scans, repeated sorting,
  repeated parsing/copying, and materializing a collection that could be batched or streamed.
- Verify timeout, cancellation, retry/backoff, idempotency, and admission/rate limiting only at boundaries where
  stalled or abusive work can exhaust a shared resource.
- Measure provider/API waterfalls separately from database time so the fix targets the actual wait.

### Cache and browser server state

- First prove the repeated work is material. No cache is the preferred result when the source meets the target.
- For a server cache, verify tenant/authorization dimensions in the key, TTL, invalidation coverage, maximum
  cardinality/eviction, stampede control, deployment consistency, and behavior on cache failure. Authenticated
  tenant data stays private unless shared-cache isolation is explicitly proven.
- Separate public hashed assets from personalized HTML, API responses and protected media. Inspect origin, CDN and
  browser directives; `Authorization`, cookies, `Set-Cookie`, `Vary`, `private`, `no-store`, cache rules and the
  observed cache status. Shared caching of authenticated content requires proof that its cache key and rules carry
  every tenant and authorization dimension. Verify the deployed provider's current behavior; for Cloudflare use
  [Origin Cache Control](https://developers.cloudflare.com/cache/concepts/cache-control/) and
  [cache responses](https://developers.cloudflare.com/cache/concepts/cache-responses/).
- For TanStack Query, verify stable scoped keys, freshness based on correctness, precise invalidation after every
  relevant mutation/external event, and request waterfalls. Components may observe the same query key; rely on the
  library’s shared query/cache behavior instead of adding a second client cache or lifting data without need.

### Queues, concurrency, and Realtime

- Measure or bound concurrency, claim/lock duration, throughput, backlog/lag, retries, and failure rate. Verify atomic
  claims, idempotent processing, bounded worker concurrency, terminal failure handling, and hot-tenant fairness.
- For Realtime, record connections, channel joins, filters, event rate, payload, recipients per event, authorization
  work, and cleanup. Verify current Supabase guidance when choosing Broadcast or Postgres Changes; high fan-out or
  an explicit capacity claim requires representative concurrency evidence.
- When a long-running server or worker can retain state, repeat representative requests or jobs and observe RSS/heap
  trend, event-loop delay, active handles, garbage-collection pressure, queue lag and OOM/restart behavior. Start a
  deep memory or CPU profile only after the bounded repeat/soak evidence shows drift. Use current runtime evidence,
  such as [Node diagnostic reports](https://nodejs.org/api/report.html), within the container's documented
  [resource constraints](https://docs.docker.com/engine/containers/resource_constraints/).

### Svelte and browser delivery

- Use a production build and browser/network/profile evidence for a changed loading or interaction path. The dev
  server is not a production navigation benchmark.
- Count requests, transferred and uncompressed bytes, route JavaScript and CSS chunks, fonts, images, third-party
  code, DOM nodes, long tasks, and repeated reactive work relevant to the change. Compare route weight with its
  prior baseline or an approved budget rather than a universal chunk limit.
- Trace the critical request chain from HTML through CSS, fonts, images, route data and hydration. Check whether
  browser loads repeat server work, public routes inherit authenticated-app dependencies, or unavailable industries
  and capabilities ship unused code or styles.
- For a cold/full navigation, record LCP, CLS and interaction evidence at phone and desktop width under the slowed
  profile. For warm client navigation, use supported soft-navigation Web Vitals where available; otherwise record a
  named route-content timing and layout stability. Scripted lab interactions record their latency and observed INP,
  but do not claim the field 75th percentile without field data. Follow current
  [SPA measurement limits](https://web.dev/articles/vitals-spa-faq) and
  [INP lab/field guidance](https://web.dev/articles/inp).
- Check responsive image dimensions and encodings, off-screen loading, decoded size, reserved layout space, font
  requests/fallback shifts, CSS coverage on the critical route, content encoding, immutable asset cache headers and
  the production HTTP protocol. Treat a synthetic score as a clue; preserve the request/profile evidence behind it.
- When an interaction animates, resizes, filters, drags or mutates a substantial DOM, inspect style recalculation,
  forced layout, paint and non-composited animation in the trace. Do not turn a bounded static page into a universal
  CSS runtime audit.
- Key stateful lists by stable identity. Choose pagination, incremental rendering, virtualization, or
  `content-visibility` from interaction requirements and observed render cost.
- Measure optional heavy dependencies on the initial critical path and dynamically load them when the evidence and
  interaction boundary justify it.
- Include serialized route-data bytes and link/code/data preloads in the request count. Record false-positive
  requests, stale or repeated work and server load, and keep eager/hover/tap preloading only when it measurably
  improves the intended navigation. Verify the current framework behavior in
  [SvelteKit link options](https://svelte.dev/docs/kit/link-options) and
  [performance guidance](https://svelte.dev/docs/kit/performance).
- Repeat representative navigation and long-lived interaction when the changed path retains subscriptions, maps,
  editors, object URLs, timers or large caches; use memory evidence to find growth that one page load cannot show.

Load the Svelte skill before changing `.svelte`, `.svelte.ts`, or `.svelte.js` files and run its required validation.

### Operational evidence

- For a production-critical qualifying path, verify that existing logs and metrics can expose the relevant latency
  percentiles, throughput, errors/timeouts, and saturation, queue lag, or Realtime lag. Include tenant skew when a
  hot tenant is a material risk without recording secrets or unnecessary personal data.
- Use the current observability stack first. Add instrumentation only when it answers a material risk and the task
  authorizes it; missing optional dashboards or a new telemetry stack is not a feature-level performance failure.
- Judge alerts and slow-operation thresholds against an approved service target or observed baseline rather than a
  universal number.

### Production delivery

- Separate network/region time, proxy/CDN time, application time, database time, storage/provider time and client
  rendering so a quick local handler is not mistaken for a quick user journey.
- Verify compression, cache headers, connection reuse and the actual HTTP version on the production-like path.
  Check container CPU/memory and database/worker/connection saturation only for resources the workload can pressure.
- Verify public hashed assets and personalized responses follow different cache policies. Inspect the observed CDN
  cache status and any edge rule that can override the origin; protected HTML, APIs and media remain isolated by
  every tenant and authorization dimension.
- Compare cold and warm behavior when startup, cache fill, connection establishment or scale-to-zero can affect the
  user. Record the deployment shape and region with the result.

## 4. Decide whether load testing is required

Require a representative concurrency or capacity test when the change creates or materially alters a high-traffic
public path, shared resource/pool, queue/worker, bulk fan-out, Realtime fan-out, contention point, or when the user
requests a numerical capacity claim. Also test when plans and single-request timings cannot answer the risk.

Ordinary bounded CRUD and equivalent refactors do not need a load test. Never direct load at production or a paid
external service without explicit authorization. Prefer an isolated local/staging environment with representative
data and define:

- concurrency or arrival rate, operation mix, tenant distribution, data size, ramp, burst, and duration;
- latency percentiles, throughput, errors/timeouts, and the relevant saturation signal;
- safe stop conditions and the baseline or target used to judge the result.

Report the environment and limitations. If the required environment or data is unavailable, mark capacity
unverified rather than converting a single-user timing into a scale claim.

## 5. Fix, re-check, and report

When authorized, fix confirmed bottlenecks and clear structural hazards without unrelated refactors. Re-run narrow
correctness checks and only the evidence invalidated by the fix.

```text
Performance Verification – [feature]
Workload contract : [data, traffic/concurrency, operation mix, burst, target]
Layers reviewed   : [only affected layers]

Layer | Evidence | Result
------|----------|-------
[...] | [plan/timing/count/size/profile/load result or reasoned bound] | ✅ / ⚠️ / 🚫

Changes made       : [authorized fixes, or none]
Unverified/deferred: [item, reason, impact, owner or next decision]
Capacity statement : [supported workload and environment, or “not established”]
Overall            : ✅ Supported | ⚠️ Partially verified | 🚫 Block
```

Use 🚫 for a correctness/security failure, an unbounded or demonstrated failure under the expected workload, or a
required capacity claim that the evidence disproves. Use ⚠️ for unavailable evidence or an authorized deferral,
with reason, impact, and owner or next decision; state when no owner is assigned. Missing unrelated observability
or optional optimization does not block the path.
