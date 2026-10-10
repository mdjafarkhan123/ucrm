-- Jafar business management E2b: reminder emails to the visitor before a booked call (plan § 6: "optional reminders
-- Jafar configures"; Calendly's and Cal.com's per-event-type invitee reminders).
--
-- 1. platform_meeting_types.visitor_reminder_minutes: when each of up to three reminder emails goes out, in minutes
--    before the call. New and existing types start with one a day before; an empty list sends none.
-- 2. platform_reminders gains the 'visitor_email' channel: an email to the booking's visitor rather than to staff.
--    calendar_rebuild_entry_reminders writes them beside the staff reminders, so moving, cancelling, approving or
--    handing a call to another host rewrites them in the same transaction, and one for an old time can never go.
--    A reminder whose time has already passed when the call is booked is not written (Calendly's rule).
-- 3. Triggers rebuild a call's reminders when its booking is made or approved, and every upcoming booked call's when
--    Jafar changes a type's reminder times.
-- 4. Booking settings read and save the reminder times.
--
-- Nothing here sends anything; the email worker does. Platform owner's server only.

-- 1. Reminder times ------------------------------------------------------------------------------------------------

alter table public.platform_meeting_types
  add column visitor_reminder_minutes integer[] not null default '{1440}',
  add constraint platform_meeting_types_visitor_reminders_check check (
    cardinality(visitor_reminder_minutes) <= 3
    and visitor_reminder_minutes <@ array[15, 30, 60, 120, 240, 1440, 2880]
    and array_position(visitor_reminder_minutes, null) is null
  );

-- 2. The visitor's channel ------------------------------------------------------------------------------------------

alter table public.platform_reminders drop constraint platform_reminders_channel_check;
alter table public.platform_reminders add constraint platform_reminders_channel_check check (
  channel in ('in_app', 'email', 'visitor_email')
  and (channel <> 'visitor_email' or (entry_id is not null and recipient_member_id is null))
);

create or replace function private.calendar_rebuild_entry_reminders(target_entry_id uuid)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  e public.platform_calendar_entries%rowtype;
  rules jsonb;
begin
  delete from public.platform_reminders where entry_id = target_entry_id and sent_at is null;

  select * into e from public.platform_calendar_entries where id = target_entry_id;
  if not found or e.status <> 'scheduled' then
    return;
  end if;

  rules := coalesce(e.reminders, case when e.kind = 'call'
    then (select defaults -> 'call' from private.calendar_preferences_for(e.owner_member_id)) end);

  insert into public.platform_reminders (entry_id, channel, fire_at, recipient_member_id)
  select target_entry_id, rule->>'channel', e.starts_at - make_interval(mins => (rule->>'minutes_before')::int),
    e.owner_member_id
  from jsonb_array_elements(coalesce(rules, '[]'::jsonb)) rule
  where rule ? 'minutes_before'
    and e.starts_at - make_interval(mins => (rule->>'minutes_before')::int) > now();

  -- E2b: the visitor's own reminders, when a visitor booked this call.
  insert into public.platform_reminders (entry_id, channel, fire_at, recipient_member_id)
  select target_entry_id, 'visitor_email', e.starts_at - make_interval(mins => m.minutes), null
  from public.platform_bookings b
  join public.platform_meeting_types t on t.id = b.meeting_type_id
  cross join lateral (select distinct unnest(t.visitor_reminder_minutes) as minutes) m
  where b.entry_id = target_entry_id and b.status = 'booked'
    and e.starts_at - make_interval(mins => m.minutes) > now();
end;
$$;

-- 3. Rebuilding when a booking or a type changes ------------------------------------------------------------------

create or replace function private.booking_reminders()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_op = 'UPDATE' and old.entry_id is distinct from new.entry_id and old.entry_id is not null then
    perform private.calendar_rebuild_entry_reminders(old.entry_id);
  end if;
  if new.entry_id is not null and (
    tg_op = 'INSERT' or (new.entry_id, new.status) is distinct from (old.entry_id, old.status)
  ) then
    perform private.calendar_rebuild_entry_reminders(new.entry_id);
  end if;
  return null;
end;
$$;

create trigger platform_bookings_reminders
  after insert or update of entry_id, status on public.platform_bookings
  for each row execute function private.booking_reminders();

create or replace function private.meeting_type_reminders_changed()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  target uuid;
begin
  if new.visitor_reminder_minutes is not distinct from old.visitor_reminder_minutes then
    return null;
  end if;
  for target in
    select e.id from public.platform_bookings b
    join public.platform_calendar_entries e on e.id = b.entry_id
    where b.meeting_type_id = new.id and e.status = 'scheduled' and e.starts_at > now()
  loop
    perform private.calendar_rebuild_entry_reminders(target);
  end loop;
  return null;
end;
$$;

create trigger platform_meeting_types_visitor_reminders
  after update of visitor_reminder_minutes on public.platform_meeting_types
  for each row execute function private.meeting_type_reminders_changed();

revoke all on function private.booking_reminders() from public, anon, authenticated;
revoke all on function private.meeting_type_reminders_changed() from public, anon, authenticated;

-- 4. Booking settings ----------------------------------------------------------------------------------------------

drop function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb);

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
          'is_active', t.is_active, 'visitor_reminder_minutes', to_jsonb(t.visitor_reminder_minutes),
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
  target_host_member_ids jsonb,
  target_visitor_reminder_minutes integer[]
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
      host_member_id, visitor_reminder_minutes)
    values (target_slug, btrim(target_name), nullif(btrim(coalesce(target_description, '')), ''),
      target_duration_minutes, target_min_notice_minutes, target_horizon_days, target_buffer_minutes,
      target_slot_interval_minutes, target_requires_approval, target_change_deadline_minutes, target_is_active,
      target_host_member_id, coalesce(target_visitor_reminder_minutes, '{}'))
    returning id into saved;
  else
    update public.platform_meeting_types
    set slug = target_slug, name = btrim(target_name),
      description = nullif(btrim(coalesce(target_description, '')), ''),
      duration_minutes = target_duration_minutes, min_notice_minutes = target_min_notice_minutes,
      horizon_days = target_horizon_days, buffer_minutes = target_buffer_minutes,
      slot_interval_minutes = target_slot_interval_minutes, requires_approval = target_requires_approval,
      change_deadline_minutes = target_change_deadline_minutes, is_active = target_is_active,
      host_member_id = target_host_member_id,
      visitor_reminder_minutes = coalesce(target_visitor_reminder_minutes, '{}')
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


revoke all on function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb, integer[]) from public, anon, authenticated;
grant execute on function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb, integer[]) to service_role;
