# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–11b, 13a, 14a–14e, **15a-1 and 15a-2** complete. 11c/12/13b belong to Invoices and Schedule.
  15a-2 (Field sees only assigned work) is applied to the remote database, verified live as a real Field
  member, and committed as `d0520f5`. Tree is clean; `npm run check` 0 errors; 1789 unit tests pass.
- The 15a-2 performance gate found a Schedule regression it deliberately did not fix. That is now
  **Part 15a-3**, written up in `parts/15a-3.md`, and it is **not yet approved** — it turns on a product
  question for Jafar.
- Contract: `docs/jobs-behavior-contract.md` (§ Field records, § Staff permissions, § RLS and command boundary).

## Next action

Ask Jafar the product question in `Memory/campaigns/jobs/parts/15a-3.md`: does a field worker's Schedule
become "My Schedule" by default? Do not build until he answers — then either build 15a-3 or select 15b
(internal Job/Visit notes, files and photos) from the roadmap.

## Deliberately deferred, not silently dropped

- The jobs behavior contract has **not** been updated for 15a-2. Do that when 15a-3 settles, so the
  Field-visibility section is written once rather than twice.
- Photo category labels: **cut** by "follow Jobber" — Jobber has no such field. May return as our own
  differentiator; nothing in 15a blocks it.
- Jobber's profit alerts; the item-cost/expense double-count case; standalone non-Job expenses; the standalone
  "Close Job" button with its incomplete-visit preview; wiring Upcoming/Today/Late/Action required into
  `private.job_derived_status` / `job_list_rows` / `job_status_count_rows`; per-entry labor rate overrides;
  a start/stop timer and a company-wide Timesheets page.

Resume command: `read memory and continue the Jobs campaign`.
