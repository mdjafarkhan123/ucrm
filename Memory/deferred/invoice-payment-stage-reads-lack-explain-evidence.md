# Payment-stage and visit-line reads have no EXPLAIN evidence

Deferred by Jafar 2026-09-07 when the Invoices campaign completed.

The stage reads (`job_schedule_stages`, `ready_to_bill_page`) and the visit-line reads were designed and
reviewed, but never measured. Raad LTD holds a dozen rows, so the planner picks sequential scans and an
`EXPLAIN (ANALYZE, BUFFERS)` there would prove nothing about the shape at 40,000 tenants.

**Reactivates when** those reads run against production-like data volume — a seeded load rig or the first
real tenant with a large job history, whichever comes first.

Already known, and what it changes: the design branch of `performance-review` was applied at build time and
its verdict is in `docs/invoice-part-5c-plan.md`; this is the verification branch only, so it is a
measurement, not a redesign. Until it exists, **do not claim invoice capacity numbers** (CLAUDE.md rule 13).

Fixtures that survive the campaign: jobs titled `5c-5 %` in Raad LTD are the invoicing browser rigs.
**Job #19 "5c-5 Partial Lock Check" is the only partly-billed payment schedule in the org** and the only
fixture that can catch a stage-lock guard over-reaching — do not clear it as stray test data.
