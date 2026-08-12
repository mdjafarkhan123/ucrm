-- Contractor CRM foundation: organizations, members, customers, properties, and requests.
-- This migration intentionally contains no seed data. Organization provisioning belongs to the
-- platform-owner workflow and should create the first organization/member explicitly.

create extension if not exists "pgcrypto";

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'admin', 'office', 'sales', 'field', 'finance')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create index organization_members_user_id_idx on public.organization_members(user_id);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 160),
  first_name text,
  last_name text,
  company_name text,
  email text,
  phone text,
  lifecycle_status text not null default 'lead' check (lifecycle_status in ('lead', 'customer')),
  source text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index contacts_organization_updated_idx on public.contacts(organization_id, updated_at desc);
create index contacts_organization_status_idx on public.contacts(organization_id, lifecycle_status);

alter table public.contacts add constraint contacts_organization_id_id_key unique (organization_id, id);

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  contact_id uuid not null references public.contacts(id) on delete cascade,
  label text not null default 'Primary property' check (char_length(trim(label)) between 2 and 120),
  address_line1 text not null check (char_length(trim(address_line1)) between 2 and 160),
  address_line2 text,
  city text not null check (char_length(trim(city)) between 2 and 80),
  state_region text,
  postal_code text,
  country text not null default 'US',
  access_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint properties_contact_organization_fk foreign key (organization_id, contact_id)
    references public.contacts(organization_id, id) on delete cascade
);

create unique index properties_contact_label_unique_idx on public.properties(contact_id, lower(label));
create index properties_organization_contact_idx on public.properties(organization_id, contact_id, updated_at desc);
alter table public.properties add constraint properties_organization_id_id_key unique (organization_id, id);

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  contact_id uuid not null,
  property_id uuid not null,
  title text not null check (char_length(trim(title)) between 2 and 160),
  description text,
  service_type text,
  source text not null default 'staff',
  preferred_time text,
  status text not null default 'new' check (status in ('new', 'unscheduled', 'upcoming', 'today', 'overdue', 'assessment_completed', 'completed', 'converted', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint requests_contact_organization_fk foreign key (organization_id, contact_id)
    references public.contacts(organization_id, id) on delete restrict,
  constraint requests_property_organization_fk foreign key (organization_id, property_id)
    references public.properties(organization_id, id) on delete restrict
);

create index requests_organization_updated_idx on public.requests(organization_id, updated_at desc);
create index requests_organization_status_idx on public.requests(organization_id, status, updated_at desc);
create index requests_contact_idx on public.requests(organization_id, contact_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();

create trigger contacts_set_updated_at
before update on public.contacts
for each row execute function public.set_updated_at();

create trigger properties_set_updated_at
before update on public.properties
for each row execute function public.set_updated_at();

create trigger requests_set_updated_at
before update on public.requests
for each row execute function public.set_updated_at();

create schema if not exists private;

create or replace function private.is_organization_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.organization_members
    where organization_id = target_organization_id
      and user_id = (select auth.uid())
  );
$$;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.contacts enable row level security;
alter table public.properties enable row level security;
alter table public.requests enable row level security;

create policy "members can view their organizations"
on public.organizations for select to authenticated
using (private.is_organization_member(id));

create policy "members can view organization membership"
on public.organization_members for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view contacts"
on public.contacts for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create contacts"
on public.contacts for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update contacts"
on public.contacts for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "members can view properties"
on public.properties for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create properties"
on public.properties for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update properties"
on public.properties for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "members can view requests"
on public.requests for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create requests"
on public.requests for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update requests"
on public.requests for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

grant select on public.organizations, public.organization_members, public.contacts, public.properties, public.requests to authenticated;
grant insert, update on public.contacts, public.properties, public.requests to authenticated;
revoke all on function private.is_organization_member(uuid) from public;
grant execute on function private.is_organization_member(uuid) to authenticated;

;
