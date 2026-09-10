# Entitlement-gated routes repeatedly resolve the full access model

- **Priority:** P2
- **Why postponed:** The resolver is cross-cutting and mixes global package data with live organization/member
  access; a safe cache/request-sharing change needs Jafar's staleness decision.
- **Reactivate when:** A gated page is slow, VPS connection pressure matters, or the access resolver is edited.
- **Constraint:** Jafar must approve acceptable staleness; never cache one member's access for another.
- **Measured evidence:** Jobs detail starts 8 gated APIs. With versioned packages, each gate performs organization
  context plus about 16 access-model Data API/RPC reads: roughly 136 access reads before endpoint work and about
  155 Supabase calls for the measured empty-side-data page. The 26-Visit fan-out measured 1.626 s median.
- **Pointers:** src/lib/server/access/effective.ts and src/lib/server/access/permission.ts.
- **Report:** docs/research/jobs-performance-verification-2026-09-10.md.
