# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–11b, 13a, 14a–14e, 15a-1 and 15a-2 complete. 11c/12/13b belong to Invoices and Schedule.
  **15a-3 is applied and correct but failed its performance gate.** Tree clean at `aca06f1` plus this
  checkpoint; `06b8685` is the code; the assessment RLS migration is applied to the remote database.
- Contract: `docs/jobs-behavior-contract.md` — still not updated for 15a-2 or 15a-3. Update it once, after
  the 15a-3 fix verifies, not before.

## Next action

**Blocked on Jafar.** Read `parts/15a-3.md` — it carries the measured table and the finding. The Schedule's
whole cost is `private.can_view_job` running once per scanned row (2.7 ms with RLS off vs 161 ms for the
owner), so the `mine` embed 15a-3 shipped roughly doubles the field worker's read (118 ms → 216 ms) and buys
nothing. Jafar has to pick the direction because every option changes RLS. Then run `performance-review`
**design** on the chosen fix, implement, re-verify, and update the contract.

Do not re-measure first: the fixture is torn down and the evidence is in the packet.

## Deliberately deferred, not silently dropped

- Photo category labels: cut by "follow Jobber" — Jobber has no such field. May return as our own
  differentiator; nothing in 15a blocks it.
- Jobber's profit alerts; the item-cost/expense double-count case; standalone non-Job expenses; the standalone
  "Close Job" button with its incomplete-visit preview; wiring Upcoming/Today/Late/Action required into
  `private.job_derived_status` / `job_list_rows` / `job_status_count_rows`; per-entry labor rate overrides;
  a start/stop timer and a company-wide Timesheets page.

Resume command: `read memory and continue the Jobs campaign`.
