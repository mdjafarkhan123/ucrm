-- Jafar business management E1: prospects book a sales call themselves from Uplift's public booking page.
--
-- 1. platform_meeting_types: what can be booked -- a name, a length, how the call happens (a phone call for now;
--    Zoom and Google Meet come in E4/E5), its host (null is Jafar), and the rules that decide which times are
--    offered: notice, how far ahead, a gap around other meetings, and how often a time can start. Each has its own
--    public link (/book/<slug>). E1 ships one, "Discovery call"; E3 lets Jafar add more and choose hosts.
-- 2. platform_booking_hours: each host's weekly hours, in the host's own time zone (My preferences).
-- 3. platform_owner_settings.booking_enabled: the public link on or off. Off keeps every past booking.
-- 4. platform_bookings: what the visitor told us, one row per booked call on the Business Management calendar.
-- 5. private.booking_open_slots: the one place that decides which times are open (the contractor booking's
--    pattern, private.compute_form_available_slots). The host's calls and Busy blocks, widened by the gap, hide
--    time; a timed to-do does not.
-- 6. public_booking_book: the visitor's booking. It takes a lock for the host and asks booking_open_slots again for
--    the chosen time inside it, so two visitors racing for the same time cannot both win. The booking joins the one
--    Lead with the visitor's email, or starts a new Lead; the call becomes that Lead's next action and takes the
--    host's default reminders, as a call Jafar books himself does.
-- 7. Jafar's read and save for Booking settings.
--
-- Nothing here sends anything; the server queues the visitor's confirmation. Platform owner's server only.

-- 1. Meeting types ------------------------------------------------------------------------------------------------

create table public.platform_meeting_types (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  description text,
  duration_minutes integer not null default 30,
  location_kind text not null default 'phone',
  -- Null is Jafar.
  host_member_id uuid references public.platform_team_members (id) on delete set null,
  min_notice_minutes integer not null default 240,
  horizon_days integer not null default 60,
  buffer_minutes integer not null default 0,
  slot_interval_minutes integer not null default 30,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_meeting_types_slug_key unique (slug),
  constraint platform_meeting_types_slug_check check (
    slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 1 and 60
  ),
  constraint platform_meeting_types_name_check check (name = btrim(name) and char_length(name) between 1 and 120),
  constraint platform_meeting_types_description_check check (
    description is null or (description = btrim(description) and char_length(description) between 1 and 1000)
  ),
  constraint platform_meeting_types_duration_check check (duration_minutes between 10 and 240),
  constraint platform_meeting_types_location_check check (location_kind in ('phone')),
  constraint platform_meeting_types_notice_check check (min_notice_minutes between 0 and 43200),
  constraint platform_meeting_types_horizon_check check (horizon_days between 1 and 365),
  constraint platform_meeting_types_buffer_check check (buffer_minutes between 0 and 240),
  constraint platform_meeting_types_interval_check check (slot_interval_minutes in (10, 15, 20, 30, 45, 60, 90, 120))
);

comment on table public.platform_meeting_types is
  'What prospects can book with Uplift from its public booking page (Jafar business management E1). Platform owner only (service role).';

create trigger platform_meeting_types_set_updated_at
  before update on public.platform_meeting_types
  for each row execute function public.set_updated_at();

alter table public.platform_meeting_types enable row level security;
revoke all on table public.platform_meeting_types from public, anon, authenticated;
grant all on table public.platform_meeting_types to service_role;

-- 2. Weekly hours ------------------------------------------------------------------------------------------------

create table public.platform_booking_hours (
  id uuid primary key default gen_random_uuid(),
  -- Null is Jafar.
  host_member_id uuid references public.platform_team_members (id) on delete cascade,
  -- 0 is Sunday, as extract(dow ...).
  weekday smallint not null,
  starts_at_time time not null,
  ends_at_time time not null,
  constraint platform_booking_hours_weekday_check check (weekday between 0 and 6),
  constraint platform_booking_hours_time_check check (ends_at_time > starts_at_time)
);

comment on table public.platform_booking_hours is
  'Each booking host''s weekly hours, in the host''s own time zone (E1). Platform owner only (service role).';

-- The slot reader asks for one host's day; the table holds a handful of rows per host.
create index platform_booking_hours_host_idx on public.platform_booking_hours (host_member_id, weekday);

alter table public.platform_booking_hours enable row level security;
revoke all on table public.platform_booking_hours from public, anon, authenticated;
grant all on table public.platform_booking_hours to service_role;

-- 3. The public link on or off ---------------------------------------------------------------------------------

