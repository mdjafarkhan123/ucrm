# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: Parts 2–7 COMPLETE (`2a402b9`). Part 8 (Closure) split by Jafar 2026-09-04 into 8a/8b/8c.
  **8a CLOSED — all seven contract journey steps walked live and passed; one defect found and fixed
  (off-screen move confirmation).** **8b is active — the timezone booking defect it surfaced is now fixed
  and browser-verified; resume the paused Map walkthrough next.**
- Branch `schedule-5b-visits-card`. The 8a fix, the timezone fix, and Memory are **uncommitted** — Jafar has
  not yet approved a commit. Checks green: svelte-check 0 errors, 1720 unit tests passing, prettier clean on
  changed files. `git status` also lists ~200 other modified files that were **already dirty before this
  work** (repo-wide formatting drift, untouched here). Files changed this campaign, beyond this file,
  `ROADMAP.md` and `Memory/INDEX.md`:
  - 8a: `src/lib/components/ui/popover-anchor.ts` (new), `src/lib/components/ui/Popover.svelte`,
    `src/lib/components/schedule/ScheduleWeek.svelte`, `src/lib/components/schedule/ScheduleDay.svelte`,
    `src/routes/(app)/schedule/+page.svelte`.
  - Timezone fix: `src/lib/time/calendar-day.ts`, `src/lib/time/calendar-day.spec.ts` (new),
    `src/lib/components/requests/AssessmentBlock.svelte`, `src/lib/components/requests/RequestForm.svelte`,
    `src/lib/requests/api.ts`, `src/lib/quotes/api.ts`, `src/routes/api/requests/[id]/+server.ts`,
    `src/routes/api/quotes/counts/+server.ts`, `src/routes/(app)/requests/new/+page.svelte`,
    `src/routes/(app)/requests/[id]/+page.svelte`.
- Behavior in docs/schedule-behavior-contract.md (journeys 515-535, permissions/recovery 496-513).

## Active part — 8b (V1.1 calendar variety + V1.2 Map)

Assessments and Events carry their own meaning, actions and permissions. Then the Map for one employee:
stops readable, Anytime stops reordered by hand, order saved and surviving a reload, an unmappable address
handled honestly, Directions opened without losing date/employee/filter state. Also covers the three corners
Part 7 never exercised: keyboard stop reordering, the multi-pin route line, and per-stop / whole-route
Directions.

### Progress so far (2026-09-04, this session)

- Event created and its preview verified: "Morning crew huddle", Fri Sep 4 8:00–8:30am. Preview correctly
  shows no client/crew fields, just Edit/Delete — Event's own meaning confirmed.
- Two Anytime Visits created for the owner on Fri Sep 4, for the Map's manual-reorder test: Job #7 "Route
  test - anytime A" (Riverbend Family Diner) and Job #8 "Route test - anytime B" (Greenfield Property Group).
- One timed Assessment created for the owner on Fri Sep 4, 12:00–13:00 (Priya Anand, 482 Maple Street,
  Burnaby — geocoded): Request "Route test - assessment". Still needs its own preview/actions verified on
  the calendar (parallel to what was just done for the Event).
- **Not yet done:** open the Map for the owner on Fri Sep 4 and walk stops-readable, drag-reorder the two
  Anytime stops, keyboard-reorder, save-and-reload, per-stop and whole-route Directions. Still need an
  unmappable-address stop (none of the 9 properties in this org fail to geocode — create a client/property
  with a bad address, or accept a code-level check instead of a live one).

### Timezone defect — FIXED and verified live (2026-09-04)

Booking an on-site assessment converted the typed day/time using the **browser's own system timezone**
instead of the org's `organization_settings.timezone`. Fixed:

