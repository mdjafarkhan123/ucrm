# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 **COMPLETE and committed** (`93c2e03` "Schedule 6a-2: Schedule-owned Events"). 6a-1
  Assessments + 6a-2 Events both shipped, build + type/test green, browser-verified 2026-09-03.
- Branch `schedule-5b-visits-card`. Working tree clean at checkpoint time.
- Now on **Part 7 — contextual Map + manual Anytime routing** (V1.2). Behavior fully specified in
  docs/schedule-behavior-contract.md ("Contextual Map and route behavior" ~418-467, V1.2 ~147-162).
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

- `properties` ALREADY has `latitude`/`longitude` numeric(9,6) + a pair-consistency check (migration
  20260816103906). No geocode STATUS column yet, no populate path. Window read (api.ts ScheduleVisit/
  ScheduleAssessment) carries address fields but NOT coords.
- Route stops = Visits + Assessments only; Events are whole-team, not routeable. Only **Anytime Visits**
  are draggable; fixed-time items + ALL Assessments are locked chronological anchors (assessment order is
  Request-owned/read-only). Contract "Contextual Map and route behavior" ~418-450.
- Server domain code: `src/lib/server/<domain>/`; pure schedule logic + co-located `.spec.ts`:
  `src/lib/schedule/`; env access `src/lib/server/env.ts`. Provider boundary → `src/lib/server/geocoding/`.

## Next action

Build 7a incrementally (mock-first). (1) pure `src/lib/schedule/route-order.ts` + `directions.ts` with specs
**DONE** — 29 specs green, types clean, not yet committed. Next: (2) provider boundary interface + mock geocoder
in `src/lib/server/geocoding/`; (3) provisional geocode-status schema + on-save path; (4) stop-list UI + Map
workspace shell + failure states. Load `svelte`+`design` before any .svelte; `supabase-postgres-best-practices`
before the migration; `performance-review` design branch before the backfill path. Part 8 (closure) needs 2-7.

7a-1 built (pure logic, no provider): `route-order.ts` (routeStops/isAnchor/defaultRouteOrder/enforceAnchorOrder/
applySavedOrder/moveAnytimeStop/serializeRouteOrder — invariant: anchor subsequence always chronological;
only Anytime Visits movable; Events excluded) and `directions.ts` (single + whole-route Google/Apple deep-links,
coords-over-address, no-destination + too-many-stops states; caps `MAX_ROUTE_STOPS` google 10 / apple 4, not
contractual). Anytime Assessments sink below timed anchors, stable by id.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events + map/route-order only.
- Map is a contextual split workspace, one selected employee, never resets date/employee/filters. Saved
  route order is a dispatch preference, not an appointment-time change. No auto-optimization / traffic / GPS.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.
