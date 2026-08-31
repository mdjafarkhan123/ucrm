-- Team & access, part 3A, item 6: the seven commands that change one team member's standing.
--
-- Everything a team manager can do to somebody else lives here: their role, their individual permission
-- adjustments, their business details, deactivation, restoration, permanent removal, and the ledger step
-- that records the Auth cleanup after a removal. Item 5 covered the one thing none of these may ever do --
-- hand over ownership -- so every command below refuses an owner target and refuses to write role = 'owner'.
--
-- The blueprint's authority rules are enforced here, in the database, not only in the API that calls it:
--   * "Nobody edits their own role or permissions" -- an actor may never target themselves.
--   * "Only the Owner may promote someone to Administrator or change, deactivate, demote, or permanently
--     remove an Administrator" -- an administrator acting on another administrator is refused.
--   * "Ordinary role editing cannot demote, deactivate, or remove the Owner" -- the owner is never a target.
--   * "Permanent removal is available only after deactivation... An Administrator must first be demoted."
-- One shared authorization helper carries the first three, so no command can quietly forget one of them.
--
-- Conflict protection, from "Each section has conflict protection so concurrent editors cannot silently
-- overwrite one another": the two access commands take the access_revision they were shown and the profile
-- command takes profile_revision. A stale editor is refused rather than merged. The status commands take no
-- revision -- deactivating someone twice is a state check, not a lost edit -- but they bump access_revision,
-- so an access editor holding a stale copy is refused afterwards.
--
-- Not here, on purpose: ending the member's live sessions, banning the Auth account and releasing the dead
-- email are Auth calls that cannot share this transaction. Removal only sets identity_cleanup_state to
-- 'required'; 3B's worker does that work and calls mark_member_identity_revoked to close the ledger.

-- ---------------------------------------------------------------------------
-- The shared authorization
-- ---------------------------------------------------------------------------

