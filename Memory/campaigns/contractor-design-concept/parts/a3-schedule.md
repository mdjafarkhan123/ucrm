# A3 — Schedule (App look)

**Branch/worktree:** `claude/a3-schedule`, `.worktrees/a3-schedule`. **Claim:** `6c3a8f4511f7` (keep until merged). **State:** Paused mid-build, NOT merged (Jafar: merge only when he says). Not type-checked or tested (his rule: once, after every screen).

**Pencil frames (classic.pen, 10 distinct):** Week `b6j0I2` ("A · Colour shows status", the chosen one; `KGgbV` is the older stripe version, ignore), Day `NfODm`, Month `uxjN7`, drawer `F62jz`, drawer states `F8bfX1`, New job `hCKLj`, New request `Hn3RV`, New event `K5LTfu`, New job error `O2Oari`. Export with Pencil `Export` to the scratchpad to compare.

**Done so far (committed WIP):**
- `schedule/status.ts`: `cardState()` (completed > late > unassigned > in-progress > scheduled). "In progress" is read from the clock (today, between start and end); the app has no real "started" record. Flag to Jafar.
- New shared `ScheduleItemCard.svelte` (colour = status, avatars, chip; densities pill/micro/compact/standard). `VisitCard`, `AssessmentCard` rebuilt on it; `EventCard` now a quiet pill; `TaskCard` aligned. New density `pill` (Anytime) in `layout.ts`.
- New `CalendarCard.svelte` (bar + grid + legend card), `ScheduleLegend.svelte`. `CalendarBar` restyled (38px buttons, joined arrows, global class `calendar-bar__button`). `SegmentedControl` got `tone="plain"`. `CalendarWeekGrid` restyled (header with late/unassigned counts via `column.attention`, now pill, 60px gutter, no own border). Week hour height 48 -> 64.

**Still to do:**
1. `ScheduleWeek`: pass `attention` per column (count late/unassigned via `cardState`), use `density="pill"` for Anytime items (currently "compact").
2. `ScheduleDay` restyle (person column with initials avatar, 122px lanes, `sharedWith` "Shared with X", route number badge in Anytime, now pill). `CalendarMonthGrid`/`ScheduleMonth` restyle (25px items, day popover, pass `nowMinutes`).
3. `ScheduleControls`: use `calendar-bar__button` class, inbox icon + yellow count chip. Page `+page.svelte`: `PageContainer variant="open"`, wrap in `CalendarCard` with `ScheduleLegend`, card fills the height, drawer its own card. Wrap the Jafar sales calendar page in `CalendarCard` too (grids no longer have their own border).
4. `Popover` + `VisitPreview` (client title, status chip, icon facts, Mark complete / Reschedule, "Open job" link, "Move to Unscheduled"); Assessment/Event previews to match.
5. `ScheduleUnscheduledDrawer` + its 5 states; `ScheduleJobCreate` / `ScheduleEventDialog` look (Job/Request/Event tabs).
6. Screenshot every state at 1440 light/dark next to the Pencil frames; fix; record results here.

**Run it:** the worktree has `.env` and `node_modules` links; start `vite dev --port 5206 --host 127.0.0.1` from the worktree. Owner login in `Login.md`. Write a small Playwright screenshot script (login by POST `/api/auth/session`).
