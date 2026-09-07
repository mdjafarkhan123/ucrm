# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Part 14 (labor, expenses, job costing) split into 14a–14e. **14a, 14b and 14c CLOSED.** Parts 1–11b,
  13a, 14a, 14b, 14c complete. 14c verified in the browser (record/edit/delete, cost gating, receipt uploader).
- Contract: `docs/jobs-behavior-contract.md` — Costing and Staff permissions carry the forward-only rate rule,
  unrated-not-free, closing-locks-the-crew (labor and expense), and the four `time.*` / `expenses.*` keys.

## Next action

Build **14d — the costing panel**: one authoritative profit for a one-off Job. Today `job_money` reports a
profit that ignores labor and expenses (the Job total panel shows "Cost $0.00" even with expenses recorded).
14d folds recorded labor cost + expense cost into the Job total panel's Cost, Estimated profit and Margin.

Approved decisions already settled (below): revenue = `total − tax`; margin = profit ÷ revenue, `—` at zero
revenue; while a job is open show "Costs so far" and no profit percentage. The reader must apply `jobs.view_cost`
the same way `job_money` / `job_labor` / `job_expenses_list` already do, and sum labor+expense cost from the same
gated totals those readers produce (both cap at 200 rows but aggregate all rows for totals — reuse that shape).

**One decision owed before 14d ships**: the targeted labor double-count warning. `job_line_items.is_labor`
makes it detectable exactly — confirm with Jafar that a labor line's cost plus time entries on the same job is
what should trigger it. The contract's Costing section already says the UI warns rather than reconciling.

Mirror the shipped costing readers: `supabase/migrations/20260908170000_job_costing_foundation.sql` (labor_cost
generated column, gated-read precedent), `20260908180000_job_labor_commands.sql` (`job_labor` reader shape),
`20260908190000_job_expense_commands.sql` (`job_expenses_list` reader shape). The Job total panel lives in
`src/routes/(app)/jobs/[id]/+page.svelte` and reads `job_money`.

## Blockers and owed work

- No blockers. `src/lib/database.types.ts` is 400KB; regenerating through the conversation is not affordable —
  14c added its four function entries to the `Functions` block by hand, alphabetically. Do the same for 14d.
- The double-count-warning decision above is owed before 14d is considered done.

## Deliberately deferred, not silently dropped

- Jobber's "profit alerts" (flag a job below a target margin) — account-wide settings plus Insights work.
- Standalone expenses not attached to a job — `job_expenses.job_id` is NOT NULL by design.
- The standalone "Close Job" button with the incomplete-visits-removal preview.
- Wiring Upcoming/Today/Late/Action required into `private.job_derived_status` / `job_list_rows` /
  `job_status_count_rows` — a larger read-model change the Jobs list still needs.
- Changing whose hours a time entry belongs to / whose expense it is. The record is re-created and removed.
- A per-entry labor rate override (overtime, weekend rates). Revisit when timesheets or payroll arrive.
- A start/stop timer and a company-wide Timesheets page. Jobber has both; neither is in this roadmap.

Resume command: `read memory and continue the Jobs campaign` (next part is 14d).
