# Pipeline formatting depends on a Settings permission

- **Priority:** P2
- **Why postponed:** A Pipeline viewer with settings.business.view explicitly denied receives default columns, UTC, and USD because organization_settings returns no row.
- **Reactivate when:** Per-member denies are used or one teammate sees different Pipeline formatting.
- **Constraint:** Serve presentation and formatting through a Pipeline-authorized read, not by weakening Settings access.
- **Pointers:** src/lib/server/pipeline/presentation.ts and src/lib/server/requests/timezone.ts.
