# Part 2 — Build the baseline (packet)

Inventory done 2026-09-21 (read-only against the remote). What `supabase db dump --linked` (3.4 MB: 231 tables, 801 functions,
161 policies, 8 `create extension` lines, schema `private`) does NOT capture, and how the baseline carries each:

**1. Reference rows (20 tables, each seeded by an old migration).** Carry live rows as `insert ... on conflict do nothing`, never tenant data:
`permissions`(72) `role_permissions`(226) `features`(19) `package_features`(37) `package_limits`(3) `platform_packages`(3)
`platform_package_versions`(8) `platform_package_version_features`(98) `platform_package_version_limits`(27)
`platform_message_templates`(8) `platform_message_template_versions`(9) `member_access_event_shapes`(18)
`communication_email_warmup_stages`(5) `communication_email_reputation_thresholds`(9) `communication_sms_retail_rates`(2)
`communication_email_platform_sending_settings`(5) `marketing_platform_templates`(4) `platform_owner_settings`(1)
`communication_sms_compliance_settings`(1) `communication_sms_quiet_hours_policy`(1). Runtime-only tables (wake ledgers, rate-limit buckets,
audit/event tables) are not reference data.
**Review before carrying:** live values Jafar edited in the owner console (packages, templates, rates, owner settings) and any column holding an
environment-specific value or secret (`platform_owner_settings`, `communication_email_platform_sending_settings`). Leave those out or blank.

**2. Objects outside the dump's schemas.** Trigger `on_auth_user_created_create_profile` on `auth.users`; policies `website_chat_staff_channel_read`
and `website_chat_visitor_channel_read` on `realtime.messages`. (Storage buckets/policies and Realtime publication tables: none exist.)

**3. 15 `pg_cron` jobs** (read exact `command` and `active` from `cron.job`; four commands are inline `net.http_post` reading Vault). Recommended
default: the baseline installs every job **off** until its Vault URL+secret exist, so no environment inherits a live sweep by accident;
activation is deployment config. Live today: 12 active, 3 SMS jobs inactive. Extensions live: btree_gist, pg_cron, pg_net, pg_stat_statements,
pgcrypto, pgtap, supabase_vault, uuid-ossp (the dump already emits these).

**4. Vault secrets (20 names, values per environment).** Baseline creates the same placeholder names the old migrations created; never values.

**5. Unapplied-work check (must run before old files leave the folder).** Replay the old files in a throwaway container (rename the duplicate
`20260916110000_financial_uninvoiced_work_reader.sql` to `...110001` in the copy only), diff against live. Anything in the repo but not live is
work that was never applied: list it for Jafar, do not silently drop it. 1 repo file has no same-named remote row:
`20260905130000_invoice_source_claims_and_chains`.

**Acceptance for Part 2:** baseline migration file + reference-row seed + cron/auth/realtime objects committed; old files removed from
`supabase/migrations/` (keep `_deferred/` as is); drift report in hand; nothing applied to the live database.
**Do not:** run `migration repair` or write to the remote ledger (Part 4).
