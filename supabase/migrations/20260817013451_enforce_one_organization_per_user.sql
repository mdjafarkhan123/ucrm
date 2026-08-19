-- A contractor Auth user belongs to exactly one organization.
--
-- This rule existed before the 2026-08-11 history reconciliation
-- (`migrations-archive/20260811-history-reconciliation/20260809052705_enforce_one_organization_per_user.sql`)
-- and was lost when that history was rewritten. Restoring it: the composite primary key
-- (organization_id, user_id) on its own still allows one Auth user to join two organizations.
--
-- Verified before applying: no user_id currently appears in more than one organization, so the
-- constraint validates without any data cleanup.
--
-- The plain user_id index is redundant once the unique constraint exists, since the unique index
-- it creates serves the same lookups.
drop index if exists public.organization_members_user_id_idx;

alter table public.organization_members
  add constraint organization_members_user_id_key unique (user_id);
