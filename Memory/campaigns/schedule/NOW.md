# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: Part 4 CLOSED. Part 5 IN PROGRESS — 5a DONE + verified + committed; 5b not started.
  - Part 5a (Schedule completion integration): SHIPPED. complete/uncomplete in the Visit popover, the
    final-visit dialog (Finish job / Add a return visit / Keep open) reusing the Jobs `FinalVisitDialog` +
    `CreateVisitsDialog`, gated by new `can_complete`/`can_close` context flags (jobs.complete / jobs.close).
    `VisitPreview.svelte.spec.ts` covers the popover controls (4 tests). `npm run check` 0 errors, 129
    schedule specs pass. Live-verified 2026-09-03: complete a one-off's last visit → final-visit dialog →
    Add a return visit opens the day-picker; completed visit shows only Mark incomplete + Open job; Mark
    incomplete restores it.
  - Part 5b (Job detail Visits card parity): NOT started. `JobVisitsSection.svelte` is still a flat
    "Scheduled visits" list with no To be scheduled/Upcoming/Past grouping, no recurrence summary/count/range,
    no next-3 + Show all, no collapsed Past, no series-exception marker. Contract section "Job detail Visits
    card" is the spec.
- Approved contract: docs/schedule-behavior-contract.md is the release boundary. ROADMAP holds the part gates.

## Exact next action

Scope Part 5b (Job detail Visits card parity) against the "Job detail Visits card" section of
`docs/schedule-behavior-contract.md` and present the plan to Jafar before building. 5b is a real UI redesign
of `JobVisitsSection.svelte` (rename to Visits; To be scheduled / Upcoming / Past grouping; next-3 Upcoming +
Show all; collapsed Past; recurrence summary/count/range; series-exception marker; don't repeat property).
Load the design skill before touching it. Do not build without approval.

TeamPicker retrofit is now built and verified (2026-09-03) — see ROADMAP "Team assignee picker" for the
correctness note on Bits UI's `Combobox` `inputValue` before touching that component again.

## Dependencies and boundary

- Jobs owns Visit/Job truth; every Schedule write is a Jobs command (`update_job_visit`, `create_job`, etc.).
- Per-row RLS cost is app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.
- All Parts 1–4 work plus the TeamPicker follow-up are on `main` working tree, not yet committed.

Resume command: read memory and continue the Schedule campaign.
