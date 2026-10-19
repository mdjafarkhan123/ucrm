# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `f9703c3ae9f0`
**State (2026-10-19):** Week `a7LTbd` and Day `ziaXI` approved by Jafar (look in `calendar.md`, joined group in
`buttons.md`, outlined pill in `badges.md`). Month `Ar5jR` "Concept · Schedule · Month · Owner · 1440" drawn,
waiting for Jafar's review.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Jobber: Month / Week / Day, Anytime lane, Today
and arrows, Type / Team / Status filters, unscheduled count, Map, More; a visit opens a small pop-up. Our live
Schedule already behaves the same, so the drawing needs no new data except event completion (below).

## Week and Day (approved 2026-10-19)

Their look is in `.claude/skills/design/calendar.md`. Late follows `src/lib/schedule/status.ts`. Day research:
Jobber, ServiceTitan, Housecall Pro, Workiz (timeline colours by technician not followed). Day keeps live
`ScheduleDay.svelte`; booked hours and "Day off" are display only (Jafar approved).

## Month as drawn (waiting for review)

Research: Jobber (`05-month-schedule.png`, `23-month-cell-eight-items.png`: rows grow, no "+ N more", visit
count chip, Anytime first then by time), Autopilot (`autopilot/16-month-populated.png`: time + name chips).
Keeps live `CalendarMonthGrid.svelte`: six weeks, 3 items per date then "+ N more", item count, late and
unassigned counts in words, closed days, padding days dimmed. Jobber's weak spot avoided: rows that grow and push
the month off screen. Drawn: toolbar with Month chosen, weekday row 36, week rows 154, cell padding 8; date 13/700
(today 24 circle), count 11/500 quiet; attention pills on their own line; items 22 high, radius 6, 12 icon, start
time + client (title for tasks/events) 11/600, kind's surface; late = 3px red left edge, unassigned = 6 amber dot,
completed = silver with a drawn strike line (Pencil's strikethrough does not render); padding days at 60%; key
without "Now". Card is 1067 tall (frame 1163), so on shorter screens the month scrolls, as live does.
Open for Jafar: drawings start the week on Monday, live starts on Sunday (`src/lib/schedule/filters.ts`).

## Decisions (2026-10-19)

- Card colour = kind of work, not status (Jafar delegated; Jobber default, colour map "a record keeps its colour").
  Status always in words; no "In progress" look (the app only guesses it from the clock); no animation.
- Any completed card turns silver. Events can be completed (Jafar chose Jobber's way).
  **New behaviour for the build:** `completed_at` on events (migration), `/api/*` write with Zod, a tick in the
  event pop-up. The live app colours cards by status today; the build changes that.

## Next

1. Jafar reviews Month (`Ar5jR`); on yes add a Month view section to `calendar.md`.
2. Then one at a time: visit pop-up (with the "+ N more" date list), Unscheduled drawer, Map.
3. Jafar saves Pencil (Ctrl+S); commit `concept.pen` from the main folder under this claim.
