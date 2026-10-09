-- Jafar business management E3: several meeting types, the teammates who may host each, one named default host,
-- and changing a booked call's host after checking that person is free (plan § 6, booking paragraph).
--
-- 1. platform_meeting_type_hosts: who may host each type (a null member is Jafar). The type's host_member_id is its
--    default host, who takes every new booking; it is always one of the eligible hosts. New bookings never rotate.
-- 2. private.booking_open_slots: a call being moved keeps its own host, so a visitor whose call was handed to a
--    teammate is offered that teammate's times. booking_view names the call's host, not the type's default.
-- 3. private.booking_host_free: whether a person can take a call at a fixed time -- inside their weekly hours and
--    clear of their calls and Busy blocks, widened by the type's gap. The notice rule does not apply: the time is
--    already booked.
-- 4. owner_booking_host_choices and owner_booking_change_host: the eligible hosts with whether each is free, and
--    the change itself. The server checks the actor can change calls and emails the visitor.
-- 5. Ownership (Jafar, 2026-10-09): a Lead's new owner takes the calls staff booked, but a call the prospect booked
--    online keeps its host until someone changes it. Removing a teammate returns their booked calls to Jafar with a
--    history line (the server emails each visitor) and takes them off every host list.
-- 6. The visitor's move takes the lock of the call's host.
-- 7. Booking settings: the link switch, meeting types (add, edit, turn off, delete when never booked) and each
--    host's weekly hours, each saved on its own.
--
-- Nothing here sends anything. Platform owner's server only.

-- 1. Eligible hosts ---------------------------------------------------------------------------------------------

create table public.platform_meeting_type_hosts (
  id uuid primary key default gen_random_uuid(),
  meeting_type_id uuid not null references public.platform_meeting_types (id) on delete cascade,
  -- Null is Jafar.
  member_id uuid references public.platform_team_members (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint platform_meeting_type_hosts_key unique nulls not distinct (meeting_type_id, member_id)
);

comment on table public.platform_meeting_type_hosts is
  'Who may host each Uplift meeting type; a null member is Jafar (E3). Platform owner only (service role).';

-- The unique key serves the type's list; removing a teammate looks up their rows.
create index platform_meeting_type_hosts_member_idx
  on public.platform_meeting_type_hosts (member_id) where member_id is not null;

alter table public.platform_meeting_type_hosts enable row level security;
revoke all on table public.platform_meeting_type_hosts from public, anon, authenticated;
grant all on table public.platform_meeting_type_hosts to service_role;

insert into public.platform_meeting_type_hosts (meeting_type_id, member_id)
select t.id, t.host_member_id from public.platform_meeting_types t
on conflict do nothing;

create index platform_meeting_types_host_idx
  on public.platform_meeting_types (host_member_id) where host_member_id is not null;

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed',
    'contact_approved', 'approval_withdrawn', 'sent_back', 'do_not_contact_set', 'do_not_contact_cleared',
    'deal_started', 'deal_stage_changed', 'pricing_shared', 'deal_lost', 'deal_reopened', 'deal_terms_changed',
    'deal_removed', 'deal_won', 'setup_owner_changed',
    'call_booked', 'call_moved', 'call_held', 'call_no_show', 'call_cancelled',
    'owner_changed',
    'booking_requested', 'booking_request_moved', 'booking_declined', 'booking_withdrawn',
    'call_host_changed'
  )
);

-- A person's name as the booking pages and history show it.
create or replace function private.booking_host_name(target_member_id uuid)
returns text
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select case when target_member_id is null then 'Jafar'
    else coalesce((select coalesce(m.full_name, m.email) from public.platform_team_members m
      where m.id = target_member_id), 'Jafar') end;
$$;

revoke all on function private.booking_host_name(uuid) from public, anon, authenticated;

-- 2. Open times follow the call's host ---------------------------------------------------------------------------

