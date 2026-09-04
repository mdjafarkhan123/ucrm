# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 COMPLETE (`93c2e03`). On **Part 7 — contextual Map + manual routing** (V1.2), split
  7a (provider-independent, mock) / 7b (live Mapbox). **7a COMPLETE + BROWSER-VERIFIED. 7b-A2 COMPLETE +
  BROWSER-VERIFIED (`91d8bbc`, 2026-09-04) — two bugs found + fixed during verify (see below).** Only 7b-B
  (stored geocoding) remains for Part 8, blocked on a secret (sk.) Mapbox token.
- Branch `schedule-5b-visits-card`. Working tree clean (latest `5b86ea7` — Filters popover
  z-index + trigger-styling follow-up fixes, committed + browser-verified).
- Behavior in docs/schedule-behavior-contract.md ("Contextual Map and route behavior" ~418-467, V1.2 ~147-162).

## Browser verification (2026-09-04, app on localhost:5173, workspace "Raad LTD")

Verified live end-to-end: Map toggle in Day view; one-employee gating chooser ("Whose route?"); stop list with
per-stop "Locating…" (all properties still pending); honest map shell; pointer drag reorder of Anytime stops;
Save Route Order button appears on drag, shows "Saving…", persists (DB row `stop_order` matched the dragged
sequence), toasts "Route order saved", clears; and the saved order **rehydrates on reload** (overriding the
default position order). No console errors. Test data (one temp visit + its route-order row) was created and
then deleted. **Found + fixed a 7a-5 gating bug** (`cc346d0`): confirming an employee in the chooser applied
the filter but left the Map closed (async-goto race vs the auto-close effect); re-verified fixed.

## What 7a-6 shipped (checks-verified AND browser-verified)

- Migration `schedule_route_orders` (`20260904100000`): PK (organization_id, employee_id, route_date);
  composite FK to `organization_members(organization_id, user_id)` ON DELETE CASCADE; `stop_order uuid[]`
  capped at 500; RLS by org membership (wrapped in `(select …)`); `set_updated_at` trigger. Applied to remote;
  no new security advisors.
- Zod `scheduleRouteOrderWriteSchema` / `scheduleRouteOrderQuerySchema` in schedule.schema.ts.
- Route `/api/schedule/route-order/+server.ts`: GET (jobs.view, lazy per employee+day, missing row → `[]`)
  and PUT upsert (jobs.schedule). Unknown stop ids are ignored on apply — a soft preference list, never FK'd.
- Client `fetchScheduleRouteOrder` / `saveScheduleRouteOrder` + `scheduleRouteOrderKey` in schedule/api.ts.
- `ScheduleRoute.svelte`: new props `savedOrder`/`saving`/`onsave`. `effectiveOrder = manualOrder ?? savedOrder`
  so a saved route rehydrates on open and a drag overrides it. "Save Route Order" button appears only when a
  drag left the order dirty, reads "Saving…", and clears once saved (server returns canonical order).
- Page wires a lazy route-order query (enabled only while Map is open on one employee) + a save mutation that
  `setQueryData`s the server's order and toasts. Contract: saved order is per employee+date; a shared Visit
  sits once per employee route at that employee's position (falls out of the (employee,date) PK).
- Checks: svelte-check 0 errors; 168 schedule unit tests pass; prettier clean; svelte autofixer clean.

## 7b split into A2 (public token, live map) + B (sk. token, stored geocoding)

Jafar gave a **public** Mapbox token (pk.), formatted into `.env` as `PUBLIC_MAPBOX_TOKEN` (+ empty
`MAPBOX_ACCESS_TOKEN=` placeholder for the future secret token). Chose path **A2**: live map now, geocoding
next. Permanent/stored geocoding needs a secret (sk.) token + plan tier, so it waits for B.

## 7b-A2 COMPLETE + BROWSER-VERIFIED 2026-09-04

`RouteMap.svelte` (in `ScheduleRoute.svelte`): live Mapbox tiles (theme-aware streets-v12/dark-v11),
numbered circular pins in route order, GeoJSON route line, fit-to-bounds, pin click → preview popover
(onselect(stop, el)), selected-pin highlight. Un-geocoded stops get display-only browser geocoding via
`geocode-client.ts` (Mapbox v6 forward, TanStack query, session cache, never stored) — retires once B stores
coords. `mapbox-gl@3.30`. Black-canvas fixed with rAF + resize() on load; Map button in every view (`6c0ac89`).