-- Returns the target's membership row, or raises. Every command starts here, so the rules about who may act
-- on whom live in exactly one place and cannot drift between the seven.
create or replace function private.authorize_team_member_command(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  owner_actor_required boolean default false
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_role text;
  target_membership public.organization_members;
begin
  if actor_user_id is null or target_user_id is null then
    raise exception 'A team change needs both a person acting and a person to act on.'
      using errcode = 'check_violation';
  end if;

  if actor_user_id = target_user_id then
    raise exception 'You cannot change your own access.' using errcode = 'check_violation';
  end if;

  select membership.role into actor_role
  from public.organization_members as membership
  where membership.organization_id = target_organization_id
    and membership.user_id = actor_user_id
    and membership.status = 'active';

  if actor_role is null or actor_role not in ('owner', 'admin') then
    raise exception 'Only an owner or administrator can manage the team.' using errcode = 'check_violation';
  end if;

  if owner_actor_required and actor_role <> 'owner' then
    raise exception 'Only the owner can do that.' using errcode = 'check_violation';
  end if;

  -- Locked here rather than in a second helper: every caller writes, and taking the lock together with the
  -- authority check means no window exists between "allowed" and "changed".
  select * into target_membership
  from public.organization_members as membership
  where membership.organization_id = target_organization_id
    and membership.user_id = target_user_id
  for update;

  if not found then
    raise exception 'That team member was not found.' using errcode = 'no_data_found';
  end if;

  -- The owner is never a target. Their role changes through item 5's ownership transfer and nothing else.
  if target_membership.role = 'owner' then
    raise exception 'The owner''s access changes by handing over ownership, not here.'
      using errcode = 'check_violation';
  end if;

  if target_membership.role = 'admin' and actor_role <> 'owner' then
    raise exception 'Only the owner can manage an administrator.' using errcode = 'check_violation';
  end if;

  return target_membership;
end;
$$;

comment on function private.authorize_team_member_command(uuid, uuid, uuid, boolean) is
  'The authority every team member command shares: nobody acts on themselves, the actor must be an active '
  'owner or administrator, the owner is never a target, and only the owner may manage an administrator. '
  'Returns the target membership row, locked for the rest of the transaction.';

revoke all on function private.authorize_team_member_command(uuid, uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

-- An access edit only makes sense while somebody is on the team. Changing a deactivated person's role or
-- permissions would be an invisible decision; restore them first, which is a decision in its own right.
create or replace function private.assert_membership_is_editable(membership public.organization_members)
returns void
language plpgsql
immutable
set search_path = pg_catalog
as $$
begin
  if membership.status not in ('pending', 'active') then
    raise exception 'Restore this person before changing their access.' using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function private.assert_membership_is_editable(public.organization_members)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1. Role
-- ---------------------------------------------------------------------------

-- keep_adjustments is the blueprint's "either the new role's standard access or retaining compatible
-- individual adjustments". Compatible means still meaningful: a grant for something the new role already
-- includes, and a deny for something it never had, both say nothing, so both go. The screen previews exactly
-- this list before Save; the database decides it, so the preview and the result cannot disagree.
create or replace function public.change_team_member_role(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  new_role text,
  keep_adjustments boolean,
  expected_access_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_role text;
  membership public.organization_members;
  previous_role text;
  dropped_keys text[];
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );
  perform private.assert_membership_is_editable(membership);

  if expected_access_revision is null or expected_access_revision <> membership.access_revision then
    raise exception 'Someone else changed this person''s access while you were editing.'
      using errcode = 'serialization_failure';
  end if;

  -- Ownership has one road, and this is not it.
  if new_role = 'owner' then
    raise exception 'Ownership is handed over, never assigned.' using errcode = 'check_violation';
  end if;

  if new_role is null or new_role not in ('admin', 'office', 'sales', 'field', 'finance') then
    raise exception '% is not a role.', coalesce(new_role, 'nothing') using errcode = 'check_violation';
  end if;

  select membership_actor.role into actor_role
  from public.organization_members as membership_actor
  where membership_actor.organization_id = target_organization_id
    and membership_actor.user_id = actor_user_id;

  if new_role = 'admin' and actor_role <> 'owner' then
    raise exception 'Only the owner can make someone an administrator.' using errcode = 'check_violation';
  end if;

  if new_role = membership.role then
    raise exception 'That person already has this role.' using errcode = 'check_violation';
  end if;

  previous_role := membership.role;

  with dropped as (
    delete from public.organization_member_permission_overrides as override
    where override.organization_id = target_organization_id
      and override.user_id = target_user_id
      and (
        keep_adjustments is not true
        or (
          override.override_state = 'grant'
          and exists (
            select 1
            from public.role_permissions as role_permission
            where role_permission.role = new_role
              and role_permission.permission_key = override.permission_key
          )
        )
        or (
          override.override_state = 'deny'
          and not exists (
            select 1
            from public.role_permissions as role_permission
            where role_permission.role = new_role
              and role_permission.permission_key = override.permission_key
          )
        )
      )
    returning override.permission_key
  )
  select coalesce(array_agg(dropped.permission_key order by dropped.permission_key), '{}'::text[])
  into dropped_keys
  from dropped;

  update public.organization_members as membership_row
  set role = new_role,
      access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.role_changed', 'member', actor_user_id, target_user_id,
    jsonb_build_object('previous_role', previous_role, 'new_role', new_role)
  );

  -- A second line, only when adjustments actually went. One Save that both changed the role and dropped
  -- three adjustments should read as both facts in the history, not as a role change that quietly did more.
  if array_length(dropped_keys, 1) is not null then
    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
    )
    values (
      target_organization_id, 'member.permissions_changed', 'member', actor_user_id, target_user_id,
      jsonb_build_object('removed_permissions', to_jsonb(dropped_keys))
    );
  end if;

  return membership;
end;
$$;

comment on function public.change_team_member_role(uuid, uuid, uuid, text, boolean, integer) is
  'Moves one member to another standard role. Drops the individual adjustments the new role makes '
  'meaningless -- or all of them when keep_adjustments is false. Never assigns ownership.';

revoke all on function public.change_team_member_role(uuid, uuid, uuid, text, boolean, integer)
  from public, anon, authenticated;
