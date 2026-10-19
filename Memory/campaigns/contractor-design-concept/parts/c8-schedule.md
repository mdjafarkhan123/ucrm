# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `e4d47ceb5e70`
**State:** Week view drawn 2026-10-19, waiting for Jafar's review. Not approved yet.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/` (week, day, month, visit pop-up, map). Jobber shows
Month / Week / Day, an Anytime lane, Today and arrows, Type / Team / Status filters, an unscheduled count, Map and
More; a visit opens a small pop-up (Completed, details, team, place, time, line items, Find a time / Edit / Details).
Our live Schedule already has the same behaviour, so the drawing needs no new data or behaviour.

## Drawn (concept.pen)

- `JpHqG` "Concept · Schedule · Week · Owner · 1440": Jobs-list shell (sidebar on Schedule), page header with the
  time-colour calendar tile, one calendar card: approved option-A toolbar (Today, arrows, range, Month/Week/Day
  switch, Unscheduled 4 switched on, Map, Filters), day headings with item count and a Late / Unassigned pill,
  Anytime row, 7 AM–6 PM grid (56 per hour), closed Sunday shaded, green now line, colour key.
- Items (revised 2026-10-19 from Jafar's final recommendation): normal cards are the soft type tint (visit
  green, assessment orange, event yellow, task grey) with the 14px type icon in the record colour (grey once completed) and **no** thick line. Late: 4px red left
  line + "Late" pill. Unassigned: 4px amber left line + "Unassigned" pill. Both: red line wins, both pills stay.
  Completed: warm silver `color-surface-active` card, 1px `color-border-interactive`, grey text and icon, green "Completed" pill with a check (Jafar 2026-10-19: white looked see-through; not `color-inactive-surface`,
  because the task tint and the inactive grey are the same colour). No fading, no animation, no "In progress".
- Today: green weekday, number in a green circle, 3px green line under its heading, column and Anytime cell on
  `color-surface-background-subtle`. Closed days moved to `color-surface-active` so they differ from today.

## Card colour decision (Jafar delegated to Claude, 2026-10-19)

Jafar proposed colour = status (blue in progress, green done, red late). Compared with Jobber (colour by item
type, completed faded with a check; https://help.getjobber.com/en/articles/calendar-colors/), Housecall Pro
(employee colour plus status changes) and dispatch boards (status colour), plus a second opinion from GPT.
Decided: card colour = kind of work (Jobber default; the colour map's "a record keeps its colour everywhere");
status always in words; only late and unassigned get a coloured edge; done goes quiet; **no "In progress"
look**, because the app only infers it from the clock (no real "started" record), and the now line already shows
the present; no looping animation. The live app today colours cards by status; building this changes that.

## Completed rule and events (Jafar 2026-10-19)

Any completed card turns silver, whatever its kind; the grey type icon still names the kind. Events too:
Jafar chose option A, follow Jobber (its `Event` has `isComplete`). Monday's "Team meeting" is drawn completed.

**New behaviour to build with the Schedule build (not a look-only change):** events can be marked complete and
reopened, like tasks: a `completed_at` on events (migration), a write through `/api/*` with Zod, a tick in the
event pop-up, and the card's completed look. Today the app has no event completion.

## Next

1. Jafar reviews Week. Then, one at a time: Day (people rows), Month, visit pop-up, Unscheduled drawer, Map.
2. Pencil saves only on Ctrl+S in the app: ask Jafar to save, then commit `concept.pen` under this claim.
