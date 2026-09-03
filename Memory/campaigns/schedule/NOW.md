# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 COMPLETE (`93c2e03`). Now on **Part 7 — contextual Map + manual Anytime routing** (V1.2).
  Behavior specified in docs/schedule-behavior-contract.md ("Contextual Map and route behavior" ~418-467,
  V1.2 ~147-162). Shipped: 7a-1 route-order+directions (`bef17be`), 7a-2 geocoding boundary+mock (`19ced68`),
  7a-3 geocode-status schema+trigger (`09645f8`), **7a-4 async geocoding worker (`5a126fe`)**.
- Branch `schedule-5b-visits-card`. Working tree clean at checkpoint time.
- 7a-4 verified on live data 2026-09-03: geocode write keeps `updated_at` (no list reorder); a real edit
  still bumps it; stale-address finalize rejected; claim uses the partial index. 13 unit tests green.
- **Provider decided 2026-09-03: managed Mapbox** behind a narrow provider boundary — Permanent geocoding
  with STORED property coordinates, managed tiles + route-line rendering, external Google/Apple navigation.
  No self-hosting until cost justifies it; re-verify pricing/terms before purchase. Recorded in the contract
  under "Map/directions provider boundary".

- Plan APPROVED 2026-09-03. Part 7 split into **7a (provider-independent foundation, mock fixtures)** and
  **7b (live Mapbox integration + verification)**. Jafar's constraint: build only provider-independent UI,
  route-order behavior and failure states now; do NOT finalize geocode persistence / call anything complete
  until real Mapbox tokens verify geocoding, rendering, routing, rate limits and errors. He provisions Mapbox
  meanwhile.

## Data facts (verified in code)

- `properties`: `latitude`/`longitude` numeric(9,6) + pair check (20260816103906); `geocode_status`
  text `pending|succeeded|failed` NOT NULL default `pending`, maintained by trigger
  `properties_mark_for_geocoding` (7a-3). All 8 existing rows are `pending` = the backfill queue. Window read
  (api.ts ScheduleVisit/ScheduleAssessment) carries address fields but NOT coords yet.
- 7a-4 worker (`src/lib/server/geocoding/worker.ts` + `provider.ts`, route
  `/api/internal/geocoding/worker`, secret `GEOCODING_WORKER_SECRET`): claim RPC
  `claim_pending_property_for_geocoding` (skip-locked, oldest first, partial index
  `properties_pending_geocoding_idx`) + `finalize_property_geocode` (guarded on the 4 query fields). The
  properties `updated_at` touch is now `private.properties_touch_updated_at` (keeps updated_at on a geocode-only
  write). Route is 503 until 7b provides a real provider — DO NOT run a mock against real rows.
- Route stops = Visits + Assessments only; Events are whole-team, not routeable. Only **Anytime Visits**
  are draggable; fixed-time items + ALL Assessments are locked chronological anchors (Request-owned order).
- Server domain code `src/lib/server/<domain>/`; pure schedule logic + `.spec.ts` `src/lib/schedule/`; env
  `src/lib/server/env.ts`. Geocoding boundary `src/lib/server/geocoding/` (`geocoder.ts` interface +
  `GeocodingProviderError(retryable)` + `geocodeQuery`; `mock-geocoder.ts` `createMockGeocoder(fixtures)`).

## Next action

**7a-5 — stop-list UI + Map workspace shell + failure states.** The contextual split workspace: one selected
employee's stops (Anytime Visits draggable; fixed-time items + ALL Assessments locked anchors) with the map
pane shell and the failure/empty states (no coords yet = `pending`; `failed` = kept in list with an
explanation, never dropped). Provider-independent — no live Mapbox tiles/routing yet (that's 7b). Reuse
route-order + directions logic from 7a-1 (`src/lib/schedule/`). Load **`svelte`** and **`design`** before
building; check `src/lib/components` for reusable pieces first. Behavior: contract ~418-467.
Part 8 (closure) needs 7a-1..7a-5 + 7b.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events + map/route-order only.
- Map is a contextual split workspace, one selected employee, never resets date/employee/filters. Saved
  route order is a dispatch preference, not an appointment-time change. No auto-optimization / traffic / GPS.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.
