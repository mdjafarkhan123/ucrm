# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `e4d47ceb5e70`
**State (2026-10-19):** Week `JpHqG` revised after Jafar's review; **not approved yet**. After approval: write
the card rules into the design skill, then Day view.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Jobber: Month / Week / Day, Anytime lane, Today
and arrows, Type / Team / Status filters, unscheduled count, Map, More; a visit opens a small pop-up. Our live
Schedule already behaves the same, so the drawing needs no new data except event completion (below).

## Week `JpHqG` as drawn

- **No page header** (Jafar 2026-10-19: Jobber and our app have none). The calendar card takes the full height.
  Toolbar: Today, arrows, range, Month/Week/Day switch, Unscheduled (off), Map, Filters, More (36 icon button,
  ellipsis). The top bar's New is the only green New.
- Day headings: weekday, date, item count, small Late / Unassigned pills. Anytime row. Grid 7 AM–7 PM, 64 per hour.
- Today: green weekday, date in a green circle, 3px green line under it, column on `color-surface-background-subtle`.
  Closed day: white with light diagonal stripes in `color-border`.
- Now line behind cards: 1px green across the open days, 3px on today, dot at today's edge, green "10:40" label
  in the hours column (a line through a title would read as "crossed out").
- Cards: soft tint of the kind of work (visit green, assessment orange, event yellow, task grey), 14px type icon,
  time 12/600 always shown, title 12/600, people circles 24 (11/700 initials, 2 apart). Late: 4px red left edge
  plus outlined "Late" pill. Unassigned: outlined pill only, no edge (event yellow = warning yellow).
  Completed: `color-surface-active`, 1px `color-border-interactive`, grey icon and text, crossed-out title, green
  "Completed" pill under the title, people on the bottom row. Late follows `src/lib/schedule/status.ts`.
- Overlap (Sat): half-width cards side by side, start time only.

## Decisions (2026-10-19)

- Card colour = kind of work, not status (Jafar delegated; Jobber default, colour map "a record keeps its colour").
  Status always in words; no "In progress" look (the app only guesses it from the clock); no animation.
- Any completed card turns silver. Events can be completed (Jafar chose Jobber's way).
  **New behaviour for the build:** `completed_at` on events (migration), `/api/*` write with Zod, a tick in the
  event pop-up. The live app colours cards by status today; the build changes that.

## Next

1. Jafar approves Week. Then one at a time: Day (people rows), Month, visit pop-up, Unscheduled drawer, Map.
2. Jafar saves Pencil (Ctrl+S); commit `concept.pen` from the main folder under this claim.
