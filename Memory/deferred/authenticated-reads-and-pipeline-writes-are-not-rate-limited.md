# Authenticated reads and non-quote/invoice/payment writes lack a shared rate-limit policy

- **Priority:** P1
- **Why postponed:** Limiting one route would be inconsistent; the decision belongs to the shared API guard and adds request overhead.
- **Narrowed 2026-09-11 (paid-launch-trust Part 14):** quote, invoice, and payment writes are now covered by
  `enforceOrganizationWriteRateLimit` (one shared per-organization-per-domain bucket, live-verified: 21st
  write in 60s gets a 429). Still open: every authenticated GET/list read anywhere in the app, and writes on
  every other domain (jobs, clients, requests, team, settings, pipeline, collaboration, checklists,
  signatures).
- **Reactivate when:** VPS deployment approaches, connection saturation appears, or shared API guards are reworked.
- **Constraint:** Decide user-facing refusal and bucket ownership once for all remaining authenticated list reads and writes.
- **Pointers:** src/lib/server/security/rate-limit.ts and src/lib/server/access/permission.ts.
