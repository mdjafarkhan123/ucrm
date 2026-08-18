-- Client and Property data model.
-- Renames the `contacts` scaffold to `clients`, adds named contacts, contact methods, communication
-- preferences, ownership, and Property structure. Tenant isolation and historical safety are preserved.
-- Permission catalog seeding is deliberately excluded and waits on the approved role matrix.

-- 1. Rename the relationship record ---------------------------------------------------------------

alter table public.contacts rename to clients;

alter table public.clients rename constraint contacts_pkey to clients_pkey;
alter table public.clients rename constraint contacts_organization_id_fkey to clients_organization_id_fkey;
alter table public.clients rename constraint contacts_organization_id_id_key to clients_organization_id_id_key;
alter table public.clients rename constraint contacts_display_name_check to clients_display_name_check;
alter table public.clients rename constraint contacts_lifecycle_status_check to clients_lifecycle_status_check;

alter index public.contacts_organization_updated_idx rename to clients_organization_updated_idx;
alter index public.contacts_organization_status_idx rename to clients_organization_status_idx;

alter trigger contacts_set_updated_at on public.clients rename to clients_set_updated_at;

alter policy "members can view contacts" on public.clients rename to "members can view clients";
alter policy "members can create contacts" on public.clients rename to "members can create clients";
alter policy "members can update contacts" on public.clients rename to "members can update clients";

alter table public.properties rename column contact_id to client_id;
alter table public.properties rename constraint properties_contact_organization_fk to properties_client_organization_fk;
alter table public.properties rename constraint properties_contact_id_fkey to properties_client_id_fkey;
alter index public.properties_contact_label_unique_idx rename to properties_client_label_unique_idx;
alter index public.properties_organization_contact_idx rename to properties_organization_client_idx;

alter table public.requests rename column contact_id to client_id;
alter table public.requests rename constraint requests_contact_organization_fk to requests_client_organization_fk;
alter index public.requests_contact_idx rename to requests_client_idx;

-- 2. Client relationship columns ------------------------------------------------------------------

alter table public.clients rename column source to lead_source;

alter table public.clients
  add column client_type text not null default 'person'
    check (client_type in ('person', 'company')),
  add column lead_temperature text
    check (lead_temperature is null or lead_temperature in ('hot', 'warm', 'cold')),
  add column owner_user_id uuid references auth.users(id) on delete set null,
  add column next_follow_up_at timestamptz,
  add column converted_to_customer_at timestamptz,
  add column archived_at timestamptz,
  add column deleted_at timestamptz;

-- Email and phone move to client_contact_methods so there is one source of truth.
alter table public.clients drop column email;
alter table public.clients drop column phone;

update public.clients
set converted_to_customer_at = coalesce(converted_to_customer_at, updated_at)
where lifecycle_status = 'customer';

alter table public.clients
  add constraint clients_converted_customer_check
    check (lifecycle_status <> 'customer' or converted_to_customer_at is not null);

create index clients_organization_owner_idx
  on public.clients(organization_id, owner_user_id)
  where deleted_at is null;

create index clients_organization_active_idx
  on public.clients(organization_id, updated_at desc)
  where deleted_at is null and archived_at is null;

create index clients_organization_follow_up_idx
  on public.clients(organization_id, next_follow_up_at)
  where deleted_at is null and next_follow_up_at is not null;

-- The Client owner must be a member of the same organization.
create or replace function private.validate_client_owner()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.owner_user_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.organization_members
    where organization_id = new.organization_id
      and user_id = new.owner_user_id
  ) then
    raise exception 'The client owner must belong to the same organization.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger clients_validate_owner
before insert or update of organization_id, owner_user_id on public.clients
for each row execute function private.validate_client_owner();

-- Lead to Customer conversion is durable.
create or replace function private.enforce_client_conversion()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if old.lifecycle_status = 'customer' and new.lifecycle_status <> 'customer' then
    raise exception 'A customer cannot be changed back to a lead.'
      using errcode = '23514';
  end if;

  if new.lifecycle_status = 'customer' and new.converted_to_customer_at is null then
    new.converted_to_customer_at = now();
  end if;

  return new;
end;
$$;

create trigger clients_enforce_conversion
before update of lifecycle_status on public.clients
for each row execute function private.enforce_client_conversion();