-- Times a meeting type can start within [range_from, range_to), soonest first. Respects the host's weekly hours in
-- the host's zone, the notice, how far ahead, and the gap around the host's calls and Busy blocks. ignore_entry_id
-- is a call being moved: it does not count as taken, and its own host's times are the ones offered. Otherwise the
-- type's default host's.
create or replace function private.booking_open_slots(
  target_type_id uuid,
  range_from timestamptz,
  range_to timestamptz,
  ignore_entry_id uuid default null
)
returns table (starts_at timestamptz, ends_at timestamptz)
language plpgsql
stable
set search_path to 'pg_catalog', 'public'
as $$
declare
  t public.platform_meeting_types%rowtype;
  host uuid;
  zone text;
  earliest timestamptz;
  latest timestamptz;
  pad interval;
  len interval;
  step interval;
  taken tstzmultirange;
  day date;
  last_day date;
  h record;
  local_start timestamp;
  slot_start timestamptz;
begin
  if range_from is null or range_to is null or range_to <= range_from then
    return;
  end if;
  if range_to - range_from > interval '45 days' then
    raise exception 'Ask for at most 45 days at a time.' using errcode = '22023';
  end if;

  select * into t from public.platform_meeting_types m where m.id = target_type_id;
  if not found or not t.is_active then
    return;
  end if;

  host := t.host_member_id;
  if ignore_entry_id is not null then
    select e.owner_member_id into host from public.platform_calendar_entries e where e.id = ignore_entry_id;
    if not found then
      host := t.host_member_id;
    end if;
  end if;

  select p.zone into zone from private.calendar_preferences_for(host) p;
  earliest := greatest(range_from, now() + make_interval(mins => t.min_notice_minutes));
  latest := least(range_to, now() + make_interval(days => t.horizon_days));
  if latest <= earliest then
    return;
  end if;
  pad := make_interval(mins => t.buffer_minutes);
  len := make_interval(mins => t.duration_minutes);
  step := make_interval(mins => t.slot_interval_minutes);

  -- The host's calls still to happen and Busy blocks near the range (an entry lasts at most 24 hours), widened by
  -- the gap. Cancelled and closed calls free their time; so does the call being moved. Requests are not calls, so
  -- they never hold a time.
  select coalesce(range_agg(tstzrange(e.starts_at - pad, e.ends_at + pad)), '{}'::tstzmultirange)
  into taken
  from public.platform_calendar_entries e
  where e.status = 'scheduled'
    and e.owner_member_id is not distinct from host
    and e.id is distinct from ignore_entry_id
    and e.starts_at >= earliest - interval '24 hours' - pad
    and e.starts_at < latest + len + pad;

  day := (earliest at time zone zone)::date;
  last_day := (latest at time zone zone)::date;
  while day <= last_day loop
    for h in
      select b.starts_at_time, b.ends_at_time
      from public.platform_booking_hours b
      where b.host_member_id is not distinct from host
        and b.weekday = extract(dow from day)::smallint
      order by b.starts_at_time
    loop
      local_start := day + h.starts_at_time;
      while local_start + len <= day + h.ends_at_time loop
        slot_start := local_start at time zone zone;
        if slot_start >= earliest and slot_start < latest
          and not (taken && tstzrange(slot_start, slot_start + len))
        then
          starts_at := slot_start;
          ends_at := slot_start + len;
          return next;
        end if;
        local_start := local_start + step;
      end loop;
    end loop;
    day := day + 1;
  end loop;
end;
$$;

