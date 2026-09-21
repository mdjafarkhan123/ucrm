-- Reusable Notes, Tags, Attachments, Property contacts, and Activity interfaces.
-- Shared by Client and Property today. Requests, Quotes, Jobs, and Invoices plug into the same
-- polymorphic tables later by adding an entity_type branch, not new schema.

-- 1. Notes -------------------------------------------------------------------------------------------

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 4000),
  pinned boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  edited_by uuid references auth.users(id) on delete set null,
  edited_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notes_organization_id_id_key unique (organization_id, id)
);

create index notes_organization_pinned_idx
  on public.notes(organization_id, pinned desc, created_at desc);

-- One note can be linked to more than one record (a Request note can also show on the Quote/Job/Invoice
-- it becomes). Only 'client' and 'property' exist as linkable entities today.
create table public.note_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  note_id uuid not null,
  entity_type text not null check (entity_type in ('client', 'property')),
  entity_id uuid not null,
  created_at timestamptz not null default now(),
  constraint note_links_unique unique (note_id, entity_type, entity_id),
  constraint note_links_note_organization_fk foreign key (organization_id, note_id)
    references public.notes(organization_id, id) on delete cascade
);

create index note_links_entity_idx
  on public.note_links(organization_id, entity_type, entity_id, created_at desc);

-- 2. Tags ----------------------------------------------------------------------------------------------

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 40),
  normalized_name text not null generated always as (lower(trim(name))) stored,
  color text check (color is null or color ~ '^#[0-9a-fA-F]{6}$'),
  created_at timestamptz not null default now(),
  constraint tags_organization_id_id_key unique (organization_id, id),
  constraint tags_organization_name_unique unique (organization_id, normalized_name)
);

create table public.tag_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tag_id uuid not null,
  entity_type text not null check (entity_type in ('client', 'property')),
  entity_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint tag_assignments_unique unique (tag_id, entity_type, entity_id),
  constraint tag_assignments_tag_organization_fk foreign key (organization_id, tag_id)
    references public.tags(organization_id, id) on delete cascade
);

create index tag_assignments_entity_idx
  on public.tag_assignments(organization_id, entity_type, entity_id);

-- 3. Attachments -----------------------------------------------------------------------------------------

-- Files live in Cloudflare R2. This row is metadata plus the object key; the server issues short-lived
-- presigned URLs for the actual upload/download, so R2 credentials never reach the browser.
create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null check (entity_type in ('client', 'property')),
  entity_id uuid not null,
  note_id uuid references public.notes(id) on delete set null,
  file_name text not null check (char_length(trim(file_name)) between 1 and 255),
  mime_type text not null check (char_length(trim(mime_type)) between 1 and 127),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 26214400),
  object_key text not null unique,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index attachments_entity_idx
  on public.attachments(organization_id, entity_type, entity_id, created_at desc);

-- 4. Property contacts ------------------------------------------------------------------------------------

-- Same shape as client_contacts / client_contact_methods from Part 2, scoped to a Property instead of a
-- Client (e.g. a tenant at a rental, distinct from the Client who pays).
create table public.property_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null,
  first_name text check (first_name is null or char_length(trim(first_name)) between 1 and 80),
  last_name text check (last_name is null or char_length(trim(last_name)) between 1 and 80),
  role_label text check (role_label is null or char_length(trim(role_label)) between 1 and 80),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint property_contacts_name_present_check
    check (coalesce(trim(first_name), '') <> '' or coalesce(trim(last_name), '') <> ''),
  constraint property_contacts_organization_id_id_key unique (organization_id, id),
  constraint property_contacts_property_organization_fk foreign key (organization_id, property_id)
    references public.properties(organization_id, id) on delete cascade
);

create unique index property_contacts_primary_unique_idx
  on public.property_contacts(property_id)
  where is_primary;

create index property_contacts_organization_property_idx
  on public.property_contacts(organization_id, property_id, created_at);

create table public.property_contact_methods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null,
  property_contact_id uuid,
  kind text not null check (kind in ('email', 'phone')),
  value text not null check (char_length(trim(value)) between 3 and 254),
  normalized_value text not null generated always as (
    case
      when kind = 'email' then lower(trim(value))
      else regexp_replace(value, '[^0-9]', '', 'g')
    end
  ) stored,
  label text check (label is null or char_length(trim(label)) between 1 and 40),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint property_contact_methods_organization_id_id_key unique (organization_id, id),
  constraint property_contact_methods_property_organization_fk foreign key (organization_id, property_id)
    references public.properties(organization_id, id) on delete cascade,
  constraint property_contact_methods_contact_organization_fk
    foreign key (organization_id, property_contact_id)
    references public.property_contacts(organization_id, id) on delete set null
);