create or replace function private.set_client_conversion_on_insert()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.lifecycle_status = 'customer' and new.converted_to_customer_at is null then
    new.converted_to_customer_at = now();
  end if;
  return new;
end;
$$;

create trigger clients_set_conversion_on_insert
before insert on public.clients
for each row execute function private.set_client_conversion_on_insert();

-- 3. Named contacts on a Client ---------------------------------------------------------------------

create table public.client_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  first_name text check (first_name is null or char_length(trim(first_name)) between 1 and 80),
  last_name text check (last_name is null or char_length(trim(last_name)) between 1 and 80),
  role_label text check (role_label is null or char_length(trim(role_label)) between 1 and 80),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_contacts_name_present_check
    check (coalesce(trim(first_name), '') <> '' or coalesce(trim(last_name), '') <> ''),
  constraint client_contacts_organization_id_id_key unique (organization_id, id),
  constraint client_contacts_client_organization_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete cascade
);

create unique index client_contacts_primary_unique_idx
  on public.client_contacts(client_id)
  where is_primary;

create index client_contacts_organization_client_idx
  on public.client_contacts(organization_id, client_id, created_at);

-- 4. Contact methods ---------------------------------------------------------------------------------

create table public.client_contact_methods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  client_contact_id uuid,
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
  constraint client_contact_methods_organization_id_id_key unique (organization_id, id),
  constraint client_contact_methods_client_organization_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete cascade,
  constraint client_contact_methods_contact_organization_fk foreign key (organization_id, client_contact_id)
    references public.client_contacts(organization_id, id) on delete set null
);

-- One primary email and one primary phone per Client.
create unique index client_contact_methods_primary_unique_idx
  on public.client_contact_methods(client_id, kind)
  where is_primary;

-- The same address or number is never stored twice on one Client.
create unique index client_contact_methods_value_unique_idx
  on public.client_contact_methods(client_id, kind, normalized_value);

-- Duplicate detection across the organization.
create index client_contact_methods_lookup_idx
  on public.client_contact_methods(organization_id, kind, normalized_value);

create index client_contact_methods_contact_idx
  on public.client_contact_methods(organization_id, client_contact_id)
  where client_contact_id is not null;

-- 5. Communication preferences -------------------------------------------------------------------------

create table public.client_communication_preferences (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  appointment_reminders boolean not null default true,
  quote_follow_ups boolean not null default true,
  invoice_reminders boolean not null default true,
  job_follow_ups boolean not null default true,
  review_requests boolean not null default true,
  marketing boolean not null default false,
  sms_opt_out_at timestamptz,
  sms_opt_in_at timestamptz,
  opt_out_source text
    constraint client_communication_preferences_opt_out_source_check
    check (opt_out_source is null or opt_out_source in ('client_reply', 'staff', 'import')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, client_id),
  constraint client_communication_preferences_client_organization_fk
    foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete cascade,
  constraint client_communication_preferences_opt_out_reason_check
    check (sms_opt_out_at is null or opt_out_source is not null)
);

-- Every Client always has a preference row, so no outbound check can silently find nothing.
create or replace function private.create_client_communication_preferences()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.client_communication_preferences (organization_id, client_id)
  values (new.organization_id, new.id)
  on conflict do nothing;
  return new;
end;
$$;

create trigger clients_create_communication_preferences
after insert on public.clients
for each row execute function private.create_client_communication_preferences();

insert into public.client_communication_preferences (organization_id, client_id)
select organization_id, id from public.clients
on conflict do nothing;

-- 6. Property structure -------------------------------------------------------------------------------

alter table public.properties
  add column is_primary boolean not null default false,
  add column is_billing_address boolean not null default false,
  add column archived_at timestamptz,
  add column deleted_at timestamptz,
  add column latitude numeric(9, 6) check (latitude is null or latitude between -90 and 90),
  add column longitude numeric(9, 6) check (longitude is null or longitude between -180 and 180),
  add constraint properties_geocode_pair_check
    check ((latitude is null) = (longitude is null));

-- At most one primary Property and one billing Property per Client.
create unique index properties_primary_unique_idx
  on public.properties(client_id)
  where is_primary;

create unique index properties_billing_unique_idx
  on public.properties(client_id)
  where is_billing_address;

create index properties_organization_active_idx
  on public.properties(organization_id, client_id, created_at)
  where deleted_at is null;

