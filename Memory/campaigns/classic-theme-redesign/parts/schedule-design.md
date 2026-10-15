# Schedule — design

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Later stages
**Stage:** Design · **Follows:** the five approved lists ([Requests, Quotes and Invoices](requests-quotes-invoices-lists.md)).
**Code:** `classic.pen` in the main folder; commit it from main in its own commit after Jafar presses Ctrl+S in
Pencil. These notes live on branch `claude/schedule-design` (worktree `.worktrees/schedule-design`).
**Done when:** Week, Day and Month are approved (done 2026-10-15) and `classic.pen` is committed from main.

## Steps

- [x] Jafar, 2026-10-14, chose Schedule as this session's screen; a subagent researches and draws, the parent
      session reviews.
- [x] Research: Jafar's saved screenshots (`Design/schedule-visits-research/`, `Design/Jobber Jobs/2026-08-31/`
      62–70, `schedule1.webp`), Jobber, Housecall Pro and ServiceTitan help pages, and
      `docs/schedule-behavior-contract.md` (Week is the default view).
- [x] `Schedule · 1440` (`RrFyy`, x 10780, y 4080) drawn, light and dark checked. Parent review fixed a
      clipped "Unassigned", per-person avatar colours (now one neutral style), the 7am label and long titles on
      narrow cards.
- [x] Jafar, 2026-10-14: asked for more variants and said the visit cards did not look premium; colour should
      mean something. Three variants drawn beside the original (row y 4080), light and dark checked:
  - `Schedule · 1440 · A · Colour shows status` (`QOFVk`, x 12340) — recommended. Scheduled = white card,
    In progress = the one dark-green featured card, Late = rose tint, Unassigned = amber tint with Assign,
    Completed = soft grey with green tick; Assessment and Event shown by icon. New legend.
  - `Schedule · 1440 · B · Colour shows who` (`PmCvg`, x 13900) — Jobber/Housecall Pro way: each crew member
    a tint (Daniel blue, Sofia violet, Amir teal, Maya amber); shared/unassigned stay white; legend lists people.
  - `Schedule · 1440 · C · Day by team` (`JMYsG`, x 15460) — Day view, one column per crew member with booked
    hours bar, A's status colours, live progress on the in-progress visit.
- [x] Jafar, 2026-10-15: deleted C. Card colour shows status (his idea, confirmed against dispatch-board
      practice); he likes A's soft red Late card and that each status badge has its own colour.
- [x] A improved 2026-10-15 (Jafar: improve A first; keep B for now, delete later): amber "Unassigned" badge
      replaces the Assign button (assigning happens from the preview); day headers add a coloured attention
      count ("1 late", "1 unassigned"); the open card gets a rose selection ring; long Anytime names end "…".
- [x] Jafar, 2026-10-15, asked why In progress is deep green. Review board `Schedule · Status colours review`
      (`Dp8ki`, x 12340, y 5252) compares A's solid dark-green card with the suggestion: white card, green
      outline, green "In progress" badge (ServiceTitan: Working = green, Done = light grey; Housecall Pro: in
      progress = white tile with outline; Jobber: completed greyed with a tick). Jafar chose the suggestion
      ("update"); A's In progress card and legend now use it, light and dark checked.
- [x] **Approved by Jafar 2026-10-15: `Schedule · 1440 · A · Colour shows status` (`QOFVk`)** — Week view,
      card colour by status. B and the review board stay in `classic.pen` until he asks to delete them.
      Week stays the default view (contract).

**Merged** into main 2026-10-15 (Week/Day/Month). Drawer notes on branch `claude/schedule-unscheduled`
(worktree `.worktrees/schedule-design-2`), reservation `fab0c8fa27ba`.

- [x] 2026-10-15 (Jafar: subagents allowed for concepts): `Schedule · Day · 1440` (`eNrFP`, x 15460, y 4080)
      drawn by the parent session, light and dark checked. Same shell and status colours as the approved
      Week. Wednesday Oct 14 with the Week's seven items: Unassigned row first (Rachel Kim's assessment, amber),
      then Daniel, Sofia, Amir, Maya rows on a 7am–5pm axis; Anytime first column with route-order numbers;
      the shared Sarah Mitchell visit appears in both Daniel's and Sofia's rows with "Shared with …"; each
      person shows visit count, booked hours and a neutral booked bar; the now line sits behind the cards.
      Legend adds Shared visit. Waiting for Jafar.
