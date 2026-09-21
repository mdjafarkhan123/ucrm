# Part 3 — Prove it (packet)

**Goal:** show the four baseline files rebuild the live database and the pgTAP tests pass on the rebuild. Files in `supabase/migrations/`:
`20260101000000_baseline_structure`, `...0100_baseline_platform_hooks`, `...0200_baseline_reference_data`, `...0300_baseline_scheduled_jobs`.

**Proof stack (throwaway; never touch the real local stack `supabase_db_ucrm` on 54322):** copy `supabase/` to the scratchpad; in the copy set
`project_id = "ucrm_baseline"`, `[db] port = 55322, shadow_port = 55320, major_version = 17`, `[auth]`, `[realtime]`, `[api]` enabled (Realtime must
be on or `realtime.messages` is missing and the hooks file fails), everything else off; copy `.temp/`. Then `npx supabase db reset --local --no-seed`,
`npx supabase db diff --linked`, and `npx supabase test db` (copy `supabase/tests/` in). Stop with `npx supabase stop --no-backup` from the copy.

**Known diff noise after rebuild — accepted, do not chase:** pgtap (left out on purpose; every test creates it); pg_net schema (image preinstalls
it in `extensions`, live has `public`); 3 `public can view published package*` policies (role-list order only); 5 check constraints
(`clients_billing_address_complete`, `invoices_tax_check`, `jobs_tax_check`, `organization_member_invitations_invited_email_check`,
`quote_versions_tax_check`: same logic, different bracket nesting); 4 Supabase-owned `storage.*` triggers (storage disabled in the stack).
Measured 2026-09-21: 82 diff lines / ~25 statements, all of the above.

**Already measured:** 4 of 5 package-dependent test files pass on the rebuild (`organization_purge`, `platform_onboarding_provisioning`,
`website_chat_wc1_entitlement_authority`, `automation_owner_limit_overview`). `package_access.sql` fails on a STALE test: it inserts
`is_unlimited = true` without `limit_state`, violating `organization_limit_overrides_state_value_check`. Fix the test (add `limit_state`), not the schema.

**Still to do:** run ALL 162 files in `supabase/tests/database/` on the rebuild (roadmap names `tenant_isolation`, `quote_proposal_draft_commands`,
`automation_6d2` as the must-pass ones). Sort each failure: stale test (fix the test) vs baseline gap (fix the baseline file, re-prove). A failure that
also fails against live's structure is a test problem; live is the truth. Record pass counts. Do not apply anything to the live database.

**Gate:** diff = only the accepted noise above; tests pass or each remaining failure is recorded as a stale test with a named owner.
