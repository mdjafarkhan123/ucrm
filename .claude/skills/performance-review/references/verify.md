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
- For TanStack Query, verify stable scoped keys, freshness based on correctness, precise invalidation after every
  relevant mutation/external event, and request waterfalls. Components may observe the same query key; rely on the
  library’s shared query/cache behavior instead of adding a second client cache or lifting data without need.

### Queues, concurrency, and Realtime

- Measure or bound concurrency, claim/lock duration, throughput, backlog/lag, retries, and failure rate. Verify atomic
  claims, idempotent processing, bounded worker concurrency, terminal failure handling, and hot-tenant fairness.
- For Realtime, record connections, channel joins, filters, event rate, payload, recipients per event, authorization
  work, and cleanup. Verify current Supabase guidance when choosing Broadcast or Postgres Changes; high fan-out or
  an explicit capacity claim requires representative concurrency evidence.

### Svelte and browser delivery

- Use a production build and browser/network/profile evidence for a changed loading or interaction path. The dev
  server is not a production navigation benchmark.
- Count requests, transferred bytes, route chunks, DOM nodes, long tasks, and repeated reactive work relevant to the
  change. Compare route weight with its prior baseline or an approved budget rather than a universal chunk limit.
- Key stateful lists by stable identity. Choose pagination, incremental rendering, virtualization, or
  `content-visibility` from interaction requirements and observed render cost.
- Measure optional heavy dependencies on the initial critical path and dynamically load them when the evidence and
  interaction boundary justify it.

Load the Svelte skill before changing `.svelte`, `.svelte.ts`, or `.svelte.js` files and run its required validation.

### Operational evidence

- For a production-critical qualifying path, verify that existing logs and metrics can expose the relevant latency
  percentiles, throughput, errors/timeouts, and saturation, queue lag, or Realtime lag. Include tenant skew when a
  hot tenant is a material risk without recording secrets or unnecessary personal data.
- Use the current observability stack first. Add instrumentation only when it answers a material risk and the task
  authorizes it; missing optional dashboards or a new telemetry stack is not a feature-level performance failure.
- Judge alerts and slow-operation thresholds against an approved service target or observed baseline rather than a
  universal number.

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
