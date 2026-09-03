# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: Part 5 CLOSED (5a + 5b live-verified 2026-09-03, committed on branch `schedule-5b-visits-card`).
  - 5b redesigned `JobVisitsSection.svelte` to the contract's "Job detail Visits card": section renamed
    "Visits"; To be scheduled / Upcoming / Past groups; next-three Upcoming + "Show all"; collapsed Past;
    recurrence summary + real visit count + date range; "Edit Schedule"; Add one vs Add multiple (new `mode`
    prop on `CreateVisitsDialog`, other callers default to multiple); as-needed vs empty; Overdue flag;
    completed-date history. New browser spec `JobVisitsSection.svelte.spec.ts` (5 tests). `npm run check` 0
    errors; jobs + schedule specs green. Live-verified on Job #2 (recurring, 26 visits) and Job #1 (one-off,
    completed visit).
  - Two contract items deferred to Jobs backend (no data source): completed-by name and the off-series
    marker — Memory/deferred/job-visit-card-backend-fields.md.
- Approved contract: docs/schedule-behavior-contract.md is the release boundary. ROADMAP holds the part gates.

## Exact next action

Await Jafar's pick of the next Schedule part. Dependency-ready options (all gated on Part 5, now closed):
- Part 6a (V1.1) — Request-owned Assessments + Schedule-owned lightweight Events. Also needs Request/
  Assessment readiness; scope against the contract before building.
- Part 7 (V1.2) — contextual Map + manual Anytime routing. Needs dated geocoded Visits and the approved
  map/directions provider boundary; 6a is a soft prerequisite (Assessments on the map).
Read ROADMAP.md only when a part is selected. Do not start a part without presenting scope + approval.

## Dependencies and boundary

- Jobs owns Visit/Job truth; every Schedule write is a Jobs command (`update_job_visit`, `create_job`, etc.).
- Per-row RLS cost is app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.
- TeamPicker `inputValue` correctness note: ROADMAP "Team assignee picker" before touching that component.
- 5b work is on branch `schedule-5b-visits-card` (commit 0f92d51), not yet merged to `main`.

Resume command: read memory and continue the Schedule campaign.