-- A booked call's host is the call's owner; a request's is the type's default host, who takes it on approval.
create or replace function private.booking_view(target_booking_id uuid)
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_build_object(
    'booking_id', b.id,
    'status', b.status,
    'call_status', e.status,
    'entry_id', b.entry_id,
    'relationship_id', b.relationship_id,
    'meeting_type_id', b.meeting_type_id,
    'starts_at', coalesce(e.starts_at, b.requested_starts_at),
    'ends_at', coalesce(e.ends_at, b.requested_ends_at),
    'name', coalesce(t.name, e.title, 'Call'),
    'slug', t.slug,
    'duration_minutes', coalesce(t.duration_minutes,
      (extract(epoch from coalesce(e.ends_at, b.requested_ends_at) - coalesce(e.starts_at, b.requested_starts_at)) / 60)::int),
    'location_kind', coalesce(t.location_kind, 'phone'),
    'horizon_days', coalesce(t.horizon_days, 60),
    'host_member_id', case when e.id is not null then e.owner_member_id else t.host_member_id end,
    'host_name', private.booking_host_name(case when e.id is not null then e.owner_member_id else t.host_member_id end),
    'visitor_name', b.visitor_name,
    'visitor_email', b.visitor_email,
    'visitor_phone', b.visitor_phone,
    'visitor_time_zone', b.visitor_time_zone,
    'business_name', r.business_name,
    'change_until', coalesce(e.starts_at, b.requested_starts_at)
      - make_interval(mins => coalesce(t.change_deadline_minutes, 0)),
    'can_change', (b.status = 'requested' or (b.status = 'booked' and e.status = 'scheduled'))
      and now() < coalesce(e.starts_at, b.requested_starts_at)
        - make_interval(mins => coalesce(t.change_deadline_minutes, 0))
  )
  from public.platform_bookings b
  join public.platform_business_relationships r on r.id = b.relationship_id
  left join public.platform_calendar_entries e on e.id = b.entry_id
  left join public.platform_meeting_types t on t.id = b.meeting_type_id
  where b.id = target_booking_id;
$$;

-- 3. Is a person free at a fixed time -----------------------------------------------------------------------------

