# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–11b, 13a, and 14a–14e all complete. Part 14 (costing) is done and committed
  (`b042539`, `1fe8b75`). 11c/12/13b were transferred to the Invoices and Schedule campaigns.
- Contract: `docs/jobs-behavior-contract.md` — now carries the recurring costing window rule.

## Next action

Nothing is in flight. The next roadmap parts both need Jafar to choose and approve before planning:

- **Part 15** — notes, attachments/photos, checklists, signatures, proof of work. Depends on attachment
  storage (shipped).
- **Part 16** — verify integrated contractor journeys, recovery, and measured performance. Depends on
  Schedule Part 5 parity and the Invoices handoff parts, so it is not startable yet.

Present the choice to Jafar; do not start Part 15 without approval.

## Verified this session (14e)

Browser-checked in Raad LTD on the two seeded jobs (#10 `per_visit`, #2 `fixed_per_period`): revenue from
completed visits / billing periods, labor and expense costs landing inside the 30-day window with live
update on record and remove, the named date range holding steady, and — via a throwaway job, since removed
— the manual-billing case showing a dash for revenue/profit/margin over real costs. Seed test data was
cleaned up; job #2 has 5 reminders again (one future pending row was re-seeded by hand).

## Blockers and owed work

- `src/lib/database.types.ts` is 400KB and cannot be regenerated through the conversation. `job_costing`'s
  signature did not change in 14e, so it owes the types file nothing.

## Deliberately deferred, not silently dropped

- Jobber's "profit alerts" (flag a job below a target margin) — account-wide settings plus Insights work.
- The material double-count case (same thing entered as an item cost AND an expense) — not machine-detectable.
- Standalone expenses not attached to a job — `job_expenses.job_id` is NOT NULL by design.
- The standalone "Close Job" button with the incomplete-visits-removal preview.
- Wiring Upcoming/Today/Late/Action required into `private.job_derived_status` / `job_list_rows` /
  `job_status_count_rows` — a larger read-model change the Jobs list still needs.
- A per-entry labor rate override (overtime, weekend rates). Revisit when timesheets or payroll arrive.
- A start/stop timer and a company-wide Timesheets page. Jobber has both; neither is in this roadmap.

Resume command: `read memory and continue the Jobs campaign` (Jafar picks Part 15, or pauses the campaign).