alter table public.platform_owner_settings
  add column booking_enabled boolean not null default false;

-- 4. Bookings -------------------------------------------------------------------------------------------------

create table public.platform_bookings (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.platform_calendar_entries (id) on delete cascade,
  meeting_type_id uuid references public.platform_meeting_types (id) on delete set null,
  visitor_name text not null,
  visitor_email text not null,
  visitor_phone text not null,
  -- The zone the visitor chose times in; their emails show times in it.
  visitor_time_zone text not null,
  created_at timestamptz not null default now(),
  constraint platform_bookings_entry_key unique (entry_id),
  constraint platform_bookings_name_check check (
    visitor_name = btrim(visitor_name) and char_length(visitor_name) between 1 and 120
  ),
  constraint platform_bookings_email_check check (
    visitor_email = lower(btrim(visitor_email)) and char_length(visitor_email) between 3 and 254
    and visitor_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  constraint platform_bookings_phone_check check (
    visitor_phone = btrim(visitor_phone) and char_length(visitor_phone) between 4 and 40
  ),
  constraint platform_bookings_zone_check check (char_length(visitor_time_zone) between 1 and 64)
);

comment on table public.platform_bookings is
  'What a visitor gave when booking a call on Uplift''s public booking page; one per call (E1). Platform owner only (service role).';

create index platform_bookings_meeting_type_idx
  on public.platform_bookings (meeting_type_id) where meeting_type_id is not null;

alter table public.platform_bookings enable row level security;
revoke all on table public.platform_bookings from public, anon, authenticated;
grant all on table public.platform_bookings to service_role;

-- Starting point: Jafar's Discovery call, weekdays 9 to 5 in his time zone. The link stays off until he turns it on.
insert into public.platform_meeting_types (slug, name, description, duration_minutes)
values ('discovery-call', 'Discovery call',
  'A friendly phone call to hear about your business and see whether Uplift can help.', 30);

insert into public.platform_booking_hours (host_member_id, weekday, starts_at_time, ends_at_time)
select null, d, time '09:00', time '17:00' from generate_series(1, 5) d;

-- 5. Open times ------------------------------------------------------------------------------------------------

-- Times a meeting type can start within [range_from, range_to), soonest first. Respects the host's weekly hours in
-- the host's zone, the notice, how far ahead, and the gap around the host's calls and Busy blocks.
create or replace function private.booking_open_slots(
  target_type_id uuid,
  range_from timestamptz,
  range_to timestamptz
)
returns table (starts_at timestamptz, ends_at timestamptz)
language plpgsql
stable
set search_path to 'pg_catalog', 'public'
as $$
declare
  t public.platform_meeting_types%rowtype;
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

  select p.zone into zone from private.calendar_preferences_for(t.host_member_id) p;
  earliest := greatest(range_from, now() + make_interval(mins => t.min_notice_minutes));
  latest := least(range_to, now() + make_interval(days => t.horizon_days));
  if latest <= earliest then
    return;
  end if;
  pad := make_interval(mins => t.buffer_minutes);
  len := make_interval(mins => t.duration_minutes);
  step := make_interval(mins => t.slot_interval_minutes);

  -- The host's calls still to happen and Busy blocks near the range (an entry lasts at most 24 hours), widened by
  -- the gap. Cancelled and closed calls free their time.
  select coalesce(range_agg(tstzrange(e.starts_at - pad, e.ends_at + pad)), '{}'::tstzmultirange)
  into taken
  from public.platform_calendar_entries e
  where e.status = 'scheduled'
    and e.owner_member_id is not distinct from t.host_member_id
    and e.starts_at >= earliest - interval '24 hours' - pad
    and e.starts_at < latest + len + pad;

  day := (earliest at time zone zone)::date;
  last_day := (latest at time zone zone)::date;
  while day <= last_day loop
    for h in
      select b.starts_at_time, b.ends_at_time
      from public.platform_booking_hours b
      where b.host_member_id is not distinct from t.host_member_id
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

revoke all on function private.booking_open_slots(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- 6. The public page -------------------------------------------------------------------------------------------

-- What the public page shows for a link, or null when the link is off or unknown (the page says it is not
-- available, never which).
create or replace function public.public_booking_page(target_slug text)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_build_object(
    'slug', t.slug,
    'name', t.name,
    'description', t.description,
    'duration_minutes', t.duration_minutes,
    'location_kind', t.location_kind,
    'horizon_days', t.horizon_days,
    'host_name', coalesce(m.full_name, 'Jafar')
  )
  from public.platform_meeting_types t
  join public.platform_owner_settings s on s.id and s.booking_enabled
  left join public.platform_team_members m on m.id = t.host_member_id
  where t.slug = target_slug and t.is_active;
$$;

create or replace function public.public_booking_slots(
  target_slug text,
  range_from timestamptz,
  range_to timestamptz
)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select s.starts_at, s.ends_at
  from public.platform_meeting_types t
  join public.platform_owner_settings o on o.id and o.booking_enabled
  cross join lateral private.booking_open_slots(t.id, range_from, range_to) s
  where t.slug = target_slug and t.is_active
  order by s.starts_at;
$$;

-- Outcome 'booked' with the new ids, 'taken' when the time is no longer open, 'unavailable' when the link is off.
create or replace function public.public_booking_book(
  target_slug text,
  target_starts_at timestamptz,
  target_name text,
  target_email text,
  target_phone text,
  target_time_zone text,
  target_business_name text,
  target_country_code text,
  target_trade text,
  target_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  t public.platform_meeting_types%rowtype;
  visitor_email text := lower(btrim(coalesce(target_email, '')));
  visitor_name text := btrim(coalesce(target_name, ''));
  visitor_phone text := btrim(coalesce(target_phone, ''));
  note text := nullif(btrim(coalesce(target_note, '')), '');
  slot_end timestamptz;
  rel_id uuid;
  matches integer;
  new_entry uuid;
  new_booking uuid;
  given_note constant text := 'Given when they booked a call';
begin
  perform private.calendar_check_time_zone(target_time_zone);

  select m.* into t
  from public.platform_meeting_types m
  join public.platform_owner_settings s on s.id and s.booking_enabled
  where m.slug = target_slug and m.is_active;
  if not found then
    return jsonb_build_object('outcome', 'unavailable');
  end if;

  -- One booking at a time per host: the second visitor waits here, then sees the first one's call below.
  perform pg_advisory_xact_lock(hashtextextended('platform-booking-host:' || coalesce(t.host_member_id::text, 'jafar'), 0));

  select s.ends_at into slot_end
  from private.booking_open_slots(t.id, target_starts_at, target_starts_at + interval '1 second') s
  where s.starts_at = target_starts_at;
  if slot_end is null then
    return jsonb_build_object('outcome', 'taken');
  end if;

  -- The Lead with this email, when exactly one has it (HubSpot's and Calendly's match on email). Otherwise a new
  -- Lead; possible duplicates show on its page for review, as for any Lead.
  select count(distinct c.relationship_id), min(c.relationship_id::text)::uuid into matches, rel_id
  from public.platform_business_contact_methods c
  where c.kind = 'email' and c.normalized_value = private.contact_method_value('email', visitor_email);

  if matches = 1 then
    perform 1 from public.platform_business_relationships where id = rel_id for update;
    if not exists (
      select 1 from public.platform_business_contact_methods c
      where c.relationship_id = rel_id and c.kind = 'phone'
        and c.normalized_value = private.contact_method_value('phone', visitor_phone)
    ) then
      insert into public.platform_business_contact_methods (relationship_id, kind, value, found_at, position)
      select rel_id, 'phone', visitor_phone, given_note, coalesce(max(c.position) + 1, 0)
      from public.platform_business_contact_methods c where c.relationship_id = rel_id;
    end if;
  else
    insert into public.platform_business_relationships (business_name, country_code, trade, source, source_detail,
      contact_name, owner_member_id, created_by_email)
    values (btrim(target_business_name), upper(btrim(target_country_code)), btrim(target_trade), 'contacted_us',
      'Booked a call on the booking page', visitor_name, t.host_member_id, visitor_email)
    returning id into rel_id;
    insert into public.platform_business_contact_methods (relationship_id, kind, value, found_at, position)
    values (rel_id, 'email', visitor_email, given_note, 0), (rel_id, 'phone', visitor_phone, given_note, 1);
  end if;

  insert into public.platform_calendar_entries (kind, relationship_id, title, notes, starts_at, ends_at,
    owner_member_id, created_by_email)
  values ('call', rel_id, t.name, note, target_starts_at, slot_end, t.host_member_id, visitor_email)
  returning id into new_entry;

  insert into public.platform_bookings (entry_id, meeting_type_id, visitor_name, visitor_email, visitor_phone,
    visitor_time_zone)
  values (new_entry, t.id, visitor_name, visitor_email, visitor_phone, target_time_zone)
  returning id into new_booking;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (rel_id, 'call_booked', jsonb_build_object(
    'entry_id', new_entry, 'title', t.name, 'starts_at', target_starts_at, 'ends_at', slot_end,
    'booked_online', true), visitor_email);

  perform private.calendar_call_becomes_next_action(new_entry, visitor_email);

  return jsonb_build_object(
    'outcome', 'booked',
    'booking_id', new_booking,
    'entry_id', new_entry,
    'relationship_id', rel_id,
    'starts_at', target_starts_at,
    'ends_at', slot_end,
    'name', t.name,
    'duration_minutes', t.duration_minutes,
    'location_kind', t.location_kind,
    'host_name', coalesce((select m.full_name from public.platform_team_members m where m.id = t.host_member_id), 'Jafar')
  );
end;
$$;

revoke all on function public.public_booking_page(text) from public, anon, authenticated;
revoke all on function public.public_booking_slots(text, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.public_booking_book(text, timestamptz, text, text, text, text, text, text, text, text)
  from public, anon, authenticated;

-- 7. Booking settings -------------------------------------------------------------------------------------------

-- E1 edits Jafar's one meeting type and his hours; E3 widens this to several types and hosts.
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
    'meeting_type', (
      select jsonb_build_object(
        'id', t.id, 'slug', t.slug, 'name', t.name, 'description', t.description,
        'duration_minutes', t.duration_minutes, 'location_kind', t.location_kind,
        'min_notice_minutes', t.min_notice_minutes, 'horizon_days', t.horizon_days,
        'buffer_minutes', t.buffer_minutes, 'slot_interval_minutes', t.slot_interval_minutes)
      from public.platform_meeting_types t
      where t.host_member_id is null
      order by t.created_at, t.id
      limit 1
    ),
    'hours', coalesce((
      select jsonb_agg(jsonb_build_object(
          'weekday', b.weekday,
          'start', to_char(b.starts_at_time, 'HH24:MI'),
          'end', to_char(b.ends_at_time, 'HH24:MI'))
        order by b.weekday, b.starts_at_time)
      from public.platform_booking_hours b
      where b.host_member_id is null
    ), '[]'::jsonb),
    'bookings_count', (select count(*) from public.platform_bookings)
  );
$$;

-- Saves the link switch, the meeting type and the weekly hours together. hours: [{ weekday, start: "HH:MM",
-- end: "HH:MM" }], at most four ranges a day, none overlapping.
create or replace function public.owner_booking_save(
  target_enabled boolean,
  target_type_id uuid,
  target_slug text,
  target_name text,
  target_description text,
  target_duration_minutes integer,
  target_min_notice_minutes integer,
  target_horizon_days integer,
  target_buffer_minutes integer,
  target_slot_interval_minutes integer,
  target_hours jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  item jsonb;
  ranges integer;
begin
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

  update public.platform_meeting_types
  set slug = target_slug, name = btrim(target_name), description = nullif(btrim(coalesce(target_description, '')), ''),
    duration_minutes = target_duration_minutes, min_notice_minutes = target_min_notice_minutes,
    horizon_days = target_horizon_days, buffer_minutes = target_buffer_minutes,
    slot_interval_minutes = target_slot_interval_minutes
  where id = target_type_id and host_member_id is null;
  if not found then
    raise exception 'That meeting type no longer exists.' using errcode = '22023';
  end if;

  delete from public.platform_booking_hours where host_member_id is null;
  insert into public.platform_booking_hours (host_member_id, weekday, starts_at_time, ends_at_time)
  select null, (value ->> 'weekday')::smallint, (value ->> 'start')::time, (value ->> 'end')::time
  from jsonb_array_elements(target_hours);

  if exists (
    select 1 from public.platform_booking_hours a
    join public.platform_booking_hours b
      on b.host_member_id is null and b.weekday = a.weekday and b.id <> a.id
      and a.starts_at_time < b.ends_at_time and b.starts_at_time < a.ends_at_time
    where a.host_member_id is null
  ) then
    raise exception 'Two ranges on the same day overlap.' using errcode = '22023';
  end if;
  select max(n) into ranges from (
    select count(*) n from public.platform_booking_hours where host_member_id is null group by weekday
  ) c;
  if ranges > 4 then
    raise exception 'Keep to four ranges a day.' using errcode = '22023';
  end if;

  insert into public.platform_owner_settings (id, booking_enabled) values (true, target_enabled)
  on conflict (id) do update set booking_enabled = excluded.booking_enabled;
  return public.owner_booking_settings();
end;
$$;

revoke all on function public.owner_booking_settings() from public, anon, authenticated;
revoke all on function public.owner_booking_save(boolean, uuid, text, text, text, integer, integer, integer, integer,
  integer, jsonb) from public, anon, authenticated;