create unique index property_contact_methods_primary_unique_idx
  on public.property_contact_methods(property_id, kind)
  where is_primary;

create unique index property_contact_methods_value_unique_idx
  on public.property_contact_methods(property_id, kind, normalized_value);

create index property_contact_methods_lookup_idx
  on public.property_contact_methods(organization_id, kind, normalized_value);

create index property_contact_methods_contact_idx
  on public.property_contact_methods(organization_id, property_contact_id)
  where property_contact_id is not null;

-- 5. Activity events ----------------------------------------------------------------------------------------

-- One row per meaningful event. This is the seam Requests/Quotes/Jobs/Invoices extend later into the full
-- unified timeline; it only records note/tag/attachment/property-contact creation today.
create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null check (entity_type in ('client', 'property')),
  entity_id uuid not null,
  event_type text not null check (char_length(trim(event_type)) between 1 and 60),
  summary text not null check (char_length(trim(summary)) between 1 and 280),
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index activity_events_entity_idx
  on public.activity_events(organization_id, entity_type, entity_id, created_at desc);

-- 6. Updated-at triggers --------------------------------------------------------------------------------------

create trigger notes_set_updated_at
before update on public.notes
for each row execute function public.set_updated_at();

create trigger property_contacts_set_updated_at
before update on public.property_contacts
for each row execute function public.set_updated_at();

create trigger property_contact_methods_set_updated_at
before update on public.property_contact_methods
for each row execute function public.set_updated_at();

-- 7. Linked-entity integrity ------------------------------------------------------------------------------------

-- A plain foreign key cannot follow a polymorphic entity_type, so this checks existence-in-organization
-- directly. Extend the case list here when Requests/Quotes/Jobs/Invoices become linkable.
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
    else false
  end;
$$;

revoke all on function private.linked_entity_exists(uuid, text, uuid) from public;
grant execute on function private.linked_entity_exists(uuid, text, uuid) to authenticated;

create or replace function private.validate_linked_entity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.linked_entity_exists(new.organization_id, new.entity_type, new.entity_id) then
    raise exception 'The linked % was not found in this organization.', new.entity_type
      using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger note_links_validate_entity
before insert or update of entity_type, entity_id, organization_id on public.note_links
for each row execute function private.validate_linked_entity();

create trigger tag_assignments_validate_entity
before insert or update of entity_type, entity_id, organization_id on public.tag_assignments
for each row execute function private.validate_linked_entity();

create trigger attachments_validate_entity
before insert or update of entity_type, entity_id, organization_id on public.attachments
for each row execute function private.validate_linked_entity();

-- 8. Visibility and management dispatchers -------------------------------------------------------------------

-- A Property's visibility follows its owning Client. No separate property-level view permission exists.
create or replace function private.can_view_property(
  target_organization_id uuid,
  target_property_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_view_client(target_organization_id, owning.client_id)
  from public.properties as owning
  where owning.id = target_property_id
    and owning.organization_id = target_organization_id;
$$;

-- One seam every future linkable entity extends: add a branch here and in can_manage_linked_entity below.
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
      else false
    end,
    false
  );
$$;

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
      else false
    end;
$$;

revoke all on function private.can_view_property(uuid, uuid) from public;
revoke all on function private.can_view_linked_entity(uuid, text, uuid) from public;
revoke all on function private.can_manage_linked_entity(uuid, text, uuid) from public;
grant execute on function private.can_view_property(uuid, uuid) to authenticated;
grant execute on function private.can_view_linked_entity(uuid, text, uuid) to authenticated;
grant execute on function private.can_manage_linked_entity(uuid, text, uuid) to authenticated;

-- 9. Activity logging triggers --------------------------------------------------------------------------------

create or replace function private.log_note_link_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.activity_events
    (organization_id, entity_type, entity_id, event_type, summary, actor_user_id)
  values
    (new.organization_id, new.entity_type, new.entity_id, 'note_added', 'A note was added.',
     (select auth.uid()));
  return new;
end;
$$;

create trigger note_links_log_activity
after insert on public.note_links
for each row execute function private.log_note_link_activity();

