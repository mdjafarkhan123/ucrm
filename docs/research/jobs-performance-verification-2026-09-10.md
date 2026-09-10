# Jobs performance verification — 2026-09-10

## Verdict

The implemented Jobs paths are supported for the measured workloads below. No correctness or measured
performance blocker was found, so the Jobs campaign may close. This is a proportional verification, not a
40,000-user or production-capacity claim: no representative concurrent load test was run.

## Workload contract

- Environment: production SvelteKit build running locally, using the managed remote Supabase project and R2.
- Browser traffic: one authenticated Contractor Owner at a time.
- Live tenant: 15 Jobs (12 active), 46 Visits, 18 line items, 19 invoice reminders, 5 signatures,
  14 checklist-answer rows, 101 activity events, 14 notes and 10 attachments. The largest Job had 26 Visits.
- Reused database evidence: a 5,000-Job tenant for list and Schedule policy work, 50,000 Jobs for status counts,
  and 200,000 combined-history rows for the activity branch.
- Success criteria: the integrated journeys from Jobs Part 16a remain correct; list and detail reads stay bounded;
  production pages settle without browser errors; no tested path demonstrates a scaling blocker.

## Evidence

| Layer | Evidence | Result |
| --- | --- | --- |
| Correctness | Part 16a passed five live owner/Field journeys, including one-off and recurring work, Schedule/Invoice handoffs, assigned-only access, recovery and two-way sync. A production build passed on 2026-09-10; only two pre-existing unused-CSS warnings appeared in Dashboard code. | Supported |
| Jobs list database path | The list uses deterministic keyset pagination, defaults to 25 rows, caps at 50, and batches money for the page. Earlier representative evidence on 5,000 Jobs measured 21.9 ms after the RLS helper fix (27.9 ms before). | Supported at 5,000 Jobs |
| Status counts | Existing representative evidence over 50,000 Jobs measured 124 ms with invoice reminders (115 ms without them); the rejected per-row reminder probe measured 915 ms. | Supported at 50,000 Jobs |
| Combined history | The result is capped at 100. A seeded 200,000-row activity branch measured 1.8 ms and 10 buffers after tenant scoping, down from 33 ms and 2,194 buffers. | Supported at 200,000 history rows |
| Other Job collections | Scope lines cap at 100; Labor and Expenses each return the latest 200 rows, calculate totals separately, and expose `has_more`. Recurrence creation permits up to 520 duration units, but Job detail currently returns all Visits. | Partly verified; 520-Visit detail is deferred |
| List APIs | In five production-preview samples, `/api/jobs?limit=25` returned 7.5 KB with 690 ms median latency; `/api/jobs/counts` returned 172 B with 586 ms median latency. The remote managed service and authentication dominate this single-user timing. | Supported for the live tenant |
| Job detail APIs | The initial page starts eight application requests. On the 26-Visit Job those requests returned 11.8 KB total; three concurrent-fan-out runs measured 818 ms minimum, 1.626 s median and 2.482 s maximum. The main 9.4 KB detail response measured 650 ms median. | Supported for 26 Visits, with access-resolution risk |
| Browser | Production-preview settled times: Jobs list 1.319–2.094 s (median 1.447 s, 873 DOM nodes); 3-Visit detail 1.633–1.724 s (median 1.669 s, 937 nodes); 26-Visit detail 1.380–1.468 s (median 1.436 s, 995 nodes). No browser warnings or errors were recorded. | Supported for one active browser |
| Browser delivery | Static-import gzip closures: shell 127.4 KB; Jobs list 189.6 KB total (62.2 KB route delta); Job detail 329.3 KB total (201.9 KB delta); New Job 262.4 KB total (135.0 KB delta). The three Jobs routes together plus the shell were 355.4 KB. No prior bundle baseline or approved budget exists. | Measured, no regression verdict |
| Idle warming | The shared app layout warms 35 routes after idle. Their union adds about 610.1 KB gzip beyond the shell and produced 95 stylesheets in the measured browser. This happens after the critical load and is app-wide rather than Jobs-owned. | Deferred cross-app efficiency risk |
| Access checks | Each of the eight initial detail APIs independently calls `requireOrganizationPermission`. On a versioned package this resolves organization context plus about 16 more Supabase Data API/RPC reads, or about 136 access-model calls before endpoint-specific work; the whole empty-side-data page is roughly 155 Supabase calls. | Deferred cross-cutting latency/pooling risk |

Managed PostgREST did not expose plan media (`PGRST107`), the Supabase CLI was not authenticated, and local
Docker was unavailable, so Part 16b could not collect fresh `EXPLAIN (ANALYZE, BUFFERS)` output. The report
therefore reuses the representative plans already collected while the relevant Jobs parts were implemented.

## Changes and deferred decisions

No product code, schema, RLS, package or infrastructure behavior changed during this review. The measured
authorization fan-out requires an approved cache/request-sharing design with explicit staleness and tenant/member
isolation rules; it was not safe to improvise during campaign closure. Leading-wildcard Job title search, the
unmeasured 520-Visit detail shape, and app-wide idle route warming are also recorded in deferred Memory.

No owner is assigned to these optimizations. Jafar's next decision is whether to prioritize them before the
production migration rehearsal; the 520-Visit case and representative concurrent load should be exercised before
making a numerical capacity claim.

## Capacity statement

Capacity is **not established**. Evidence supports the exact single-browser/live-tenant paths and the isolated
database data sizes stated above. It does not establish concurrent users, requests per second, sustained duration,
VPS pool saturation, hot-tenant behavior or the product's 40,000-user target.

**Overall: Partially verified.** The measured Jobs flows are healthy enough to close the feature campaign; the
remaining risks are explicit, bounded and independently reactivatable.
