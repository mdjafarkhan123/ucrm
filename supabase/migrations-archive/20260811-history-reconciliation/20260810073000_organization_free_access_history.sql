-- Owner-managed free access history.
-- Free access changes billing treatment only. Package assignments remain the
-- source of package features and limits, and payment confirmations remain
-- reserved for real offsite payments.

create table public.organization_free_access_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  package_version_id uuid not null references public.platform_package_versions(id),
  action text not null check (
    action in ('grant', 'extend', 'convert_to_forever', 'end')
  ),
  access_until_date date,
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  actor_kind text not null default 'platform_owner' check (actor_kind = 'platform_owner'),
  actor_owner_email text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint organization_free_access_event_state_check check (
    (action in ('convert_to_forever', 'end') and access_until_date is null)
    or (action in ('grant', 'extend'))
  ),
  constraint organization_free_access_event_actor_email_check check (
    actor_owner_email is null
    or char_length(trim(actor_owner_email)) between 3 and 320
  )
);

create index organization_free_access_events_current_idx
  on public.organization_free_access_events (organization_id, occurred_at desc, id desc);

create index organization_free_access_events_expiry_idx
  on public.organization_free_access_events (access_until_date, organization_id)
  where access_until_date is not null;

create or replace function private.validate_organization_free_access_event()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  package_assignment_exists boolean;
begin
  if new.occurred_at > now() then
    raise exception 'Free access events cannot be dated in the future.'
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1
    from public.organization_package_assignments as assignment
    where assignment.organization_id = new.organization_id
      and assignment.package_version_id = new.package_version_id
  )
  into package_assignment_exists;

  if not package_assignment_exists then
    raise exception 'Free access must use a package version assigned to the organization.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_organization_free_access_event() from public;

create trigger organization_free_access_events_validate
before insert on public.organization_free_access_events
for each row execute function private.validate_organization_free_access_event();

create or replace function private.prevent_organization_free_access_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Free access history is append-only.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_organization_free_access_event_mutation() from public;

create trigger organization_free_access_events_immutable
before update or delete on public.organization_free_access_events
for each row execute function private.prevent_organization_free_access_event_mutation();

alter table public.organization_free_access_events enable row level security;

revoke all on public.organization_free_access_events from anon, authenticated;
revoke all on public.organization_free_access_events from service_role;
grant select, insert on public.organization_free_access_events to service_role;
