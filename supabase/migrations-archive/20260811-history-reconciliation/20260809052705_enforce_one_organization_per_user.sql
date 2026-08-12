-- A contractor Auth user belongs to exactly one organization.
-- The duplicate check was run before this migration; no conflicting rows exist.
drop index if exists public.organization_members_user_id_idx;

alter table public.organization_members
  add constraint organization_members_user_id_key unique (user_id);
