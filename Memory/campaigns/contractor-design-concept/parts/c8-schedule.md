# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `e4d47ceb5e70`
**State (2026-10-19):** Week approved by Jafar, then the improved variant approved the same day. The final
drawing is `a7LTbd` "Concept · Schedule · Week · Owner · 1440"; the first version `JpHqG` was deleted. Its look is
written in the design skill: `calendar.md` (new), joined group in `buttons.md`, outlined pill in `badges.md`.
Day approved by Jafar 2026-10-19 with booked hours and Day off: `ziaXI` "Concept · Schedule · Day · Owner ·
1440"; its look is in `calendar.md` → Day view. Next: Month.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Jobber: Month / Week / Day, Anytime lane, Today
and arrows, Type / Team / Status filters, unscheduled count, Map, More; a visit opens a small pop-up. Our live
Schedule already behaves the same, so the drawing needs no new data except event completion (below).

## Week as drawn

Everything is in `.claude/skills/design/calendar.md`. Late follows `src/lib/schedule/status.ts`
(past day, not done). Events are drawn completable (below).

## Day as drawn (approved 2026-10-19)

Research: Jobber (`06-day-schedule.png`, `21-…`), ServiceTitan (technician rows, unassigned tray, capacity),
Housecall Pro (shared job highlighted in each person's lane), Workiz (timeline colours by technician — not
followed, our colour means kind of work). Jobber's weak spots avoided: tall empty rows, sideways scroll.
Keeps live `ScheduleDay.svelte`: Unassigned row first, one row per person, Anytime column, shared visit in
both rows ("With Jake"), overlap stacks a second lane, late/unassigned counts in the corner.
Drawn: 7 AM–7 PM at 64 per hour (whole working day, no scroll), 208 people column, 140 Anytime column,
lanes 88. Cards follow `calendar.md`; under 2 hours show the start time only; no people circles (the row
says who). Jafar approved the additions (display only, no new data): booked hours + a `--color-time` bar per person;
"Day off" row hatched (from member availability).

## Decisions (2026-10-19)

- Card colour = kind of work, not status (Jafar delegated; Jobber default, colour map "a record keeps its colour").
  Status always in words; no "In progress" look (the app only guesses it from the clock); no animation.
- Any completed card turns silver. Events can be completed (Jafar chose Jobber's way).
  **New behaviour for the build:** `completed_at` on events (migration), `/api/*` write with Zod, a tick in the
  event pop-up. The live app colours cards by status today; the build changes that.

## Next

1. One at a time: Month, visit pop-up, Unscheduled drawer, Map.
2. Jafar saves Pencil (Ctrl+S); commit `concept.pen` from the main folder under this claim.