-- 'free', 'outside_hours' (not inside one of their weekly ranges, in their zone) or 'busy' (a call or Busy block of
-- theirs, widened by the type's gap, overlaps). ignore_entry_id: the call itself.
create or replace function private.booking_host_free(
  target_type_id uuid,
  target_member_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  ignore_entry_id uuid default null
)
returns text
language plpgsql
stable
set search_path to 'pg_catalog', 'public'
as $$
declare
  zone text;
  pad interval;
  local_start timestamp;
  local_end timestamp;
begin
  select p.zone into zone from private.calendar_preferences_for(target_member_id) p;
  select make_interval(mins => coalesce(max(t.buffer_minutes), 0)) into pad
  from public.platform_meeting_types t where t.id = target_type_id;
  local_start := target_starts_at at time zone zone;
  local_end := target_ends_at at time zone zone;

  if local_end::date <> local_start::date or not exists (
    select 1 from public.platform_booking_hours b
    where b.host_member_id is not distinct from target_member_id
      and b.weekday = extract(dow from local_start)::smallint
      and b.starts_at_time <= local_start::time
      and b.ends_at_time >= local_end::time
  ) then
    return 'outside_hours';
  end if;

  if exists (
    select 1 from public.platform_calendar_entries e
    where e.status = 'scheduled'
      and e.owner_member_id is not distinct from target_member_id
      and e.id is distinct from ignore_entry_id
      and e.starts_at < target_ends_at + pad
      and e.ends_at > target_starts_at - pad
  ) then
    return 'busy';
  end if;
  return 'free';
end;
$$;

revoke all on function private.booking_host_free(uuid, uuid, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;

-- 4. Changing a booked call's host -------------------------------------------------------------------------------

-- The booked call's eligible hosts, each 'current', 'free', 'outside_hours', 'busy' or 'removed'; null when the
-- call is not a visitor's booking. can_change is false once the call is over, closed, or its type is gone.
create or replace function public.owner_booking_host_choices(target_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_build_object(
    'booking', private.booking_view(b.id),
    'can_change', e.status = 'scheduled' and e.starts_at > now() and t.id is not null,
    'choices', coalesce((
      select jsonb_agg(jsonb_build_object(
          'member_id', h.member_id,
          'name', private.booking_host_name(h.member_id),
          'state', case
            when h.member_id is not distinct from e.owner_member_id then 'current'
            when h.member_id is not null and m.status is distinct from 'active' then 'removed'
            else private.booking_host_free(t.id, h.member_id, e.starts_at, e.ends_at, e.id) end)
        order by h.member_id is not null, private.booking_host_name(h.member_id))
      from public.platform_meeting_type_hosts h
      left join public.platform_team_members m on m.id = h.member_id
      where h.meeting_type_id = t.id
    ), '[]'::jsonb)
  )
  from public.platform_bookings b
  join public.platform_calendar_entries e on e.id = b.entry_id
  left join public.platform_meeting_types t on t.id = b.meeting_type_id
  where b.entry_id = target_entry_id and b.status = 'booked';
$$;

-- Hands a booked call to another eligible host when they are free then. Outcome 'changed' with the booking's view
-- and the previous host's name; 'busy' or 'outside_hours' (the new host cannot take it); 'not_eligible'; 'same';
-- 'closed' (over, closed, or its type is gone); 'retry' when the call changed hands a moment ago; 'unknown'.
-- The server checks the actor can change calls and that a teammate host still can.
create or replace function public.owner_booking_change_host(
  actor_email text,
  target_entry_id uuid,
  target_member_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  b public.platform_bookings%rowtype;
  e public.platform_calendar_entries%rowtype;
  t public.platform_meeting_types%rowtype;
  was uuid;
  state text;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;

  select * into b from public.platform_bookings where entry_id = target_entry_id and status = 'booked';
  if not found then
    return jsonb_build_object('outcome', 'unknown');
  end if;
  select * into e from public.platform_calendar_entries where id = target_entry_id;
  was := e.owner_member_id;
  if was is not distinct from target_member_id then
    return jsonb_build_object('outcome', 'same');
  end if;

  -- Both hosts' booking locks, in one order, so a visitor booking either person's time waits for this change.
  perform private.booking_lock_host(k.host)
  from (select was as host union select target_member_id) k
  order by coalesce(k.host::text, 'jafar');

  select * into e from public.platform_calendar_entries where id = target_entry_id for update;
  if e.owner_member_id is distinct from was then
    return jsonb_build_object('outcome', 'retry');
  end if;
  select * into t from public.platform_meeting_types where id = b.meeting_type_id;
  if not found or e.status <> 'scheduled' or e.starts_at <= now() then
    return jsonb_build_object('outcome', 'closed');
  end if;
  if not exists (
    select 1 from public.platform_meeting_type_hosts h
    left join public.platform_team_members m on m.id = h.member_id
    where h.meeting_type_id = t.id and h.member_id is not distinct from target_member_id
      and (h.member_id is null or m.status = 'active')
  ) then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;

  state := private.booking_host_free(t.id, target_member_id, e.starts_at, e.ends_at, e.id);
  if state <> 'free' then
    return jsonb_build_object('outcome', state);
  end if;

  -- The reminders trigger rewrites the call's reminders for the new host.
  update public.platform_calendar_entries set owner_member_id = target_member_id where id = e.id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (b.relationship_id, 'call_host_changed', jsonb_build_object(
    'entry_id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at,
    'from', private.booking_host_name(was), 'to', private.booking_host_name(target_member_id)), actor);

  return jsonb_build_object('outcome', 'changed', 'from_host_name', private.booking_host_name(was))
    || private.booking_view(b.id);
end;
$$;

-- The visitor-booked calls a teammate still hosts, so the server can email those visitors when the calls come back
-- to Jafar on the teammate's removal.
create or replace function public.owner_booking_hosted_calls(target_member_id uuid)
returns table (entry_id uuid)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select e.id
  from public.platform_calendar_entries e
  join public.platform_bookings b on b.entry_id = e.id and b.status = 'booked'
  where e.owner_member_id = target_member_id and e.status = 'scheduled' and e.kind = 'call';
$$;

revoke all on function public.owner_booking_host_choices(uuid) from public, anon, authenticated;
revoke all on function public.owner_booking_change_host(text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.owner_booking_hosted_calls(uuid) from public, anon, authenticated;
grant execute on function public.owner_booking_host_choices(uuid) to service_role;
grant execute on function public.owner_booking_change_host(text, uuid, uuid) to service_role;
grant execute on function public.owner_booking_hosted_calls(uuid) to service_role;

-- 5. Ownership ----------------------------------------------------------------------------------------------------

-- Hands the business, and every call of it still to happen or to close that staff booked, to the new owner. A call
-- a visitor booked online keeps its host (Jafar, 2026-10-09): handing it over checks the new host is free and tells
-- the visitor, so it is its own step. Writes one history line. Used by owner_lead_set_owner and a teammate's removal.
create or replace function private.relationship_change_owner(
  target_relationship_id uuid,
  target_member_id uuid,
  actor text,
  reason text default null
)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  rel public.platform_business_relationships%rowtype;
  previous public.platform_team_members%rowtype;
  member public.platform_team_members%rowtype;
begin
  select * into rel from public.platform_business_relationships where id = target_relationship_id for update;
  if not found or rel.owner_member_id is not distinct from target_member_id then
    return;
  end if;
  select * into previous from public.platform_team_members where id = rel.owner_member_id;
  select * into member from public.platform_team_members where id = target_member_id;

  update public.platform_business_relationships set owner_member_id = target_member_id where id = rel.id;
  update public.platform_calendar_entries e set owner_member_id = target_member_id
  where e.relationship_id = rel.id and e.kind = 'call' and e.status = 'scheduled'
    and e.owner_member_id is distinct from target_member_id
    and not exists (select 1 from public.platform_bookings b where b.entry_id = e.id);

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (rel.id, 'owner_changed', jsonb_strip_nulls(jsonb_build_object(
    'from', case when previous.id is null then null else coalesce(previous.full_name, previous.email) end,
    'to', case when member.id is null then null else coalesce(member.full_name, member.email) end,
    'reason', reason
  )), actor);
end;
$$;

-- A removed teammate's scheduled calls come back to Jafar -- a visitor's booked call with a history line, as a host
-- change -- and they leave every host list; a type they were the default host of falls back to Jafar. Their Busy
-- blocks stay theirs, off his calendar.
create or replace function private.team_member_removed_returns_work()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  target uuid;
  actor text := coalesce(new.removed_by_email, new.email);
  former text := coalesce(new.full_name, new.email);
begin
  if new.status <> 'removed' or old.status = 'removed' then
    return null;
  end if;
  for target in select id from public.platform_business_relationships where owner_member_id = new.id loop
    perform private.relationship_change_owner(target, null, actor, 'removed');
  end loop;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  select e.relationship_id, 'call_host_changed', jsonb_build_object(
    'entry_id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at,
    'from', former, 'to', 'Jafar', 'reason', 'removed'), actor
  from public.platform_calendar_entries e
  join public.platform_bookings b on b.entry_id = e.id
  where e.owner_member_id = new.id and e.status = 'scheduled' and e.kind = 'call' and e.relationship_id is not null;

  -- Their remaining calls: visitors' bookings, and calls of businesses someone else now owns.
  update public.platform_calendar_entries set owner_member_id = null
  where owner_member_id = new.id and status = 'scheduled' and kind = 'call';

  insert into public.platform_meeting_type_hosts (meeting_type_id, member_id)
  select t.id, null from public.platform_meeting_types t where t.host_member_id = new.id
  on conflict do nothing;
  update public.platform_meeting_types set host_member_id = null where host_member_id = new.id;
  delete from public.platform_meeting_type_hosts where member_id = new.id;
  return null;
end;
$$;

-- 6. The visitor's move follows the call's host -------------------------------------------------------------------

create or replace function public.public_booking_reschedule(target_token_hash text, target_starts_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  b public.platform_bookings%rowtype;
  t public.platform_meeting_types%rowtype;
  host uuid;
  was jsonb;
  slot_end timestamptz;
begin
  select * into b from public.platform_bookings where manage_token_hash = target_token_hash;
  if not found or b.meeting_type_id is null then
    return jsonb_build_object('outcome', 'unknown');
  end if;
  select * into t from public.platform_meeting_types where id = b.meeting_type_id;

  host := (private.booking_view(b.id) ->> 'host_member_id')::uuid;
  perform private.booking_lock_host(host);
  select * into b from public.platform_bookings where id = b.id for update;
  was := private.booking_view(b.id);
  if not (was ->> 'can_change')::boolean then
    return jsonb_build_object('outcome', 'closed');
  end if;
  -- Handed to another host a moment ago: their times may differ, so the visitor picks again.
  if (was ->> 'host_member_id')::uuid is distinct from host then
    return jsonb_build_object('outcome', 'taken');
  end if;
  if (was ->> 'starts_at')::timestamptz = target_starts_at then
    return jsonb_build_object('outcome', 'moved', 'from_starts_at', was -> 'starts_at') || was;
  end if;

  select s.ends_at into slot_end
  from private.booking_open_slots(t.id, target_starts_at, target_starts_at + interval '1 second', b.entry_id) s
  where s.starts_at = target_starts_at;
  if slot_end is null then
    return jsonb_build_object('outcome', 'taken');
  end if;

  if b.status = 'booked' then
    -- The calendar's own move: history, the next action and the reminders follow the call.
    perform public.owner_calendar_move(b.visitor_email, b.entry_id, target_starts_at, slot_end);
  else
    update public.platform_bookings
    set requested_starts_at = target_starts_at, requested_ends_at = slot_end
    where id = b.id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (b.relationship_id, 'booking_request_moved', jsonb_build_object(
      'booking_id', b.id, 'title', t.name, 'from_starts_at', b.requested_starts_at,
      'starts_at', target_starts_at, 'ends_at', slot_end), b.visitor_email);
  end if;

  return jsonb_build_object('outcome', 'moved', 'from_starts_at', was -> 'starts_at') || private.booking_view(b.id);
end;
$$;

-- 7. Booking settings ---------------------------------------------------------------------------------------------

drop function public.owner_booking_save(boolean, uuid, text, text, text, integer, integer, integer, integer, integer,
  boolean, integer, jsonb);

-- The link switch, every meeting type with its hosts, every host's weekly hours, and the people involved: Jafar
-- (null id) and each teammate who hosts a type or has hours, with their zone.
create or replace function public.owner_booking_settings()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_build_object(
    'enabled', coalesce((select s.booking_enabled from public.platform_owner_settings s where s.id), false),
    'time_zone', (select s.time_zone from public.platform_owner_settings s where s.id),
    'meeting_types', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', t.id, 'slug', t.slug, 'name', t.name, 'description', t.description,
          'duration_minutes', t.duration_minutes, 'location_kind', t.location_kind,
          'min_notice_minutes', t.min_notice_minutes, 'horizon_days', t.horizon_days,
          'buffer_minutes', t.buffer_minutes, 'slot_interval_minutes', t.slot_interval_minutes,
          'requires_approval', t.requires_approval, 'change_deadline_minutes', t.change_deadline_minutes,
          'is_active', t.is_active,
          'host_member_id', t.host_member_id,
          'host_member_ids', coalesce((
            select jsonb_agg(h.member_id order by h.member_id is not null, h.created_at)
            from public.platform_meeting_type_hosts h where h.meeting_type_id = t.id
          ), '[]'::jsonb),
          'bookings_count', (select count(*) from public.platform_bookings b where b.meeting_type_id = t.id))
        order by t.created_at, t.id)
      from public.platform_meeting_types t
    ), '[]'::jsonb),
    'hours', coalesce((
      select jsonb_agg(jsonb_build_object(
          'member_id', b.host_member_id,
          'weekday', b.weekday,
          'start', to_char(b.starts_at_time, 'HH24:MI'),
          'end', to_char(b.ends_at_time, 'HH24:MI'))
        order by b.host_member_id nulls first, b.weekday, b.starts_at_time)
      from public.platform_booking_hours b
      left join public.platform_team_members m on m.id = b.host_member_id
      where b.host_member_id is null or m.status = 'active'
    ), '[]'::jsonb),
    'people', (
      select jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', private.booking_host_name(p.id),
          'time_zone', (select c.zone from private.calendar_preferences_for(p.id) c))
        order by p.id is not null, private.booking_host_name(p.id))
      from (
        select null::uuid as id
        union
        select m.id from public.platform_team_members m
        where m.status = 'active' and (
          exists (select 1 from public.platform_meeting_type_hosts h where h.member_id = m.id)
          or exists (select 1 from public.platform_booking_hours b where b.host_member_id = m.id))
      ) p
    ),
    'bookings_count', (select count(*) from public.platform_bookings)
  );
