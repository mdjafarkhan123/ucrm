# No `requests.*` permission keys seeded

- **Priority:** P2


- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Every request route and every request note currently only checks organization membership.
  Seeding a real role matrix is a separate, cross-cutting call, not specific to Requests.
- **What is missing:** `requests.view` / `requests.create` / etc. equivalent to the `customers.*` keys
  clients already use (`requireClientPermission`).
- **Reactivation trigger:** Jafar asks for role-gated request access, or a second campaign needs the same
  pattern and it's worth doing once for both.
- **Prerequisites:** Decide the role matrix shape with Jafar first — this affects every future work object,
  not just requests.
- **Checkpoint:** `src/lib/server/access/`, `src/routes/api/requests/`.