- [x] `Schedule · Month · 1440` (`MCHpH`, x 17020, y 4080) drawn by a subagent the same session, reviewed by the
      parent, light and dark checked. Sep 27–Oct 31; each date shows count + attention count, at most 3 compact
      status-coloured rows (Anytime first, then by time) and "+ N more"; Oct 11–17 match the Week; the "+ 4 more"
      panel is open on Wed 14 listing all 7 items, with "Open Day view" and "New visit on this date" links
      (the two links are a proposal, not in the contract). Closed days shaded; legend note "Shaded days are
      closed". Waiting for Jafar.
- Open question for Jafar: in the approved Week, Rachel Kim's 1:30pm assessment has no crew but shows as a
  white card; Day shows it amber Unassigned. Ask whether the Week card should turn amber too.

- [x] **Approved by Jafar 2026-10-15: `Schedule · Day · 1440` (`eNrFP`) and `Schedule · Month · 1440` (`MCHpH`).**
      He then removed the page header (title + New job) from every Schedule screen and deleted variant B
      (Jobber, Housecall Pro and Google Calendar also start the calendar under the top bar). Follow-up the same
      day: Week, Day and Month became 1440×1024 with the calendar card filling the page — Week hours 65px
      (7am–5pm), Day rows taller with a locality line on each card and a fifth person (Liam Ortiz, free all day),
      Month rows share the extra height (still 3 rows per date; 4 do not fit). "New job" stays reachable through the top bar's Add new.

- [x] 2026-10-15, after Jafar showed a Dribbble vet-clinic calendar (dribbble.com/shots/14994519): Week gets a faint
      now line across every day behind the cards, solid on today (Apple Calendar way); Day already spans all rows.
      Saved by Jafar and committed on main (`8cdb2940`). For Medspa planning: that shot's docked right-side
      details panel and per-provider columns match Boulevard/Fresha; not adopted for Contractor (Jobber popover,
      long visits suit rows). Its colour-by-service fills and tiny pale text were judged not to fit.
- Open: should the Week's Rachel Kim card turn amber Unassigned to match Day and Month?

- [x] Jafar, 2026-10-15 ("do what is best"): Week's Rachel Kim card is now amber Unassigned and Wed's header reads
      "7 items · 1 unassigned", matching Day and Month. Next screen chosen: the Unscheduled drawer.
