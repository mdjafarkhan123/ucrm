# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `f9703c3ae9f0` (Jafar closed
that session 2026-10-19; the next session resuming this part takes it over). `concept.pen` commits go on main.
**State (2026-10-19):** Week `a7LTbd` and Day `ziaXI` approved by Jafar (look in `calendar.md`, joined group in
`buttons.md`, outlined pill in `badges.md`). Month `Ar5jR` "Concept · Schedule · Month · Owner · 1440" approved by
Jafar 2026-10-19 with a floating today tile, today's weekday line and bolder day names (Jafar delegated the
tile look) (look in `calendar.md` → Month view). Week start
is a business setting (Jafar): drawings use Monday, live default is Sunday.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Jobber: Month / Week / Day, Anytime lane, Today
and arrows, Type / Team / Status filters, unscheduled count, Map, More; a visit opens a small pop-up. Our live
Schedule already behaves the same, so the drawing needs no new data except event completion (below).

## Week and Day (approved 2026-10-19)

Their look is in `.claude/skills/design/calendar.md`. Late follows `src/lib/schedule/status.ts`. Day research:
Jobber, ServiceTitan, Housecall Pro, Workiz (timeline colours by technician not followed). Day keeps live
`ScheduleDay.svelte`; booked hours and "Day off" are display only (Jafar approved).

## Month (approved 2026-10-19)

Research: Jobber (`05-month-schedule.png`, `23-month-cell-eight-items.png`: rows grow, no "+ N more", visit
count chip, Anytime first then by time), Autopilot (`autopilot/16-month-populated.png`: time + name chips).
Keeps live `CalendarMonthGrid.svelte`: six weeks, 3 items per date then "+ N more", item count, late and
unassigned counts in words, closed days, padding days dimmed. Jobber's weak spot avoided: rows that grow and push
the month off screen. Drawn: toolbar with Month chosen, weekday row 36, week rows 154, cell padding 8; date 13/700
(today 24 circle), count 11/500 quiet; attention pills on their own line; items 22 high, radius 6, 12 icon, start
time + client (title for tasks/events) 11/600, kind's surface; late = 3px red left edge, unassigned = 6 amber dot,
completed = silver with a drawn strike line (Pencil's strikethrough does not render); padding days at 60%; key
without "Now". Card is 1067 tall (frame 1163), so on shorter screens the month scrolls, as live does.

## Decisions (2026-10-19)

- Card colour = kind of work, not status (Jafar delegated; Jobber default, colour map "a record keeps its colour").
  Status always in words; no "In progress" look (the app only guesses it from the clock); no animation.
- Any completed card turns silver. Events can be completed (Jafar chose Jobber's way).
  **New behaviour for the build:** `completed_at` on events (migration), `/api/*` write with Zod, a tick in the
  event pop-up. The live app colours cards by status today; the build changes that.

## Visit pop-up (approved by Jafar 2026-10-19)

Board `GsICu` "Concept · Schedule · Pop-ups · 1440" (Jafar 2026-10-19: all Schedule pop-ups on one board, no
full-screen copies), node `yf6UX` beside the chosen Week card. Keeps live `VisitPreview.svelte` content and order: client title, work line,
status, When / Team / Where, the reader's timer, Mark complete + Reschedule, Open job # and Move to Unscheduled.
Look: 368 wide, form pop-up header (40 job tile, ×), small status pill beside the name, 32 fact tiles (time,
time, client), timer in a subtle panel ("Your timer · Not started on this visit", a new label Jafar approved),
links in a subtle footer. No arrow (Jafar approved dropping it). Look in `calendar.md` → Visit pop-up. Research: Jobber `02-visit-popover.png`.

## "+ N more" day list (approved by Jafar 2026-10-19)

Same board, node `gDpeK` beside the Oct 21 Month date.
Keeps live `CalendarMonthGrid.svelte`: date title (weekday, month, day), item count with late/unassigned
marks, every item in reading order, a picked item opens its visit pop-up in the same place. Look: 368 wide
(same as the visit pop-up), header with a 40 `--color-time` calendar tile, rows as compact Week cards (kind's
surface, radius 8, padding 8 10, 6 apart: icon + time + status pill, then client + work).

## Quote visit and event pop-ups (approved by Jafar 2026-10-19)

On the board: `UVzdh` (live `AssessmentPreview`: client title, request title, status, Client / When / Team /
Where, today's timer, only "Open request" in the footer) and `QqZfs` (live `EventPreview`: title, "Event",
When, Details, Edit, Delete as a danger button; plus "Mark complete", the approved event completion). Approved as
drawn, so the quote visit keeps the client fact under the title (as live).

## Move visit (approved by Jafar 2026-10-19)

On the board: `Xdknw`, live `MoveConfirm` with every part: Now / Move to, a double-booking warning, the repeat
choice, "Notify customer", Cancel + Save move. Jafar approved the new line under the title (client · work) and the
radio option tiles, now the concept's radio look (`inputs.md`). The customer notice is email only (checked
2026-10-19); a channel choice would be new behaviour.

## New event form (drawn 2026-10-19, waiting for Jafar)

On the board: `abdXu`, live `ScheduleEventDialog` as a 600 form pop-up over the dimmed page: Event title, Day +
Time, Anytime checkbox, Details (optional), Cancel + Create event. Built from New job's approved field blocks.

## Next

1. Ask Jafar whether the new event form (`abdXu`) is approved (saved and committed, not yet answered).
2. **Order (Jafar 2026-10-19): finish every Schedule drawing first, then build Schedule in one go.** Draw onto
   the pop-ups board `GsICu`, one at a time (from `(app)/schedule/+page.svelte` and `components/schedule`):
   the book-work form (`ScheduleJobCreate`: Job / Request / Event switch, light job form, More options, Save
   job), Filters, the two menus, "are you sure?" pop-ups (Delete this event?, Move to Unscheduled?, Whose
   route?) on the shared pattern, Unscheduled drawer. Then Map (its own screen).
3. Then build Schedule (C7), including event completion (migration + `/api/*` + Zod).
4. Jafar saves Pencil (Ctrl+S) after each drawing; commit `concept.pen` from the main folder.
