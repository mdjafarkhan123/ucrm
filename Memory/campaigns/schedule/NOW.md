# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 COMPLETE (`93c2e03`). On **Part 7 — contextual Map + manual routing** (V1.2), split
  7a (provider-independent, mock) / 7b (live Mapbox). Shipped: 7a-1 route-order+directions (`bef17be`),
  7a-2 geocoding boundary+mock (`19ced68`), 7a-3 geocode-status schema+trigger (`09645f8`),
  7a-4 async geocoding worker (`5a126fe`), **7a-5 contextual Map workspace (`7aaa2c8`)**.
- Branch `schedule-5b-visits-card`. Working tree clean at checkpoint time.
- Behavior in docs/schedule-behavior-contract.md ("Contextual Map and route behavior" ~418-467, V1.2 ~147-162).

## What 7a-5 shipped (checks-verified; browser verification still pending)

- Map toggle in the **Day view only**, one-employee gating (opening from All/Unassigned prompts a chooser
  that also sets the employee filter). Split workspace replaces the grid while open; closing returns to it.
- Ordered stop list (`ScheduleRoute.svelte` + `RouteStopCard.svelte`) reusing tested `route-order.ts`:
  fixed-time Visits + ALL Assessments locked anchors; only Anytime Visits reorder by pointer drag or
  Arrow keys. Manual order held **in-session only** (feeds whole-route Directions); NOT persisted yet.
- Honest per-stop geocode states via new pure `src/lib/schedule/stops.ts` (+ `stops.spec.ts`):
  located / pending("Locating…") / failed("Address didn't map") / no-address — unmappable stops stay in the
  list, never dropped. Map pane is a shell (no live tiles) summarising how many stops are placeable.
- Google/Apple Directions per stop and whole-route (waypoint-limit spelled out on the over-cap provider).
- Window read (`api/schedule/visits/+server.ts`, `ScheduleVisit`/`ScheduleAssessment`/`AssessmentItem`) now
  carries `property_latitude`/`property_longitude`/`property_geocode_status`. All 8 properties still `pending`
  (no geocode run yet) → in the app every stop shows "Locating…" until 7b geocodes.
- Checks: svelte-check 0 errors; 179 schedule unit/component tests pass (incl. 12 new stops.spec cases);
  svelte MCP autofixer clean bar the standard trusted-icon {@html} caution; prettier clean.

## Next action

**7a-6 — persist Save Route Order.** Purely additive to the drag that already works: a per-(employee, date)
route-order store + save command + `/api/*` route + Zod + RLS + TanStack invalidation, and a "Save Route
Order" button in `ScheduleRoute.svelte` wired to it (button intentionally absent in 7a-5). Contract: saved
order is a dispatch preference scoped to employee+date, not an appointment-time change; a shared Visit sits
once per employee route at that employee's saved position (~424-426). Load **supabase-postgres-best-practices**
before the migration, then **svelte**/**design** for the button. Serialize via `serializeRouteOrder`; rehydrate
via `applySavedOrder` (both already in `route-order.ts`).
Also recommended before/with 7a-6: **browser-verify the 7a-5 Map UI** (toggle, gating, stop list, drag,
failure states, Directions) on the running app.
Part 8 (closure) needs 7a-1..7a-6 + 7b.

## Data facts (verified in code)

- `properties`: `latitude`/`longitude` numeric(9,6); `geocode_status` text `pending|succeeded|failed` NOT NULL
  default `pending`, maintained by trigger `properties_mark_for_geocoding` (7a-3). All 8 rows `pending`.
- 7a-4 worker (`src/lib/server/geocoding/worker.ts`+`provider.ts`, route `/api/internal/geocoding/worker`,
  secret `GEOCODING_WORKER_SECRET`): claim RPC `claim_pending_property_for_geocoding` (skip-locked, partial
  index `properties_pending_geocoding_idx`) + `finalize_property_geocode`. Route is 503 until 7b provides a
  real provider — DO NOT run a mock against real rows.
- **Provider decided 2026-09-03: managed Mapbox** (Permanent geocoding, STORED coords; managed tiles + route
  line; external Google/Apple navigation). Re-verify pricing/terms before purchase. Contract "Map/directions
  provider boundary". 7b is BLOCKED on Jafar's Mapbox tokens.
- Route stops = Visits + Assessments only; Events are whole-team, not routeable. Server domain code
  `src/lib/server/<domain>/`; pure schedule logic + `.spec.ts` `src/lib/schedule/`.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events + map/route-order only.
- Map is a contextual split workspace, one selected employee, never resets date/employee/filters. Saved route
  order is a dispatch preference, not an appointment-time change. No auto-optimization / traffic / GPS.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.
