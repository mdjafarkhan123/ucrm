# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: Part 5 CLOSED. **Part 6a-1 CLOSED 2026-09-03** (tested + browser-verified). Part 6a-2 (Events) is
  the next dependency-ready part and is NOT yet started.
- Grounding: docs/schedule-behavior-contract.md is the approved product/UI boundary; ROADMAP 6a-2 is the gate.

## Next action — plan Part 6a-2 (Schedule-owned Events)

6a-2 introduces a NEW domain (Schedule owns Events; nothing else does), so it is a plan-first part, not a
straight build. Before writing code, present a plan to Jafar and get approval:

- One-time timed **or** Anytime whole-team Event. Required title, optional description. NO assignment,
  privacy, client/property, address or recurrence fields (contract "Opening, creating and editing").
- Lives only through a Schedule popover + create/edit modal. No Event sidebar item, list page or detail page.
- create/edit/delete gated on the existing `jobs.schedule` authority (the calendar-change permission) — no
  new permission invented.
- Events contribute to overlap/working-hours warnings (contract "Conflict boundary") but are NOT routeable
  and never enter the Unscheduled backlog.
- Needs a new `schedule_events` table + RLS + API (load supabase-postgres-best-practices BEFORE any SQL) and
  calendar wiring: Events flow through the same `ScheduleItem` union (`src/lib/schedule/items.ts`) the way
  Assessments now do, with their own card/preview (type = 'event', see the card matrix's Event row).
- The empty-slot chooser (`ScheduleJobCreate.svelte`) is the natural third tab once Events can be created
  from a slot — Job / Request / Event.

## How 6a-1 shipped (for reference; truth is in code/tests/git)

- Assessments render on Week/Day/Month + preview (Stages 1-2, done earlier).
- Stage 3 (empty-slot chooser): `ScheduleJobCreate` now has a Job/Request SegmentedControl (Job default).
  Request stages the slot via `src/lib/requests/assessmentSeed.ts` and opens `/requests/new`, whose
  `RequestForm` → `AssessmentBlock` reads the seed once and opens the on-site assessment pre-booked. The
  Schedule header button relabelled "New job" → "New" (it opens the same chooser). Existing Requests still
  schedule their assessment from the Request surface.

## Dependencies and boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events. Every Schedule write to a
  non-owned domain stays an owner command.
- Per-row RLS cost is app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.
- Work continues on branch `schedule-5b-visits-card` (Part 5 not yet merged to main).

Resume command: read memory and continue the Schedule campaign.
