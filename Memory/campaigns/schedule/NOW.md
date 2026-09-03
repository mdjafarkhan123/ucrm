# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: Part 4 CLOSED — Part 4c (Unscheduled backlog drawer) shipped and live-verified 2026-09-03.
  Create-undated → drawer, drag drawer→grid (Move confirm), and grid→drawer (menu + drag, explicit confirm)
  all verified; `npm run check` 0 errors, 120 schedule specs pass, no console errors.
- Approved contract: docs/schedule-behavior-contract.md is the release boundary. ROADMAP holds the part gates.

## Exact next action

Part 5 (Jobs-owned completion integration + Job Visits parity) is the next V1 part but is BLOCKED on Jobs
Part 13a, which has not landed (see INDEX: "13a resumes as a Schedule dependency"). Do not start Part 5 until
Jobs 13a exists. When resuming, confirm with Jafar whether to (a) drive Jobs 13a first, or (b) pick up an
approved follow-up below.

## Approved follow-ups (not blockers, can be done any time)

- TeamPicker retrofit — shared searchable multi-select combobox replacing the flat assignee checkbox list in
  ScheduleJobCreate + JobVisitDialog. Approved 2026-09-03, not built. Details in ROADMAP "Team assignee picker".

## Dependencies and boundary

- Jobs owns Visit/Job truth; every Schedule write is a Jobs command (`update_job_visit`, `create_job`, etc.).
- Per-row RLS cost is app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.
- Uncommitted: Part 4c wiring is on `main` working tree, not yet committed.

Resume command: read memory and continue the Schedule campaign.
