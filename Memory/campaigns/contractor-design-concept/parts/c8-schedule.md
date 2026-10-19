# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** none (released
2026-10-19 at Jafar's pause); the next session claims it. Notes merged to main 2026-10-19. `concept.pen` commits go on main.
**State (2026-10-19):** Week `a7LTbd` and Day `ziaXI` approved by Jafar (look in `calendar.md`, joined group in
`buttons.md`, outlined pill in `badges.md`). Month `Ar5jR` "Concept · Schedule · Month · Owner · 1440" approved by
Jafar 2026-10-19 with a floating today tile, today's weekday line and bolder day names (Jafar delegated the
tile look) (look in `calendar.md` → Month view). Week start
is a business setting (Jafar): drawings use Monday, live default is Sunday.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Our live Schedule already behaves like Jobber's,
so the drawings need no new data except event completion (below).

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
- Review 2026-10-19 (Claude, Jafar said go ahead with the improvements): the ••• button removed from every
  Schedule toolbar (live has no More menu; nothing to put in it). Map: colour key removed (live hides it there);
  each stop shows its kind icon and the time in the record colour (Chris Hall's quote visit reads orange);
  "Save route order" in normal capitals (the build changes the live label). Unscheduled: calendar-off icon in
  the toolbar and panel (inbox means Request), each card a green hammer before the work line.
- Jafar's asks 2026-10-19, drawn, waiting for his pick: Unscheduled age as a small pill with a clock — Option A
  (recommended) blue "Added today", amber 1–6 days, red from 7 days (the 7 is a new rule: Jafar decides);
  Option B amber only, beside it on the board (delete the loser). Place pin 12 → 14. "Change property" on the
  picked-client card is now a small secondary button (map-pin) like "Change client" — also on New job's
  drawings, so the build changes live New job too.
- Not drawn yet, opened from Schedule: `jobs/FinalVisitDialog`, `jobs/CreateVisitsDialog`,
  `jobs/ApplyToFutureDialog` (shared-parts checklist). Jafar to say: draw before the Schedule build, or later.

## Decisions

- Card colour = kind of work, status always in words; no "In progress" look; no animation.
- Completed cards turn silver. Events can be completed (Jafar chose Jobber's way). **New behaviour for the
  build:** `completed_at` on events (migration), `/api/*` write with Zod, Mark complete in the event pop-up.
  The live app colours cards by status today; the build changes that.

## Next

1. **Order (Jafar 2026-10-19): finish every Schedule drawing first, then build Schedule in one go.** Every
   drawing is now drawn; get Jafar's yes on the waiting ones (review fixes above).
2. Then build Schedule (C7), including event completion (migration + `/api/*` + Zod).
3. Jafar saves Pencil (Ctrl+S); commit `concept.pen` from the main folder.
