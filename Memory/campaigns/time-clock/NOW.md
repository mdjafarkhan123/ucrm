# Time clock — now

**Goal:** Crews start and stop timers on visits and clock in and out on a phone; hours land on the Job once
and on a weekly Timesheets page that a manager can check, correct and approve. Launch roadmap Part 16.
**Plan:** `docs/time-clock-behavior-contract.md` — first version and build order approved by Jafar
2026-10-11.
**Stage:** Building (Part 2 of 9 done)

**In progress:** nothing. Part 2 Visit timer done and merged into `main` 2026-10-11 (`89928483`).

**Next part:** Part 3 Day clock — clock in and out from Home, running timer with Stop on every page. Reuse
`src/lib/components/time-clock/` (`RunningClock`, `TimerRunningElsewhere`, `VisitTimerControl`) and the
shared `myTimerKey` query in `src/lib/time-clock/api.ts`.

**Blockers:** none. The shared shell was settled 2026-10-11 (`selectable-design-experiences` Part 4); add the
running timer to the header through a `Topbar.svelte` snippet so Classic and Botanical both show it.
