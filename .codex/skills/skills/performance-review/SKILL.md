---
name: performance-review
description: >
  Performance review for Postgres queries, Supabase RLS, connection pooling, API routes,
  server-side caching, TanStack Query, Svelte rendering (including virtual scrolling),
  Supabase Realtime, and page weight. Load this skill after implementing any feature that
  touches a database query, API handler, list rendering, realtime subscription, or adds a
  new npm dependency — even if the change looks minor. Also load before any task handoff or
  completion checkpoint. Do not mark work done without running the checks relevant to the
  changed layers. This app targets ~20,000 concurrent users; a missed scale issue here is a
  production outage, not a follow-up ticket. Given code examples are just to let you understand, maybe 100% not correct to copy paste as it is.
---

# Performance Review

Measure, then optimize. Establish correctness first, inspect the changed path, then support
every performance claim with evidence — query plans, timings, request counts, payload sizes,
or a reasoned scale constraint. Fix confirmed problems and obvious structural hazards. Skip
speculative micro-optimizations and clever abstractions that make future measurement harder.

## Process

1. Identify the database queries, API calls, connection pool usage, cache keys, realtime
   subscriptions, and rendered lists touched by the change.
2. Apply only the sections relevant to what changed.
3. Measure suspected bottlenecks when a representative environment or query plan is available.
4. Fix confirmed problems and clear scale hazards without unrelated refactors.
5. Re-run correctness checks and the relevant measurement after each fix.
6. Produce a completion report using the template at the bottom of this skill.

---

## Connection Pooling

Postgres has a hard `max_connections` limit. At 20,000 concurrent users, raw connections
are the first thing to run out — long before CPU or memory. Supabase routes pooled traffic
through Supavisor (Transaction mode, port **6543**), which multiplexes many application
connections onto far fewer Postgres connections.

- Use the **pooler connection string (port 6543)** for all API routes and server-side
  queries. The direct connection (port 5432) is for migrations and DDL only. A direct URL
  in application code will exhaust `max_connections` under load.
- Confirm `DATABASE_URL` in every deployed environment points to the pooler.
- Avoid `PREPARE`/`EXECUTE`, advisory locks, and `SET` session variables over the pooler.
  Transaction mode drops all session state between statements. Features that need session
  state must go through a Supabase Edge Function or a dedicated persistent connection.
- Watch live connection counts in Supabase Dashboard → Database → Connections. Alert at
  80 % of `max_connections` so you have headroom to react.
- **VPS phase:** `pool_size × app_instances ≤ max_connections × 0.8`. Start at
  `pool_size = 10` per instance and raise only under measured pressure.

---

## Database

**Column selection**

- Select only the columns the consumer uses. `SELECT *` transfers unused data over the
  network, prevents index-only scans, and breaks when columns are later renamed or dropped.

**Query shape**

- Prefer one well-shaped query over multiple sequential round trips. Each round trip adds
  network latency and occupies a pooled connection for longer.
- Eliminate N+1 access. Join, aggregate, or batch related rows instead of one query per
  parent row — at scale, 50 rows × 1 query each = 50 connections held simultaneously.

**Indexes**

- Index every foreign-key column. An unindexed FK forces a sequential scan on every join.
- Check every column in frequent or scale-sensitive `WHERE`, `JOIN`, `ORDER BY`, and RLS
  predicates. Add the smallest useful index when the access pattern, table growth, or
  tenant-isolation design justifies it.
- **Composite indexes:** put leading equality predicates first, then range or sort columns.
  An index on `(org_id, status, created_at)` serves `WHERE org_id = ? AND status = ?
ORDER BY created_at` without a separate sort step.
- **Partial indexes:** narrow an index with a `WHERE` clause when queries always include
  that predicate (e.g., `WHERE deleted_at IS NULL`). Smaller index, faster scans, lower
  write overhead than a full-column index.
- **Covering indexes:** `INCLUDE (col1, col2)` lets Postgres satisfy a query entirely from
  the index without a heap fetch. Use on high-frequency queries where the projection columns
  are stable.
- **BRIN:** for large append-only time-series columns (`created_at`, `scheduled_at`).
  Orders of magnitude smaller than B-tree; acceptable for range scans on correlated data.
- **GIN:** for JSONB columns queried with `@>` / `?` or for full-text search via
  `to_tsvector`.

**RLS performance**

- Every column used in an RLS predicate must be indexed. An unindexed tenant predicate on
  a large table performs a full sequential scan on every policy-guarded query.
- Wrap `auth.uid()` and `auth.jwt()` in a subquery inside every RLS policy. Without the
  subquery, Postgres re-evaluates the function for every row scanned:

  ```sql
  -- Slow: auth.uid() called once per row
  USING (organization_id = auth.uid())

  -- Fast: evaluated once per query, then reused
  USING (organization_id = (SELECT auth.uid()))
  ```

