-- Team & access, part 3F: when each person can work.
--
-- Blueprint: "member availability supports a regular weekly pattern plus dated exceptions such as leave,
-- training, or temporary hours. Business Hours describe when the company operates; member availability
-- describes when that person can work. Owners and administrators manage any member's availability, and
-- members may update their own." And: "Availability guides scheduling rather than blocking it. An authorized
-- scheduler may assign an unavailable member after a clear warning."
--
-- Two decisions worth stating up front, because both are departures from the sibling table:
--
-- 1. No seeding, and no row on member creation. public.organization_business_hours seeds every organization
--    Mon-Fri 8-17 because a business always has operating hours, even unedited ones. A person does not: a
--    member with no pattern means "nobody has said", not "works nine to five". The Schedule reads the absence
--    exactly the way $lib/schedule/hours already reads an unconfigured business week -- as nothing to warn
--    about -- rather than measuring someone against a week they never agreed to. So there is no backfill here
--    and no trigger on organization_members.
--
-- 2. One band per weekday, not business hours' up-to-three periods. A person's working day is one window; the
--    lunch break a business closes for is not a fact the calendar needs about an employee. If a real case for
--    split shifts turns up, this grows a period_index the same way business hours did.

-- ---------------------------------------------------------------------------
-- 1. The section's own revision counter
-- ---------------------------------------------------------------------------

-- "Member details, Role & access, and Availability save independently... Each section has conflict protection
-- so concurrent editors cannot silently overwrite one another." organization_members already carries
-- profile_revision and access_revision for the first two sections. This is the third, counted the same way.
alter table public.organization_members
  add column if not exists availability_revision integer not null default 1
    check (availability_revision >= 1);

comment on column public.organization_members.availability_revision is
  'Bumped by every accepted availability save. The Availability section sends the value it read; a stale one '
  'conflicts instead of overwriting an edit the screen never saw.';

-- ---------------------------------------------------------------------------
-- 2. A new closed value kind for team history: which part of availability changed
-- ---------------------------------------------------------------------------

