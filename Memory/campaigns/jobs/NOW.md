# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–11b, 13a, 14a–14e, 15a-1 and 15a-2 complete. 11c/12/13b belong to Invoices and Schedule.
  **15a-3 is written and committed as `06b8685` but not applied and not verified.** Tree is clean;
  `npm run check` 0 errors; 1789 unit tests pass.
- Contract: `docs/jobs-behavior-contract.md` (§ Field records, § Staff permissions, § RLS and command
  boundary) — still not updated for 15a-2 or 15a-3; update it once, after 15a-3 verifies.

## Next action

Finish 15a-3's verification stage, in the order written in `parts/15a-3.md` § "The exact next action":
apply the assessment migration, collect the EXPLAIN ANALYZE evidence the performance gate is owed, check it
live as a real Field member, then update the behavior contract for 15a-2 and 15a-3 together.

Nothing here needs Jafar first. When 15a-3 closes, the next roadmap part is 15b (internal Job/Visit notes,
files and photos).

## Deliberately deferred, not silently dropped

- Photo category labels: cut by "follow Jobber" — Jobber has no such field. May return as our own
  differentiator; nothing in 15a blocks it.
- Jobber's profit alerts; the item-cost/expense double-count case; standalone non-Job expenses; the standalone
  "Close Job" button with its incomplete-visit preview; wiring Upcoming/Today/Late/Action required into
  `private.job_derived_status` / `job_list_rows` / `job_status_count_rows`; per-entry labor rate overrides;
  a start/stop timer and a company-wide Timesheets page.

Resume command: `read memory and continue the Jobs campaign`.