grant execute on function public.change_team_member_role(uuid, uuid, uuid, text, boolean, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2. Permissions
-- ---------------------------------------------------------------------------

-- The whole adjustment set in one call, because the screen saves a section rather than a control, and
-- because "one Save produces one understandable summary, not one message per control" needs one command
-- that can see the before and the after together. The added/removed lists are worked out here, so an API
-- cannot describe the save as something other than what it did.
create or replace function public.save_team_member_permissions(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  desired_overrides jsonb,
  expected_access_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  added_keys text[];
  removed_keys text[];
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );
  perform private.assert_membership_is_editable(membership);

  if expected_access_revision is null or expected_access_revision <> membership.access_revision then
    raise exception 'Someone else changed this person''s access while you were editing.'
      using errcode = 'serialization_failure';
  end if;

  if desired_overrides is null or jsonb_typeof(desired_overrides) <> 'array' then
    raise exception 'The permission adjustments must be a list.' using errcode = 'check_violation';
  end if;

  -- Every entry names a real permission and one of the two states. An unknown key would be caught by the
  -- foreign key anyway, but the message it produces is not one anybody could act on.
  if exists (
    select 1
    from jsonb_array_elements(desired_overrides) as entry(item)
    where jsonb_typeof(entry.item) <> 'object'
      or (entry.item ->> 'permission_key') is null
      or (entry.item ->> 'override_state') not in ('grant', 'deny')
      or not exists (
        select 1 from public.permissions as permission
        where permission.key = entry.item ->> 'permission_key'
      )
  ) then
    raise exception 'One of those permission adjustments is not something we can save.'
      using errcode = 'check_violation';
  end if;

  -- The packet's rule, restated where it would be broken: no domain enforces "Assigned work only" yet, so
  -- the only scope this command will store is 'all'. A caller asking for anything else is refused here
  -- rather than by the scope trigger, which cannot explain itself as clearly.
  if exists (
    select 1
    from jsonb_array_elements(desired_overrides) as entry(item)
    where coalesce(entry.item ->> 'access_scope', 'all') <> 'all'
  ) then
    raise exception 'Assigned-only access is not available yet.' using errcode = 'check_violation';
  end if;

  if exists (
    select entry.item ->> 'permission_key'
    from jsonb_array_elements(desired_overrides) as entry(item)
    group by entry.item ->> 'permission_key'
    having count(*) > 1
  ) then
    raise exception 'The same permission was adjusted twice in one save.' using errcode = 'check_violation';
  end if;

  -- Added and removed are worked out against what is stored right now, before anything is written. A
  -- grant that becomes a deny appears in both lists, which is the truth: one adjustment left, another came.
  -- The wanted set is read straight out of the argument each time rather than staged in a temporary table:
  -- these are a handful of rows per member, and a temporary table on a transaction-pooled connection is
  -- catalog churn nobody asked for.
  select
    coalesce(array_agg(distinct changed.permission_key) filter (where changed.direction = 'added'), '{}'),
    coalesce(array_agg(distinct changed.permission_key) filter (where changed.direction = 'removed'), '{}')
  into added_keys, removed_keys
  from (
    select entry.item ->> 'permission_key' as permission_key, 'added' as direction
    from jsonb_array_elements(desired_overrides) as entry(item)
    where not exists (
      select 1
      from public.organization_member_permission_overrides as existing
      where existing.organization_id = target_organization_id
        and existing.user_id = target_user_id
        and existing.permission_key = entry.item ->> 'permission_key'
        and existing.override_state = entry.item ->> 'override_state'
    )
    union all
    select existing.permission_key, 'removed'
    from public.organization_member_permission_overrides as existing
    where existing.organization_id = target_organization_id
      and existing.user_id = target_user_id
      and not exists (
        select 1
        from jsonb_array_elements(desired_overrides) as entry(item)
        where entry.item ->> 'permission_key' = existing.permission_key
          and entry.item ->> 'override_state' = existing.override_state
      )
  ) as changed;

  -- Adjustments the save left out are gone. One that only changed sides is left to the upsert below, so a
  -- grant becoming a deny never passes through a moment of having no adjustment at all.
  delete from public.organization_member_permission_overrides as override
  where override.organization_id = target_organization_id
    and override.user_id = target_user_id
    and not exists (
      select 1
      from jsonb_array_elements(desired_overrides) as entry(item)
      where entry.item ->> 'permission_key' = override.permission_key
    );

  insert into public.organization_member_permission_overrides (
    organization_id, user_id, permission_key, override_state, access_scope
  )
  select
    target_organization_id,
    target_user_id,
    entry.item ->> 'permission_key',
    entry.item ->> 'override_state',
    'all'
  from jsonb_array_elements(desired_overrides) as entry(item)
  on conflict (organization_id, user_id, permission_key) do update
  set override_state = excluded.override_state,
      access_scope = excluded.access_scope,
      updated_at = now();

  -- Nothing moved, so nothing is recorded and no editor is invalidated. Saving an unchanged form is not an
  -- access change, and a history full of "changed nothing" lines is a history nobody reads.
  if array_length(added_keys, 1) is null and array_length(removed_keys, 1) is null then
    return membership;
  end if;

  update public.organization_members as membership_row
  set access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.permissions_changed', 'member', actor_user_id, target_user_id,
    jsonb_strip_nulls(
      jsonb_build_object(
        'added_permissions',
          case when array_length(added_keys, 1) is null then null else to_jsonb(added_keys) end,
        'removed_permissions',
          case when array_length(removed_keys, 1) is null then null else to_jsonb(removed_keys) end
      )
    )
  );

  return membership;
