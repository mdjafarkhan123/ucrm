-- Requests become linkable: notes, tags, attachments, and activity events may now point at a request,
-- the way Jobber puts a Notes card on the request page.
--
-- This is the extension the original polymorphic seam in 20260816130000 was written for. Nothing about
-- clients or properties changes. Every existing row already satisfies the wider list, so each constraint
-- is replaced NOT VALID and validated afterwards — the validation pass takes a lock that still lets
-- reads and writes through, instead of holding the table while it rescans.

-- 1. Widen the four entity_type lists -----------------------------------------------------------------

alter table public.note_links drop constraint note_links_entity_type_check;
alter table public.note_links add constraint note_links_entity_type_check
  check (entity_type in ('client', 'property', 'request')) not valid;
alter table public.note_links validate constraint note_links_entity_type_check;

alter table public.tag_assignments drop constraint tag_assignments_entity_type_check;
alter table public.tag_assignments add constraint tag_assignments_entity_type_check
  check (entity_type in ('client', 'property', 'request')) not valid;
alter table public.tag_assignments validate constraint tag_assignments_entity_type_check;

alter table public.attachments drop constraint attachments_entity_type_check;
alter table public.attachments add constraint attachments_entity_type_check
  check (entity_type in ('client', 'property', 'request')) not valid;
alter table public.attachments validate constraint attachments_entity_type_check;

alter table public.activity_events drop constraint activity_events_entity_type_check;
alter table public.activity_events add constraint activity_events_entity_type_check
  check (entity_type in ('client', 'property', 'request')) not valid;
alter table public.activity_events validate constraint activity_events_entity_type_check;

-- 2. Who may reach a request --------------------------------------------------------------------------

-- One place that decides it, mirroring can_view_client and can_view_property. Requests carry no
-- permission keys of their own yet, so this repeats exactly what the requests table's own RLS policy
-- says: any member of the organization. When request permissions land, only this function changes.
create or replace function private.can_view_request(
  target_organization_id uuid,
  target_request_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.is_organization_member(owning.organization_id)
  from public.requests as owning
  where owning.id = target_request_id
    and owning.organization_id = target_organization_id;
$$;

revoke all on function private.can_view_request(uuid, uuid) from public;
grant execute on function private.can_view_request(uuid, uuid) to authenticated;

-- 3. Teach the three linked-entity helpers about requests ---------------------------------------------

create or replace function private.linked_entity_exists(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then exists (
      select 1 from public.clients
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'property' then exists (
      select 1 from public.properties
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'request' then exists (
      select 1 from public.requests
      where id = target_entity_id and organization_id = target_organization_id
    )
    else false
  end;
$$;

create or replace function private.can_view_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    case target_entity_type
      when 'client' then private.can_view_client(target_organization_id, target_entity_id)
      when 'property' then private.can_view_property(target_organization_id, target_entity_id)
      when 'request' then private.can_view_request(target_organization_id, target_entity_id)
      else false
    end,
    false
  );
$$;

-- Editing a request's notes follows editing the request itself, which today is any member.
create or replace function private.can_manage_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_view_linked_entity(target_organization_id, target_entity_type, target_entity_id)
    and case target_entity_type
      when 'client' then private.has_permission(target_organization_id, 'customers.edit')
      when 'property' then private.has_permission(target_organization_id, 'property.manage')
      when 'request' then true
      else false
    end;
$$;
