# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Part 14 (labor, expenses, job costing) split into 14a–14e. **14a and 14b CLOSED.** Parts 1–11b,
  13a, 14a, 14b complete.
- Contract: `docs/jobs-behavior-contract.md` — the Costing and Staff permissions sections now carry the
  forward-only rate rule, unrated-not-free, closing-locks-the-crew, and the four `time.*` / `expenses.*` keys.

## Next action

Build **14c — expenses**: `add/edit/delete job expense` command functions, `/api/jobs/[id]/expenses`, and the
Expenses section on Job detail, with receipts through the shipped attachment subsystem
(`entity_type = 'job_expense'`, already wired in 14a). Mirror 14b exactly: `expenses.record` is own-level and
`expenses.manage_team` is team-level, a closed job refuses an own-level write with P0410, and every change
appends to `job_costing_events` with `subject_kind = 'expense'` and `after_close` set. Add the two expense
keys to the editor list in `src/lib/server/access/team-access-editor.ts` — 14b added a `time-tracking`
capability group there; expenses can extend it or take its own. Jobber's field set is captured in
`Design/Jobber Jobs/2026-08-31/25-expense-form.png`.

Copy the shape from 14b rather than inventing one: `supabase/migrations/20260908180000_job_labor_commands.sql`,
`src/routes/api/jobs/[id]/time-entries/`, `src/lib/components/jobs/JobLaborSection.svelte`.

## Approved decisions that are not yet in the contract

- **Revenue = job line-item total, after discount, before tax** (`total − tax`), matching both Jobber's
  documented "pre-tax" and the shipped `job_money` precedent. Not invoiced amounts, not cash collected.
- **Margin = profit ÷ revenue** (not markup). At zero revenue show the dollar profit and `—` for the
  percentage. While a job is open, headline "Costs so far" and no profit percentage.
- **Recurring costing follows `price_basis`**: `per_visit` → visits in the rolling 30 days valued by the
  shipped visit-billing valuation; `fixed_per_period` → billing/reminder occurrences in that window.
  Rolling 30 days is Jobber's documented rule; the revenue pairing is our decision, undocumented by Jobber.

## Blockers and owed work

- No blockers. `npm run db:types` needs an interactive `supabase login`; the Supabase MCP reaches the same
  remote project and needs no login. `src/lib/database.types.ts` is 400KB, so regenerating through the
  conversation is not affordable — 14b added its five function entries to the `Functions` block by hand,
  alphabetically, matching the generator's shape. Do the same for 14c.
- **One decision owed before 14d**: the targeted labor double-count warning. `job_line_items` already carries
  `is_labor`, so it is detectable exactly — confirm with Jafar that a labor line's cost plus time entries on
  the same job is what should trigger it.

## Deliberately deferred, not silently dropped

- Jobber's "profit alerts" (flag a job below a target margin) — account-wide settings plus Insights work.
- Standalone expenses not attached to a job — `job_expenses.job_id` is NOT NULL by design.
- The standalone "Close Job" button with the incomplete-visits-removal preview.
- Wiring Upcoming/Today/Late/Action required into `private.job_derived_status` / `job_list_rows` /
  `job_status_count_rows` — a larger read-model change the Jobs list still needs.
- Changing whose hours a time entry belongs to. It carries their rate, so the fix is record-again-and-remove.

Resume command: `read memory and continue the Jobs campaign` (next part is 14c).