**Aggregates and reporting**

- Dashboard aggregates (`COUNT`, `SUM`, `AVG`) on large tenant tables must not run on
  demand. Pre-compute them in a **materialized view** refreshed on schedule or after
  relevant writes, and serve via a lightweight read-only endpoint.

**Query verification**

- Run `EXPLAIN (ANALYZE, BUFFERS)` on every material query change against representative
  data. Use plain `EXPLAIN` when executing would be unsafe (e.g., destructive statements).
- Flag: Seq Scan on a growing table; Nested Loop with a large outer set; Actual Rows ≫
  Plan Rows (stale statistics — run `ANALYZE` on the affected table).

**Timeouts**

- Set `statement_timeout` per session in API route handlers. A runaway query holds a
  pooled connection for its duration, starving other requests:

  ```sql
  SET LOCAL statement_timeout = '5000';  -- 5 s, user-facing queries
  SET LOCAL statement_timeout = '30000'; -- 30 s, background jobs
  ```

For schema, index, SQL, or RLS changes, also load the Supabase Postgres best-practices
skill and follow its migration and verification rules.

---

## API Routes

- Run independent I/O concurrently with `Promise.all`. Sequential awaits that could run
  in parallel add latency equal to the sum of all waits instead of the longest one.
- Return only the fields and rows the client needs.
- **Rate limiting:** enforce on all mutating endpoints and expensive reads, keyed by
  `organization_id` or user ID. Without it, one misbehaving client can exhaust the
  connection pool across all tenants.
- **Maximum page size:** hard-cap list endpoints (e.g., 100–250 rows). Reject or clamp
  requests that exceed it. An unbounded query that returns tens of thousands of rows will
  serialize the response slowly and hold a connection the entire time.
- **Cursor-based pagination:** use keyset pagination instead of `LIMIT`/`OFFSET`. Offset
  scans re-read and discard previously seen rows; cost grows linearly with page number.
- **`Cache-Control` headers:** set deliberately on every response type:
  - `no-store` — mutations and sensitive per-user data.
  - `private, max-age=N` — authenticated reads that are user-specific.
  - `public, max-age=N, stale-while-revalidate=M` — stable tenant-scoped reference data.
- Count database and external round trips. Remove duplicates and per-item calls. Preserve
  authorization, validation, and transaction boundaries while optimizing.

---

## Server-Side Caching

TanStack Query caches data in the browser for one user. At 20,000 concurrent users,
the same hot reference data — lookup tables, org settings, feature flags, plan limits —
gets fetched from Postgres by every user independently unless the server caches it.

- Cache hot reference data server-side. Data qualifies when it is: needed by most
  requests, slow to fetch, and safe to serve slightly stale.
- **Single-instance (current phase):** an in-process `Map` with TTL entries is enough.
  Key by record ID or config name, set an expiry, flush on the write that changes it.
- **Multi-instance (VPS phase):** use Redis. In-process caches diverge across instances;
  Redis keeps them consistent. Set a TTL matched to acceptable staleness; flush via the
  same cache key on write. Use separate key prefixes from BullMQ (`cache:*` vs `bull:*`).
- Never cache per-user data across users. Cache only tenant-global or truly global data.
- After any manual DDL not run through a Supabase migration, reload PostgREST from the
  Supabase Dashboard — PostgREST caches the schema on startup and will serve stale types
  until reloaded.

---

## TanStack Query

- Set `staleTime` based on how quickly the data can become wrong and how writes invalidate
  it. The default is 0 ms (always stale), which refetches on every mount — pointless for
  data that changes infrequently.
- Give stable reference data (lookup tables, config) a long `staleTime`. Give work lists
  and job data a short, deliberate window.
- Invalidate only the affected query keys and scopes. Updating or removing an exact cached
  record is cheaper and more precise than invalidating a broad namespace.
- Reuse cached data immediately; revalidate in the background when stale.
- Sibling components must not independently fetch the same data. Lift the query to a
  shared ancestor or use one query with `select` transforms per consumer. Duplicate fetches
  waste connections and produce inconsistent UI if responses arrive in different order.

---

## Supabase Realtime

Realtime uses persistent WebSocket connections. Unmanaged subscriptions multiply with
users and become a bottleneck on both the Supabase side and the client.

- Filter every channel to the exact rows the view needs. Use `filter: 'col=eq.value'`
  options. A table-wide subscription with no filter receives every change on that table
  for every connected user.
