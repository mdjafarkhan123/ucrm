-- Owner-only package version management.
-- Draft versions can be edited; published versions are immutable.

create table public.platform_owner_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_owner_email text not null,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_type text not null check (target_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_key text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now()
);

create index platform_owner_audit_events_target_idx
  on public.platform_owner_audit_events (target_type, target_key, created_at desc);

alter table public.platform_owner_audit_events enable row level security;
revoke all on public.platform_owner_audit_events from anon, authenticated;
grant select, insert on public.platform_owner_audit_events to service_role;

create or replace function public.manage_platform_package_version(
  operation text,
  target_package_key text,
  target_version_id uuid default null,
  target_display_name text default null,
  target_public_description text default null,
  target_value_explanation text default null,
  target_price_usd_cents integer default null,
  target_feature_keys text[] default '{}',
  target_limit_state text default null,
  target_limit_value integer default null,
  actor_email text default null
)
returns uuid
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  package_row public.platform_packages%rowtype;
  version_row public.platform_package_versions%rowtype;
  before_state jsonb;
  after_state jsonb;
begin
  if operation not in ('create_draft', 'update_draft', 'publish') then
    raise exception 'Unsupported package version operation.' using errcode = 'invalid_parameter_value';
  end if;
  if actor_email is null or char_length(trim(actor_email)) = 0 then
    raise exception 'An owner email is required.' using errcode = 'not_null_violation';
  end if;

  select * into package_row
  from public.platform_packages
  where package_key = target_package_key
    and status <> 'retired'
  for update;
  if not found then
    raise exception 'Package was not found.' using errcode = 'foreign_key_violation';
  end if;

  if operation = 'create_draft' then
    if target_display_name is null or target_public_description is null
      or target_price_usd_cents is null then
      raise exception 'Draft package name, description, and price are required.' using errcode = 'check_violation';
    end if;

    insert into public.platform_package_versions (
      package_id, version_number, display_name, public_description,
      value_explanation, price_usd_cents
    )
    select package_row.package_id, coalesce(max(version_number), 0) + 1,
      target_display_name, target_public_description,
      target_value_explanation, target_price_usd_cents
    from public.platform_package_versions
    where package_id = package_row.package_id
    returning * into version_row;
  else
    select * into version_row
    from public.platform_package_versions
    where id = target_version_id
      and package_id = package_row.package_id
    for update;
    if not found then
      raise exception 'Package version was not found.' using errcode = 'foreign_key_violation';
    end if;
    if operation in ('update_draft', 'publish') and version_row.status <> 'draft' then
      raise exception 'Only draft package versions can be changed.' using errcode = 'check_violation';
    end if;
  end if;

  if operation in ('create_draft', 'update_draft') then
    if target_display_name is null or target_public_description is null
      or target_price_usd_cents is null then
      raise exception 'Package name, description, and price are required.' using errcode = 'check_violation';
    end if;
    before_state := to_jsonb(version_row);
    if operation = 'update_draft' then
      update public.platform_package_versions
      set display_name = target_display_name,
          public_description = target_public_description,
          value_explanation = target_value_explanation,
          price_usd_cents = target_price_usd_cents
      where id = version_row.id;
      select * into version_row from public.platform_package_versions where id = version_row.id;
    end if;

    delete from public.platform_package_version_features where package_version_id = version_row.id;
    insert into public.platform_package_version_features (package_version_id, feature_key)
    select version_row.id, feature_key from unnest(target_feature_keys) as feature_key;

    delete from public.platform_package_version_limits where package_version_id = version_row.id;
    if target_limit_state is not null then
      insert into public.platform_package_version_limits (
        package_version_id, limit_key, limit_state, limit_value
      ) values (version_row.id, 'employee_seats', target_limit_state, target_limit_value);
    end if;
  end if;

  if operation = 'publish' then
    if version_row.public_description is null or char_length(trim(version_row.public_description)) = 0
      or version_row.price_usd_cents is null then
      raise exception 'A package version needs a description and price before publishing.' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.platform_package_version_features where package_version_id = version_row.id)
      and (version_row.value_explanation is null or char_length(trim(version_row.value_explanation)) = 0) then
      raise exception 'A package version needs an included capability or value explanation.' using errcode = 'check_violation';
    end if;
    update public.platform_package_versions
    set status = 'retired', retired_at = now()
    where package_id = package_row.package_id and status = 'published';
    update public.platform_package_versions
    set status = 'published', published_at = now()
    where id = version_row.id
    returning * into version_row;
    update public.platform_packages
    set status = 'published',
        public_description = version_row.public_description,
        price_usd_cents = version_row.price_usd_cents,
        currency = version_row.currency,
        billing_period = version_row.billing_period
    where package_id = package_row.package_id;
  end if;

  after_state := to_jsonb(version_row);
  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    lower(trim(actor_email)), 'package.' || operation, 'platform_package_version',
    version_row.id::text, before_state, after_state
  );

  return version_row.id;
end;
$$;

revoke all on function public.manage_platform_package_version(text, text, uuid, text, text, text, integer, text[], text, integer, text) from public;
grant execute on function public.manage_platform_package_version(text, text, uuid, text, text, text, integer, text[], text, integer, text) to service_role;
