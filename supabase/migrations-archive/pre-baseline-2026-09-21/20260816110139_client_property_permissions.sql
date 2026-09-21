-- Client and Property permissions.
-- Seeds the approved role-by-permission matrix and moves client visibility behind it. Field workers get
-- no blanket client access; they will reach clients only through their assigned work once Jobs and Visits
-- exist. The assigned-work seam is created here so that later work extends one function instead of
-- rewriting every policy.

-- 1. Permission catalog -----------------------------------------------------------------------------

insert into public.permissions (key, description)
values
  ('customers.view', 'See clients and their properties'),
  ('customers.create', 'Add a new client'),
  ('customers.edit', 'Change client details, contacts, and communication preferences'),
  ('property.manage', 'Add, edit, and archive a property'),
  ('customers.archive', 'Archive and restore a client'),
  ('customers.delete', 'Move a client to Recently Deleted'),
  ('customers.merge', 'Merge two clients into one'),
  ('customers.import_export', 'Bulk import and export client lists'),
  ('customers.view_financials', 'See client lifetime revenue and balance'),
  ('team.manage', 'Manage team members and their roles')
on conflict (key) do update set description = excluded.description;

-- 2. Approved role defaults --------------------------------------------------------------------------

-- Field is intentionally absent from every row. A crew member reaches a client through assigned work,
-- never through the client list.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'customers.view'),
  ('owner', 'customers.create'),
  ('owner', 'customers.edit'),
  ('owner', 'property.manage'),
  ('owner', 'customers.archive'),
  ('owner', 'customers.delete'),
  ('owner', 'customers.merge'),
  ('owner', 'customers.import_export'),
  ('owner', 'customers.view_financials'),
  ('owner', 'team.manage'),

  ('admin', 'customers.view'),
  ('admin', 'customers.create'),
  ('admin', 'customers.edit'),
  ('admin', 'property.manage'),
  ('admin', 'customers.archive'),
  ('admin', 'customers.delete'),
  ('admin', 'customers.merge'),
  ('admin', 'customers.import_export'),
  ('admin', 'customers.view_financials'),
  ('admin', 'team.manage'),

  ('office', 'customers.view'),
  ('office', 'customers.create'),
  ('office', 'customers.edit'),
  ('office', 'property.manage'),
  ('office', 'customers.archive'),
  ('office', 'customers.view_financials'),

  ('sales', 'customers.view'),
  ('sales', 'customers.create'),
  ('sales', 'customers.edit'),
  ('sales', 'property.manage'),

  ('finance', 'customers.view'),
  ('finance', 'customers.view_financials')
on conflict (role, permission_key) do nothing;

-- 3. Permission and assigned-work helpers --------------------------------------------------------------

-- Resolves one permission for the calling member: the role default, overridden per member when an
-- override exists. Package feature entitlement is deliberately not applied here. Entitlement is a
-- commercial gate enforced in the server layer; this function is the security boundary.
create or replace function private.has_permission(
  target_organization_id uuid,
  target_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (
      select override.override_state = 'grant'
      from public.organization_member_permission_overrides as override
      where override.organization_id = target_organization_id
        and override.user_id = (select auth.uid())
        and override.permission_key = target_permission_key
    ),
    exists (
      select 1
      from public.organization_members as membership
      join public.role_permissions as role_permission
        on role_permission.role = membership.role
      where membership.organization_id = target_organization_id
        and membership.user_id = (select auth.uid())
        and role_permission.permission_key = target_permission_key
    )
  );
$$;

-- The assigned-work seam. Jobs, Visits, and assignments do not exist yet, so this grants nothing today.
-- When scheduling lands, extend only this function so a field worker can reach the clients and
-- properties attached to their own assigned work without gaining the client list.
create or replace function private.client_is_assigned_to_current_user(
  target_organization_id uuid,
  target_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select false;
$$;

-- One place that decides whether the caller may see a client and everything hanging off it.
create or replace function private.can_view_client(
  target_organization_id uuid,
  target_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.is_organization_member(target_organization_id)
    and (
      private.has_permission(target_organization_id, 'customers.view')
      or private.client_is_assigned_to_current_user(target_organization_id, target_client_id)
    );
$$;

revoke all on function private.has_permission(uuid, text) from public;
revoke all on function private.client_is_assigned_to_current_user(uuid, uuid) from public;
revoke all on function private.can_view_client(uuid, uuid) from public;
grant execute on function private.has_permission(uuid, text) to authenticated;
grant execute on function private.client_is_assigned_to_current_user(uuid, uuid) to authenticated;
grant execute on function private.can_view_client(uuid, uuid) to authenticated;

-- 4. Permission-aware policies --------------------------------------------------------------------------

drop policy "members can view clients" on public.clients;
drop policy "members can create clients" on public.clients;
drop policy "members can update clients" on public.clients;

create policy "permitted members can view clients"
on public.clients for select to authenticated
using (private.can_view_client(organization_id, id));

create policy "permitted members can create clients"
on public.clients for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'customers.create')
);

create policy "permitted members can update clients"
on public.clients for update to authenticated
using (
  private.can_view_client(organization_id, id)
  and private.has_permission(organization_id, 'customers.edit')
)
with check (
  private.can_view_client(organization_id, id)
  and private.has_permission(organization_id, 'customers.edit')
);

drop policy "members can view properties" on public.properties;
drop policy "members can create properties" on public.properties;
drop policy "members can update properties" on public.properties;

create policy "permitted members can view properties"
on public.properties for select to authenticated
using (private.can_view_client(organization_id, client_id));

create policy "permitted members can create properties"
on public.properties for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'property.manage')
);

create policy "permitted members can update properties"
on public.properties for update to authenticated
using (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'property.manage')
)
with check (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'property.manage')
);

drop policy "members can view client contacts" on public.client_contacts;
drop policy "members can create client contacts" on public.client_contacts;
drop policy "members can update client contacts" on public.client_contacts;
drop policy "members can delete client contacts" on public.client_contacts;

create policy "permitted members can view client contacts"
on public.client_contacts for select to authenticated
using (private.can_view_client(organization_id, client_id));

create policy "permitted members can create client contacts"
on public.client_contacts for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'customers.edit')
);

create policy "permitted members can update client contacts"
on public.client_contacts for update to authenticated
using (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
)
with check (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
);

create policy "permitted members can delete client contacts"
on public.client_contacts for delete to authenticated
using (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
);

drop policy "members can view client contact methods" on public.client_contact_methods;
drop policy "members can create client contact methods" on public.client_contact_methods;
drop policy "members can update client contact methods" on public.client_contact_methods;
drop policy "members can delete client contact methods" on public.client_contact_methods;

create policy "permitted members can view client contact methods"
on public.client_contact_methods for select to authenticated
using (private.can_view_client(organization_id, client_id));

create policy "permitted members can create client contact methods"
on public.client_contact_methods for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'customers.edit')
);

create policy "permitted members can update client contact methods"
on public.client_contact_methods for update to authenticated
using (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
)
with check (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
);

create policy "permitted members can delete client contact methods"
on public.client_contact_methods for delete to authenticated
using (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
);

drop policy "members can view client communication preferences" on public.client_communication_preferences;
drop policy "members can update client communication preferences" on public.client_communication_preferences;

create policy "permitted members can view client communication preferences"
on public.client_communication_preferences for select to authenticated
using (private.can_view_client(organization_id, client_id));

create policy "permitted members can update client communication preferences"
on public.client_communication_preferences for update to authenticated
using (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
)
with check (
  private.can_view_client(organization_id, client_id)
  and private.has_permission(organization_id, 'customers.edit')
);
