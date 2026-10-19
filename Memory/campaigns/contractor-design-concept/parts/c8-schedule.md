# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Claim:** next session claims the build. `concept.pen` commits go on main.
**State (2026-10-19): every Schedule drawing approved by Jafar** (last ones with "Option A. All approved");
build next. Every look is in design `calendar.md` (radio in `inputs.md`, joined group in `buttons.md`, outlined
pill in `badges.md`). Week start is a business setting: drawings use Monday, live default is Sunday.

## Drawings (all approved 2026-10-19)

- Screens: Week `a7LTbd`, Day `ziaXI`, Month `Ar5jR`, Map `FiSuX`. Keep live `ScheduleWeek/Day.svelte`,
  `CalendarMonthGrid.svelte`, `ScheduleRoute.svelte`. Month: 3 items then "+ N more", grid scrolls.
- Pop-ups board `GsICu` (all Schedule pop-ups on one board): visit, day list, quote visit, event, Move visit,
  New event, Book work (Job / Request / Event), the three "are you sure?" pop-ups, Filters and Directions menus,
  Unscheduled panel. Each keeps its live component's content; customer notice stays email only.
- Toolbar has no ••• (live has no More menu). Unscheduled icon is calendar-off (inbox means Request).
- Research: Jobber screenshots in `Design/schedule-visits-research/jobber/`.

## Changes the build brings (look or approved new behaviour)

- Card colour = kind of work, status always in words; no "In progress" look; no animation. Live colours cards by
  status today. Completed cards turn silver.
- **Event completion (new behaviour, Jafar chose Jobber's way):** `completed_at` on events (migration), `/api/*`
  write with Zod, Mark complete in the event pop-up.
- **Unscheduled age pill (new rule, Jafar 2026-10-19):** blue "Added today", amber 1–6 days, red from 7 days.
- Map: no colour key; stops show their kind icon and record-coloured time; label "Save route order".
- Picked-client card: "Change property" becomes a small secondary button (map-pin) like "Change client"; live
  New job changes too.

## Jobs pop-ups opened from Schedule

- Approved by Jafar 2026-10-19 on `GsICu`, section `hWDBL`: Final visit completed `WbpEc`, Create visits
  `S5TPc` (new day picker, `inputs.md`), Apply to later visits `a03Qm`. Same content as live; looks in
  `calendar.md`.

## Next

1. Build Schedule in one go (C7), with event completion and the three Jobs pop-ups. Then compare live with
   each Pencil frame.
2. After Built ✅, tidy Pencil drafts per `docs/pencil-workflow.md`.
