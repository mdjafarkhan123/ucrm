# Industry editions need design-time and post-build performance gates

**Why it waits:** the first industry release and its representative workloads are not approved yet, so bundle,
query, interaction and capacity evidence cannot be collected honestly.
**Brings it back:** before the first industry-edition build part is approved, then after every coherent slice and
again on the production-like staging VPS before release.
**Known constraints:** complete the performance-review design branch before code and verification branch after
code. Measure a production build phone-first for entry, sign-in, initial workspace, setup and each changed main
interaction. Record JS/CSS/font/image bytes, request count, Core Web Vitals, server/database work, rendered rows,
concurrency and tenant isolation with representative data. Confirm unavailable industries and capabilities do
not ship their code or assets. Audit the root query provider, permission probes and idle route warm-up against
measured benefit. Reuse `pre-launch-speed-pass.md` for real-region and protocol evidence. Do not state capacity
beyond the workload exercised.
