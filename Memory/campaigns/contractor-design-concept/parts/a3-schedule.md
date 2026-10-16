# A3 — Schedule (App look)

**Branch/worktree:** `claude/a3-schedule`, `.worktrees/a3-schedule`. **Claim:** `6c3a8f4511f7` (keep until merged). **State:** Built, NOT merged (Jafar: merge only when he says). Not type-checked or tested (his rule: once, after every screen).

**Pencil frames (classic.pen, 10 distinct):** Week `b6j0I2` ("A · Colour shows status", the chosen one; `KGgbV` is the older stripe version, ignore), Day `NfODm`, Month `uxjN7`, drawer `F62jz`, drawer states `F8bfX1`, New job `hCKLj`, New request `Hn3RV`, New event `K5LTfu`, New job error `O2Oari`. Export with Pencil `Export` to the scratchpad to compare.

**Done so far (committed WIP):**
- `schedule/status.ts`: `cardState()` (completed > late > unassigned > in-progress > scheduled). "In progress" is read from the clock (today, between start and end); the app has no real "started" record. Flag to Jafar.
- New shared `ScheduleItemCard.svelte` (colour = status, avatars, chip; densities pill/micro/compact/standard). `VisitCard`, `AssessmentCard` rebuilt on it; `EventCard` now a quiet pill; `TaskCard` aligned. New density `pill` (Anytime) in `layout.ts`.
- New `CalendarCard.svelte` (bar + grid + legend card), `ScheduleLegend.svelte`. `CalendarBar` restyled (38px buttons, joined arrows, global class `calendar-bar__button`). `SegmentedControl` got `tone="plain"`. `CalendarWeekGrid` restyled (header with late/unassigned counts via `column.attention`, now pill, 60px gutter, no own border). Week hour height 48 -> 64.

**Finished (2026-10-16, second session):**
- `ScheduleWeek`: late/unassigned counts in each day heading; Anytime items are one-line pills. One-hour cards now use the compact form with the chip beside the time (`cardDensity` standard starts at 84px).
- `ScheduleDay`: corner heading (date, items, late, unassigned), initials avatars, 122px lanes, "Shared with X" (count on narrow cards), numbered Anytime pills, green now-pill on the ruler. Fixed a bug that was already there: the pinned Anytime column slid over the names once scrolled (the grid was narrower than its columns).
- `CalendarMonthGrid` / `ScheduleMonth`: frameless, 25px items, closed days shaded from business hours, late/unassigned beside each date count, day popover with a subtitle and list rows (new `row` card density). `nowMinutes` passed in.
- Page: `CalendarCard` around toolbar + grid + `ScheduleLegend`, page fills the height; Jafar sales calendar wrapped the same way. Toolbar buttons use `calendar-bar__button`, inbox icon and yellow count chip. Day heading uses the short month ("Wednesday, Oct 14, 2026") so the bar fits beside the drawer.
- Previews: `SchedulePreviewFacts` (icon rows) shared by Visit, Assessment and Event previews; `Popover` got an optional `subtitle`; Visit preview has "Open job" link and quiet "Move to Unscheduled".
- Drawer: its own card, yellow inbox tile, grip-strip cards with waiting label, place, people, neutral Schedule button; Loading, Empty, No match, Failed and Over-the-limit states.
- Dialogs: `Dialog` got opt-in `icon`, `iconTone`, `footer` and `medium` size (nothing else in the app changes). `SegmentedControl` options can carry an icon. New job/Request/Event dialog has icon tabs, a "First visit" group, date-tile hand-off for Request and Event, red alert with icon, actions in a pinned footer. The standalone Event dialog matches.
- Phone (390): page scrolls, grids get a fixed height, drawer stacks under the calendar, Day columns narrower. Usable, still cramped on Week.

**Checked live (1440 light + dark, 390):** Week, Day, Month, Month day popover, Visit preview, drawer with sample cards, drawer failed state, drawer empty, New job, New job error, Request tab, Event dialog, Map "Whose route?" (unchanged), Jafar sales calendar. Not run: type check, lint, tests (Jafar's rule: once, after every screen).

**Known differences from Pencil (not fixed):** the Assigned team box is the shared `TeamPicker` (boxed with a legend; Pencil shows a plain label); the time pickers are the shared separate Start/End fields (Pencil draws one range field); "More options" and "Cancel" use the shared tertiary button (dashed border). The numbers on Anytime pills count the list from top to bottom; they are NOT a route order. "In progress" is read from the clock (no real "started" record).

**Run it:** the worktree has `.env` and `node_modules` links; start `vite dev --port 5206 --host 127.0.0.1` from the worktree. Owner login in `Login.md`. Write a small Playwright screenshot script (login by POST `/api/auth/session`).