- Added `zonedTimeToUtc(day, time, timezone)` to `src/lib/time/calendar-day.ts` (reverse of
  `calendarDay`/`clockMinutesInZone`, same offset-read-twice technique as the server's `localMidnight`).
- `AssessmentBlock.svelte` now takes a `timezone` prop and uses it in `isoFrom`, `localPart`, `localTime`,
  and the `dayFormat`/`timeFormat` display formatters (those also read browser-local before this fix).
- Threaded the org timezone in from both callers: `/api/requests/[id]` (already computed it for status) and
  `/api/quotes/counts` (already carried currency/locale for the New Request page) each now also return
  `timezone`; `RequestDetail` and `QuoteOverview` types, the two pages, and `RequestForm.svelte` pass it
  down. Default `'UTC'` while a query is loading, matching the existing currencyCode/locale pattern.
- New `src/lib/time/calendar-day.spec.ts` (4 tests, includes the exact Asia/Dhaka reproduction). Checks
  green: svelte-check 0 errors, 1720 unit tests passing (was 1716), prettier clean on all changed files.
- **Verified live in-browser**: booked "Fri 4 Sept, 12:00 PM" on org timezone `Asia/Dhaka` from this
  sandbox's `America/Denver` browser; detail page correctly showed "Fri, 4 Sept 2026, 12:00 – 13:00" and the
  DB row confirmed `starts_at = 2026-09-04 06:00:00+00` (12:00 Dhaka, UTC+6). Test request deleted after.
- **Same bug found and fixed in a second place, on Jafar's approval**: `ScheduleAssessmentDialog.svelte`
  (Pipeline's "drop card onto Assessment scheduled" dialog, and its Brief-drawer "Schedule assessment"
  button) had its own duplicate `isoFrom` with the same browser-local-time defect. Now takes a `timezone`
  prop wired through `PipelineColumn.svelte` and `OpportunityNextActionSection.svelte` (from the
  `BoardFormatting` each already carried one level up) through to `OpportunityBriefDrawer.svelte`, using the
  same `zonedTimeToUtc`. Verified live: scheduled "A test request" for Sep 4 12:00-1:00 PM, DB confirmed
  `2026-09-04 06:00:00+00`; reverted that opportunity's assessment back to unscheduled afterwards since it
  is pre-existing seed data, not a throwaway fixture.
- svelte-check 0 errors (2950 files), 1720 unit tests passing, prettier clean — reconfirmed after this
  second fix.
- Ready to commit (both fixes) — Jafar approved committing in this session.

Test data left behind from the 8b investigation (Job #7, Job #8, and the "Route test - assessment" Request)
is fine to keep — it is exactly the fixture 8b's Map walkthrough needs next.

## Environment (this sandbox)

- Use `http://localhost:5173`. The `app.upliftcontractor.com` tunnel is dead here (`cloudflared` not
  installed). Agents cannot type passwords — ask Jafar to sign in.
- Node is not on PATH by default: `export PATH="$PATH:$HOME/.nvm/versions/node/v24.20.0/bin"`.
- The Playwright browser test project (15 of 204 files) cannot run here — chromium is not downloaded. The
  189 node test files run fine.
- Browser coordinates are **not** CSS pixels: the viewport was 1783×953 CSS while screenshots were 1512×808
  (factor 0.848). Read a real rect with `javascript_tool` before aiming at anything small, like the 8px
  resize grip. Screenshots occasionally time out for ~10s during heavy drags; wait and retake.
- This sandbox's OS timezone is `America/Denver` (MDT, UTC-6) — relevant to the timezone bug above, and
  worth rechecking after Jafar's restart in case it changes.

## Data facts (verified 2026-09-04, org Raad LTD `18f0d717-904e-48d8-bd99-9df7e3844cda`)

- Test data 8a left behind: **Job #5** "Gutter clearing - closure test" (closed/Requires invoicing, one
  completed visit Sep 4 13:30–16:30, both owner + admin assigned) and **Job #6** "Overlap probe" (active,
  visit Sep 4 10:00–11:00, owner only). Job #6 is deliberately kept — it is the second visit that makes
  overlap and permission checks possible. Delete both when the campaign closes.
- Test data 8b left behind so far: **Job #7** "Route test - anytime A" (Riverbend Family Diner, Anytime, Fri
  Sep 4, owner), **Job #8** "Route test - anytime B" (Greenfield Property Group, Anytime, Fri Sep 4, owner),
  and Request "Route test - assessment" (Priya Anand, timed 12:00–13:00 Fri Sep 4 — see timezone defect
  above for why it currently displays wrong). Delete all three when the campaign closes.
- Members: `info.socialmediauser1` = owner (shows as "Jafar Khan"), `jafarkhaninupwork` = admin ("Jafar
  Admin"), `dev.jafarkhan` = **field role** ("Jafar member") — the restricted login for 8c.
- Working hours: Mon–Thu roughly 9am–5pm; **Friday and the weekend are closed days** (the move confirmation
  says "Your business is closed that day").
- `job_visits`: `visit_date` date (nullable = unscheduled), `start_time`/`end_time` time, `all_day` bool,
  `completed_at`/`completed_by` uuid. `job_visit_assignments(visit_id, user_id)` holds assignees.
- `assessments`: `starts_at`/`ends_at` timestamptz (nullable = not booked), `all_day` bool,
  `completed_at`. `assessment_assignees(assessment_id, user_id)` holds assignees.
- `properties`: all geocoded rows `geocode_status = succeeded` with real Mapbox Permanent coordinates (9
  properties now, all succeeded — still no naturally-occurring unmappable one for that 8b test case).
  Worker `/api/internal/geocoding/worker` is live (secret `GEOCODING_WORKER_SECRET`).
- `schedule_route_orders`: one row per (org, employee, day); `stop_order` lists Visit/Assessment ids; save
  gated on jobs.schedule, read on jobs.view. Generated `database.types.ts` is intentionally stale.
- Route stops = Visits + Assessments only; Events are whole-team, not routeable. Route-order helpers:
  `serializeRouteOrder`, `applySavedOrder` in `route-order.ts`.
- `organization_settings.timezone` for Raad LTD = `Asia/Dhaka`.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events + map/route-order only.
- Map is a contextual split workspace, one selected employee, never resets date/employee/filters. Saved route
  order is a dispatch preference, not an appointment-time change. No auto-optimization / traffic / GPS.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.