$$;

create or replace function public.owner_booking_set_enabled(target_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  insert into public.platform_owner_settings (id, booking_enabled) values (true, target_enabled)
  on conflict (id) do update set booking_enabled = excluded.booking_enabled;
  return public.owner_booking_settings();
end;
$$;

-- Adds a meeting type (target_type_id null) or saves one. target_host_member_ids: who may host it, as a JSON list
-- of member ids with null for Jafar; the default host must be among them, and every teammate must be active (the
-- server checks they can change Leads & Deals). Returns the settings with 'saved_id'.
create or replace function public.owner_booking_save_type(
  target_type_id uuid,
  target_slug text,
  target_name text,
  target_description text,
  target_duration_minutes integer,
  target_min_notice_minutes integer,
  target_horizon_days integer,
  target_buffer_minutes integer,
  target_slot_interval_minutes integer,
  target_requires_approval boolean,
  target_change_deadline_minutes integer,
  target_is_active boolean,
  target_host_member_id uuid,
  target_host_member_ids jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  saved uuid;
  hosts uuid[];
begin
  if jsonb_typeof(target_host_member_ids) is distinct from 'array'
    or jsonb_array_length(target_host_member_ids) not between 1 and 50
    or exists (
      select 1 from jsonb_array_elements(target_host_member_ids) v
      where jsonb_typeof(v) not in ('null', 'string')
    )
  then
    raise exception 'Choose who can host this meeting.' using errcode = '22023';
  end if;
  select array_agg(distinct (v #>> '{}')::uuid) into hosts from jsonb_array_elements(target_host_member_ids) v;
  if not exists (select 1 from unnest(hosts) x(id) where x.id is not distinct from target_host_member_id) then
    raise exception 'The default host must be one of the hosts.' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(hosts) x(id)
    where x.id is not null
      and not exists (select 1 from public.platform_team_members m where m.id = x.id and m.status = 'active')
  ) then
    raise exception 'A host you chose is no longer on the team.' using errcode = '22023';
  end if;

  if target_type_id is null then
    insert into public.platform_meeting_types (slug, name, description, duration_minutes, min_notice_minutes,
      horizon_days, buffer_minutes, slot_interval_minutes, requires_approval, change_deadline_minutes, is_active,
      host_member_id)
    values (target_slug, btrim(target_name), nullif(btrim(coalesce(target_description, '')), ''),
      target_duration_minutes, target_min_notice_minutes, target_horizon_days, target_buffer_minutes,
      target_slot_interval_minutes, target_requires_approval, target_change_deadline_minutes, target_is_active,
      target_host_member_id)
    returning id into saved;
  else
    update public.platform_meeting_types
    set slug = target_slug, name = btrim(target_name),
      description = nullif(btrim(coalesce(target_description, '')), ''),
      duration_minutes = target_duration_minutes, min_notice_minutes = target_min_notice_minutes,
      horizon_days = target_horizon_days, buffer_minutes = target_buffer_minutes,
      slot_interval_minutes = target_slot_interval_minutes, requires_approval = target_requires_approval,
      change_deadline_minutes = target_change_deadline_minutes, is_active = target_is_active,
      host_member_id = target_host_member_id
    where id = target_type_id
    returning id into saved;
    if saved is null then
      raise exception 'That meeting type no longer exists.' using errcode = '22023';
    end if;
  end if;

  delete from public.platform_meeting_type_hosts h
  where h.meeting_type_id = saved
    and not exists (select 1 from unnest(hosts) x(id) where x.id is not distinct from h.member_id);
  insert into public.platform_meeting_type_hosts (meeting_type_id, member_id)
  select saved, x.id from unnest(hosts) x(id)
  on conflict do nothing;

  return public.owner_booking_settings() || jsonb_build_object('saved_id', saved);
end;
$$;

-- 'deleted', 'booked' (it has bookings; turn it off instead, so their links keep working) or 'unknown'.
create or replace function public.owner_booking_delete_type(target_type_id uuid)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform 1 from public.platform_meeting_types where id = target_type_id for update;
  if not found then
    return 'unknown';
  end if;
  if exists (select 1 from public.platform_bookings where meeting_type_id = target_type_id) then
    return 'booked';
  end if;
  delete from public.platform_meeting_types where id = target_type_id;
  return 'deleted';
end;
$$;

-- One person's weekly hours (null is Jafar), in their own zone. hours: [{ weekday, start: "HH:MM", end: "HH:MM" }],
-- at most four ranges a day, none overlapping.
create or replace function public.owner_booking_save_hours(target_member_id uuid, target_hours jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  item jsonb;
  ranges integer;
begin
  if target_member_id is not null and not exists (
    select 1 from public.platform_team_members where id = target_member_id and status = 'active'
  ) then
    raise exception 'That teammate is no longer on the team.' using errcode = '22023';
  end if;
  if jsonb_typeof(target_hours) is distinct from 'array' or jsonb_array_length(target_hours) > 28 then
    raise exception 'Give the weekly hours as a list.' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(target_hours) loop
    if jsonb_typeof(item -> 'weekday') is distinct from 'number' or (item ->> 'weekday')::int not between 0 and 6
      or coalesce(item ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or coalesce(item ->> 'end', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    then
      raise exception 'Each range needs a day, a start and an end.' using errcode = '22023';
    end if;
  end loop;

  -- One save at a time per person, as the booking lock: a visitor booking their time waits for the new hours.
  perform private.booking_lock_host(target_member_id);
  delete from public.platform_booking_hours where host_member_id is not distinct from target_member_id;
  insert into public.platform_booking_hours (host_member_id, weekday, starts_at_time, ends_at_time)
  select target_member_id, (value ->> 'weekday')::smallint, (value ->> 'start')::time, (value ->> 'end')::time
  from jsonb_array_elements(target_hours);

  if exists (
    select 1 from public.platform_booking_hours a
    join public.platform_booking_hours b
      on b.host_member_id is not distinct from target_member_id and b.weekday = a.weekday and b.id <> a.id
      and a.starts_at_time < b.ends_at_time and b.starts_at_time < a.ends_at_time
    where a.host_member_id is not distinct from target_member_id
  ) then
    raise exception 'Two ranges on the same day overlap.' using errcode = '22023';
  end if;
  select max(n) into ranges from (
    select count(*) n from public.platform_booking_hours
    where host_member_id is not distinct from target_member_id group by weekday
  ) c;
  if ranges > 4 then
    raise exception 'Keep to four ranges a day.' using errcode = '22023';
  end if;
  return public.owner_booking_settings();
end;
$$;

revoke all on function public.owner_booking_set_enabled(boolean) from public, anon, authenticated;
revoke all on function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.owner_booking_delete_type(uuid) from public, anon, authenticated;
revoke all on function public.owner_booking_save_hours(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.owner_booking_set_enabled(boolean) to service_role;
grant execute on function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb) to service_role;
grant execute on function public.owner_booking_delete_type(uuid) to service_role;
grant execute on function public.owner_booking_save_hours(uuid, jsonb) to service_role;