-- The first active Property a Client gets becomes its primary Property automatically.
create or replace function private.set_first_property_primary()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.deleted_at is null and not new.is_primary then
    if not exists (
      select 1
      from public.properties
      where client_id = new.client_id
        and deleted_at is null
        and id <> new.id
    ) then
      new.is_primary = true;
    end if;
  end if;

  if new.deleted_at is not null and new.is_primary then
    new.is_primary = false;
  end if;

  return new;
end;
$$;

create trigger properties_set_first_primary
before insert or update of client_id, deleted_at, is_primary on public.properties
for each row execute function private.set_first_property_primary();

-- Exactly one primary Property whenever a Client still has an active Property. Deferred so a single
-- transaction can promote a replacement while demoting or deleting the previous primary.
create or replace function private.enforce_client_primary_property()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  affected_clients uuid[];
  affected_client uuid;
  active_count integer;
  primary_count integer;
begin
  -- An update that moves a Property between Clients has to leave both Clients valid.
  if tg_op = 'DELETE' then
    affected_clients := array[old.client_id];
  elsif tg_op = 'INSERT' then
    affected_clients := array[new.client_id];
  else
    affected_clients := array[old.client_id, new.client_id];
  end if;

  foreach affected_client in array affected_clients
  loop
    select
      count(*) filter (where deleted_at is null),
      count(*) filter (where deleted_at is null and is_primary)
    into active_count, primary_count
    from public.properties
    where client_id = affected_client;

    if active_count > 0 and primary_count <> 1 then
      raise exception 'A client with an active property must have exactly one primary property.'
        using errcode = '23514';
    end if;
  end loop;

  return null;
end;
$$;

create constraint trigger properties_enforce_primary
after insert or update or delete on public.properties
deferrable initially deferred
for each row execute function private.enforce_client_primary_property();

-- A deleted Property can never remain the billing address.
create or replace function private.validate_property_billing_address()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.is_billing_address and new.deleted_at is not null then
    raise exception 'A deleted property cannot be the billing address.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger properties_validate_billing_address
before insert or update of is_billing_address, deleted_at on public.properties
for each row execute function private.validate_property_billing_address();

-- 7. Updated-at triggers --------------------------------------------------------------------------------

create trigger client_contacts_set_updated_at
before update on public.client_contacts
for each row execute function public.set_updated_at();

create trigger client_contact_methods_set_updated_at
before update on public.client_contact_methods
for each row execute function public.set_updated_at();

create trigger client_communication_preferences_set_updated_at
before update on public.client_communication_preferences
for each row execute function public.set_updated_at();

-- 8. Row level security ----------------------------------------------------------------------------------

alter table public.client_contacts enable row level security;
alter table public.client_contact_methods enable row level security;
alter table public.client_communication_preferences enable row level security;

create policy "members can view client contacts"
on public.client_contacts for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create client contacts"
on public.client_contacts for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update client contacts"
on public.client_contacts for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "members can delete client contacts"
on public.client_contacts for delete to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view client contact methods"
on public.client_contact_methods for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create client contact methods"
on public.client_contact_methods for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update client contact methods"
on public.client_contact_methods for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "members can delete client contact methods"
on public.client_contact_methods for delete to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view client communication preferences"
on public.client_communication_preferences for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can update client communication preferences"
on public.client_communication_preferences for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

grant select on
  public.client_contacts,
  public.client_contact_methods,
  public.client_communication_preferences
to authenticated;

grant insert, update, delete on public.client_contacts, public.client_contact_methods to authenticated;
grant update on public.client_communication_preferences to authenticated;

-- 9. Atomic Client creation ---------------------------------------------------------------------------------

-- Runs as the caller so row level security still decides what may be written. Keeps the Client, its
-- contact methods, and its first Property in one transaction so a partial failure leaves no orphan.
create or replace function public.create_client(payload jsonb)
returns public.clients
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  created_client public.clients;
  new_property_id uuid;
  email_value text := nullif(trim(payload->>'email'), '');
  phone_value text := nullif(trim(payload->>'phone'), '');
  property_payload jsonb := payload->'property';
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
    next_follow_up_at,
    notes
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
    nullif(payload->>'next_follow_up_at', '')::timestamptz,
    nullif(trim(payload->>'notes'), '')
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

  return created_client;
end;
$$;

revoke all on function public.create_client(jsonb) from public;
grant execute on function public.create_client(jsonb) to authenticated;