Browser-verified live (Sep 1, Jafar Khan's route, one stop at Savar): Map opens; tiles render; numbered green
pin placed via display geocoding; pin-click preview + list-card selection; **light app→light map, dark toggle
→ dark map live**; selected pin turns **blue** and survives a theme re-style. The stop-list "Locating…" is
EXPECTED (stored geocode_status still pending until 7b-B; map pins come from session display geocoding).

**Two bugs found + fixed during verify (`91d8bbc`):**
1. Map theme ignored the app: `currentTheme()` fell back to prefers-color-scheme, but the app keys its
   palette only on `[data-theme='dark']` and never reads the OS → light app on a dark-OS machine got a dark
   map. Now the map mirrors the app (dark iff data-theme='dark'); watchTheme dropped its OS-pref listener.
2. Pin selection never highlighted: the selection `$effect` read `selectedItemId` only inside a loop that is
   empty before any stop geocodes, so it never subscribed. Now read unconditionally at the top.
Checks after fixes: svelte-check 0 errors; 172 schedule tests pass; prettier + autofixer clean.

Aside (NOT fixed, app-wide, needs Jafar): `Topbar.applyTheme` uses `toggleAttribute('data-theme', dark)`,
which REMOVES data-theme in light mode (so absent = light). The map fix accounts for this; the app renders
fine. A cleaner whole-app fix would always set data-theme='light'|'dark', but that is outside Schedule scope.

## Filters popover DONE + BROWSER-VERIFIED 2026-09-04 (`4e9d6c1`)

Jafar chose the Jobber-style layout. `ScheduleControls.svelte` now keeps date-nav + View + Unscheduled + Map
on the row and moves Employee + Status + Density behind a single **Filters** button — repo-standard bits-ui
`Popover.Root/Trigger/Portal/Content` (as NotificationBell). Count badge = active data filters only (Employee,
Status; Density is a view option, never counts). "Clear" link in the panel header resets Employee+Status when
count>0. No `+page` wiring changed. Verified live: row collapses; panel opens with all three; picking Employee
narrows the grid + lights badge "1" + shows Clear; Clear resets; no console errors. Checks: svelte-check 0
errors; 172 schedule tests; prettier clean. (Autofixer flagged SCSS `//` + `&--active` — false positives from
no SCSS preprocessing; svelte-check is authoritative and clean.)

## Filters popover follow-up fixes DONE + BROWSER-VERIFIED 2026-09-04

Two bugs found after the popover shipped, both fixed same day:
1. The Employee/Status `Select` dropdowns opened *behind* the Filters panel (Select content sits at
   `--elevation-modal` 1001, the panel at `--elevation-tooltip` 1002 — fine when a Select is on the page, not
   when nested in a popover). Fixed via a new `Select.svelte` `contentClass` prop; the two Selects here pass
   `schedule-controls__filters-select`, styled one z-index above the panel.
2. The Filters trigger itself had zero real styling (raw browser button border) — it is a Bits UI
   `Popover.Trigger`, which renders its own `<button>` outside Svelte's scoped-CSS reach, so the scoped
   `.schedule-controls__unscheduled` pill rule silently never matched it. Made that rule `:global()`
   (no visual change for the plain Unscheduled/Map buttons, which still carry the class).

Both re-verified live: dropdowns render fully above the panel; trigger now matches Map/Unscheduled exactly in
all states (rest, hover, open/active, focus).

## Next action — 7b-B (the only thing left for Part 8)

- **7b-B (BLOCKED on sk. token):** turn the 7a-4 worker route on (503 until a real provider), geocode the 8
  pending properties permanently, store lat/lng. Then stored coords win in `stopGeocodeState` and the A2
  display lookup stops running. Re-verify pricing/terms before purchase.

Part 8 (closure) needs 7a (done) + 7b-A2 (done ✅) + 7b-B (blocked on sk. token).

Not-yet-tested corner (only one stop in verify data): keyboard reordering (Arrow keys on a focused Anytime
stop), multi-pin route line, and per-stop / whole-route Directions — exercise when 7b brings more stops.

## Data facts (verified in code)

- `properties`: `latitude`/`longitude` numeric(9,6); `geocode_status` text `pending|succeeded|failed` NOT NULL
  default `pending`, maintained by trigger `properties_mark_for_geocoding` (7a-3). All 8 rows `pending`.
- 7a-4 worker (`src/lib/server/geocoding/worker.ts`+`provider.ts`, route `/api/internal/geocoding/worker`,
  secret `GEOCODING_WORKER_SECRET`): claim RPC `claim_pending_property_for_geocoding` (skip-locked, partial
  index `properties_pending_geocoding_idx`) + `finalize_property_geocode`. Route is 503 until 7b provides a
  real provider — DO NOT run a mock against real rows.
- `schedule_route_orders`: one row per (org, employee, day); `stop_order` is a list of Visit/Assessment ids;
  save gated on jobs.schedule, read on jobs.view. Generated `database.types.ts` is stale (predates even
  schedule_events); the supabase client is not strictly bound to it, so it was intentionally not regenerated.
- Route stops = Visits + Assessments only; Events are whole-team, not routeable. Server domain code
  `src/lib/server/<domain>/`; pure schedule logic + `.spec.ts` `src/lib/schedule/`.
- Route-order serialize/rehydrate helpers live in `route-order.ts`: `serializeRouteOrder`, `applySavedOrder`.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events + map/route-order only.
- Map is a contextual split workspace, one selected employee, never resets date/employee/filters. Saved route
  order is a dispatch preference, not an appointment-time change. No auto-optimization / traffic / GPS.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.
