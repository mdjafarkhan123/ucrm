# Job detail with the maximum recurring Visit count is unmeasured

- **Priority:** P2
- **Why postponed:** The largest live Job had 26 Visits and behaved normally; no representative 520-Visit Job
  exists, and creating benchmark data in the managed project was outside campaign closure.
- **Reactivate when:** Preparing production-like load evidence, a long recurring contract approaches this size, or
  Job detail rendering/loading is changed.
- **Constraint:** The recurrence contract permits 520 duration units and detail currently returns every Visit;
  measure API bytes, database time, DOM size and interaction latency before choosing pagination or virtualization.
- **Owner/decision:** No owner assigned; Jafar decides whether this is a pre-cutover benchmark.
- **Report:** docs/research/jobs-performance-verification-2026-09-10.md.
