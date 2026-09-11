# Global Search Performance Verification — 2026-09-11

## Scope

Desktop contractor-web global search against the managed Supabase project. Mobile browser verification is
excluded by product direction because mobile users will use the separate mobile app.

## Verified bounds and correctness

- Search starts at 2 characters, waits 300 ms, and uses one user-scoped TanStack Query entry per term.
- Each of the six result groups returns at most 5 summaries. Core and conversation reads run concurrently;
  every source query is tenant-scoped and bounded before browser delivery.
- The focused Vitest run passed 19 dialog, API, tenant/scope, conversation, and defensive-boundary checks.
- A live `Priya` request returned HTTP 200 with `private, no-cache`, 2 permitted results, and 518 bytes.
- Desktop browser checks passed for top-bar open, immediate input focus, `Ctrl+K`, grouped results,
  arrow-key movement, Escape, focus return, and cached reopen.

## Representative managed-project plans

`EXPLAIN (ANALYZE, BUFFERS)` used the live Raad LTD tenant and the same leading-wildcard predicate as the API.

| Read | Observed rows considered | Execution | Plan note |
| --- | ---: | ---: | --- |
| Client name | 15 | 0.196 ms | Sequential scan, 1 shared data buffer hit |
| Request title/service | 11 | 0.215 ms | Sequential scan, 1 shared data buffer hit |
| Email delivery subject/recipient | 32 | 0.333 ms | Sequential scan, 4 shared data buffer hits |
| Website chat body | 31 | 0.128 ms | Sequential scan, 1 shared data buffer hit |
| Client contact value | 23 | 0.329 ms | Organization index scan, then wildcard filter |

The sequential scans are appropriate for these tiny observed tables, but leading-wildcard matching grows with
tenant rows and ordinary B-tree indexes cannot serve that predicate. No trigram index, search service, or cache
was added without representative larger-tenant evidence.

## Verdict

The bounded desktop interaction is supported for the exercised single-user, small-tenant workload. Registered
user capacity, concurrent search throughput, and large/hot-tenant latency were not established. Before making a
capacity claim or onboarding a tenant whose measured search latency misses its target, run a production-like
staging test with representative tenant skew and concurrency, then choose trigram/full-text indexing or a search
service from that evidence.
