---
name: performance-review
description: >
  Design, investigate, and verify user-felt speed and scale-sensitive application paths, or audit a whole
  release across browser delivery, CSS/assets, server/API, database, Realtime, workers, providers, and
  production delivery. Use before and after qualifying implementation, for reported slowness, explicit
  performance work, release audits, or capacity claims. Skip bounded mechanical changes unless evidence shows
  a regression.
---

# Performance Review

Performance is a **contract**, not end-of-project polish. Protect a qualifying path twice: choose the smallest
sound design before code, then verify the implemented path with proportional evidence. Use the whole-app branch
at release boundaries. Correctness, tenant isolation, accessibility, and maintainability remain constraints,
not performance trade-offs.

## Invocation gate

Invoke this skill when the request explicitly asks about performance, scalability, capacity, or a slowdown,
when a release or whole application needs a performance audit, or when a change creates or materially alters a
path whose work grows with usage. Qualifying paths include:

- growing queries, searches, aggregates, reports, lists, pagination, bulk operations, and tenant/RLS access;
- high-traffic or public APIs, external fan-out, queues, workers, shared pools, and contention points;
- Realtime subscriptions, server caches, large client datasets, rendered collections, and browser dependencies;
- a screen that materially changes a critical journey, route payload/dependency, hydration work, rendered
  collection, or main interaction cost (open, filter, drag, save);
- algorithms whose time or memory grows with user-controlled or persistent input.

A filename is not a trigger by itself. Skip the full skill for copy, ordinary styling, documentation, tests,
type-only work, validation-only changes, bounded unique-key lookups, and behavior-preserving refactors unless
the user reports a regression or the change alters a qualifying path. If the gate is ambiguous, state in one
sentence what grows and why it can or cannot become material; load no branch when it cannot.

## Choose the branch

- **Design:** Before planning or implementing a qualifying path, read
  [references/design.md](references/design.md) completely. Finish the design verdict before code or schema work.
- **Verification:** Once the coherent implementation and its affected layers exist, read
  [references/verify.md](references/verify.md) completely. Review the path once and reuse its evidence unless a
  later change can invalidate it.
- **Investigation:** Start with the verification branch to establish the bottleneck. If the proposed fix changes
  the data model, access pattern, concurrency model, cache, queue, or client delivery shape, complete the design
  branch before implementing that fix, then verify again.
- **Whole application or release audit:** Read [references/audit.md](references/audit.md) completely. It defines
  the representative journey matrix and system-wide evidence. Use the verification branch for each material path
  it identifies; use the design branch only for a fix that changes the path's shape.

An implementation task can require both branches at different moments. A planning-only or review-only task
usually needs one. Do not load both references by default.

## Shared constraints

- **Workload before capacity.** Translate “thousands of users” into relevant dimensions such as rows per tenant,
  tenant skew, active sessions, requests or writes per second, event fan-out, payload size, and burst duration.
  Never turn registered-user count into a capacity claim.
- **Complexity budget.** Every index, cache, denormalized value, queue, dependency, abstraction, and service must
  address a named risk and earn its read benefit against write, consistency, operating, and maintenance cost.
- **User-felt speed.** Screens target Google's Core Web Vitals "good" thresholds — LCP ≤ 2.5 s, INP ≤ 200 ms,
  CLS ≤ 0.1 at the 75th percentile ([web.dev](https://web.dev/articles/vitals)) — judged on phone first. Without
  field data, measure a production build under a slowed CPU and mobile network with representative data, and
  label the result lab evidence.
- **End-to-end budget.** Trace the user's wait across delivery, browser, server, database, storage, provider and
  background work. Moving time between layers is not an improvement unless the user's wait, resource cost, or
  supported workload improves.
- **Regression control.** A verified critical journey leaves a repeatable baseline or budget with its device,
  network, data and environment recorded. Re-measure when later work can invalidate it; do not rerun unrelated
  evidence mechanically.
- **Evidence over folklore.** Prefer representative plans, timings, request counts, payload sizes, profiles, and
  load results. A reasoned bound is acceptable when measurement is unavailable; label the claim unverified.
- **Affected path only.** Inspect every changed layer in the path and omit unrelated layers and general cleanup.
- **Authority is unchanged.** A review does not authorize schema, RLS, permission, package, infrastructure, or
  external-service changes. Report a finding when the current task does not authorize its fix.
- **Current sources.** For version-sensitive behavior, verify official documentation or source. Load the Supabase
  skill for Supabase behavior, Supabase Postgres best practices before SQL/schema/RLS work or Postgres diagnosis,
  and the Svelte skill before changing Svelte code.

## Completion contract

A design is complete only when every material growth variable has a stated assumption, the chosen shape is the
smallest one that meets it, and the design verdict names the exact evidence later verification must collect.
Verification is complete only when every affected layer has evidence or an explicit unverified item with reason,
impact, and next owner or decision; state when no owner is assigned. State capacity only to the workload actually
exercised; otherwise say that capacity was not established. A whole-application audit is complete only when every
representative journey and shared resource in its audit matrix has evidence or an explicit unverified owner and
reactivation trigger.
