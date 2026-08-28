# Growing-table RLS helpers run per returned row

- **Priority:** P2
- **Why postponed:** Fixing this crosses Clients, Requests, collaboration, and other growing tables; tiny fixed-size Settings tables do not benefit from the same rewrite.
- **Reactivate when:** A growing list slows down or its policies are already being changed.
- **Constraint:** Preserve assigned-work visibility. Collaboration notes need the linked-entity helper itself optimized; changing only the policy shape made it worse.
- **Pointer:** supabase/migrations/20260818133726_pipeline_rls_permission_lookup_once_per_query.sql.