create or replace function private.log_tag_assignment_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  tag_name text;
begin
  select name into tag_name from public.tags where id = new.tag_id;

  insert into public.activity_events
    (organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata)
  values
    (new.organization_id, new.entity_type, new.entity_id, 'tag_assigned',
     'Tagged "' || coalesce(tag_name, '') || '".', (select auth.uid()),
     jsonb_build_object('tag_id', new.tag_id));
  return new;
end;
$$;

create trigger tag_assignments_log_activity
after insert on public.tag_assignments
for each row execute function private.log_tag_assignment_activity();

create or replace function private.log_attachment_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.activity_events
    (organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata)
  values
    (new.organization_id, new.entity_type, new.entity_id, 'attachment_added',
     'Attached "' || new.file_name || '".', (select auth.uid()),
     jsonb_build_object('attachment_id', new.id));
  return new;
end;
$$;

create trigger attachments_log_activity
after insert on public.attachments
for each row execute function private.log_attachment_activity();

create or replace function private.log_property_contact_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.activity_events
    (organization_id, entity_type, entity_id, event_type, summary, actor_user_id)
  values
    (new.organization_id, 'property', new.property_id, 'property_contact_added',
     'A property contact was added.', (select auth.uid()));
  return new;
end;
$$;

create trigger property_contacts_log_activity
after insert on public.property_contacts
for each row execute function private.log_property_contact_activity();

-- 10. Row level security --------------------------------------------------------------------------------------

alter table public.notes enable row level security;
alter table public.note_links enable row level security;
alter table public.tags enable row level security;
alter table public.tag_assignments enable row level security;
alter table public.attachments enable row level security;
alter table public.property_contacts enable row level security;
alter table public.property_contact_methods enable row level security;
alter table public.activity_events enable row level security;

create policy "permitted members can view notes"
on public.notes for select to authenticated
using (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
  )
);

create policy "permitted members can create notes"
on public.notes for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "permitted members can update notes"
on public.notes for update to authenticated
using (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_manage_linked_entity(link.organization_id, link.entity_type, link.entity_id)
  )
)
with check (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_manage_linked_entity(link.organization_id, link.entity_type, link.entity_id)
  )
);

create policy "permitted members can delete notes"
on public.notes for delete to authenticated
using (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_manage_linked_entity(link.organization_id, link.entity_type, link.entity_id)
  )
);

create policy "permitted members can view note links"
on public.note_links for select to authenticated
using (private.can_view_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can create note links"
on public.note_links for insert to authenticated
with check (private.can_manage_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can delete note links"
on public.note_links for delete to authenticated
using (private.can_manage_linked_entity(organization_id, entity_type, entity_id));

create policy "members can view tags"
on public.tags for select to authenticated
using (private.is_organization_member(organization_id));

create policy "permitted members can create tags"
on public.tags for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'customers.edit')
);

