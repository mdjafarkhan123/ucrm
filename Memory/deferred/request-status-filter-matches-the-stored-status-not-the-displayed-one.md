# Request Status filter matches the stored status, not the displayed one

- **Priority:** P2


- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Confirmed in the browser pass — honest but confusing, not decided whether worth fixing yet.
- **What is wrong:** Picking "Unscheduled" in the Status filter also returns rows badged "Overdue"/"Today"
  in the table, because the filter runs against `requests.status` (six stored values) while the badge shown
  is the derived nine-value status. Filtering by the derived status is possible with the same day-boundary
  logic `GET /api/requests/counts` already computes.
- **Reactivation trigger:** Jafar reports the filter behaving unexpectedly, or asks for it to match the
  badge.
- **Prerequisites:** Decide whether to filter by computed status server-side (extra per-row date math) or
  keep the stored-status filter and relabel it so it reads honestly.
- **Checkpoint:** `src/routes/api/requests/+server.ts`, `src/lib/server/requests/status.ts`.

