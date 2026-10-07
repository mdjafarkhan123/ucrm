# Whole-Application Performance Audit

Use this branch for an explicit whole-app audit, release readiness review, or “make the application fast” request.
Audit representative journeys and shared bottlenecks, not every file. The output is an evidence map, prioritized
findings, and repeatable regression baselines; it is not a license for an application-wide rewrite.

## 1. Fix the audit matrix

Name the production-like environment, regions, phone/desktop profiles, network and CPU throttling, build revision,
data sizes, tenant skew, roles, industries, concurrency and cache state. Select the smallest journey matrix that
covers how the product is actually used:

- public entry, purchase/application and sign-in;
- first authenticated workspace and normal warm navigation;
- setup/onboarding for each released industry experience;
- the busiest list/search and its detail/create/save journey;
- uploads or media-heavy views;
- communication, Realtime or other long-lived activity;
- worker/provider-backed completion where the user waits or operational capacity matters.

Include each released industry only where its route, payload or workflow differs. For every journey, define the
cold-load, warm-navigation and main-interaction target or baseline. Missing workload facts that change the design
are decisions, not guessed numbers.

**Done when:** every important user group, distinct delivery shape and shared finite resource appears in the matrix,
or is excluded with a reason.

## 2. Capture the user journey end to end

For each matrix row, use a production build and retain the evidence behind summary scores:

- HTML/route-data timing, redirects and authentication work;
- critical request chain, request count, transferred bytes and uncompressed route JS/CSS;
- fonts, images/media, third-party code, caching, compression and HTTP version;
- server rendering, hydration, serialized route data, preload work, browser-only fetch waterfalls, long tasks, DOM
  size and retained memory;
- cold-load Web Vitals; supported soft-navigation metrics or a named warm route-content timing; and scripted
  interaction latency without presenting lab evidence as a field percentile;
- application, database, storage and provider time with call counts;
- relevant CPU, memory, connection, worker, queue or Realtime saturation.

Test phone first. Record cold and warm results separately. Repeat navigation or interaction when listeners,
subscriptions, timers, editors, maps, object URLs or browser caches could accumulate. Trace style/layout/paint only
where a substantial DOM mutation, drag, resize, filter or animation makes its runtime cost material.

**Done when:** each result can be reproduced from its build, environment, device/network profile, data and steps.

## 3. Audit the shared delivery surface

Check the boundaries that affect many journeys:

- the root layout, global providers, global CSS, fonts and always-loaded dependencies;
- route and capability code splitting, including proof that unavailable industries do not ship their code/assets;
- public pages inheriting authenticated application code or client-only work they do not need;
- CDN/proxy/static asset behavior, responsive image derivatives, R2 or other object delivery; distinguish public
  hashed assets from personalized HTML, APIs and protected media, and prove authenticated shared-cache isolation;
- deployment region, TLS/connection reuse, HTTP/2 or HTTP/3, compression and immutable asset caching;
- server/container CPU and memory, database access method and connection limits; repeat/soak long-running servers
  and workers when state retention can expose heap/RSS, event-loop, handle, GC, queue-lag or restart drift;
- shared queues, workers, external providers and Realtime fan-out;
- hover/tap/eager code and data preloads, including false-positive requests and measurable navigation benefit;
- observability sufficient to see latency percentiles, errors and the finite resource likely to saturate.

Use [verification](verify.md) for the affected path's detailed evidence. A mechanism earns its place only by solving
a measured risk; an unused cache, index, preload, service worker or new dependency is additional cost.

**Done when:** every shared cost is assigned to the journeys it affects and every shared finite resource has a
measured or reasoned bound.

## 4. Prioritize and design fixes

Rank findings by user impact, frequency, missed target and confidence. Prefer removing work, bytes, round trips and
rendered items before adding caches or infrastructure. Keep quick local improvements separate from topology or
provider changes that need approval.

When a fix changes the access pattern, data model, concurrency, cache, queue, SSR/hydration boundary or delivery
shape, complete [design](design.md) before implementation. After a fix, rerun correctness and only the measurements
it can invalidate.

**Done when:** every proposed change names the evidence it addresses, the simpler rejected option, authorization
needed, expected benefit and re-check.

## 5. Leave regression protection

For each critical journey, retain a baseline or budget for route bytes, request count, Core Web Vitals/main
interaction, server/database work and any relevant shared-resource workload. Choose the lightest repeatable check:
build-size comparison, a production-build browser scenario, a representative query plan, or a bounded load test.
Field data replaces lab assumptions when enough real traffic exists; lab evidence remains useful for controlled
regression checks.

Do not turn one browser run or one request into a capacity statement. Capacity requires the exercised operation
mix, tenant/data distribution, arrival rate or concurrency, duration, environment, success thresholds and
saturation signals.

## Report

```text
Whole-Application Performance Audit – [release/build]
Environment      : [build, deployment, regions]
Profiles         : [phone/desktop, network/CPU, cold/warm]
Workload         : [data, roles/industries, concurrency]

Journey | Browser delivery/CWV | Server/data | Shared resource | Result
--------|----------------------|-------------|-----------------|-------
[...]   | [evidence]           | [evidence]  | [evidence]      | ✅ / ⚠️ / 🚫

Prioritized findings : [evidence-backed order]
Regression baselines : [repeatable checks and triggers]
Unverified/deferred  : [reason, impact, owner, reactivation trigger]
Capacity statement  : [supported workload and environment, or “not established”]
Overall             : ✅ Supported | ⚠️ Partially verified | 🚫 Block
```

Use 🚫 for a correctness/security failure, an unbounded or demonstrated failure at the expected workload, a missed
release-critical user target, or a disproved required capacity claim. Use ⚠️ for unavailable evidence or an approved
deferral with its owner and trigger. A good synthetic score does not override a failed real journey.
