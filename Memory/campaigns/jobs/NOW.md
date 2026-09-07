# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–11b, 13a, 14a–14e and **15a-1** complete. 11c/12/13b belong to Invoices and Schedule.
  Part 15a was split at a verified boundary: 15a-1 (field-record permissions + record seam) shipped
  2026-09-07, is live on the remote database and is committed as `51a91fc`; **15a-2 (narrow Field to
  assigned work only) is next.**
- Tree is clean. `npm run check` is 0 errors and the unit suite is green (1789 passing).
- Contract: `docs/jobs-behavior-contract.md` (§ Field records, § Staff permissions, § RLS and command boundary).

## Next action

Implement 15a-2 from `Memory/campaigns/jobs/parts/15a-2.md`, which carries the finished design, the sweep
list and the risks already paid for. Do not redesign it and do not redo the performance gate. Build, verify,
stop.

## Deliberately deferred, not silently dropped

- Photo category labels: **cut** by "follow Jobber" — Jobber has no such field. May return as our own
  differentiator; nothing in 15a blocks it.
- Jobber's profit alerts; the item-cost/expense double-count case; standalone non-Job expenses; the standalone
  "Close Job" button with its incomplete-visit preview; wiring Upcoming/Today/Late/Action required into
  `private.job_derived_status` / `job_list_rows` / `job_status_count_rows`; per-entry labor rate overrides;
  a start/stop timer and a company-wide Timesheets page.

Resume command: `read memory and continue the Jobs campaign with Part 15a-2`.
