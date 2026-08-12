# Deferred Tests

Tests that are written and reviewed but not yet executed, because running them needs something
not set up yet (usually Docker for local database tests). Each entry stays here until it's actually
run and confirmed passing — then move the result into the relevant task's own Memory file (or delete
this line if there's nothing left to track) and remove it from this list.

## Open

### `supabase/tests/database/platform_operations_foundation.sql`

- **What it checks:** RLS on `platform_operation_attempts`, `platform_owner_notifications`,
  `platform_outbox_deliveries` (anon/authenticated blocked, service_role allowed); the operation
  attempts unique-key constraint rejecting a simulated concurrent duplicate-failure insert; the
  notification trigger allowing a read-only update but rejecting a content change or delete; the
  audit-events immutability trigger rejecting update/delete. 31 pgTAP assertions.
- **How to run:** `npx supabase test db` (needs Docker Desktop running — see [[docker-decision]] below).
- **Deferred:** 2026-08-12. User chose to defer rather than install Docker right now. See
  `Memory/jafar-complete-roadmap.md` Part 2e for the task this belongs to.
- **Status:** written, reviewed against the exact schema/constraint/trigger names in migration
  `20260812055458_platform_operations_foundation.sql`, not yet executed.

### `supabase/tests/database/platform_owner_settings.sql`

- **What it checks:** RLS on `platform_owner_settings` (anon/authenticated blocked, service_role
  allowed); the boolean-primary-key singleton constraint rejecting `id = false` and rejecting a second
  row; the `update_owner_settings` function producing both the row update and its matching
  `platform_owner_audit_events` row. 15 pgTAP assertions.
- **How to run:** `npx supabase test db` (needs Docker Desktop — see [[docker-decision]] below).
- **Deferred:** 2026-08-12, same standing Docker deferral as the file above. See
  `Memory/jafar-complete-roadmap.md` Part 4a for the task this belongs to.
- **Status:** written, reviewed against migration `20260812091402_platform_owner_settings.sql`, not yet
  executed.