create policy "permitted members can view tag assignments"
on public.tag_assignments for select to authenticated
using (private.can_view_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can create tag assignments"
on public.tag_assignments for insert to authenticated
with check (private.can_manage_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can delete tag assignments"
on public.tag_assignments for delete to authenticated
using (private.can_manage_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can view attachments"
on public.attachments for select to authenticated
using (private.can_view_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can create attachments"
on public.attachments for insert to authenticated
with check (private.can_manage_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can delete attachments"
on public.attachments for delete to authenticated
using (private.can_manage_linked_entity(organization_id, entity_type, entity_id));

create policy "permitted members can view property contacts"
on public.property_contacts for select to authenticated
using (private.can_view_property(organization_id, property_id));

create policy "permitted members can create property contacts"
on public.property_contacts for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'property.manage')
);

create policy "permitted members can update property contacts"
on public.property_contacts for update to authenticated
using (
  private.can_view_property(organization_id, property_id)
  and private.has_permission(organization_id, 'property.manage')
)
with check (
  private.can_view_property(organization_id, property_id)
  and private.has_permission(organization_id, 'property.manage')
);

create policy "permitted members can delete property contacts"
on public.property_contacts for delete to authenticated
using (
  private.can_view_property(organization_id, property_id)
  and private.has_permission(organization_id, 'property.manage')
);

create policy "permitted members can view property contact methods"
on public.property_contact_methods for select to authenticated
using (private.can_view_property(organization_id, property_id));

create policy "permitted members can create property contact methods"
on public.property_contact_methods for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'property.manage')
);

create policy "permitted members can update property contact methods"
on public.property_contact_methods for update to authenticated
using (
  private.can_view_property(organization_id, property_id)
  and private.has_permission(organization_id, 'property.manage')
)
with check (
  private.can_view_property(organization_id, property_id)
  and private.has_permission(organization_id, 'property.manage')
);

create policy "permitted members can delete property contact methods"
on public.property_contact_methods for delete to authenticated
using (
  private.can_view_property(organization_id, property_id)
  and private.has_permission(organization_id, 'property.manage')
);

-- Activity events are written only by the security-definer triggers above (which run as the table owner
-- and bypass RLS). No insert/update/delete policy exists for authenticated, so the API cannot write here
-- directly even by mistake.
create policy "permitted members can view activity events"
on public.activity_events for select to authenticated
using (private.can_view_linked_entity(organization_id, entity_type, entity_id));

grant select, insert, update, delete on public.notes, public.note_links to authenticated;
grant select, insert on public.tags to authenticated;
grant select, insert, delete on public.tag_assignments to authenticated;
grant select, insert, delete on public.attachments to authenticated;
grant select, insert, update, delete on public.property_contacts, public.property_contact_methods
  to authenticated;
grant select on public.activity_events to authenticated;

-- 11. Retire the flat clients.notes column in favour of the new notes table -------------------------------------

do $$
declare
  client_row record;
  new_note_id uuid;
begin
  for client_row in
    select id, organization_id, notes
    from public.clients
    where notes is not null and trim(notes) <> ''
  loop
    insert into public.notes (organization_id, body)
    values (client_row.organization_id, trim(client_row.notes))
    returning id into new_note_id;

    insert into public.note_links (organization_id, note_id, entity_type, entity_id)
    values (client_row.organization_id, new_note_id, 'client', client_row.id);
  end loop;
end;
$$;

alter table public.clients drop column notes;

-- 12. create_client: initial note joins the same atomic write as the client and first property ------------------

create or replace function public.create_client(payload jsonb)
returns public.clients
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  created_client public.clients;
  new_property_id uuid;
  new_note_id uuid;
  email_value text := nullif(trim(payload->>'email'), '');
  phone_value text := nullif(trim(payload->>'phone'), '');
  property_payload jsonb := payload->'property';
  initial_note_value text := nullif(trim(payload->>'initial_note'), '');
begin
  insert into public.clients (
    organization_id,
    display_name,
    client_type,
    first_name,
    last_name,
    company_name,
    lifecycle_status,
    lead_source,
    lead_temperature,
    owner_user_id,
    next_follow_up_at
  )
  values (
    (payload->>'organization_id')::uuid,
    payload->>'display_name',
    coalesce(nullif(payload->>'client_type', ''), 'person'),
    nullif(trim(payload->>'first_name'), ''),
    nullif(trim(payload->>'last_name'), ''),
    nullif(trim(payload->>'company_name'), ''),
    coalesce(nullif(payload->>'lifecycle_status', ''), 'lead'),
    nullif(trim(payload->>'lead_source'), ''),
    nullif(payload->>'lead_temperature', ''),
    nullif(payload->>'owner_user_id', '')::uuid,
    nullif(payload->>'next_follow_up_at', '')::timestamptz
  )
  returning * into created_client;

  if email_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'email', email_value, true);
  end if;

  if phone_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'phone', phone_value, true);
  end if;

  if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
    insert into public.properties (
      organization_id,
      client_id,
      label,
      address_line1,
      address_line2,
      city,
      state_region,
      postal_code,
      country,
      access_notes,
      is_billing_address
    )
    values (
      created_client.organization_id,
      created_client.id,
      coalesce(nullif(trim(property_payload->>'label'), ''), 'Primary property'),
      property_payload->>'address_line1',
      nullif(trim(property_payload->>'address_line2'), ''),
      property_payload->>'city',
      nullif(trim(property_payload->>'state_region'), ''),
      nullif(trim(property_payload->>'postal_code'), ''),
      coalesce(nullif(property_payload->>'country', ''), 'US'),
      nullif(trim(property_payload->>'access_notes'), ''),
      coalesce((property_payload->>'is_billing_address')::boolean, false)
    )
    returning id into new_property_id;
  end if;

  if initial_note_value is not null then
    insert into public.notes (organization_id, body, created_by)
    values (created_client.organization_id, initial_note_value, (select auth.uid()))
    returning id into new_note_id;

    insert into public.note_links (organization_id, note_id, entity_type, entity_id)
    values (created_client.organization_id, new_note_id, 'client', created_client.id);
  end if;

  return created_client;
end;
$$;

revoke all on function public.create_client(jsonb) from public;
grant execute on function public.create_client(jsonb) to authenticated;
