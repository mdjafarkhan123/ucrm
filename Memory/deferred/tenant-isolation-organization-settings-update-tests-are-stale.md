# `tenant_isolation.sql` still expects direct UPDATE on `organization_settings`

- **Priority:** P2
- **Campaign:** none — found while verifying an unrelated migration (clients.owner_user_id removal, 2026-08-24)
- **Reason:** `supabase/tests/database/tenant_isolation.sql` lines ~396-404 run
  `update public.organization_settings set locale = ... ` directly as the `authenticated` role and expect
  `lives_ok`/cross-tenant-denial behavior. But `supabase/migrations/20260823100000_contractor_settings_foundation.sql`
  (Part 1 of contractor-settings) deliberately revoked table `UPDATE` on `organization_settings` from
  `authenticated` — all writes now go through a `SECURITY DEFINER` command instead, specifically so the
  currency-lock and revision-conflict rules can't be bypassed. The test file was never updated to match, so
  both assertions ("a member can update their organization settings" and "cross-tenant settings update is
  denied") now die with `42501: permission denied for table organization_settings` instead of testing what
  they claim to test. Confirmed pre-existing and unrelated to any change in this session — same 2 failures
  happen on a clean run of the file as committed.
- **Reactivation trigger:** Someone next touches `tenant_isolation.sql` or the settings write path, or
  wants the pgTAP suite fully green again.
- **Checkpoint:** `supabase/tests/database/tenant_isolation.sql`,
  `supabase/migrations/20260823100000_contractor_settings_foundation.sql`
