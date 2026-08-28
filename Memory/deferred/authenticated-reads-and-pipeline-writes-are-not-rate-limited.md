# Authenticated reads and writes lack a shared rate-limit policy

- **Priority:** P1
- **Why postponed:** Limiting one route would be inconsistent; the decision belongs to the shared API guard and adds request overhead.
- **Reactivate when:** VPS deployment approaches, connection saturation appears, or shared API guards are reworked.
- **Constraint:** Decide user-facing refusal and bucket ownership once for all authenticated list reads and writes.
- **Pointers:** src/lib/server/security/rate-limit.ts and src/lib/server/access/permission.ts.