- Unsubscribe when the component unmounts. In Svelte 5, use the `$effect` return:

  ```ts
  $effect(() => {
  	const channel = supabase
  		.channel('jobs')
  		.on(
  			'postgres_changes',
  			{
  				event: '*',
  				schema: 'public',
  				table: 'jobs',
  				filter: `organization_id=eq.${orgId}`
  			},
  			handler
  		)
  		.subscribe();
  	return () => channel.unsubscribe();
  });
  ```

- Subscribe to a narrow view or materialized aggregation rather than the raw table when
  the client only needs derived state.
- Keep active channels per page to 3–5 or fewer. More is a design smell; consolidate.

---

## Svelte

- Move non-trivial derived values into `$derived` runes. Values computed inline in a
  template re-run on every render cycle that touches the enclosing reactive scope.
- Key `{#each}` blocks by stable identity: `{#each items as item (item.id)}`. Without a
  key, Svelte patches by position and recreates DOM nodes unnecessarily on reorder.
- **Virtualize long lists.** Any list that can exceed 100–200 rows (contacts, jobs,
  leads, activity logs, invoices) must use a virtual scroller. Rendering 1,000 DOM nodes
  is a frame-budget and memory problem regardless of server speed. Use `svelte-virtual-list`
  or `content-visibility: auto` with fixed row heights.
- Do not filter, sort, or construct objects inside templates or nested `{#each}` loops.
  That work runs on every reactive update. Move it to `$derived` or the server query.

For `.svelte`, `.svelte.ts`, or `.svelte.js` changes, also load the Svelte skill and run
its required validation.

---

## Page Weight and Navigation

Every page is a separate JavaScript chunk. A first visit blocks on that chunk's download
before anything renders — no skeleton can appear because the skeleton is inside the chunk.

- Navigate with links so hover preloading fires. Register routinely used routes in the
  warm routes list in `src/routes/(app)/+layout.svelte`.
- Evaluate every new browser dependency before adding it. Prefer a server route over a
  package that ships a large reference dataset to every client.
- After adding a dependency, run `npm run build` and check chunk sizes in
  `.svelte-kit/output/client/_app/immutable/`. Report anything over 200 kB and identify
  what caused it.
- Use `import()` dynamically for heavy components that only appear in specific interactions
  (rich text editors, chart libraries, map views, file upload widgets). They should not
  bloat the main page chunk.
- Measure navigation on `npm run build && npm run preview`. The dev server recompiles
  chunks on first request and gives a misleading picture of real-world load time.

---

## Monitoring and Observability

Problems found after production traffic arrives cost more than problems caught before.
Set up the minimum viable observability baseline before the first users hit the system.

- Enable **Query Performance** in Supabase Dashboard (backed by `pg_stat_statements`).
  Review top queries by `total_exec_time` before every release and after schema changes.
  Treat `mean_exec_time > 100 ms` under normal load as a candidate for optimization.
- Log slow API responses server-side (> 500 ms). Treat them as bugs, not warnings.
- Alert when active connections exceed 80 % of `max_connections`.
- **VPS phase:** expose `pg_stat_activity`, `pg_stat_bgwriter`, and Redis `INFO` to a
  monitoring stack (Prometheus + Grafana). Track connection saturation, buffer cache hit
  ratio, and dead tuple accumulation.
- Add OpenTelemetry spans around database calls in API routes so slow requests can be
  attributed to specific queries in production traces.

---

## Completion Report

After reviewing the changed path, output a report in this format:

```
Performance Review – [feature name]
Layers reviewed: [pool | db | api | server-cache | tanstack | realtime | svelte | page-weight | monitoring]

Layer          | Evidence                                         | Result
---------------|--------------------------------------------------|--------
Connection pool| [pooler URL verified / pool headroom checked]    | ✅ / ⚠️ / 🚫
Database       | [query plan, index coverage, RLS policy check]   | ✅ / ⚠️ / 🚫
API            | [round trips, rate limit, pagination, headers]   | ✅ / ⚠️ / 🚫
Server cache   | [TTL, invalidation key, Redis plan]              | ✅ / ⚠️ / 🚫
TanStack Query | [staleTime values, invalidation keys]            | ✅ / ⚠️ / 🚫
Realtime       | [filter scope, cleanup registered, channel count]| ✅ / ⚠️ / 🚫
Svelte UI      | [keyed lists, virtual scroller, derived work]    | ✅ / ⚠️ / 🚫
Page weight    | [chunk sizes, dynamic imports]                   | ✅ / ⚠️ / 🚫
Monitoring     | [slow-query threshold, connection alert]         | ✅ / ⚠️ / 🚫

Changes made : [what was fixed in this review]
Deferred      : [any item needing follow-up, with reason and owner]
Overall       : ✅ Pass | ⚠️ Pass with deferred | 🚫 Block
```

Omit rows for layers not touched by the change. A ⚠️ deferred item must have an owner
and a reason. A 🚫 block must be resolved before the work is closed.