end;
$$;

comment on function public.save_team_member_permissions(uuid, uuid, uuid, jsonb, integer) is
  'Replaces one member''s individual permission adjustments with the set the screen saved, and records what '
  'actually moved as a single history line. Refuses assigned scope, which no domain enforces yet.';

revoke all on function public.save_team_member_permissions(uuid, uuid, uuid, jsonb, integer)
  from public, anon, authenticated;
grant execute on function public.save_team_member_permissions(uuid, uuid, uuid, jsonb, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Member details
-- ---------------------------------------------------------------------------

-- Three of these four live on the membership, so they mean "at this business". The name does not: it lives
-- on the person's profile and follows them everywhere, which is why a null name means "leave it alone"
-- rather than "clear it". The other three clear on null, because a work phone can genuinely be removed.
create or replace function public.update_team_member_profile(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  new_full_name text,
  new_work_phone text,
  new_job_title text,
  new_schedule_color text,
  expected_profile_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  current_full_name text;
  clean_full_name text;
  clean_work_phone text;
  clean_job_title text;
  clean_schedule_color text;
  changed_fields text[] := '{}'::text[];
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );
  perform private.assert_membership_is_editable(membership);

  if expected_profile_revision is null or expected_profile_revision <> membership.profile_revision then
    raise exception 'Someone else changed this person''s details while you were editing.'
      using errcode = 'serialization_failure';
  end if;

  -- Blank and absent are the same intention from a form, so both arrive here as null.
  clean_full_name := nullif(btrim(coalesce(new_full_name, '')), '');
  clean_work_phone := nullif(btrim(coalesce(new_work_phone, '')), '');
  clean_job_title := nullif(btrim(coalesce(new_job_title, '')), '');
  clean_schedule_color := nullif(btrim(coalesce(new_schedule_color, '')), '');

  select profile.full_name into current_full_name
  from public.profiles as profile
  where profile.id = target_user_id;

  if clean_full_name is not null and clean_full_name is distinct from current_full_name then
    if char_length(clean_full_name) > 160 then
      raise exception 'That name is too long.' using errcode = 'check_violation';
    end if;

    update public.profiles as profile
    set full_name = clean_full_name,
        updated_at = now()
    where profile.id = target_user_id;

    changed_fields := changed_fields || 'full_name';
  end if;

  if clean_work_phone is distinct from membership.work_phone then
    changed_fields := changed_fields || 'work_phone';
  end if;

  if clean_job_title is distinct from membership.job_title then
    changed_fields := changed_fields || 'job_title';
  end if;

  if clean_schedule_color is distinct from membership.schedule_color then
    changed_fields := changed_fields || 'schedule_color';
  end if;

  -- Saving an unchanged form changes nothing, records nothing, and invalidates nobody's open editor.
  if array_length(changed_fields, 1) is null then
    return membership;
  end if;

  update public.organization_members as membership_row
  set work_phone = clean_work_phone,
      job_title = clean_job_title,
      schedule_color = clean_schedule_color,
      profile_revision = membership_row.profile_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.profile_updated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('changed_fields', to_jsonb(changed_fields))
  );

  return membership;
