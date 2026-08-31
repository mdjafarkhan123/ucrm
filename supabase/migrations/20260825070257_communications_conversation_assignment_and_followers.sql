-- Part 5B: conversation ownership and followers.
--
-- Conversations are grouped by client_id (see groupMessagesByContact), not a standalone table, so
-- assignment/following key off (organization_id, client_id) the same way read marks already do
-- (20260825121100_communications_conversation_read_marks.sql).
--
-- Absence of an assignment row means Unassigned -- there is no default owner to fall back to. The
-- contract's original "the contact's eligible assigned user is the default conversation owner" assumed
-- clients.owner_user_id, which 20260902140000_remove_client_owner_no_jobber_precedent.sql removed
-- (Jobber has no client-level owner). Jafar confirmed 2026-08-25 that conversations start Unassigned
-- instead.
--
-- Both tables reference organization_members(organization_id, user_id), not auth.users(id), so a former
-- member's assignment/follow row is gone the moment their membership row is (leaving, removal, or any
-- future hard-delete path) -- "missing or inactive owner falls back to Unassigned" per
-- docs/unified-inbox-behavior-contract.md. A merely deactivated member (status <> 'active') keeps their
-- membership row, so member_has_permission already excludes them from eligibility on write, but an
-- existing assignment/follow row is not retroactively cleared -- the read path must treat a
-- currently-ineligible assignee as Unassigned rather than relying on the row being gone.

create table public.communication_conversation_assignments (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  client_id uuid not null,
  assigned_to uuid not null,
  assigned_by uuid references auth.users (id) on delete set null,
  assigned_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, client_id),
  constraint communication_conversation_assignments_client_fk
    foreign key (organization_id, client_id) references public.clients (organization_id, id) on delete cascade,
  constraint communication_conversation_assignments_member_fk
    foreign key (organization_id, assigned_to)
    references public.organization_members (organization_id, user_id) on delete cascade
);

-- Reverse lookup for "conversations assigned to me" (My Inbox); the primary key already covers lookup by
-- client_id.
create index communication_conversation_assignments_assignee_idx
  on public.communication_conversation_assignments (organization_id, assigned_to);

create trigger communication_conversation_assignments_set_updated_at
before update on public.communication_conversation_assignments
for each row execute function public.set_updated_at();

alter table public.communication_conversation_assignments enable row level security;
revoke all on public.communication_conversation_assignments from anon, authenticated;
grant select, insert, update, delete on public.communication_conversation_assignments to service_role;

-- An assignee who cannot see conversations at all would be given work they can never open, so this is
-- checked the same way opportunity ownership is
-- (20260818232309_pipeline_opportunity_ownership_value_dates.sql): member_has_permission already folds
-- in membership.status = 'active', so a deactivated member is rejected here too.
create or replace function private.communication_conversation_assignee_eligible()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not (
    private.member_has_permission(new.organization_id, new.assigned_to, 'conversations.view_team')
    or private.member_has_permission(new.organization_id, new.assigned_to, 'conversations.view_assigned')
  ) then
    raise exception 'That person cannot be assigned conversations.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.communication_conversation_assignee_eligible() from public;
revoke execute on function private.communication_conversation_assignee_eligible() from anon, authenticated;

create trigger communication_conversation_assignments_validate_assignee
before insert or update of assigned_to on public.communication_conversation_assignments
for each row execute function private.communication_conversation_assignee_eligible();

-- Assigning is an administrative action gated by conversations.manage_assignment (already seeded in
-- 20260823080419_communications_email_delivery_foundation.sql, never granted to a role by default).
-- owner/admin get it by default, matching the other administrative conversations permission
-- (conversations.manage_connections, conversations.view_team) -- everyone else needs an explicit
-- per-member override.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'conversations.manage_assignment'),
  ('admin', 'conversations.manage_assignment')
on conflict (role, permission_key) do nothing;

-- Following has no dedicated permission in the contract's capability list -- anyone who can already see a
-- conversation (view_team or view_assigned) may follow or unfollow it for themselves, so there is no
-- separate "who can follow" gate here.
create table public.communication_conversation_followers (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  client_id uuid not null,
  user_id uuid not null,
  followed_at timestamptz not null default now(),
  primary key (organization_id, client_id, user_id),
  constraint communication_conversation_followers_client_fk
    foreign key (organization_id, client_id) references public.clients (organization_id, id) on delete cascade,
  constraint communication_conversation_followers_member_fk
    foreign key (organization_id, user_id)
    references public.organization_members (organization_id, user_id) on delete cascade
);

-- Reverse lookup for "conversations I follow" (My Inbox); the primary key already covers lookup by
-- client_id.
create index communication_conversation_followers_user_idx
  on public.communication_conversation_followers (organization_id, user_id);

alter table public.communication_conversation_followers enable row level security;
revoke all on public.communication_conversation_followers from anon, authenticated;
grant select, insert, delete on public.communication_conversation_followers to service_role;
