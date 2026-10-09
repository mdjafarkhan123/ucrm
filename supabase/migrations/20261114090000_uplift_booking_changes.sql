-- Jafar business management E2: a visitor can move or cancel their booking from a secure link, and a meeting type can
-- ask Jafar to approve each booking first.
--
-- 1. platform_meeting_types.requires_approval and change_deadline_minutes: approval mode, and how long before the
--    call the visitor's own links stop working (Jafar's deadline).
-- 2. platform_bookings becomes a booking or a request: status 'requested' (no call yet; the time is NOT reserved),
--    'booked' (it has a call; the call's own status says held, missed or cancelled), 'declined' or 'withdrawn'.
--    manage_token_hash is the SHA-256 of the secret in the visitor's emails; the secret itself is never stored.
-- 3. private.booking_open_slots can leave out one call, so a visitor moving their booking can pick a time that
--    overlaps the one they are leaving.
-- 4. public_booking_book: in approval mode it records a request instead of a call. The request becomes the Lead's
--    next action, due today.
-- 5. The visitor's link: read, open times, move, cancel. Each checks the deadline and, for a move, takes the host's
--    lock and asks booking_open_slots again, as booking does. Moving a call goes through owner_calendar_move, so the
--    old time frees, the next action follows and the reminders are rewritten for the new time.
-- 6. Jafar's side: a Lead's open requests, approve (at the asked time or another, rechecked) or decline, and the
--    booking behind a call so the server can tell the visitor when staff move or cancel it.
-- 7. Booking settings read and save the two new choices.
--
-- Nothing here sends anything; the server queues the emails. Platform owner's server only.

-- 1. Approval mode and the change deadline ----------------------------------------------------------------------

alter table public.platform_meeting_types
  add column requires_approval boolean not null default false,
  add column change_deadline_minutes integer not null default 240,
  add constraint platform_meeting_types_change_deadline_check check (change_deadline_minutes between 0 and 10080);

-- 2. Bookings and requests -------------------------------------------------------------------------------------

alter table public.platform_bookings
  alter column entry_id drop not null,
  add column relationship_id uuid references public.platform_business_relationships (id) on delete cascade,
  add column status text not null default 'booked',
  add column requested_starts_at timestamptz,
  add column requested_ends_at timestamptz,
  add column manage_token_hash text,
  add column cancel_reason text,
  add column decided_at timestamptz,
  add column decided_by_email text,
  add column updated_at timestamptz not null default now();

update public.platform_bookings b set relationship_id = e.relationship_id
from public.platform_calendar_entries e where e.id = b.entry_id;

alter table public.platform_bookings
  alter column relationship_id set not null,
  add constraint platform_bookings_status_check check (status in ('requested', 'booked', 'declined', 'withdrawn')),
  add constraint platform_bookings_shape_check check (
    (status = 'booked') = (entry_id is not null)
    and (status = 'booked' or (requested_starts_at is not null and requested_ends_at > requested_starts_at))
    and (decided_at is null) = (decided_by_email is null)
  ),
  add constraint platform_bookings_token_check check (manage_token_hash is null or manage_token_hash ~ '^[0-9a-f]{64}$'),
  add constraint platform_bookings_cancel_reason_check check (
    cancel_reason is null or (cancel_reason = btrim(cancel_reason) and char_length(cancel_reason) between 1 and 500)
  ),
  add constraint platform_bookings_token_key unique (manage_token_hash);

create trigger platform_bookings_set_updated_at
  before update on public.platform_bookings
  for each row execute function public.set_updated_at();

-- The Lead page asks for a business's open requests.
create index platform_bookings_relationship_idx on public.platform_bookings (relationship_id);

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
    'booking_requested', 'booking_request_moved', 'booking_declined', 'booking_withdrawn'
  )
);

-- 3. Open times, leaving one call out --------------------------------------------------------------------------

drop function private.booking_open_slots(uuid, timestamptz, timestamptz);