- [x] Unscheduled drawer redrawn to match the live app (Jafar 2026-10-15: "we are here not to change any
      behavior, we are just to design screen"; checked against `ScheduleUnscheduledDrawer.svelte` and the page).
      `Schedule · Unscheduled drawer · 1440` (`Obv2U`, x 18580, y 4080): the Day view with the drawer docked
      beside the calendar (the calendar narrows, as in the app), search plus an All-employees select, oldest
      first, a card per visit with drag handle, client, work, place, waiting age, assignment and Schedule, and a
      foot note that a visit dropped here is unscheduled after confirming. `… · states` (`FlsaG`): empty,
      filtered-empty and failed, using the app's wording. An earlier on-top version with status filter and sort
      was deleted. To match the app the same day: Day rows show name + "N items" only (booked hours and bar
      removed), and the Month "+ more" panel lost its two extra links. Light and dark checked. Waiting for Jafar.

- [x] 2026-10-15, Jafar asked for a new design concept for the drawer instead of approving the redraw (NOW.md
      **Target**: a new concept, not a conversion). `Schedule · Unscheduled drawer · 1440 · Concept 2` (`HHi5u`,
      x 18518, y 4080), light and dark checked. Same controls and wording as the live drawer. New look: amber
      inbox tile and count in the header; search, then a compact All-employees pill; grey list background with
      white cards; each card has a full-height grip strip, client and waiting age on one line, work, place, then
      crew initials (or the amber Unassigned badge) and Schedule. The first card shows hover lift. The hint line
      and drop foot note are gone, since the live drawer has neither. The pressed Unscheduled button is neutral
      grey. States board `Schedule · Unscheduled drawer · Concept 2 · states` (`FLIPT`, x 18518, y 5184): loading
      skeleton cards, empty (count 0), no match ("maple", Daniel Reyes), failed (rose icon, the page's fallback
      wording, Try again; no count), and over the limit ("Showing the first 500…", from `SCHEDULE_VISIT_LIMIT`).
      Light and dark checked. Waiting for Jafar; the old states board `FlsaG` is replaced if he approves.
- [x] Jafar, 2026-10-15: the grey list matched the page and the drawer had no edge of its own. As in the live
      page (the drawer is its own bordered panel beside the calendar), Concept 2's drawer is now a separate
      white card with the calendar card's border, corners and shadow, 12px from the calendar; the list is
      white and the cards keep their borders. The calendar card is 952 wide; its legend drops the
      business-hours note while the drawer is open so it fits. States drawers match. Light and dark checked.
- [x] **Approved by Jafar 2026-10-15: the Unscheduled drawer (`HHi5u`) and its states (`FLIPT`).** Renamed
      `Schedule · Unscheduled drawer · 1440` and `… · states` and moved to x 16978 (y 4080 / 5184); the old
      redraw `Obv2U` deleted (its states board was already gone).
- [x] 2026-10-15: `Schedule · New job from empty slot · 1440` (`rGwsg`, x 18518, y 4080) drawn from
      `ScheduleJobCreate.svelte`: the approved Week, dimmed (preview closed), with the centred "New job" dialog
      (560 wide). Job / Request / Event switch (Segmented control part); Job title; Client with Change property;
      a soft "First visit" panel holding Schedule later, Day of the first visit + Time, Anytime and Notes for
      the first visit; Assigned team; Notify customer (ticked); More options and Save job in the footer. Same
      fields and wording as the app; the "First visit" panel heading is the one new label (grouping only).
      Light and dark checked. **Approved by Jafar 2026-10-15**, "First visit" heading included.
- [x] 2026-10-15: the two hand-off tabs and the Job error drawn from `ScheduleJobCreate.svelte`, same wording and
      one button each (Jobber's empty-slot chooser has the same four kinds; ours hands Request and Event off).
      `Schedule · New request from empty slot · 1440` (`AOJ6z`, x 19998) and `… New event …` (`Xvtrv`, x 21478):
      lead line, the slot as a ticket (date tile "OCT 14", then "Wed, Oct 14" and a clock line "1:00 PM – 2:00 PM"
      — the app's one-line summary split in two, look only), the note with an arrow, and "Continue to new
      request / event" alone in the footer. `Schedule · New job · error · 1440` (`LWT2a`, x 22958): Client empty,
      a rose alert with an alert icon above the form, "Choose a client to continue." Light and dark checked.
      Not drawn: the dateless slot ("No date yet — you can pick the day next."); the ticket would show only that
      line, without a date tile. Waiting for Jafar.
- [x] Jafar, 2026-10-15: an element the same colour as its background looks odd. The date tile's grey month
      strip matched the grey ticket behind it; the strip is now solid brand green with white "OCT" (the
      calendar's chosen-date colour) and the tile has the stronger control border. Light and dark checked.

## Next (new sessions; redesign the look only, copy the live component's behaviour and wording)

Commit `classic.pen` from main after Jafar presses Ctrl+S, if that wasn't done at session end. Then, in this order:

1. Empty-slot quick create, remaining tabs — drawn 2026-10-15 (`AOJ6z`, `Xvtrv`, `LWT2a`); waiting for Jafar.
2. Previews — `AssessmentPreview` (read-only, Open request) and `EventPreview` (Edit/Delete), alongside the
   approved Visit preview.
3. Event form — `ScheduleEventDialog.svelte`: title, description, one day, timed or Anytime.
4. Move confirmation — `MoveConfirm.svelte`: old → new, overlap and out-of-hours warnings, this visit or
   this-and-future, notify customer. Also the Unschedule confirmation and the drag ghost.
5. Filters panel — `ScheduleControls.svelte`: Employee, Status, density.
6. Map workspace — `ScheduleRoute`, `RouteStopCard`, `RouteMap`: one employee's day, ordered stops with
   locks, map, Directions.
7. Pipeline Task card — `TaskCard.svelte`, on the calendar.

Phone layouts are adapted while building.

## Proposals (not in the app today; data exists)

- Card edge colour by kind (visit green, assessment amber, event grey, Late red); team shown by neutral initials,
  replacing today's per-person `schedule_color` edges.
- Green "New job" button in the page header, opening today's quick-create (Job / Request / Event).
- Legend row under the calendar.
- Sidebar collapsed on Schedule so seven columns stay readable.
- If neutral team initials are approved, `Job details · 1440` still uses per-person tints; ask whether to match.
