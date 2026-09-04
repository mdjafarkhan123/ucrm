# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 COMPLETE (`93c2e03`). On **Part 7 — contextual Map + manual routing** (V1.2), split
  7a (provider-independent, mock) / 7b (live Mapbox). **7a is now COMPLETE: 7a-1..7a-6 all shipped.**
  Latest: 7a-6 persist Save Route Order (`300d3ce`). Earlier: 7a-1 route-order+directions (`bef17be`),
  7a-2 geocoding boundary+mock (`19ced68`), 7a-3 geocode-status schema+trigger (`09645f8`),
  7a-4 async geocoding worker (`5a126fe`), 7a-5 contextual Map workspace (`7aaa2c8`).
- Branch `schedule-5b-visits-card`. Working tree clean at checkpoint time.
- Behavior in docs/schedule-behavior-contract.md ("Contextual Map and route behavior" ~418-467, V1.2 ~147-162).

## What 7a-6 shipped (checks-verified; browser verification still pending)

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

## Next action

Two independent threads, neither dependency-locked on the other:

1. **Browser-verify the Map UI (7a-5 + 7a-6)** on the running app — toggle + one-employee gating, ordered stop
   list, pointer/keyboard drag of Anytime stops, per-stop geocode failure states (all 8 properties are still
   `pending`, so every stop shows "Locating…"), per-stop + whole-route Directions, and the new Save Route
   Order button (appears on drag, persists, rehydrates on reopen, clears when saved). Needs the dev server up
   and a logged-in session. Recommended before declaring 7a done-done.
2. **7b — live Mapbox** (BLOCKED on Jafar's Mapbox tokens). Provider decided 2026-09-03: managed Mapbox
   (Permanent geocoding, STORED coords; managed tiles + route line; external Google/Apple navigation). Turns
   the 7a-4 worker route on (503 until a real provider), swaps the map shell for live tiles/pins, geocodes the
   8 pending properties. Re-verify pricing/terms before purchase.

Part 8 (closure) needs all of 7a (done) + 7b.

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
