-- Fix found during Part 2C's own performance/RLS review, before any API route was built on top of it.
--
-- Target margin landed on organization_settings in the prior migration, gated by that table's one existing
-- SELECT policy: `settings.business.view`. That permission is granted to every role including `field` --
-- unlike Price Book, whose cost/profit data (`catalog_items`) sits behind the much narrower `catalog.view`
-- (excludes `field`). Left as-is, a `field` member could read the target margin straight over PostgREST
-- (`GET /organization_settings?select=quote_target_margin_basis_points`), bypassing the API layer's planned
-- redaction entirely -- the exact "shown only to staff authorized to see internal cost and profit" rule the
-- blueprint requires. RLS cannot narrow visibility for one column of a row that a broader policy already
-- exposes for its other columns, so the fix is the same one `organization_tax_rates` already used: give the
-- data its own table with its own SELECT policy.
--
-- Read policy: `quotes.view_cost` OR `settings.quotes.manage` -- covers cost-permitted staff (e.g. finance)
-- who can see it without managing Settings, and owner/admin who manage it. Write stays SECURITY DEFINER-only,
-- same as every other Settings section.

-- 1. Undo the organization_settings placement -----------------------------------------------------------

alter table public.organization_settings
  drop constraint if exists organization_settings_quote_target_margin_check,
  drop column if exists quote_target_margin_basis_points,
  drop column if exists quote_target_margin_revision,
  drop column if exists quote_target_margin_updated_by,
  drop column if exists quote_target_margin_updated_at;

-- 2. Its own table, its own visibility rule --------------------------------------------------------------

create table public.organization_quote_target_margin (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  target_margin_basis_points integer
    check (target_margin_basis_points is null or (target_margin_basis_points > 0 and target_margin_basis_points < 10000)),
  revision integer not null default 1,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.organization_quote_target_margin is
  'Private target-margin guidance, split out of organization_settings so its SELECT policy can require '
  'quotes.view_cost -- settings.business.view (granted to every role, including field) would otherwise '
  'expose it over PostgREST regardless of what the API layer redacts.';

revoke insert, update, delete, truncate, references, trigger
  on public.organization_quote_target_margin
  from anon, authenticated;

alter table public.organization_quote_target_margin enable row level security;

create policy "cost-permitted staff can view target margin"
on public.organization_quote_target_margin for select to authenticated
using (
  private.has_permission(organization_id, 'quotes.view_cost')
  or private.has_permission(organization_id, 'settings.quotes.manage')
);

-- 3. Backfill every existing organization, seed every future one ------------------------------------------

insert into public.organization_quote_target_margin (organization_id)
select id from public.organizations
on conflict (organization_id) do nothing;

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

  insert into public.organization_quote_target_margin (organization_id)
  values (new.id)
  on conflict (organization_id) do nothing;

  return new;
end;
$$;

-- 4. The section command now targets its own table ---------------------------------------------------------

create or replace function public.set_organization_quote_target_margin(
  target_organization_id uuid,
  expected_revision integer,
  new_margin_basis_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  margin_row public.organization_quote_target_margin;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.quotes.manage') then
    raise exception 'You do not have access to manage Quote Settings.' using errcode = 'insufficient_privilege';
  end if;

  if new_margin_basis_points is not null and (new_margin_basis_points <= 0 or new_margin_basis_points >= 10000) then
    raise exception 'Target margin must be greater than 0%% and below 100%%.' using errcode = 'check_violation';
  end if;

  select * into margin_row
  from public.organization_quote_target_margin
  where organization_id = target_organization_id
  for update;

  if margin_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from margin_row.revision then
    select profile.full_name, margin_row.updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = margin_row.updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, margin_row.updated_at)
    );
  end if;

  update public.organization_quote_target_margin
  set target_margin_basis_points = new_margin_basis_points,
      revision = revision + 1,
      updated_by = (select auth.uid()),
      updated_at = now()
  where organization_id = target_organization_id
  returning revision into margin_row.revision;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'quote_target_margin', array['target_margin_basis_points'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'quote_target_margin_revision', margin_row.revision,
    'quote_target_margin_basis_points', new_margin_basis_points
  );
end;
$$;

revoke all on function public.set_organization_quote_target_margin(uuid, integer, integer) from public;
revoke execute on function public.set_organization_quote_target_margin(uuid, integer, integer) from anon;
grant execute on function public.set_organization_quote_target_margin(uuid, integer, integer) to authenticated;