-- The allow-list stays a closed vocabulary. An availability save records which half of the section changed,
-- and those two words are the only strings this kind will accept -- no date, no reason, no name.
create or replace function private.member_access_summary_kinds_are_known(candidate jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when jsonb_typeof(candidate) <> 'object' then false
    else not exists (
      select 1
      from jsonb_each_text(candidate) as entry(summary_key, value_kind)
      where value_kind not in (
        'role', 'member_status', 'permission_key_list', 'profile_field_list', 'id', 'assignment_count',
        'availability_field_list'
      )
    )
  end;
$$;

comment on function private.member_access_summary_kinds_are_known(jsonb) is
  'True when every value in a shape''s summary_keys map names one of the known closed value kinds. None of '
  'them is free text -- that is the whole point of the allow-list.';

revoke all on function private.member_access_summary_kinds_are_known(jsonb) from public, anon, authenticated;

create or replace function private.member_access_summary_value_fits(value_kind text, candidate jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  case value_kind
    when 'role' then
      return jsonb_typeof(candidate) = 'string'
        and candidate #>> '{}' in ('owner', 'admin', 'office', 'sales', 'field', 'finance');
    when 'member_status' then
      return jsonb_typeof(candidate) = 'string'
        and candidate #>> '{}' in ('pending', 'active', 'deactivated', 'removed');
    when 'permission_key_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or not exists (
            select 1 from public.permissions as permission where permission.key = element.item #>> '{}'
          )
      );
    when 'profile_field_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or element.item #>> '{}' not in ('full_name', 'work_phone', 'job_title', 'schedule_color')
      );
    when 'availability_field_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or element.item #>> '{}' not in ('weekly_pattern', 'exceptions')
      );
    when 'id' then
      return jsonb_typeof(candidate) = 'string'
        and (candidate #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    when 'assignment_count' then
      return jsonb_typeof(candidate) = 'number'
        and (candidate #>> '{}')::numeric >= 0
        and (candidate #>> '{}')::numeric = floor((candidate #>> '{}')::numeric);
    else
      -- An unknown kind is a refusal, never a pass. A future kind must be added here on purpose.
      return false;
  end case;
end;
$$;

revoke all on function private.member_access_summary_value_fits(text, jsonb)
  from public, anon, authenticated;

insert into public.member_access_event_shapes (event_type, subject_kind, summary_keys, required_summary_keys)
values (
  'member.availability_updated', 'member',
  '{"changed": "availability_field_list"}'::jsonb,
  array['changed']
)
on conflict (event_type) do nothing;

-- ---------------------------------------------------------------------------
-- 3. The weekly pattern
-- ---------------------------------------------------------------------------
-- weekday follows Postgres extract(dow) and the Business Hours screen: 0 = Sunday .. 6 = Saturday.

create table public.organization_member_availability (
  organization_id uuid not null,
  user_id uuid not null,
  weekday smallint not null check (weekday between 0 and 6),
  is_working boolean not null default true,
  starts_at time,
  ends_at time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id, weekday),
  -- Composite, so a row can never outlive the membership it describes or drift to another organization.
  foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade,
  constraint organization_member_availability_band_check
    check (not is_working or (starts_at is not null and ends_at is not null and ends_at > starts_at))
);

comment on table public.organization_member_availability is
  'One person''s ordinary working week, seven rows or none at all. No rows means nobody has set a pattern, '
  'which the Schedule treats as "nothing to warn about" rather than as a nine-to-five default.';

create trigger organization_member_availability_set_updated_at
before update on public.organization_member_availability
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Dated exceptions
-- ---------------------------------------------------------------------------

create table public.organization_member_availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  user_id uuid not null,
  exception_date date not null,
  -- The common case is a day off, so that is the default. Custom hours are the same row with a band on it.
  is_working boolean not null default false,
  starts_at time,
  ends_at time,
  -- Free text, deliberately. This is not the audit table -- the allow-list rule belongs to
  -- organization_member_access_events, which never learns a reason. "Annual leave" is the point of the row,
  -- and a teammate reading the calendar is the audience the blueprint names.
  reason text check (reason is null or char_length(btrim(reason)) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade,
  -- One answer per person per day. A second exception for a date replaces the first rather than stacking.
  unique (organization_id, user_id, exception_date),
  constraint organization_member_availability_exceptions_band_check
    check (not is_working or (starts_at is not null and ends_at is not null and ends_at > starts_at))
);

comment on table public.organization_member_availability_exceptions is
  'Dated overrides on top of the weekly pattern: a day off, training, or a day with different hours. An '
  'exception wins over the weekly row for that date, whether or not a weekly pattern exists.';

create trigger organization_member_availability_exceptions_set_updated_at
before update on public.organization_member_availability_exceptions
for each row execute function public.set_updated_at();

-- The Schedule asks one question of this table: "for this organization, across this date window, who is
-- off?" -- so the index leads with the organization and the date, not the person.
create index organization_member_availability_exceptions_window_idx
  on public.organization_member_availability_exceptions (organization_id, exception_date, user_id);

-- ---------------------------------------------------------------------------
-- 5. Reading
-- ---------------------------------------------------------------------------

alter table public.organization_member_availability enable row level security;
alter table public.organization_member_availability_exceptions enable row level security;

-- Any active member of the organization may read the team's availability. This is calendar information, not
-- personnel information: the dispatcher who needs the warning is often an office or sales member with no
-- team.manage permission at all, and every one of these people can already see the same team's visits on the
-- Schedule. Nothing sensitive is stored here -- the reason field holds what the member chose to type on a
-- shared work calendar.
create policy "members can view team availability"
on public.organization_member_availability for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view team availability exceptions"
on public.organization_member_availability_exceptions for select to authenticated
using (private.is_organization_member(organization_id));

grant select on public.organization_member_availability to authenticated;
grant select on public.organization_member_availability_exceptions to authenticated;

-- No insert/update/delete grant at all. Every write goes through the commands below, which are the only
-- place the "owner, administrator, or yourself" rule and the revision check are enforced.
revoke insert, update, delete on public.organization_member_availability from authenticated;
revoke insert, update, delete on public.organization_member_availability_exceptions from authenticated;

-- ---------------------------------------------------------------------------
-- 6. Who may change whose availability
-- ---------------------------------------------------------------------------

-- private.authorize_team_member_command is the wrong authority here and cannot be reused: it refuses a
-- self-edit outright ("You cannot change your own access"), which is correct for a role or a permission and
-- exactly backwards for availability, where the blueprint says "members may update their own". It also
-- refuses the owner as a target, and an owner who cannot say when they work would be a strange hole. So this
-- is its own helper, with its own rule.
create or replace function private.authorize_member_availability_command(
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
  actor_role text;
  target_membership public.organization_members;
begin
  if actor_user_id is null or target_user_id is null then
    raise exception 'An availability change needs both a person acting and a person to act on.'
      using errcode = 'check_violation';
  end if;

  select membership.role into actor_role
  from public.organization_members as membership
  where membership.organization_id = target_organization_id
    and membership.user_id = actor_user_id
    and membership.status = 'active';

  if actor_role is null then
    raise exception 'Only an active member of this organization can do that.'
      using errcode = 'check_violation';
  end if;

  if actor_user_id <> target_user_id and actor_role not in ('owner', 'admin') then
    raise exception 'Only an owner or administrator can change someone else''s availability.'
      using errcode = 'check_violation';
  end if;

  -- Locked with the authority check, so no window exists between "allowed" and "changed".
  select * into target_membership
  from public.organization_members as membership
  where membership.organization_id = target_organization_id
    and membership.user_id = target_user_id
  for update;

  if not found then
    raise exception 'That team member was not found.' using errcode = 'no_data_found';
  end if;

  perform private.assert_membership_is_editable(target_membership);

  return target_membership;
end;
$$;

comment on function private.authorize_member_availability_command(uuid, uuid, uuid) is
  'The authority every availability command shares: the actor must be an active member, and may act on '
  'themselves or -- as an owner or administrator -- on anybody. Returns the target membership, locked.';

revoke all on function private.authorize_member_availability_command(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Saving the weekly pattern
-- ---------------------------------------------------------------------------

-- The whole week arrives at once, the way the Business Hours save takes the whole week: the screen reads all
-- seven rows, edits what it likes, and sends them back together, so a half-written week can never be stored.
-- A null or empty pattern clears it, which is the honest way to say "no set pattern" again.
create or replace function public.save_member_weekly_availability(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  new_pattern jsonb,
  expected_availability_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  clearing boolean;
  day_count integer;
begin
  membership := private.authorize_member_availability_command(
    target_organization_id, actor_user_id, target_user_id
  );

  if expected_availability_revision is null
    or expected_availability_revision <> membership.availability_revision then
    -- P0409, not serialization_failure: PostgREST retries 40001, so a stale save would hang pending
    -- forever instead of telling the editor to reload. Same lesson as the member-details command.
    raise exception 'Someone else changed this person''s availability while you were editing.'
      using errcode = 'P0409';
  end if;

  clearing := new_pattern is null
    or jsonb_typeof(new_pattern) <> 'array'
    or jsonb_array_length(new_pattern) = 0;

  delete from public.organization_member_availability
  where organization_id = target_organization_id
    and user_id = target_user_id;

  if not clearing then
    -- The per-row band constraint fires here: a working day without times, or one that ends before it
    -- starts, is refused rather than quietly stored.
    insert into public.organization_member_availability (
      organization_id, user_id, weekday, is_working, starts_at, ends_at
    )
    select
      target_organization_id,
      target_user_id,
      (item ->> 'weekday')::smallint,
      coalesce((item ->> 'is_working')::boolean, false),
      nullif(item ->> 'starts_at', '')::time,
      nullif(item ->> 'ends_at', '')::time
    from jsonb_array_elements(new_pattern) as item;

    select count(*) into day_count
    from public.organization_member_availability
    where organization_id = target_organization_id
      and user_id = target_user_id;

    -- Seven rows or none. A pattern covering only the days somebody happened to edit would leave the rest
    -- of the week meaning neither "off" nor "unset".
    if day_count <> 7 then
      raise exception 'A working week must cover every day.' using errcode = 'check_violation';
    end if;
  end if;

  update public.organization_members as membership_row
  set availability_revision = membership_row.availability_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.availability_updated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('changed', jsonb_build_array('weekly_pattern'))
  );

  return membership;
end;
$$;

comment on function public.save_member_weekly_availability(uuid, uuid, uuid, jsonb, integer) is
  'Replaces one member''s ordinary working week in a single step. Seven days or none; an empty pattern means '
  'nobody has said when this person works, which is not the same as saying they never do.';

revoke all on function public.save_member_weekly_availability(uuid, uuid, uuid, jsonb, integer)
  from public, anon, authenticated;
grant execute on function public.save_member_weekly_availability(uuid, uuid, uuid, jsonb, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 8. Saving and clearing a dated exception
-- ---------------------------------------------------------------------------

create or replace function public.save_member_availability_exception(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  target_date date,
  new_is_working boolean,
  new_starts_at time,
  new_ends_at time,
  new_reason text,
  expected_availability_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  clean_reason text;
begin
  membership := private.authorize_member_availability_command(
    target_organization_id, actor_user_id, target_user_id
  );

  if expected_availability_revision is null
    or expected_availability_revision <> membership.availability_revision then
    -- P0409, not serialization_failure: PostgREST retries 40001, so a stale save would hang pending
    -- forever instead of telling the editor to reload. Same lesson as the member-details command.
    raise exception 'Someone else changed this person''s availability while you were editing.'
      using errcode = 'P0409';
  end if;

  if target_date is null then
    raise exception 'An exception needs a date.' using errcode = 'check_violation';
  end if;

  clean_reason := nullif(btrim(coalesce(new_reason, '')), '');
  if clean_reason is not null and char_length(clean_reason) > 120 then
    raise exception 'That reason is too long.' using errcode = 'check_violation';
  end if;

  insert into public.organization_member_availability_exceptions (
    organization_id, user_id, exception_date, is_working, starts_at, ends_at, reason
  )
  values (
    target_organization_id, target_user_id, target_date,
    coalesce(new_is_working, false), new_starts_at, new_ends_at, clean_reason
  )
  on conflict (organization_id, user_id, exception_date) do update
  set is_working = excluded.is_working,
      starts_at = excluded.starts_at,
      ends_at = excluded.ends_at,
      reason = excluded.reason;

  update public.organization_members as membership_row
  set availability_revision = membership_row.availability_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.availability_updated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('changed', jsonb_build_array('exceptions'))
  );

  return membership;
end;
$$;

comment on function public.save_member_availability_exception(
  uuid, uuid, uuid, date, boolean, time, time, text, integer
) is
  'Adds or replaces one dated exception. One row per person per day, so saving the same date twice corrects '
  'it instead of stacking a second answer behind the first.';

revoke all on function public.save_member_availability_exception(
  uuid, uuid, uuid, date, boolean, time, time, text, integer
) from public, anon, authenticated;
grant execute on function public.save_member_availability_exception(
  uuid, uuid, uuid, date, boolean, time, time, text, integer
) to service_role;

create or replace function public.delete_member_availability_exception(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  target_exception_id uuid,
  expected_availability_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  removed_count integer;
begin
  membership := private.authorize_member_availability_command(
    target_organization_id, actor_user_id, target_user_id
  );

  if expected_availability_revision is null
    or expected_availability_revision <> membership.availability_revision then
    -- P0409, not serialization_failure: PostgREST retries 40001, so a stale save would hang pending
    -- forever instead of telling the editor to reload. Same lesson as the member-details command.
    raise exception 'Someone else changed this person''s availability while you were editing.'
      using errcode = 'P0409';
  end if;

  delete from public.organization_member_availability_exceptions
  where id = target_exception_id
    and organization_id = target_organization_id
    and user_id = target_user_id;

  get diagnostics removed_count = row_count;

  -- Removing something that is already gone changes nothing and records nothing, so a double-click on
  -- Remove cannot invalidate the editor the second time.
  if removed_count = 0 then
    return membership;
  end if;

  update public.organization_members as membership_row
  set availability_revision = membership_row.availability_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.availability_updated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('changed', jsonb_build_array('exceptions'))
  );

  return membership;
end;
$$;

comment on function public.delete_member_availability_exception(uuid, uuid, uuid, uuid, integer) is
  'Removes one dated exception, returning that date to the ordinary weekly pattern.';

revoke all on function public.delete_member_availability_exception(uuid, uuid, uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.delete_member_availability_exception(uuid, uuid, uuid, uuid, integer)
  to service_role;
