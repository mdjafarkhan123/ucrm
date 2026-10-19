# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `3e5fd3980784`
(`claude-schedule-opus-2`, took over 2026-10-19). `concept.pen` commits go on main.
**State (2026-10-19):** Week `a7LTbd` and Day `ziaXI` approved by Jafar (look in `calendar.md`, joined group in
`buttons.md`, outlined pill in `badges.md`). Month `Ar5jR` "Concept · Schedule · Month · Owner · 1440" approved by
Jafar 2026-10-19 with a floating today tile, today's weekday line and bolder day names (Jafar delegated the
tile look) (look in `calendar.md` → Month view). Week start
is a business setting (Jafar): drawings use Monday, live default is Sunday.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Jobber: Month / Week / Day, Anytime lane, Today
and arrows, Type / Team / Status filters, unscheduled count, Map, More; a visit opens a small pop-up. Our live
Schedule already behaves the same, so the drawing needs no new data except event completion (below).

## Approved drawings (2026-10-19; every look is in design `calendar.md`, radio in `inputs.md`)

- Week `a7LTbd`, Day `ziaXI`, Month `Ar5jR`: keep live `ScheduleWeek/Day.svelte`, `CalendarMonthGrid.svelte`.
  Month avoids Jobber's growing rows: 3 items then "+ N more", grid scrolls. Pencil's strikethrough does not
  render, so completed items use a drawn line.
- Pop-ups board `GsICu` (Jafar: all Schedule pop-ups on one board, no full-screen copies): visit `yf6UX`
  (new "Your timer" label, no arrow), day list `gDpeK`, quote visit `UVzdh` (keeps the client fact, as live),
  event `QqZfs`, Move visit `Xdknw` (new client · work line; radio tiles). Each keeps its live component's
  content. Customer notice is email only; a channel choice would be new behaviour.
- New event form `abdXu` approved by Jafar 2026-10-19 (live `ScheduleEventDialog`, New job's fields).
- Book-work form approved by Jafar 2026-10-19, two sections on `GsICu`: Job `OemVt` and Request / Event hand-offs `GTfk2`, `CejfJ`
  (live `ScheduleJobCreate`; same content; Job / Request / Event switch; More options at left, no Cancel as live).
- Waiting (drawn 2026-10-19, all at once as Jafar asked): on `GsICu` — "are you sure?" pop-ups (Delete this
  event? `rHBtY`, Move to Unscheduled? `t6PZW`, Whose route? `R76KaR`), Filters panel and the two Directions menus
  (section `S6RecI`), Unscheduled panel `se5NW` (docked beside the calendar as live, 360 wide). Map screen `FiSuX`
  "Concept · Schedule · Map · Owner · 1440" (Day toolbar with Map on; route list + map, AI map image).
- Open question for Jafar: the approved Week/Day toolbar has a ••• button, but live Schedule has no More menu.

## Decisions

- Card colour = kind of work, status always in words; no "In progress" look; no animation.
- Completed cards turn silver. Events can be completed (Jafar chose Jobber's way). **New behaviour for the
  build:** `completed_at` on events (migration), `/api/*` write with Zod, Mark complete in the event pop-up.
  The live app colours cards by status today; the build changes that.

## Next

1. **Order (Jafar 2026-10-19): finish every Schedule drawing first, then build Schedule in one go.** Every
   drawing is now drawn; get Jafar's yes on the waiting ones and his answer on •••.
2. Then build Schedule (C7), including event completion (migration + `/api/*` + Zod).
3. Jafar saves Pencil (Ctrl+S) after each drawing; commit `concept.pen` from the main folder.
