-- Contractor employee roles and per-member permission overrides.
-- The role catalog is product-controlled; contractor administrators can only
-- change a member's assigned role or override an existing permission.

insert into public.permissions (key, description)
values
  ('customer.view', 'View customers'),
  ('customer.edit', 'Create and edit customers'),
  ('property.view', 'View properties'),
  ('property.edit', 'Create and edit properties'),
  ('request.view', 'View requests'),
  ('request.create', 'Create requests'),
  ('request.edit', 'Edit requests'),
  ('pipeline.view', 'View the sales pipeline'),
  ('pipeline.edit', 'Manage the sales pipeline'),
  ('quote.view', 'View quotes'),
  ('quote.create', 'Create quotes'),
  ('quote.edit', 'Edit quotes'),
  ('quote.send', 'Send quotes'),
  ('job.view', 'View jobs'),
  ('job.create', 'Create jobs'),
  ('job.edit', 'Edit jobs'),
  ('schedule.view', 'View the schedule'),
  ('schedule.manage', 'Manage the schedule'),
  ('invoice.view', 'View invoices'),
  ('invoice.create', 'Create invoices'),
  ('invoice.send', 'Send invoices'),
  ('payment.view', 'View payments'),
  ('payment.record', 'Record payments'),
  ('inbox.view', 'View the unified inbox'),
  ('inbox.respond', 'Respond in the unified inbox'),
  ('portal.manage', 'Manage the client portal'),
  ('automation.manage', 'Manage workflow automations'),
  ('report.view', 'View reports'),
  ('team.view', 'View team members'),
  ('team.manage', 'Manage team members and permissions'),
  ('settings.manage', 'Manage organization settings')
on conflict (key) do nothing;

-- Owners and admins start with every permission. Individual employee roles
-- receive the least privilege defaults approved in the product matrix.
insert into public.role_permissions (role, permission_key)
select role_name, permission_row.key
from (values ('owner'::text), ('admin'::text)) as roles(role_name)
cross join public.permissions as permission_row
on conflict (role, permission_key) do nothing;

insert into public.role_permissions (role, permission_key)
values
  ('office', 'customer.view'),
  ('office', 'customer.edit'),
  ('office', 'property.view'),
  ('office', 'property.edit'),
  ('office', 'request.view'),
  ('office', 'request.create'),
  ('office', 'request.edit'),
  ('office', 'quote.view'),
  ('office', 'quote.create'),
  ('office', 'quote.edit'),
  ('office', 'quote.send'),
  ('office', 'job.view'),
  ('office', 'job.create'),
  ('office', 'job.edit'),
  ('office', 'schedule.view'),
  ('office', 'schedule.manage'),
  ('office', 'invoice.view'),
  ('office', 'invoice.create'),
  ('office', 'invoice.send'),
  ('office', 'inbox.view'),
  ('office', 'inbox.respond'),
  ('office', 'report.view'),
  ('sales', 'customer.view'),
  ('sales', 'customer.edit'),
  ('sales', 'property.view'),
  ('sales', 'property.edit'),
  ('sales', 'request.view'),
  ('sales', 'request.create'),
  ('sales', 'request.edit'),
  ('sales', 'pipeline.view'),
  ('sales', 'pipeline.edit'),
  ('sales', 'quote.view'),
  ('sales', 'quote.create'),
  ('sales', 'quote.edit'),
  ('sales', 'quote.send'),
  ('sales', 'inbox.view'),
  ('sales', 'inbox.respond'),
  ('sales', 'report.view'),
  ('field', 'customer.view'),
  ('field', 'property.view'),
  ('field', 'request.view'),
  ('field', 'job.view'),
  ('field', 'schedule.view'),
  ('finance', 'customer.view'),
  ('finance', 'property.view'),
  ('finance', 'quote.view'),
  ('finance', 'invoice.view'),
  ('finance', 'invoice.create'),
  ('finance', 'invoice.send'),
  ('finance', 'payment.view'),
  ('finance', 'payment.record'),
  ('finance', 'report.view')
on conflict (role, permission_key) do nothing;

-- Role updates are allowed only through an organization-admin RLS policy below.
-- These triggers make the invariant hold even if another caller races the API.
create or replace function private.prevent_unsafe_organization_member_change()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' then
    if old.role in ('owner', 'admin') and not exists (
      select 1
      from public.organization_members as other_member
      where other_member.organization_id = old.organization_id
        and other_member.user_id <> old.user_id
        and other_member.role in ('owner', 'admin')
    ) then
      raise exception 'The organization must retain at least one owner or admin.' using errcode = 'check_violation';
    end if;
    return old;
  end if;

  if new.organization_id <> old.organization_id or new.user_id <> old.user_id then
    raise exception 'Organization membership identity cannot be changed.' using errcode = 'check_violation';
  end if;

  if old.role in ('owner', 'admin') and new.role not in ('owner', 'admin') then
    if not exists (
      select 1
      from public.organization_members as other_member
      where other_member.organization_id = old.organization_id
        and other_member.user_id <> old.user_id
        and other_member.role in ('owner', 'admin')
    ) then
      raise exception 'The organization must retain at least one owner or admin.' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists organization_members_prevent_unsafe_change on public.organization_members;
create trigger organization_members_prevent_unsafe_change
before update or delete on public.organization_members
for each row execute function private.prevent_unsafe_organization_member_change();

create or replace function private.audit_contractor_member_role_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.role is distinct from new.role then
    if auth.uid() is null then
      raise exception 'An authenticated contractor user is required.' using errcode = 'insufficient_privilege';
    end if;
    insert into public.access_audit_events (
      organization_id, actor_kind, actor_user_id, event_type, target_type,
      target_key, before_state, after_state
    )
    values (
      new.organization_id, 'contractor_user', auth.uid(), 'employee_role_changed',
      new.user_id::text, jsonb_build_object('role', old.role),
      jsonb_build_object('role', new.role)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists organization_members_audit_role_change on public.organization_members;
create trigger organization_members_audit_role_change
after update on public.organization_members
for each row execute function private.audit_contractor_member_role_change();

create or replace function private.audit_contractor_permission_override_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid;
  target_user_id uuid;
  target_permission_key text;
begin
  if auth.uid() is null then
    raise exception 'An authenticated contractor user is required.' using errcode = 'insufficient_privilege';
  end if;

  if tg_op = 'DELETE' then
    target_organization_id := old.organization_id;
    target_user_id := old.user_id;
    target_permission_key := old.permission_key;
  else
    target_organization_id := new.organization_id;
    target_user_id := new.user_id;
    target_permission_key := new.permission_key;
  end if;
  insert into public.access_audit_events (
    organization_id, actor_kind, actor_user_id, event_type, target_type,
    target_key, before_state, after_state
  )
  values (
    target_organization_id, 'contractor_user', auth.uid(),
    'employee_permission_override_changed', 'employee_permission',
    target_user_id::text || ':' || target_permission_key,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists organization_member_permission_overrides_audit_change
  on public.organization_member_permission_overrides;
create trigger organization_member_permission_overrides_audit_change
after insert or update or delete on public.organization_member_permission_overrides
for each row execute function private.audit_contractor_permission_override_change();

create policy "organization admins can update member roles"
on public.organization_members for update to authenticated
using (private.is_organization_admin(organization_id))
with check (private.is_organization_admin(organization_id));

grant update on public.organization_members to authenticated;

revoke all on function private.prevent_unsafe_organization_member_change() from public;
revoke all on function private.audit_contractor_member_role_change() from public;
revoke all on function private.audit_contractor_permission_override_change() from public;
