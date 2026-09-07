# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Part 14 (labor, expenses, job costing) split into 14a–14e. **14a, 14b, 14c and 14d CLOSED.**
  Parts 1–11b, 13a, 14a–14d complete. 14d verified in the browser (costing card, open-state wording, no
  margin while open, live update on record/remove; Job total card is selling-only again).
- Contract: `docs/jobs-behavior-contract.md` — Costing carries forward-only rates, unrated-not-free,
  closing-locks-the-crew, "screens always name the period and never present costs to date as cash received".

## Next action

Plan **14e — recurring Job costing over the rolling 30-day window**, then get Jafar's approval before code.
Today `job_costing` returns `{costing_basis:'recurring'}` with no figures for any recurring job, and
`JobCostingCard` shows a "coming in a later part" note. 14e replaces that with a real panel.

Roadmap gate: `per_visit` and `fixed_per_period` each pair costs with the revenue their pricing basis
defines, and the trailing window is named on screen. Open questions for the plan: which window (Jobber uses
costs-so-far over a labelled trailing period — confirm 30 days vs billing-period against the `jobber` skill);
how revenue for the window is derived per basis (`per_visit` = visits in-window × their price; `fixed_per_period`
= the period amount); and whether labor/expense sums filter by `started_at` / `expense_date` in the window
(the shipped `job_time_entries_member_started_idx` and `job_expenses_job_date_idx` already support a date range).

Mirror the shipped one-off reader: `supabase/migrations/20260908200000_job_costing_panel.sql`
(`public.job_costing`, gated on `jobs.view_cost`, definer, per-job aggregate). The card is
`src/lib/components/jobs/JobCostingCard.svelte`; it already branches on `costing_basis`.

## Blockers and owed work

- No blockers. `src/lib/database.types.ts` is 400KB; regenerating through the conversation is not affordable —
  14d added `job_costing` to the `Functions` block by hand, alphabetically. Do the same for any 14e reader.

## Deliberately deferred, not silently dropped

- Jobber's "profit alerts" (flag a job below a target margin) — account-wide settings plus Insights work.
- The material double-count case (same thing entered as an item cost AND an expense) — not machine-detectable,
  and Jobber does not detect it either. 14d ships the detectable case only: a labor line item AND tracked time
  raise a heads-up in the costing card.
- Standalone expenses not attached to a job — `job_expenses.job_id` is NOT NULL by design.
- The standalone "Close Job" button with the incomplete-visits-removal preview.
- Wiring Upcoming/Today/Late/Action required into `private.job_derived_status` / `job_list_rows` /
  `job_status_count_rows` — a larger read-model change the Jobs list still needs.
- A per-entry labor rate override (overtime, weekend rates). Revisit when timesheets or payroll arrive.
- A start/stop timer and a company-wide Timesheets page. Jobber has both; neither is in this roadmap.

Resume command: `read memory and continue the Jobs campaign` (next part is 14e).
