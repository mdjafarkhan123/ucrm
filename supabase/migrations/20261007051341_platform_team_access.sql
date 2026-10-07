-- Jafar business D2: per-teammate access in /jafar (ADR 0008).
-- A teammate's access is their role's starting set plus Jafar's individual adjustments: an area raised or
-- lowered (none / look / work) and sensitive actions granted. `access_revision` lets a save refuse to
-- overwrite a change made since the editor loaded. Every save writes its history row in the same
-- transaction, so an access change can never exist without who made it and when.

alter table public.platform_team_members
  add column area_adjustments jsonb not null default '{}'::jsonb,
  add column action_grants text[] not null default '{}'::text[],
  add column access_revision integer not null default 0,
  add constraint platform_team_members_area_adjustments_shape check (
    jsonb_typeof(area_adjustments) = 'object'
    and not jsonb_path_exists(
      area_adjustments,
      '$.keyvalue() ? (@.value.type() != "string"
        || !(@.key like_regex "^(leads|applications|onboarding|support|organizations|packages|operations)$")
        || !(@.value like_regex "^(none|look|work)$"))'
    )
  ),
  add constraint platform_team_members_action_grants_known check (
    action_grants <@ array['payments', 'client_setup', 'packages', 'client_accounts']::text[]
  ),
  add constraint platform_team_members_access_revision_nonnegative check (access_revision >= 0);

comment on column public.platform_team_members.area_adjustments is
  'Areas Jafar set differently from the role''s starting access: {area: none|look|work}.';
comment on column public.platform_team_members.action_grants is
  'Sensitive actions Jafar granted this teammate. Every role starts with none.';

-- Saves a teammate's role and access in one step, refusing when the revision moved on (returns no row)
-- and recording the before and after in platform_audit_events.
create or replace function public.platform_team_set_access(
  p_member_id uuid,
  p_expected_revision integer,
  p_role text,
  p_area_adjustments jsonb,
  p_action_grants text[],
  p_actor_email text
)
returns table (access_revision integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_before public.platform_team_members%rowtype;
  v_grants text[];
begin
  select coalesce(array_agg(distinct g order by g), '{}'::text[])
    into v_grants
    from unnest(p_action_grants) as g;

  select * into v_before
    from public.platform_team_members m
   where m.id = p_member_id
     and m.status <> 'removed'
     and m.access_revision = p_expected_revision
   for update;

  if not found then
    return;
  end if;

  update public.platform_team_members m
     set role = p_role,
         area_adjustments = p_area_adjustments,
         action_grants = v_grants,
         access_revision = m.access_revision + 1
   where m.id = p_member_id;

  insert into public.platform_audit_events
    (actor_owner_email, event_type, target_type, target_key, before_state, after_state)
  values (
    p_actor_email,
    'team_access_changed',
    'platform_team_member',
    p_member_id::text,
    jsonb_build_object(
      'role', v_before.role,
      'area_adjustments', v_before.area_adjustments,
      'action_grants', to_jsonb(v_before.action_grants)
    ),
    jsonb_build_object(
      'role', p_role,
      'area_adjustments', p_area_adjustments,
      'action_grants', to_jsonb(v_grants)
    )
  );

  return query select v_before.access_revision + 1;
end;
$$;

revoke all on function public.platform_team_set_access(uuid, integer, text, jsonb, text[], text)
  from public, anon, authenticated;
grant execute on function public.platform_team_set_access(uuid, integer, text, jsonb, text[], text)
  to service_role;
