# 38 pgTAP files fail on a rebuild because they no longer match live

- **Priority:** P2
- **Found:** 2026-09-21 (migration-baseline Part 3). Rebuild == live for structure and permissions, so each failure is a stale test or a
  live-behavior question, never a baseline gap. 124 of 162 files pass (4,747 assertions). To regenerate: copy `supabase/` to a scratch dir, set
  `project_id`, `[db] port/shadow_port` (not 54322), `major_version = 17`, enable `[api] [auth] [realtime]`, `supabase start`, replace every
  `REPLACE_ME…` Vault value with a fake `http://127.0.0.1:9/x` (pg_net raises on non-URLs), then `supabase test db`.
- **Stale, cause known:** `owner_organization_directory`, `organization_free_access_scheduling_and_lifecycle_control`,
  `organization_legacy_pending_setup_reconciliation` (one org per user, one owner per org); `quote_*` (send now needs a tax answer; tests set
  tax fields without `tax_source`); `package_access` (members and overrides are now written through the API, not the table);
  `communications_conversation_reply_command`, `communications_outbound_attachments` (function gained parameters, service-role only);
  `team_function_grant_matrix`, `team_member_access_events`, `team_invitation_service_role_primitives` (function count, vocabulary 18 vs 16, seat counts).
- **First error seen, cause not yet checked:** the four job/invoice files ("You do not have access to this job"), `jobs_identity_lifecycle_foundation`,
  `invoices_refunds_and_closure` (credit 25,000 vs 40,000: money, check first), `client_create_edit` (no `marketing` column), `jobs_list_read_model`
  (missing function), `website_chat_wc2/wc3` (missing function / column), `versioned_package_compatibility` (Growth price NULL), and about ten more.
- **Already fixed 2026-09-21:** stale-edit code `P0409`, temp-table result capture (11 files), generated `normalized_value`, `limit_state`.
- **Reactivation trigger:** before the self-hosted rehearsal relies on `supabase test db`, or when Jafar asks. Treat "money" and "job access" first.
