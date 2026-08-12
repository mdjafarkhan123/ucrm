-- Versioned package foundation.
-- This is an additive compatibility step. Legacy package keys and access reads
-- remain in place until a later cutover migration.

alter table public.platform_packages
  add column package_id uuid not null default gen_random_uuid(),
  add column status text not null default 'draft',
  add column public_description text,
  add column price_usd_cents integer,
  add column currency text not null default 'USD',
  add column billing_period text not null default 'monthly',
  add constraint platform_packages_package_id_key unique (package_id),
  add constraint platform_packages_status_check check (status in ('draft', 'published', 'retired')),
  add constraint platform_packages_price_check check (price_usd_cents is null or price_usd_cents >= 0),
  add constraint platform_packages_currency_check check (currency = 'USD'),
  add constraint platform_packages_billing_period_check check (billing_period = 'monthly');

create table public.platform_package_versions (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.platform_packages(package_id),
  version_number integer not null check (version_number > 0),
  status text not null default 'draft' check (status in ('draft', 'published', 'retired')),
  display_name text not null check (char_length(trim(display_name)) between 2 and 80),
  public_description text,
  value_explanation text,
  price_usd_cents integer,
  currency text not null default 'USD' check (currency = 'USD'),
  billing_period text not null default 'monthly' check (billing_period = 'monthly'),
  published_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  unique (package_id, version_number),
  constraint platform_package_versions_price_check
    check (price_usd_cents is null or price_usd_cents >= 0),
  constraint platform_package_versions_status_dates_check
    check (
      (status = 'draft' and retired_at is null)
      or (status = 'published' and published_at is not null and retired_at is null)
      or (status = 'retired' and published_at is not null and retired_at is not null)
    )
);

create unique index platform_package_versions_one_published_idx
  on public.platform_package_versions (package_id)
  where status = 'published';

create index platform_package_versions_public_list_idx
  on public.platform_package_versions (status, created_at desc)
  where status = 'published';

create table public.platform_package_version_features (
  package_version_id uuid not null references public.platform_package_versions(id) on delete cascade,
  feature_key text not null references public.features(feature_key),
  created_at timestamptz not null default now(),
  primary key (package_version_id, feature_key)
);

create index platform_package_version_features_feature_idx
  on public.platform_package_version_features (feature_key, package_version_id);

create table public.platform_package_version_limits (
  package_version_id uuid not null references public.platform_package_versions(id) on delete cascade,
  limit_key text not null check (limit_key = 'employee_seats'),
  limit_state text not null check (limit_state in ('unlimited', 'not_included', 'numeric')),
  limit_value integer,
  created_at timestamptz not null default now(),
  primary key (package_version_id, limit_key),
  constraint platform_package_version_limits_value_check check (
    (limit_state = 'unlimited' and limit_value is null)
    or (limit_state = 'not_included' and limit_value is null)
    or (limit_state = 'numeric' and limit_value is not null and limit_value > 0)
  )
);

create index platform_package_version_limits_limit_idx
  on public.platform_package_version_limits (limit_key, package_version_id);

create or replace function private.validate_platform_package_version()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  has_feature boolean;
begin
  if new.status in ('published', 'retired') then
    if new.public_description is null or char_length(trim(new.public_description)) = 0 then
      raise exception 'A published package version needs a public description.' using errcode = 'check_violation';
    end if;

    if new.price_usd_cents is null then
      raise exception 'A published package version needs a monthly price.' using errcode = 'check_violation';
    end if;

    select exists (
      select 1
      from public.platform_package_version_features
      where package_version_id = new.id
    ) into has_feature;

    if not has_feature and (new.value_explanation is null or char_length(trim(new.value_explanation)) = 0) then
      raise exception 'A published package version needs an included capability or value explanation.' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.status = 'retired' then
    raise exception 'Retired package versions are immutable.' using errcode = 'check_violation';
  end if;

  if tg_op = 'UPDATE' and old.status = 'published' then
    if new.status <> 'retired'
      or new.package_id <> old.package_id
      or new.version_number <> old.version_number
      or new.display_name <> old.display_name
      or new.public_description is distinct from old.public_description
      or new.value_explanation is distinct from old.value_explanation
      or new.price_usd_cents is distinct from old.price_usd_cents
      or new.currency <> old.currency
      or new.billing_period <> old.billing_period
      or new.published_at is distinct from old.published_at then
      raise exception 'Published package versions are immutable; create a new version instead.' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.validate_platform_package_version() from public;

create trigger platform_package_versions_validate
before insert or update on public.platform_package_versions
for each row execute function private.validate_platform_package_version();

create or replace function private.validate_published_package_version_feature()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  version_status text;
begin
  select status into version_status
  from public.platform_package_versions
  where id = coalesce(new.package_version_id, old.package_version_id);

  if version_status in ('published', 'retired') and tg_op in ('INSERT', 'UPDATE', 'DELETE') then
    raise exception 'Published and retired package version features are immutable.' using errcode = 'check_violation';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function private.validate_published_package_version_feature() from public;

create trigger platform_package_version_features_immutable
before insert or update or delete on public.platform_package_version_features
for each row execute function private.validate_published_package_version_feature();

create or replace function private.validate_published_package_version_limit()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  version_status text;
begin
  select status into version_status
  from public.platform_package_versions
  where id = coalesce(new.package_version_id, old.package_version_id);

  if version_status in ('published', 'retired') and tg_op in ('INSERT', 'UPDATE', 'DELETE') then
    raise exception 'Published and retired package version limits are immutable.' using errcode = 'check_violation';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function private.validate_published_package_version_limit() from public;

create trigger platform_package_version_limits_immutable
before insert or update or delete on public.platform_package_version_limits
for each row execute function private.validate_published_package_version_limit();

alter table public.platform_package_versions enable row level security;
alter table public.platform_package_version_features enable row level security;
alter table public.platform_package_version_limits enable row level security;

create policy "public can view published package versions"
on public.platform_package_versions for select
to anon, authenticated
using (status = 'published');

create policy "public can view published package version features"
on public.platform_package_version_features for select
to anon, authenticated
using (
  exists (
    select 1
    from public.platform_package_versions as version
    where version.id = package_version_id
      and version.status = 'published'
  )
);

create policy "public can view published package version limits"
on public.platform_package_version_limits for select
to anon, authenticated
using (
  exists (
    select 1
    from public.platform_package_versions as version
    where version.id = package_version_id
      and version.status = 'published'
  )
);

revoke all on public.platform_package_versions,
  public.platform_package_version_features,
  public.platform_package_version_limits from anon, authenticated;

grant select on public.platform_package_versions,
  public.platform_package_version_features,
  public.platform_package_version_limits to anon, authenticated;
