-- Jafar business management E4a: Zoom meeting types and each booking's own joining link (plan § 6: "a choice of
-- phone, Google Meet, or Zoom ... custom-link mode ... UCRM never tells the visitor they have complete video
-- details until a link has been supplied"; Calendly's and Cal.com's per-event-type location).
--
-- 1. platform_meeting_types: location_kind may be 'zoom', and video_link_mode says whether UCRM makes the meeting
--    ('automatic', once Zoom is connected -- E4b) or the host adds a link to each booking ('custom').
-- 2. platform_bookings keeps its own location_kind, taken from its type when it is made, so changing a type later
--    does not change how calls already booked happen. A video booking carries its joining link once there is one;
--    until then its emails say the details will follow. video_link_source says who made the link; a provider's
--    meeting id is kept so the meeting can be moved or cancelled with the booking (E4b).
-- 3. booking_view reports the booking's location and link; Booking settings read and save the location and mode.
-- 4. owner_booking_set_video_link: the host adds or replaces a booked call's link.
--
-- Platform owner's server only (service role).

-- 1. Meeting types --------------------------------------------------------------------------------------------------

alter table public.platform_meeting_types drop constraint platform_meeting_types_location_check;
alter table public.platform_meeting_types
  add constraint platform_meeting_types_location_check check (location_kind in ('phone', 'zoom')),
  add column video_link_mode text not null default 'automatic',
  add constraint platform_meeting_types_video_link_mode_check check (video_link_mode in ('automatic', 'custom'));

-- 2. Bookings -------------------------------------------------------------------------------------------------------

alter table public.platform_bookings
  add column location_kind text,
  add column video_join_url text,
  add column video_link_source text,
  add column video_provider_meeting_id text,
  add column video_link_set_at timestamptz;

update public.platform_bookings b
set location_kind = coalesce((select t.location_kind from public.platform_meeting_types t where t.id = b.meeting_type_id),
  'phone');

alter table public.platform_bookings
  alter column location_kind set not null,
  add constraint platform_bookings_location_check check (location_kind in ('phone', 'zoom')),
  add constraint platform_bookings_video_link_check check (
    (video_join_url is null) = (video_link_source is null)
    and (video_join_url is null or (
      location_kind <> 'phone'
      and video_join_url ~ '^https://[^\s/]+\.[^\s]+$'
      and char_length(video_join_url) <= 2048
    ))
    and video_link_source in ('provider', 'custom')
  ),
  add constraint platform_bookings_video_meeting_check check (
    video_provider_meeting_id is null or char_length(video_provider_meeting_id) between 1 and 200
  );

comment on column public.platform_bookings.location_kind is
  'How the call happens, fixed when it was booked: phone or zoom (E4a).';
comment on column public.platform_bookings.video_join_url is
  'The visitor''s joining link for a video call; null while the details are still to follow (E4a).';

-- A booking takes its type's location when it is made; public_booking_book need not name it.
create or replace function private.booking_take_location()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.location_kind is null then
    new.location_kind := coalesce(
      (select t.location_kind from public.platform_meeting_types t where t.id = new.meeting_type_id), 'phone');
  end if;
  return new;
end;
$$;

create trigger platform_bookings_take_location
  before insert on public.platform_bookings
  for each row execute function private.booking_take_location();

revoke all on function private.booking_take_location() from public, anon, authenticated;

-- 3. What the booking and the settings say --------------------------------------------------------------------------

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
    'location_kind', b.location_kind,
    'video_join_url', b.video_join_url,
    'video_link_source', b.video_link_source,
    'video_link_mode', coalesce(t.video_link_mode, 'custom'),
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
          'video_link_mode', t.video_link_mode,
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

drop function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb, integer[]);

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
  target_visitor_reminder_minutes integer[],
  target_location_kind text,
  target_video_link_mode text
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
      host_member_id, visitor_reminder_minutes, location_kind, video_link_mode)
    values (target_slug, btrim(target_name), nullif(btrim(coalesce(target_description, '')), ''),
      target_duration_minutes, target_min_notice_minutes, target_horizon_days, target_buffer_minutes,
      target_slot_interval_minutes, target_requires_approval, target_change_deadline_minutes, target_is_active,
      target_host_member_id, coalesce(target_visitor_reminder_minutes, '{}'), coalesce(target_location_kind, 'phone'),
      coalesce(target_video_link_mode, 'automatic'))
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
      visitor_reminder_minutes = coalesce(target_visitor_reminder_minutes, '{}'),
      location_kind = coalesce(target_location_kind, location_kind),
      video_link_mode = coalesce(target_video_link_mode, video_link_mode)
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
  integer, boolean, integer, boolean, uuid, jsonb, integer[], text, text) from public, anon, authenticated;
grant execute on function public.owner_booking_save_type(uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, boolean, uuid, jsonb, integer[], text, text) to service_role;

-- 4. The host adds or replaces a call's link --------------------------------------------------------------------------

-- 'set' with the booking and the link it replaced (so a replaced provider meeting can be cancelled), 'same' when the
-- link is already this one, 'phone' for a phone call, 'closed' once the call is over, cancelled or not yet approved,
-- or 'unknown' when no visitor booked this call.
create or replace function public.owner_booking_set_video_link(target_entry_id uuid, target_url text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  b public.platform_bookings%rowtype;
  e public.platform_calendar_entries%rowtype;
  url text := btrim(coalesce(target_url, ''));
begin
  select * into b from public.platform_bookings where entry_id = target_entry_id for update;
  if not found then
    return jsonb_build_object('outcome', 'unknown');
  end if;
  if b.location_kind = 'phone' then
    return jsonb_build_object('outcome', 'phone');
  end if;
  select * into e from public.platform_calendar_entries where id = target_entry_id;
  if b.status <> 'booked' or e.status <> 'scheduled' or e.ends_at <= now() then
    return jsonb_build_object('outcome', 'closed');
  end if;
  if b.video_join_url = url and b.video_link_source = 'custom' then
    return jsonb_build_object('outcome', 'same') || private.booking_view(b.id);
  end if;

  update public.platform_bookings
  set video_join_url = url, video_link_source = 'custom', video_provider_meeting_id = null, video_link_set_at = now()
  where id = b.id;

  return jsonb_build_object(
    'outcome', 'set',
    'replaced_url', b.video_join_url,
    'replaced_provider_meeting_id', b.video_provider_meeting_id
  ) || private.booking_view(b.id);
end;
$$;

revoke all on function public.owner_booking_set_video_link(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_booking_set_video_link(uuid, text) to service_role;
