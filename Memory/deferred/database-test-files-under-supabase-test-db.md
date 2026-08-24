# Database test files under `supabase test db`

- **Priority:** P3


- **Campaign:** `clients-properties` (applies to every campaign that adds database tests)
- **Reason:** Development runs against the remote Supabase project with no Docker and no local stack, so
  the pgTAP runner cannot execute. Assertions are verified against the remote project instead, inside one
  transaction that is rolled back.
- **Reactivation trigger:** The app is containerized with local Supabase, or Docker becomes available.
- **Prerequisites:** `npx supabase start`, then `npx supabase test db`. Expect the runner to surface plan
  counts and ordering problems that single-transaction verification cannot.
- **Checkpoint:** `supabase/tests/database/tenant_isolation.sql` (plan 75 as of 2026-08-17). Note: this file
  has never actually been executed by the pgTAP runner, so its plan count and statement ordering are
  unproven — expect the first real run to surface problems that per-assertion verification cannot.
- `supabase/tests/database/client_create_edit.sql` (plan 21) is different: on 2026-08-17 its whole body was
  executed against the remote project in one rolled-back transaction, as the real `authenticated` role, and
  all 21 assertions passed. Its plan count and ordering are proven; only the CLI runner itself is untried.

