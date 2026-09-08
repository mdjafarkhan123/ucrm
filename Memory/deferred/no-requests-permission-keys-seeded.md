# No `requests.*` permission keys seeded

- **Priority:** P1 — raised from P2 on 2026-09-08. Jobs 15g Round 1 observed the consequence live: a **Field
  member sees every request in the business** on the Dashboard, with only the customer and property names
  redacted (they read "Unknown customer / Unknown property" because the clients read is scoped while the
  request rows are not). The request title and description are fully visible. The `requests` RLS policies
  confirm it — SELECT *and* UPDATE both allow any `private.is_organization_member(organization_id)`. Jobs
  15a-2/15a-3 narrowed jobs, visits and assessments to assigned work; requests were never in that boundary.


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

