# Shared batch 12 — 2026-10-20

Approved board `ooCwt` and design/time-clock.md. RunningClock is the indigo capsule with the breathing ring (still
under reduced motion), warning family and "Over 12 hours" past 12 hours, and a `joined` shape for the visit row.
WorkTimerControl gained `presentation`: `panel` (Schedule visit/assessment pop-ups, Request assessment) shows the
timer tile, Not started / running time with "Since …" / Over 12 hours / Running elsewhere; `inline` (Job visit
row) joins the clock to Stop timer at 32 high. Start/Stop carry indigo play/stop icons; busy stays on until the
timer queries refresh, so a press cannot repeat. TimerRunningElsewhere reads "Running on Job #… ↗". Schedule's
own timer-label row was removed; the panel now owns it. Timer start/stop commands are unchanged.

Built by Codex, finished by Claude. Focused ESLint: time-clock components clean; four older errors in
JobVisitsSection, AssessmentBlock and Schedule are in untouched lines (already on main). Prettier clean. MCP
autofixer: no real issues (SCSS-nesting false positives, the existing ticking-clock interval).

Fixture screenshots (temporary route, removed): capsule, panel, visit row and running elsewhere — running and
over-12-hours at 1440/390 light/dark, plus idle. Live check: see live-*.png.

Live check (owner, Raad LTD, after merge): the Schedule visit pop-up showed the panel inside a second grey box
left from the old timer row; the pop-ups' wrapper box was removed so the panel draws its own (time-clock.md).
`live-schedule-panel.png` — Not started panel with indigo Start timer; `live-job-visit-rows.png` — Job page visit
rows with indigo Start timer. No timer was started on live, so no real time entries were made; running, over
12 hours and running elsewhere are proven by the fixture screenshots.
