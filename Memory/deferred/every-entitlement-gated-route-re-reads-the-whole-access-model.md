# Entitlement-gated routes repeatedly resolve the full access model

- **Priority:** P2
- **Why postponed:** The resolver is cross-cutting and mixes global package data with live organization/member access.
- **Reactivate when:** A gated page is slow, VPS connection pressure matters, or the access resolver is edited.
- **Constraint:** Jafar must approve acceptable staleness; never cache one member's access for another.
- **Pointers:** src/lib/server/access/effective.ts and src/lib/server/access/permission.ts.
