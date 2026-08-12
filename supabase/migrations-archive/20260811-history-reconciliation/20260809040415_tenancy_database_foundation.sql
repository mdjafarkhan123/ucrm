-- Tenancy foundation: user profiles, organization settings, and a durable
-- role/permission catalog. Permission assignments remain intentionally empty
-- until the product permission matrix is approved.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text check (full_name is null or char_length(trim(full_name)) between 1 and 160),
  avatar_url text check (avatar_url is null or char_length(trim(avatar_url)) between 1 and 2048),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  timezone text not null default 'UTC' check (char_length(trim(timezone)) between 1 and 64),
  locale text not null default 'en-US' check (locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$'),
  currency_code text not null default 'USD' check (currency_code ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.permissions (
  key text primary key check (key ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  description text not null check (char_length(trim(description)) between 1 and 240),
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role text not null check (role in ('owner', 'admin', 'office', 'sales', 'field', 'finance')),
  permission_key text not null references public.permissions(key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role, permission_key)
);

create index role_permissions_permission_key_idx on public.role_permissions(permission_key);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger organization_settings_set_updated_at
before update on public.organization_settings
for each row execute function public.set_updated_at();

create or replace function private.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row execute function private.handle_new_user_profile();

create or replace function private.create_organization_settings()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.organization_settings (organization_id)
  values (new.id)
  on conflict (organization_id) do nothing;
  return new;
end;
$$;

create trigger organizations_create_settings
after insert on public.organizations
for each row execute function private.create_organization_settings();

alter table public.profiles enable row level security;
alter table public.organization_settings enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;

create policy "users can view their profile"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "users can update their profile"
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy "members can view organization settings"
on public.organization_settings for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can update organization settings"
on public.organization_settings for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "authenticated users can view permissions"
on public.permissions for select to authenticated
using (true);

create policy "authenticated users can view role permissions"
on public.role_permissions for select to authenticated
using (true);

grant select, update on public.profiles to authenticated;
grant select, update on public.organization_settings to authenticated;
grant select on public.permissions, public.role_permissions to authenticated;

revoke all on function private.handle_new_user_profile() from public;
revoke all on function private.create_organization_settings() from public;