-- Times a meeting type can start within [range_from, range_to), soonest first. Respects the host's weekly hours in
-- the host's zone, the notice, how far ahead, and the gap around the host's calls and Busy blocks. ignore_entry_id
-- is a call that does not count as taken: the one a visitor is moving.
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
  -- the gap. Cancelled and closed calls free their time; so does the call being moved. Requests are not calls, so
  -- they never hold a time.
  select coalesce(range_agg(tstzrange(e.starts_at - pad, e.ends_at + pad)), '{}'::tstzmultirange)
  into taken
  from public.platform_calendar_entries e
  where e.status = 'scheduled'
    and e.owner_member_id is not distinct from t.host_member_id
    and e.id is distinct from ignore_entry_id
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

revoke all on function private.booking_open_slots(uuid, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;

-- One booking-or-change at a time per host.
create or replace function private.booking_lock_host(target_host uuid)
returns void
language sql
set search_path to 'pg_catalog'
as $$
  select pg_advisory_xact_lock(hashtextextended('platform-booking-host:' || coalesce(target_host::text, 'jafar'), 0));
$$;

revoke all on function private.booking_lock_host(uuid) from public, anon, authenticated;

-- The open request's next action: its words, due today in the owner's zone.
create or replace function private.booking_request_label(type_name text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select left('Booking request: ' || coalesce(type_name, 'call'), 200);
$$;

revoke all on function private.booking_request_label(text) from public, anon, authenticated;

-- Clears a business's next action when it is still the request's (Jafar may have replaced it by hand).
create or replace function private.booking_request_clear_next_action(
  target_relationship_id uuid,
  type_name text,
  actor text
)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  r public.platform_business_relationships%rowtype;
begin
  select * into r from public.platform_business_relationships where id = target_relationship_id for update;
  if r.next_action is distinct from private.booking_request_label(type_name) then
    return;
  end if;
  update public.platform_business_relationships
  set next_action = null, next_action_due_on = null
  where id = r.id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (r.id, 'next_action_cleared',
    jsonb_build_object('next_action', r.next_action, 'due_on', r.next_action_due_on), actor);
end;
$$;

revoke all on function private.booking_request_clear_next_action(uuid, text, text) from public, anon, authenticated;

-- What a booking looks like to its visitor and to the server sending its emails.
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
    'starts_at', coalesce(e.starts_at, b.requested_starts_at),
    'ends_at', coalesce(e.ends_at, b.requested_ends_at),
    'name', coalesce(t.name, e.title, 'Call'),
    'slug', t.slug,
    'duration_minutes', coalesce(t.duration_minutes,
      (extract(epoch from coalesce(e.ends_at, b.requested_ends_at) - coalesce(e.starts_at, b.requested_starts_at)) / 60)::int),
    'location_kind', coalesce(t.location_kind, 'phone'),
    'horizon_days', coalesce(t.horizon_days, 60),
    'host_name', coalesce(m.full_name, 'Jafar'),
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
  left join public.platform_team_members m on m.id = coalesce(e.owner_member_id, t.host_member_id)
  where b.id = target_booking_id;
$$;

revoke all on function private.booking_view(uuid) from public, anon, authenticated;

-- 4. Booking, or asking ----------------------------------------------------------------------------------------

drop function public.public_booking_book(text, timestamptz, text, text, text, text, text, text, text, text);

-- Outcome 'booked' or 'requested' with the booking's view, 'taken' when the time is no longer open, 'unavailable'
-- when the link is off. target_token_hash: the SHA-256 (hex) of the secret the server puts in the visitor's emails.
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
  target_token_hash text,
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
  label text;
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
  perform private.booking_lock_host(t.host_member_id);

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

  if t.requires_approval then
    -- A request holds no time: Jafar approves it, and the time is checked again then.
    insert into public.platform_bookings (entry_id, relationship_id, status, meeting_type_id, visitor_name,
      visitor_email, visitor_phone, visitor_time_zone, requested_starts_at, requested_ends_at, manage_token_hash)
    values (null, rel_id, 'requested', t.id, visitor_name, visitor_email, visitor_phone, target_time_zone,
      target_starts_at, slot_end, target_token_hash)
    returning id into new_booking;

    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (rel_id, 'booking_requested', jsonb_build_object(
      'booking_id', new_booking, 'title', t.name, 'starts_at', target_starts_at, 'ends_at', slot_end,
      'note', note), visitor_email);

    label := private.booking_request_label(t.name);
    perform 1 from public.platform_business_relationships where id = rel_id for update;
    update public.platform_business_relationships r
    set next_action = label,
      next_action_due_on = (now() at time zone (select p.zone from private.calendar_preferences_for(r.owner_member_id) p))::date
    where r.id = rel_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    select r.id, 'next_action_set', jsonb_build_object('next_action', r.next_action, 'due_on', r.next_action_due_on),
      visitor_email
    from public.platform_business_relationships r where r.id = rel_id;

    return jsonb_build_object('outcome', 'requested') || private.booking_view(new_booking);
  end if;

  insert into public.platform_calendar_entries (kind, relationship_id, title, notes, starts_at, ends_at,
    owner_member_id, created_by_email)
  values ('call', rel_id, t.name, note, target_starts_at, slot_end, t.host_member_id, visitor_email)
  returning id into new_entry;

  insert into public.platform_bookings (entry_id, relationship_id, status, meeting_type_id, visitor_name, visitor_email,
    visitor_phone, visitor_time_zone, manage_token_hash)
  values (new_entry, rel_id, 'booked', t.id, visitor_name, visitor_email, visitor_phone, target_time_zone,
    target_token_hash)
  returning id into new_booking;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (rel_id, 'call_booked', jsonb_build_object(
    'entry_id', new_entry, 'title', t.name, 'starts_at', target_starts_at, 'ends_at', slot_end,
    'booked_online', true), visitor_email);

  perform private.calendar_call_becomes_next_action(new_entry, visitor_email);

  return jsonb_build_object('outcome', 'booked') || private.booking_view(new_booking);
end;
$$;

-- 5. The visitor's link ----------------------------------------------------------------------------------------

-- The booking behind a link, or null.
create or replace function public.public_booking_manage(target_token_hash text)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select private.booking_view(b.id)
  from public.platform_bookings b
  where b.manage_token_hash = target_token_hash;
$$;

-- Times the visitor could move to: the same rules as booking, with their own call not counted as taken. Nothing once
-- the deadline has passed. The public link being off does not stop a visitor changing what they already booked.
create or replace function public.public_booking_manage_slots(
  target_token_hash text,
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
  from public.platform_bookings b
  cross join lateral private.booking_open_slots(b.meeting_type_id, range_from, range_to, b.entry_id) s
  where b.manage_token_hash = target_token_hash
    and b.meeting_type_id is not null
    and (private.booking_view(b.id) ->> 'can_change')::boolean
  order by s.starts_at;
$$;

-- Outcome 'moved' with the old time and the booking's view, 'taken', 'closed' (past the deadline, cancelled or
-- already held), or 'unknown'.
create or replace function public.public_booking_reschedule(target_token_hash text, target_starts_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  b public.platform_bookings%rowtype;
  t public.platform_meeting_types%rowtype;
  was jsonb;
  slot_end timestamptz;
begin
  select * into b from public.platform_bookings where manage_token_hash = target_token_hash;
  if not found or b.meeting_type_id is null then
    return jsonb_build_object('outcome', 'unknown');
  end if;
  select * into t from public.platform_meeting_types where id = b.meeting_type_id;

  perform private.booking_lock_host(t.host_member_id);
  select * into b from public.platform_bookings where id = b.id for update;
  was := private.booking_view(b.id);
  if not (was ->> 'can_change')::boolean then
    return jsonb_build_object('outcome', 'closed');
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

-- Outcome 'cancelled' with the booking's view, 'closed', or 'unknown'. A cancelled call leaves its business a
-- "Reschedule" step due today, as a missed call does; a withdrawn request takes its next action away.
create or replace function public.public_booking_cancel(target_token_hash text, target_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  b public.platform_bookings%rowtype;
  info jsonb;
  reason text := nullif(btrim(coalesce(target_reason, '')), '');
  e public.platform_calendar_entries%rowtype;
  label text;
begin
  select * into b from public.platform_bookings where manage_token_hash = target_token_hash for update;
  if not found then
    return jsonb_build_object('outcome', 'unknown');
  end if;
  info := private.booking_view(b.id);
  if not (info ->> 'can_change')::boolean then
    return jsonb_build_object('outcome', 'closed');
  end if;

  update public.platform_bookings
  set cancel_reason = left(reason, 500), status = case when status = 'requested' then 'withdrawn' else status end
  where id = b.id;

  if b.status = 'requested' then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (b.relationship_id, 'booking_withdrawn', jsonb_build_object(
      'booking_id', b.id, 'title', info ->> 'name', 'starts_at', info -> 'starts_at', 'ends_at', info -> 'ends_at',
      'reason', reason), b.visitor_email);
    perform private.booking_request_clear_next_action(b.relationship_id, info ->> 'name', b.visitor_email);
  else
    select * into e from public.platform_calendar_entries where id = b.entry_id;
    label := 'Reschedule: ' || private.calendar_call_label(e.title, info ->> 'business_name');
    perform public.owner_calendar_close_call(b.visitor_email, b.entry_id, 'cancelled', left(label, 200),
      (now() at time zone (select p.zone from private.calendar_preferences_for(e.owner_member_id) p))::date);
    if reason is not null then
      update public.platform_business_history h set details = h.details || jsonb_build_object('reason', reason,
        'by_visitor', true)
      where h.id = (
        select id from public.platform_business_history
        where relationship_id = b.relationship_id and kind = 'call_cancelled' and details ->> 'entry_id' = e.id::text
        order by occurred_at desc limit 1
      );
    end if;
  end if;

  return jsonb_build_object('outcome', 'cancelled') || private.booking_view(b.id);
end;
$$;

revoke all on function public.public_booking_book(text, timestamptz, text, text, text, text, text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.public_booking_manage(text) from public, anon, authenticated;
revoke all on function public.public_booking_manage_slots(text, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke all on function public.public_booking_reschedule(text, timestamptz) from public, anon, authenticated;
revoke all on function public.public_booking_cancel(text, text) from public, anon, authenticated;
grant execute on function public.public_booking_book(text, timestamptz, text, text, text, text, text, text, text, text,
  text) to service_role;
grant execute on function public.public_booking_manage(text) to service_role;
grant execute on function public.public_booking_manage_slots(text, timestamptz, timestamptz) to service_role;
grant execute on function public.public_booking_reschedule(text, timestamptz) to service_role;
grant execute on function public.public_booking_cancel(text, text) to service_role;

-- 6. Jafar's side ----------------------------------------------------------------------------------------------

-- A business's requests still waiting for an answer, oldest first.
create or replace function public.owner_booking_requests(target_relationship_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select coalesce(jsonb_agg(private.booking_view(b.id) order by b.created_at), '[]'::jsonb)
  from public.platform_bookings b
  where b.relationship_id = target_relationship_id and b.status = 'requested';
$$;

-- Approve a request at the time asked for, or at target_starts_at; or decline it. Outcome 'approved' or 'declined'
-- with the booking's view, 'taken' when the time is no longer open (Jafar offers another), 'closed' when the request
-- was already answered or withdrawn, or 'unknown'.
create or replace function public.owner_booking_decide(
  actor_email text,
  target_booking_id uuid,
  decision text,
  target_starts_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  b public.platform_bookings%rowtype;
  t public.platform_meeting_types%rowtype;
  wanted timestamptz;
  slot_end timestamptz;
  new_entry uuid;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if decision not in ('approve', 'decline') then
    raise exception 'Approve or decline.' using errcode = '22023';
  end if;

  select * into b from public.platform_bookings where id = target_booking_id;
  if not found then
    return jsonb_build_object('outcome', 'unknown');
  end if;
  select * into t from public.platform_meeting_types where id = b.meeting_type_id;
  perform private.booking_lock_host(t.host_member_id);
  select * into b from public.platform_bookings where id = target_booking_id for update;
  if b.status <> 'requested' then
    return jsonb_build_object('outcome', 'closed');
  end if;

  if decision = 'decline' then
    update public.platform_bookings set status = 'declined', decided_at = now(), decided_by_email = actor
    where id = b.id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (b.relationship_id, 'booking_declined', jsonb_build_object(
      'booking_id', b.id, 'title', t.name, 'starts_at', b.requested_starts_at, 'ends_at', b.requested_ends_at), actor);
    perform private.booking_request_clear_next_action(b.relationship_id, t.name, actor);
    return jsonb_build_object('outcome', 'declined') || private.booking_view(b.id);
  end if;

  -- Checked again now: something may have taken the time since the visitor asked. Jafar approving does not skip the
  -- notice, so he can offer any time the page would offer.
  wanted := coalesce(target_starts_at, b.requested_starts_at);
  select s.ends_at into slot_end
  from private.booking_open_slots(t.id, wanted, wanted + interval '1 second') s
  where s.starts_at = wanted;
  if slot_end is null then
    return jsonb_build_object('outcome', 'taken');
  end if;

  perform private.booking_request_clear_next_action(b.relationship_id, t.name, actor);

  insert into public.platform_calendar_entries (kind, relationship_id, title, starts_at, ends_at, owner_member_id,
    created_by_email)
  values ('call', b.relationship_id, t.name, wanted, slot_end, t.host_member_id, actor)
  returning id into new_entry;
  update public.platform_bookings
  set status = 'booked', entry_id = new_entry, decided_at = now(), decided_by_email = actor
  where id = b.id;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (b.relationship_id, 'call_booked', jsonb_build_object(
    'entry_id', new_entry, 'title', t.name, 'starts_at', wanted, 'ends_at', slot_end, 'booked_online', true,
    'approved', true), actor);
  perform private.calendar_call_becomes_next_action(new_entry, actor);

  return jsonb_build_object('outcome', 'approved', 'requested_starts_at', b.requested_starts_at)
    || private.booking_view(b.id);
end;
$$;

-- The visitor's booking behind a call, so a staff move or cancel can tell them; null for a call Jafar booked himself.
create or replace function public.owner_booking_for_entry(target_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select private.booking_view(b.id) from public.platform_bookings b where b.entry_id = target_entry_id;
$$;

revoke all on function public.owner_booking_requests(uuid) from public, anon, authenticated;
revoke all on function public.owner_booking_decide(text, uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.owner_booking_for_entry(uuid) from public, anon, authenticated;
grant execute on function public.owner_booking_requests(uuid) to service_role;
grant execute on function public.owner_booking_decide(text, uuid, text, timestamptz) to service_role;
grant execute on function public.owner_booking_for_entry(uuid) to service_role;

-- 7. Booking settings -------------------------------------------------------------------------------------------

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
        'buffer_minutes', t.buffer_minutes, 'slot_interval_minutes', t.slot_interval_minutes,
        'requires_approval', t.requires_approval, 'change_deadline_minutes', t.change_deadline_minutes)
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

drop function public.owner_booking_save(boolean, uuid, text, text, text, integer, integer, integer, integer, integer,
  jsonb);

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
  target_requires_approval boolean,
  target_change_deadline_minutes integer,
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
    slot_interval_minutes = target_slot_interval_minutes, requires_approval = target_requires_approval,
    change_deadline_minutes = target_change_deadline_minutes
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

revoke all on function public.owner_booking_save(boolean, uuid, text, text, text, integer, integer, integer, integer,
  integer, boolean, integer, jsonb) from public, anon, authenticated;
grant execute on function public.owner_booking_save(boolean, uuid, text, text, text, integer, integer, integer,
  integer, integer, boolean, integer, jsonb) to service_role;
