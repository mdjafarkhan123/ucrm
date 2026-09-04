# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 COMPLETE (`93c2e03`). On **Part 7 — contextual Map + manual routing** (V1.2), split
  7a (provider-independent, mock) / 7b (live Mapbox). **7a is COMPLETE and BROWSER-VERIFIED.**
  Latest: drag-ghost suppression in pointer-drag (`66b9dbf`), 7a-5 gating fix (`cc346d0`), 7a-6 persist Save Route Order (`300d3ce`). Earlier: 7a-1
  route-order+directions (`bef17be`), 7a-2 geocoding boundary+mock (`19ced68`), 7a-3 geocode-status
  schema+trigger (`09645f8`), 7a-4 async geocoding worker (`5a126fe`), 7a-5 contextual Map workspace (`7aaa2c8`).
- Branch `schedule-5b-visits-card`. Working tree clean (drag-ghost fix committed `66b9dbf`).
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

## Next action — BROWSER-VERIFY 7b-A2, then B

**7b-A2 SHIPPED (checks-verified, browser-verify pending).** Added `mapbox-gl@3.30` (its own types; removed
redundant @types/mapbox-gl). New `RouteMap.svelte` replaces the map shell in `ScheduleRoute.svelte`: live
Mapbox tiles (theme-aware streets-v12/dark-v11), numbered circular pins in route order, a GeoJSON route line,
fit-to-bounds, pin click → same preview popover (onselect(stop, el)), selected-pin highlight. Un-geocoded
stops get display-only browser geocoding via `geocode-client.ts` (Mapbox v6 forward, TanStack query, session
cache, never stored) — retires itself once B stores coords. Checks: svelte-check 0 errors; 172 schedule tests
(4 new geocode); prettier + autofixer clean. Property addresses are real (Springfield/Vancouver/Savar) so
pins will resolve.
Follow-up fixes (`6c0ac89`): Map button now shows in every view (Jobber parity) and opening from Week/Month
switches to Day first; construct Mapbox after a rAF + resize() on load to fix a black (0-size) canvas. Token
verified valid via curl (geocoding + both styles 200), so black was init timing, not the token. Contract
updated ("Contextual Map and route behavior": button in every view).
Browser-verify (PENDING JAFAR, needs hard refresh): Schedule → Map button (any view) → pick employee →
confirm tiles render (not black), pins, line, pin-click preview, selection highlight, dark/light.

Parked (do right after map is confirmed OK, Jafar 2026-09-04): the Schedule filter row is getting long —
show a few filters and collapse the rest behind a "More…" button (standard overflow pattern). Not started.

**7b-B (BLOCKED on sk. token):** turn the 7a-4 worker route on (503 until a real provider), geocode the 8
pending properties permanently, store lat/lng. Then stored coords win in `stopGeocodeState` and the A2
display lookup stops running. Re-verify pricing/terms before purchase.

Part 8 (closure) needs 7a (done) + 7b-A2 (done, pending browser-verify) + 7b-B.

Not-yet-tested corner (no data during verification): keyboard reordering (Arrow keys on a focused Anytime
stop) and per-stop / whole-route Directions were present in code but not exercised live — worth a quick check
when 7b brings real geocoded stops.

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
