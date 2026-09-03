# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: V1.1 **COMPLETE and committed** (`93c2e03` "Schedule 6a-2: Schedule-owned Events"). 6a-1
  Assessments + 6a-2 Events both shipped, build + type/test green, browser-verified 2026-09-03.
- Branch `schedule-5b-visits-card`. Working tree clean at checkpoint time.
- Now on **Part 7 — contextual Map + manual Anytime routing** (V1.2). Behavior fully specified in
  docs/schedule-behavior-contract.md ("Contextual Map and route behavior" ~418-467, V1.2 ~147-162).
  7a-1 route-order+directions (`bef17be`), 7a-2 geocoding boundary+mock (`19ced68`), 7a-3 geocode-status
  schema+trigger (`09645f8`) shipped.
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

- `properties`: `latitude`/`longitude` numeric(9,6) + pair check (20260816103906); now `geocode_status`
  text `pending|succeeded|failed` NOT NULL default `pending`, maintained by trigger
  `properties_mark_for_geocoding` (07a-3). All 8 existing rows are `pending` = the backfill queue. Window read
  (api.ts ScheduleVisit/ScheduleAssessment) carries address fields but NOT coords yet.
- Route stops = Visits + Assessments only; Events are whole-team, not routeable. Only **Anytime Visits**
  are draggable; fixed-time items + ALL Assessments are locked chronological anchors (Request-owned order).
- Server domain code `src/lib/server/<domain>/`; pure schedule logic + `.spec.ts` `src/lib/schedule/`; env
  `src/lib/server/env.ts`. Geocoding boundary `src/lib/server/geocoding/` (`geocoder.ts` interface +
  `GeocodingProviderError(retryable)` + `geocodeQuery`; `mock-geocoder.ts` `createMockGeocoder(fixtures)`).

## Next action

**7a-4 — background geocoding worker.** Jafar chose Jobber-style async (save returns instantly at `pending`;
a background job fills coords). Build a worker that claims `pending` properties, calls the **injected**
`Geocoder` (mock now, Mapbox in 7b), and writes coords + `succeeded`/`failed`; on `GeocodingProviderError`
leave the row `pending` to retry (never mark `failed`). Reuse the existing worker pattern (secret-gated
endpoint + claim/drain, cf. communications email-outbox worker; add a `*_WORKER_SECRET` to
`src/lib/server/env.ts`). Add a **partial index** on `properties … where geocode_status='pending'` for the claim.
- **Constraint (verified):** `properties_set_updated_at` fires on ANY update, and
  `properties_organization_contact_idx` orders by `updated_at desc` — so a naive worker coords-write churns
  every client's property-list order during backfill. The worker's write must NOT bump `updated_at`.
- **Gates:** `performance-review` design branch BEFORE building (backfill of all properties + per-property
  provider calls is scale-sensitive); `supabase-postgres-best-practices` for the index/claim SQL.
Then **7a-5** (was step 4): stop-list UI + Map workspace shell + failure states — load `svelte`+`design`.
Part 8 (closure) needs 7a-1..7a-5 + 7b.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events + map/route-order only.
- Map is a contextual split workspace, one selected employee, never resets date/employee/filters. Saved
  route order is a dispatch preference, not an appointment-time change. No auto-optimization / traffic / GPS.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.
