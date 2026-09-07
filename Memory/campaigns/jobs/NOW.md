# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Part 14 (labor, expenses, job costing) selected by Jafar 2026-09-07 and split into 14a–14e.
  **14a CLOSED** (commit 41e758f): schema applied to remote Supabase and verified — RLS on all four tables,
  no money column readable by `authenticated`, append-only trail proven (update and delete both refused),
  `npm run check` 0 errors. Parts 1–11b, 13a, 14a complete.
- Contract: `docs/jobs-behavior-contract.md` (Costing + Staff permissions sections).

## Next action

Build **14b — labor**: `add/edit/delete time entry` command functions, `/api/jobs/[id]/time-entries`, and the
Labor section on Job detail. Snapshot the rate from `organization_member_cost_profiles` onto each entry at
recording time. Write a `job_costing_events` row for every change, with `after_close = true` once the job is
closed. Add `time.track_own` / `time.track_team` to the editor list in `src/lib/server/access/team-access-editor.ts`
(14a seeded the keys but added no editor switches). 14a also owes the rate field on the Team member screen,
gated by `team.manage`.

## Approved decisions that are not yet in the contract

- **Revenue = job line-item total, after discount, before tax** (`total − tax`), matching both Jobber's
  documented "pre-tax" and the shipped `job_money` precedent. Not invoiced amounts, not cash collected.
- **Margin = profit ÷ revenue** (not markup). At zero revenue show the dollar profit and `—` for the
  percentage. While a job is open, headline "Costs so far" and no profit percentage.
- **Recurring costing follows `price_basis`**: `per_visit` → visits in the rolling 30 days valued by the
  shipped visit-billing valuation; `fixed_per_period` → billing/reminder occurrences in that window.
  Rolling 30 days is Jobber's documented rule; the revenue pairing is our decision, undocumented by Jobber.
- **Closing locks the crew, not the books**: after close, own-level holders lose edit; team-level holders can
  still correct, and every correction is appended to `job_costing_events`. Invoicing never locks costs.
- **Workers never see money** — not even on their own entry. Rates, costs, profit and margin stay behind
  `jobs.view_cost`.

## Blockers and owed work

- No blockers. Types are regenerated and committed (de31078). `npm run db:types` needs an interactive
  `supabase login`, but the Supabase MCP reaches the same remote project and needs no login — regenerate
  through the MCP and write the payload straight to the file, never through the conversation.
- **One decision owed before 14d**, not before 14b: the targeted labor double-count warning. `job_line_items`
  already carries `is_labor`, so it is detectable exactly — confirm with Jafar that a labor line's cost plus
  time entries on the same job is what should trigger it.

## Deliberately deferred, not silently dropped

- Jobber's "profit alerts" (flag a job below a target margin) — account-wide settings plus Insights work,
  outside this roadmap entry.
- Standalone expenses not attached to a job — `job_expenses.job_id` is NOT NULL by design.
- The standalone "Close Job" button with the incomplete-visits-removal preview.
- Wiring Upcoming/Today/Late/Action required into `private.job_derived_status` / `job_list_rows` /
  `job_status_count_rows` — a larger read-model change the Jobs list still needs.

Resume command: `read memory and continue the Jobs campaign` (next part is 14b).