end;
$$;

comment on function public.update_team_member_profile(uuid, uuid, uuid, text, text, text, text, integer) is
  'Saves one member''s business details. Work phone, job title and colour belong to this organization; the '
  'name belongs to the person, so a null name leaves it untouched instead of erasing it everywhere.';

revoke all on function public.update_team_member_profile(uuid, uuid, uuid, text, text, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.update_team_member_profile(uuid, uuid, uuid, text, text, text, text, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4. Deactivate
-- ---------------------------------------------------------------------------

-- Only an active member can be deactivated. Somebody still pending has not accepted anything yet, and the
-- honest way to stop them is to cancel their invitation, which item 3 already ships -- otherwise restoring
-- them later would have to guess whether they were meant to come back as pending or as active.
create or replace function public.deactivate_team_member(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  previous_status text;
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );

  if membership.status = 'deactivated' then
    raise exception 'That person is already deactivated.' using errcode = 'check_violation';
  end if;

  if membership.status <> 'active' then
    raise exception 'Only an active team member can be deactivated.' using errcode = 'check_violation';
  end if;

  previous_status := membership.status;

  -- The seat is freed by this write alone: private.employee_seats_used counts pending and active
  -- memberships, so nothing else has to remember to release it.
  update public.organization_members as membership_row
  set status = 'deactivated',
      deactivated_at = now(),
      status_changed_at = now(),
      status_changed_by = actor_user_id,
      access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.deactivated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('previous_status', previous_status)
  );

  return membership;
end;
$$;

comment on function public.deactivate_team_member(uuid, uuid, uuid) is
  'Takes away a member''s access and frees their seat, keeping everything they ever did. Ending their live '
  'sessions is the API''s half; the database half is that all seven membership helpers now deny them.';

revoke all on function public.deactivate_team_member(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.deactivate_team_member(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Restore
-- ---------------------------------------------------------------------------

-- The blueprint: "Restoration is blocked when no seat is available and shows the current seat count and
-- upgrade path." The block itself is here, on the one seat authority, so a restore can never be the write
-- that puts an organization over its limit.
create or replace function public.restore_team_member(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );

  if membership.status = 'removed' then
    raise exception 'A permanently removed person cannot be restored. Invite them again instead.'
      using errcode = 'check_violation';
  end if;

  if membership.status <> 'deactivated' then
    raise exception 'That person is not deactivated.' using errcode = 'check_violation';
  end if;

  -- Takes the organization's advisory lock, so two restores cannot both read the last free seat.
  perform private.assert_employee_seat_available(target_organization_id);

  update public.organization_members as membership_row
  set status = 'active',
      deactivated_at = null,
      status_changed_at = now(),
      status_changed_by = actor_user_id,
      access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.restored', 'member', actor_user_id, target_user_id,
    jsonb_build_object('restored_role', membership.role)
  );

  return membership;
end;
$$;

comment on function public.restore_team_member(uuid, uuid, uuid) is
  'Brings a deactivated member back with the role they had, taking a seat. Refused when the organization '
  'has none free. Old work assignments are not restored -- that is deliberate.';

revoke all on function public.restore_team_member(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.restore_team_member(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Permanent removal
-- ---------------------------------------------------------------------------

-- A tombstone, never a delete. 24 authorship columns point at auth.users with on delete no action, so
-- deleting the login of anybody who has ever done anything fails -- and should. The packet's Permanent
-- removal identity rule is what this command implements: the name is snapshotted now, while the profile is
-- still readable, so every quote, invoice and note that person touched keeps a name on it forever.
create or replace function public.remove_team_member(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  name_at_removal text;
begin
  -- Owner-only: "Permanent removal is available only after deactivation and requires the Owner".
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id, true
  );

  if membership.status = 'removed' then
    raise exception 'That person has already been removed.' using errcode = 'check_violation';
  end if;

  if membership.status <> 'deactivated' then
    raise exception 'Deactivate this person before removing them permanently.'
      using errcode = 'check_violation';
  end if;

  -- "An Administrator must first be demoted by the Owner." Two deliberate decisions, never one.
  if membership.role = 'admin' then
    raise exception 'Change this administrator to another role before removing them.'
      using errcode = 'check_violation';
  end if;

  select nullif(btrim(coalesce(profile.full_name, '')), '') into name_at_removal
  from public.profiles as profile
  where profile.id = target_user_id;

  -- A profile with no name still needs one here: the removed_keeps_a_name constraint refuses the row
  -- otherwise, and an unlabelled line in somebody's history is worse than a plain one.
  name_at_removal := left(coalesce(name_at_removal, 'Removed team member'), 160);

  -- The adjustments go now, not with the Auth cleanup: they grant access, and access ends here.
  delete from public.organization_member_permission_overrides as override
  where override.organization_id = target_organization_id
    and override.user_id = target_user_id;

  update public.organization_members as membership_row
  set status = 'removed',
      removed_at = now(),
      status_changed_at = now(),
      status_changed_by = actor_user_id,
      display_name_at_removal = name_at_removal,
      identity_cleanup_state = 'required',
      identity_cleanup_error = null,
      access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.removed', 'member', actor_user_id, target_user_id, '{}'::jsonb
  );

  return membership;
end;
$$;

comment on function public.remove_team_member(uuid, uuid, uuid) is
  'Owner-only permanent removal of an already-deactivated member. Keeps the row as a tombstone with a name '
  'snapshot, drops their adjustments, and marks the Auth cleanup as required for 3B''s worker.';

revoke all on function public.remove_team_member(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.remove_team_member(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 7. The identity cleanup ledger
-- ---------------------------------------------------------------------------

-- Banning the Auth account and releasing the dead email are HTTP calls to Auth, so they cannot live in the
-- transaction that removed the member. This is how the worker writes down what it managed: forward only,
-- repeatable, and with somewhere to record a failure so a stuck cleanup is visible rather than lost.
create or replace function public.mark_member_identity_revoked(
  target_organization_id uuid,
  target_user_id uuid,
  new_cleanup_state text,
  cleanup_error text default null
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  state_order constant text[] := array['not_required', 'required', 'ban_applied', 'email_released', 'done'];
  current_position integer;
  new_position integer;
begin
  select * into membership
  from public.organization_members as membership_row
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  for update;

  if not found then
    raise exception 'That team member was not found.' using errcode = 'no_data_found';
  end if;

  if membership.status <> 'removed' then
    raise exception 'Only a permanently removed person has an identity cleanup to record.'
      using errcode = 'check_violation';
  end if;

  new_position := array_position(state_order, new_cleanup_state);
  current_position := array_position(state_order, membership.identity_cleanup_state);

  if new_position is null or new_cleanup_state in ('not_required', 'required') then
    raise exception '% is not a cleanup step.', coalesce(new_cleanup_state, 'nothing')
      using errcode = 'check_violation';
  end if;

  -- Forward or standing still. A retry that reports a step already recorded is fine; a worker claiming the
  -- account was un-banned is not.
  if new_position < current_position then
    raise exception 'The identity cleanup has already gone past that step.' using errcode = 'check_violation';
  end if;

  update public.organization_members as membership_row
  set identity_cleanup_state = new_cleanup_state,
      identity_cleanup_error = cleanup_error
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  -- One history line, written the first time the cleanup finishes. The intermediate steps are plumbing and
  -- belong in the ledger column, not in a contractor's team history.
  if new_cleanup_state = 'done' and current_position < new_position then
    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
    )
    values (
      target_organization_id, 'member.identity_revoked', 'system', null, target_user_id, '{}'::jsonb
    );
  end if;

  return membership;
end;
$$;

comment on function public.mark_member_identity_revoked(uuid, uuid, text, text) is
  'Records how far the Auth cleanup after a permanent removal has got. Forward only, safe to repeat, and '
  'writes the single member.identity_revoked history line the first time it completes.';

revoke all on function public.mark_member_identity_revoked(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.mark_member_identity_revoked(uuid, uuid, text, text) to service_role;
