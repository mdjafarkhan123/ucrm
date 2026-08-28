# Scale Design Gate

Use this branch before implementation. Its output is a small design verdict, not a speculative architecture
project. Start from the current stack and established project primitives; add machinery only when the workload
requires it.

## 1. Define the workload contract

Identify the variable that grows and the expected operating range. Use existing product requirements, traffic,
and budgets before inventing numbers.

- **Data:** rows per tenant and overall, retention, row size, growth rate, and skew or “hot” tenants.
- **Traffic:** active sessions, request/read/write rate, burst duration, bulk size, and external fan-out.
- **Delivery:** response or background-completion target, returned bytes, rendered items, event rate, and
  acceptable staleness.
- **Correctness:** transaction boundary, ordering, idempotency, retry behavior, tenant isolation, and failure
  recovery.

“20,000 users” is incomplete. Distinguish registered accounts, simultaneous sessions, requests per second,
database transactions, and open subscriptions. If a missing number would materially choose a different
architecture, present the alternatives and obtain the required product decision. Otherwise state a conservative
assumption and show where it stops being safe.

**Done when:** every dimension that can change the design is known, explicitly assumed, or identified as a real
decision blocker.

## 2. Trace the growth path

Follow one representative operation from input to completion: browser or caller → API/auth → database, storage,
provider, cache, queue, or Realtime → response or event. Record:

- network and database round trips;
- rows scanned, joined, sorted, changed, and returned;
- loops, lookups, copies, serialization, and their time and memory complexity;
- transactions, locks, connections, worker slots, sockets, and other finite shared resources;
- work repeated per parent row, recipient, subscriber, tenant, retry, or rendered item.

Name the dominant growth term. A bounded operation needs no scale mechanism merely because it touches an API or
database.

**Done when:** the path accounts for every I/O boundary and every loop or shared resource whose work grows.

## 3. Choose the smallest proven shape

Compare only credible alternatives. Prefer the design with the fewest moving parts that meets the workload and
correctness contract. For a non-obvious or version-sensitive choice, verify the current primary documentation or
source and name the production pattern being used.

### Data and database

- Model domain facts and constraints clearly before optimizing storage. Keep tenant ownership explicit wherever
  the access model requires it.
- Design each growing read from its predicate, authorization scope, ordering, projection, and maximum result size.
  Use deterministic ordering with a unique tie-breaker when pagination must continue reliably.
- Propose an index only for a concrete access or referential-action pattern. Match composite order to the query and
  account for duplicate indexes, write amplification, storage, and maintenance.
- Start aggregates as live, bounded queries when they meet the workload. Choose maintained counters, a read model,
  or a materialized result only when read cost requires it and freshness, repair, and write cost are defined.
- Determine the actual access method before discussing connections: Supabase Data API/PostgREST, a direct Postgres
  driver, a persistent container, and a transient function have different pooling requirements.
- Treat partitioning, replicas, and separate datastores as threshold decisions, not “scale-ready” defaults.

Before writing SQL, schema, indexes, functions, or RLS, load the Supabase Postgres best-practices skill and the
relevant rule files it routes to.

### API, algorithms, and external work

- Bound user-controlled collection sizes and result sizes. Pick offset or keyset pagination from access needs and
  expected depth rather than applying either universally.
- Batch repeated I/O and run independent work concurrently only when ordering, rate limits, transaction semantics,
  memory, and downstream capacity remain safe.
- For growing in-memory collections, state time and peak-memory complexity. Use maps, sets, streaming, or batching
  when they improve the material bound; keep direct linear code for small bounded input.
- Keep database transactions short and exclude slow network calls. Define timeouts, cancellation, retries, and
  idempotency where partial execution or retry is possible.
- Add rate limiting or admission control at an abuse or resource-exhaustion boundary, with a key that matches the
  protected tenant/user/resource. It is not a checkbox for every endpoint.

### Concurrency, queues, and Realtime

- Identify the finite resource and overload behavior. Bound concurrency so pressure waits, sheds, or queues instead
  of multiplying connections and work without limit.
- Design worker claims atomically; define idempotency, retry/backoff, terminal failure, backlog visibility, and
  per-tenant fairness when a hot tenant could monopolize capacity.
- For Realtime, define subscribers, events, payload, authorization cost, and fan-out. With Supabase, verify current
  guidance and choose between Broadcast and Postgres Changes from the required security and scale, then define
  filters and cleanup.

### Caching and derived state

Introduce a cache only after identifying repeated expensive work and acceptable staleness. Define:

- the owner of the source of truth;
- a key containing every tenant and authorization dimension needed to prevent cross-scope reuse;
- TTL, invalidation on every relevant write, maximum cardinality/eviction, and stampede behavior;
- whether the deployment is single-instance, multi-instance, or transient and how consistency changes across it.

Prefer no server cache when the database query already meets the budget. TanStack Query remains the owner of
browser server-state caching; do not create a parallel client cache.

### Browser delivery

- Return and render only what the interaction needs. Choose server pagination, incremental rendering,
  virtualization, or `content-visibility` from the UX and measured DOM/render cost, not a universal row count.
- Keep query keys tenant/authorization scoped, choose freshness from correctness, and specify mutation/external-event
  invalidation.
- Evaluate a browser dependency by the route’s production critical path and baseline. Dynamically load optional
  heavy interactions when that materially reduces initial work.

## 4. Challenge complexity and failure modes

For every proposed index, cache, denormalized field, queue, service, dependency, or abstraction, record the named
risk it addresses and the simpler rejected option. Check degraded dependency behavior, retries and duplicates,
ordering, stale data, hot rows/tenants, overload, tenant leakage, and recovery after partial failure.

**Done when:** every added mechanism has a workload-backed reason, an owner, and a correctness story; speculative
machinery has been removed from the proposal.

## 5. Produce the design verdict

```text
Performance Design – [feature]
Growth path       : [what grows and where]
Workload contract : [data, traffic, burst, delivery, consistency assumptions]
Chosen shape      : [smallest proven design]
Complexity cost   : [indexes/caches/queues/dependencies added, or none]
Rejected options  : [more complex alternatives and why they are unnecessary]
Failure behavior  : [overload, retry, partial failure, tenant isolation]
Verification plan : [exact plans, counts, sizes, profiles, or load scenarios to collect]
Open decisions    : [material decisions only, with owner]
Overall           : Ready | Blocked by [decision]
```

A `Ready` verdict requires a verification item for every material growth risk. It approves a design, not a capacity
claim and not implementation beyond the user’s authorization.
