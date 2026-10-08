-- Jafar business management C2: the Business Management calendar and its reminders.
--
-- 1. platform_calendar_entries: sales calls (always with a business) and Busy blocks, each with a start and an end.
--    A call has one outcome once it has passed: held, they didn't show, or cancelled. Owner is null for Jafar; D3
--    fills it for teammates. E1's public bookings will be calls with a booking attached.
-- 2. A Lead's one next action may now carry a time (next_action_at), point at the call it stands for
--    (next_action_entry_id), and its own reminders (next_action_reminders; null follows the defaults). A writer that
--    replaces the next action's words or date without setting these clears them, so every older command stays right.
-- 3. platform_reminders: each reminder that is still to come, derived from its call or next action by triggers.
--    Moving, cancelling or replacing either deletes the unsent reminders and writes new ones in the same transaction,
--    so a reminder for an old time can never be sent.
-- 4. Personal calendar choices (time zone and default reminders) on platform_owner_settings for Jafar; D3 adds the
--    same to teammates.
-- 5. Reads and commands: the calendar window, booking, moving, editing and closing a call, Busy blocks, preferences,
--    and the email worker's claim and record of due reminders.
--
-- A reminder rule is { "channel": "in_app" | "email", "minutes_before": n } for anything with a time, or
-- { "channel": ..., "days_before": n, "at": "HH:MM" } for a follow-up that only has a day (Google Calendar's
-- notification model). Nothing here sends anything; the email worker does. Platform owner's server only.

begin;

-- 1. Calls and Busy blocks ------------------------------------------------------------------------------------------

create table public.platform_calendar_entries (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  relationship_id uuid references public.platform_business_relationships (id) on delete cascade,
  -- A call's subject ("Discovery call"), or a Busy block's label ("Dentist"). Optional.
  title text,
  notes text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled',
  outcome_at timestamptz,
  outcome_by_email text,
  -- Null is Jafar. A teammate removed later falls back to Jafar when read.
  owner_member_id uuid references public.platform_team_members (id) on delete set null,
  -- This entry's own reminders; null follows the defaults for its kind.
  reminders jsonb,
  created_by_email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_calendar_entries_kind_check check (kind in ('call', 'busy')),
  constraint platform_calendar_entries_business_check check ((kind = 'call') = (relationship_id is not null)),
  constraint platform_calendar_entries_time_check check (
    ends_at > starts_at and ends_at - starts_at <= interval '24 hours'
  ),
  constraint platform_calendar_entries_status_check check (
    status in ('scheduled', 'held', 'no_show', 'cancelled')
    and (kind = 'call' or status = 'scheduled')
  ),
  constraint platform_calendar_entries_outcome_check check (
    (status = 'scheduled') = (outcome_at is null) and (outcome_at is null) = (outcome_by_email is null)
  ),
  constraint platform_calendar_entries_title_check check (
    title is null or (title = btrim(title) and char_length(title) between 1 and 200)
  ),
  constraint platform_calendar_entries_notes_check check (
    notes is null or char_length(notes) between 1 and 4000
  )
);

comment on table public.platform_calendar_entries is
  'Uplift sales calls and Busy blocks on the Business Management calendar (Jafar business management C2). Platform owner only (service role).';

-- The calendar window: everything overlapping a few weeks, found from its start.
create index platform_calendar_entries_starts_idx on public.platform_calendar_entries (starts_at);
create index platform_calendar_entries_relationship_idx
  on public.platform_calendar_entries (relationship_id, starts_at desc) where relationship_id is not null;
-- Calls that have ended and still need "How did it go?".
create index platform_calendar_entries_unclosed_idx
  on public.platform_calendar_entries (ends_at) where kind = 'call' and status = 'scheduled';
create index platform_calendar_entries_owner_idx
  on public.platform_calendar_entries (owner_member_id) where owner_member_id is not null;

create trigger platform_calendar_entries_set_updated_at
  before update on public.platform_calendar_entries
  for each row execute function public.set_updated_at();

alter table public.platform_calendar_entries enable row level security;
revoke all on table public.platform_calendar_entries from public, anon, authenticated;
grant all on table public.platform_calendar_entries to service_role;

-- 2. A next action with a time, a call, and its own reminders --------------------------------------------------------

alter table public.platform_business_relationships
  add column next_action_at timestamptz,
  add column next_action_entry_id uuid references public.platform_calendar_entries (id) on delete set null,
  add column next_action_reminders jsonb,
  add constraint platform_business_relationships_next_action_time_check check (
    (next_action_at is null or next_action_due_on is not null)
    and (next_action_entry_id is null or next_action_at is not null)
    and (next_action_reminders is null or next_action is not null)
  );

-- The calendar window and the home's "next 7 days" read dated next actions by their day.
create index platform_business_relationships_due_idx
  on public.platform_business_relationships (next_action_due_on) where next_action_due_on is not null;
create index platform_business_relationships_next_entry_idx
  on public.platform_business_relationships (next_action_entry_id) where next_action_entry_id is not null;

-- 3. Reminders ---------------------------------------------------------------------------------------------------

create table public.platform_reminders (
  id uuid primary key default gen_random_uuid(),
  -- A call's reminder, or a next action's: exactly one.
  entry_id uuid references public.platform_calendar_entries (id) on delete cascade,
  relationship_id uuid references public.platform_business_relationships (id) on delete cascade,
  channel text not null,
  fire_at timestamptz not null,
  -- Null is Jafar.
  recipient_member_id uuid references public.platform_team_members (id) on delete set null,
  -- The email worker's lease: a claim older than five minutes that never recorded an outcome is claimed again.
  claimed_at timestamptz,
  sent_at timestamptz,
  outcome text,
  created_at timestamptz not null default now(),
  constraint platform_reminders_subject_check check ((entry_id is null) <> (relationship_id is null)),
  constraint platform_reminders_channel_check check (channel in ('in_app', 'email')),
  constraint platform_reminders_outcome_check check (
    (sent_at is null) = (outcome is null) and (outcome is null or outcome in ('sent', 'late'))
  )
);

comment on table public.platform_reminders is
  'Reminders for Business Management calls and next actions, derived by triggers from their subject (C2). Platform owner only (service role).';

create index platform_reminders_due_idx on public.platform_reminders (fire_at) where sent_at is null;
create index platform_reminders_entry_idx on public.platform_reminders (entry_id) where entry_id is not null;
create index platform_reminders_relationship_idx
  on public.platform_reminders (relationship_id) where relationship_id is not null;
create index platform_reminders_recipient_idx
  on public.platform_reminders (recipient_member_id) where recipient_member_id is not null;

alter table public.platform_reminders enable row level security;
revoke all on table public.platform_reminders from public, anon, authenticated;
grant all on table public.platform_reminders to service_role;

-- 4. Personal choices ------------------------------------------------------------------------------------------------

alter table public.platform_owner_settings
  add column time_zone text,
  add column reminder_defaults jsonb;

-- The defaults Jafar approved (2026-10-08): a call emails a day before and alerts and emails 15 minutes before; a
-- follow-up with only a day alerts at 9:00 that day; a follow-up with a time alerts 15 minutes before.
create or replace function private.calendar_default_reminders()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select jsonb_build_object(
    'call', jsonb_build_array(
      jsonb_build_object('channel', 'email', 'minutes_before', 1440),
      jsonb_build_object('channel', 'in_app', 'minutes_before', 15),
      jsonb_build_object('channel', 'email', 'minutes_before', 15)
    ),
    'follow_up_day', jsonb_build_array(
      jsonb_build_object('channel', 'in_app', 'days_before', 0, 'at', '09:00')
    ),
    'follow_up_timed', jsonb_build_array(
      jsonb_build_object('channel', 'in_app', 'minutes_before', 15)
    )
  );
$$;

-- Up to five rules, each a channel and one way of saying when. `timed` asks for minutes_before rules; otherwise
-- days_before + at. Raises with a plain message rather than storing something the triggers cannot read.
create or replace function private.calendar_check_reminders(rules jsonb, timed boolean)
returns void
language plpgsql
immutable
set search_path to 'pg_catalog'
as $$
declare
  rule jsonb;
begin
  if rules is null then
    return;
  end if;
  if jsonb_typeof(rules) <> 'array' or jsonb_array_length(rules) > 5 then
    raise exception 'Choose up to five reminders.' using errcode = '22023';
  end if;
  for rule in select value from jsonb_array_elements(rules) loop
    if jsonb_typeof(rule) <> 'object' or rule->>'channel' is null or rule->>'channel' not in ('in_app', 'email') then
      raise exception 'Each reminder is an alert or an email.' using errcode = '22023';
    end if;
    if timed then
      if jsonb_typeof(rule->'minutes_before') <> 'number'
        or (rule->>'minutes_before')::numeric not between 0 and 40320
        or (rule->>'minutes_before')::numeric <> trunc((rule->>'minutes_before')::numeric)
        or rule ? 'days_before' then
        raise exception 'A reminder comes 0 minutes to 4 weeks before.' using errcode = '22023';
      end if;
    else
      if jsonb_typeof(rule->'days_before') <> 'number'
        or (rule->>'days_before')::numeric not between 0 and 28
        or (rule->>'days_before')::numeric <> trunc((rule->>'days_before')::numeric)
        or coalesce(rule->>'at', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or rule ? 'minutes_before' then
        raise exception 'A day reminder comes 0 to 28 days before, at a time of day.' using errcode = '22023';
      end if;
    end if;
  end loop;
end;
$$;

create or replace function private.calendar_check_time_zone(zone text)
returns void
language plpgsql
stable
set search_path to 'pg_catalog'
as $$
begin
  if zone is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = zone) then
    raise exception 'That time zone is not known.' using errcode = '22023';
  end if;
end;
$$;

-- Jafar's time zone and defaults, filled in where nothing was chosen yet.
create or replace function private.calendar_preferences(out zone text, out defaults jsonb)
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select
    coalesce((select s.time_zone from public.platform_owner_settings s where s.id), 'UTC'),
    private.calendar_default_reminders()
      || coalesce((select s.reminder_defaults from public.platform_owner_settings s where s.id), '{}'::jsonb);
$$;

-- The reminders a next action should have now. Nothing for a next action that stands for a call: the call's own
-- reminders cover it.
create or replace function private.calendar_rebuild_follow_up_reminders(target_relationship_id uuid)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  r public.platform_business_relationships%rowtype;
  prefs record;
  rules jsonb;
begin
  delete from public.platform_reminders where relationship_id = target_relationship_id and sent_at is null;

  select * into r from public.platform_business_relationships where id = target_relationship_id;
  if not found or r.next_action_due_on is null or r.next_action_entry_id is not null then
    return;
  end if;

  select * into prefs from private.calendar_preferences();
  rules := coalesce(
    r.next_action_reminders,
    prefs.defaults -> (case when r.next_action_at is null then 'follow_up_day' else 'follow_up_timed' end)
  );

  insert into public.platform_reminders (relationship_id, channel, fire_at)
  select target_relationship_id, x.channel, x.fire_at
  from (
    select
      rule->>'channel' as channel,
      case
        when r.next_action_at is not null and rule ? 'minutes_before'
          then r.next_action_at - make_interval(mins => (rule->>'minutes_before')::int)
        when r.next_action_at is null and rule ? 'days_before'
          then ((r.next_action_due_on - (rule->>'days_before')::int) + (rule->>'at')::time) at time zone prefs.zone
      end as fire_at
    from jsonb_array_elements(coalesce(rules, '[]'::jsonb)) rule
  ) x
  where x.fire_at is not null and x.fire_at > now();
end;
$$;

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

  rules := coalesce(e.reminders, case when e.kind = 'call' then (select defaults -> 'call' from private.calendar_preferences()) end);

  insert into public.platform_reminders (entry_id, channel, fire_at, recipient_member_id)
  select target_entry_id, rule->>'channel', e.starts_at - make_interval(mins => (rule->>'minutes_before')::int),
    e.owner_member_id
  from jsonb_array_elements(coalesce(rules, '[]'::jsonb)) rule
  where rule ? 'minutes_before'
    and e.starts_at - make_interval(mins => (rule->>'minutes_before')::int) > now();
end;
$$;

-- Older commands replace a next action's words or date without knowing about times, calls or reminders. When they
-- do, those go with the old next action. The commands below that set them on purpose say so for their own update
-- with private.next_action_explicit().
create or replace function private.next_action_explicit(on_off boolean)
returns void
language sql
set search_path to 'pg_catalog'
as $$
  select set_config('uplift.explicit_next_action', case when on_off then 'on' else 'off' end, true);
$$;

revoke all on function private.next_action_explicit(boolean) from public, anon, authenticated;

create or replace function private.relationship_next_action_follow_through()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.next_action is not null and coalesce(current_setting('uplift.explicit_next_action', true), 'off') = 'on' then
    return new;
  end if;
  if new.next_action is null then
    new.next_action_at := null;
    new.next_action_entry_id := null;
    new.next_action_reminders := null;
  elsif (new.next_action, new.next_action_due_on) is distinct from (old.next_action, old.next_action_due_on)
    and new.next_action_at is not distinct from old.next_action_at
    and new.next_action_entry_id is not distinct from old.next_action_entry_id
    and new.next_action_reminders is not distinct from old.next_action_reminders then
    new.next_action_at := null;
    new.next_action_entry_id := null;
    new.next_action_reminders := null;
  end if;
  return new;
end;
$$;

create trigger platform_business_relationships_next_action_follow_through
  before update of next_action, next_action_due_on on public.platform_business_relationships
  for each row execute function private.relationship_next_action_follow_through();

create or replace function private.relationship_next_action_reminders()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_op = 'INSERT'
    or (new.next_action, new.next_action_due_on, new.next_action_at, new.next_action_entry_id, new.next_action_reminders)
      is distinct from
       (old.next_action, old.next_action_due_on, old.next_action_at, old.next_action_entry_id, old.next_action_reminders)
  then
    perform private.calendar_rebuild_follow_up_reminders(new.id);
  end if;
  return null;
end;
$$;

create trigger platform_business_relationships_next_action_reminders
  after insert or update of next_action, next_action_due_on, next_action_at, next_action_entry_id, next_action_reminders
  on public.platform_business_relationships
  for each row execute function private.relationship_next_action_reminders();

create or replace function private.calendar_entry_reminders()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_op = 'INSERT'
    or (new.starts_at, new.status, new.reminders, new.owner_member_id)
      is distinct from (old.starts_at, old.status, old.reminders, old.owner_member_id)
  then
    perform private.calendar_rebuild_entry_reminders(new.id);
  end if;
  return null;
end;
$$;

create trigger platform_calendar_entries_reminders
  after insert or update of starts_at, status, reminders, owner_member_id on public.platform_calendar_entries
  for each row execute function private.calendar_entry_reminders();

-- A new time zone or new defaults rewrite every reminder still to come that depends on them.
create or replace function private.calendar_preferences_changed()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  target uuid;
begin
  if tg_op = 'UPDATE'
    and (new.time_zone, new.reminder_defaults) is not distinct from (old.time_zone, old.reminder_defaults) then
    return null;
  end if;
  for target in
    select r.id from public.platform_business_relationships r
    where r.next_action_due_on >= current_date - 1 and r.next_action_entry_id is null
      and (r.next_action_reminders is null or r.next_action_at is null)
  loop
    perform private.calendar_rebuild_follow_up_reminders(target);
  end loop;
  for target in
    select e.id from public.platform_calendar_entries e
    where e.status = 'scheduled' and e.reminders is null and e.kind = 'call' and e.starts_at > now()
  loop
    perform private.calendar_rebuild_entry_reminders(target);
  end loop;
  return null;
end;
$$;

create trigger platform_owner_settings_calendar_preferences
  after insert or update of time_zone, reminder_defaults on public.platform_owner_settings
  for each row execute function private.calendar_preferences_changed();

revoke all on function private.calendar_default_reminders() from public, anon, authenticated;
revoke all on function private.calendar_check_reminders(jsonb, boolean) from public, anon, authenticated;
revoke all on function private.calendar_check_time_zone(text) from public, anon, authenticated;
revoke all on function private.calendar_preferences() from public, anon, authenticated;
revoke all on function private.calendar_rebuild_follow_up_reminders(uuid) from public, anon, authenticated;
revoke all on function private.calendar_rebuild_entry_reminders(uuid) from public, anon, authenticated;

-- History and in-app reminders --------------------------------------------------------------------------------------

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed',
    'contact_approved', 'approval_withdrawn', 'sent_back', 'do_not_contact_set', 'do_not_contact_cleared',
    'deal_started', 'deal_stage_changed', 'pricing_shared', 'deal_lost', 'deal_reopened', 'deal_terms_changed',
    'deal_removed', 'deal_won', 'setup_owner_changed',
    'call_booked', 'call_moved', 'call_held', 'call_no_show', 'call_cancelled'
  )
);

-- An in-app reminder lands in the bell and opens the business it is about.
alter table public.platform_owner_notifications drop constraint platform_owner_notifications_target_kind_check;
alter table public.platform_owner_notifications add constraint platform_owner_notifications_target_kind_check check (
  target_kind in ('onboarding_application', 'organization', 'operation_attempt', 'platform', 'business_relationship')
);
create unique index platform_owner_notifications_reminder_idx
  on public.platform_owner_notifications (correlation_id) where kind = 'business_reminder';

-- 5. Reads ---------------------------------------------------------------------------------------------------------

-- Everything on the calendar between two days (inclusive) in the given time zone: calls and Busy blocks that overlap
-- it, and dated next actions that are not a call's. At most 42 days; at most 1,500 of each, flagged when cut.
create or replace function public.owner_calendar_window(from_date date, to_date date, zone text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  window_start timestamptz;
  window_end timestamptz;
  item_limit constant integer := 1500;
  result jsonb;
begin
  perform private.calendar_check_time_zone(zone);
  if from_date is null or to_date is null or to_date < from_date or to_date - from_date > 41 then
    raise exception 'Choose up to six weeks.' using errcode = '22023';
  end if;
  window_start := from_date::timestamp at time zone zone;
  window_end := (to_date + 1)::timestamp at time zone zone;

  with entries as (
    select e.*
    from public.platform_calendar_entries e
    -- Nothing lasts more than a day, so a start a day before the window bounds the overlap search.
    where e.starts_at >= window_start - interval '24 hours' and e.starts_at < window_end
      and e.ends_at > window_start and e.status <> 'cancelled'
    order by e.starts_at, e.id
    limit item_limit + 1
  ),
  follow_ups as (
    select r.id, r.business_name, r.next_action, r.next_action_due_on, r.next_action_at, r.next_action_kind
    from public.platform_business_relationships r
    where r.next_action_due_on between from_date and to_date and r.next_action_entry_id is null
    order by r.next_action_due_on, r.next_action_at nulls first, r.business_name, r.id
    limit item_limit + 1
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'relationship_id', e.relationship_id, 'business_name', b.business_name,
        'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at, 'status', e.status,
        'owner_member_id', e.owner_member_id, 'deal_stage', d.stage
      ) order by e.starts_at, e.id)
      from (select * from entries order by starts_at, id limit item_limit) e
      left join public.platform_business_relationships b on b.id = e.relationship_id
      left join public.platform_deals d on d.relationship_id = e.relationship_id and d.stage not in ('lost', 'won')
    ), '[]'::jsonb),
    'follow_ups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'business_name', f.business_name, 'next_action', f.next_action,
        'due_on', f.next_action_due_on, 'due_at', f.next_action_at,
        'first_contact', f.next_action_kind = 'first_contact', 'deal_stage', d.stage
      ) order by f.next_action_due_on, f.next_action_at nulls first, f.business_name, f.id)
      from (select * from follow_ups order by next_action_due_on, next_action_at nulls first, business_name, id limit item_limit) f
      left join public.platform_deals d on d.relationship_id = f.id and d.stage not in ('lost', 'won')
    ), '[]'::jsonb),
    'truncated', (select count(*) from entries) > item_limit or (select count(*) from follow_ups) > item_limit
  ) into result;
  return result;
end;
$function$;

-- One call or Busy block with what its dialog shows, including its own reminder choice (null: the defaults).
create or replace function public.owner_calendar_entry(target_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'id', e.id, 'kind', e.kind, 'relationship_id', e.relationship_id, 'business_name', b.business_name,
    'contact_name', b.contact_name, 'title', e.title, 'notes', e.notes, 'starts_at', e.starts_at,
    'ends_at', e.ends_at, 'status', e.status, 'outcome_at', e.outcome_at, 'outcome_by_email', e.outcome_by_email,
    'reminders', e.reminders, 'owner_member_id', e.owner_member_id,
    'is_next_action', b.next_action_entry_id = e.id, 'deal_stage', d.stage
  )
  from public.platform_calendar_entries e
  left join public.platform_business_relationships b on b.id = e.relationship_id
  left join public.platform_deals d on d.relationship_id = e.relationship_id and d.stage not in ('lost', 'won')
  where e.id = target_id;
$function$;

-- Calls that have ended and still wait for "How did it go?", oldest first.
create or replace function public.owner_calendar_unclosed_calls(limit_count integer default 20)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'count', (select count(*) from public.platform_calendar_entries
      where kind = 'call' and status = 'scheduled' and ends_at <= now()),
    'calls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'relationship_id', c.relationship_id, 'business_name', b.business_name, 'title', c.title,
        'starts_at', c.starts_at, 'ends_at', c.ends_at
      ) order by c.ends_at, c.id)
      from (
        select * from public.platform_calendar_entries
        where kind = 'call' and status = 'scheduled' and ends_at <= now()
        order by ends_at, id
        limit least(greatest(coalesce(limit_count, 20), 1), 100)
      ) c
      join public.platform_business_relationships b on b.id = c.relationship_id
    ), '[]'::jsonb)
  );
$function$;

-- 5. Commands --------------------------------------------------------------------------------------------------------

-- What the next action is called when it stands for a call.
create or replace function private.calendar_call_label(entry_title text, business text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select left(coalesce(entry_title, 'Call with ' || business), 200);
$$;

-- Makes the call the business's next action, with its day in Jafar's time zone and its start time.
create or replace function private.calendar_call_becomes_next_action(target_entry_id uuid, actor text)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  e public.platform_calendar_entries%rowtype;
  r public.platform_business_relationships%rowtype;
  label text;
  due date;
begin
  select * into e from public.platform_calendar_entries where id = target_entry_id;
  select * into r from public.platform_business_relationships where id = e.relationship_id for update;
  label := private.calendar_call_label(e.title, r.business_name);
  due := (e.starts_at at time zone (select zone from private.calendar_preferences()))::date;
  if (r.next_action, r.next_action_due_on, r.next_action_at, r.next_action_entry_id)
    is not distinct from (label, due, e.starts_at, e.id) then
    return;
  end if;
  perform private.next_action_explicit(true);
  update public.platform_business_relationships
  set next_action = label, next_action_due_on = due, next_action_at = e.starts_at, next_action_entry_id = e.id,
    next_action_kind = null, next_action_reminders = null
  where id = r.id;
  perform private.next_action_explicit(false);
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (r.id, 'next_action_set', jsonb_build_object('next_action', label, 'due_on', due, 'due_at', e.starts_at), actor);
end;
$$;

revoke all on function private.calendar_call_label(text, text) from public, anon, authenticated;
revoke all on function private.calendar_call_becomes_next_action(uuid, text) from public, anon, authenticated;

create or replace function public.owner_calendar_book_call(
  actor_email text,
  target_relationship_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  target_title text default null,
  target_notes text default null,
  target_reminders jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  new_id uuid;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  perform private.calendar_check_reminders(target_reminders, true);
  if not exists (select 1 from public.platform_business_relationships where id = target_relationship_id) then
    return null;
  end if;

  insert into public.platform_calendar_entries (kind, relationship_id, title, notes, starts_at, ends_at, reminders,
    created_by_email)
  values ('call', target_relationship_id, nullif(btrim(coalesce(target_title, '')), ''),
    nullif(btrim(coalesce(target_notes, '')), ''), target_starts_at, target_ends_at, target_reminders, actor)
  returning id into new_id;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_relationship_id, 'call_booked', jsonb_build_object(
    'entry_id', new_id, 'title', nullif(btrim(coalesce(target_title, '')), ''),
    'starts_at', target_starts_at, 'ends_at', target_ends_at), actor);

  perform private.calendar_call_becomes_next_action(new_id, actor);
  return new_id;
end;
$function$;

-- Moves a call or a Busy block. A call that is the business's next action takes its next action along.
create or replace function public.owner_calendar_move(
  actor_email text,
  target_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  e public.platform_calendar_entries%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  select * into e from public.platform_calendar_entries where id = target_id for update;
  if not found then
    return false;
  end if;
  if e.status <> 'scheduled' then
    raise exception 'This call is already closed.' using errcode = '22023';
  end if;
  if (e.starts_at, e.ends_at) = (target_starts_at, target_ends_at) then
    return true;
  end if;

  update public.platform_calendar_entries set starts_at = target_starts_at, ends_at = target_ends_at
  where id = target_id;

  if e.kind = 'call' then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (e.relationship_id, 'call_moved', jsonb_build_object(
      'entry_id', e.id, 'title', e.title, 'from_starts_at', e.starts_at, 'from_ends_at', e.ends_at,
      'starts_at', target_starts_at, 'ends_at', target_ends_at), actor);
    if exists (select 1 from public.platform_business_relationships
      where id = e.relationship_id and next_action_entry_id = e.id) then
      perform private.calendar_call_becomes_next_action(e.id, actor);
    end if;
  end if;
  return true;
end;
$function$;

-- A call's or Busy block's words and reminders. Null reminders follow the defaults.
create or replace function public.owner_calendar_edit(
  target_id uuid,
  target_title text,
  target_notes text,
  target_reminders jsonb
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  e public.platform_calendar_entries%rowtype;
begin
  perform private.calendar_check_reminders(target_reminders, true);
  select * into e from public.platform_calendar_entries where id = target_id for update;
  if not found then
    return false;
  end if;
  update public.platform_calendar_entries
  set title = nullif(btrim(coalesce(target_title, '')), ''), notes = nullif(btrim(coalesce(target_notes, '')), ''),
    reminders = target_reminders
  where id = target_id;
  -- The next action's words follow a renamed call.
  if e.kind = 'call' and exists (select 1 from public.platform_business_relationships
    where id = e.relationship_id and next_action_entry_id = e.id) then
    perform private.next_action_explicit(true);
    update public.platform_business_relationships r
    set next_action = private.calendar_call_label(nullif(btrim(coalesce(target_title, '')), ''), r.business_name)
    where r.id = e.relationship_id;
    perform private.next_action_explicit(false);
  end if;
  return true;
end;
$function$;

-- Closes a call: held, they didn't show, or cancelled. When the call was the business's next action, the next step
-- given here replaces it (none leaves the business without one; the Leads list flags that).
create or replace function public.owner_calendar_close_call(
  actor_email text,
  target_id uuid,
  outcome text,
  target_next_action text default null,
  target_due_on date default null,
  target_due_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  e public.platform_calendar_entries%rowtype;
  r public.platform_business_relationships%rowtype;
  new_action text := nullif(btrim(coalesce(target_next_action, '')), '');
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if outcome not in ('held', 'no_show', 'cancelled') then
    raise exception 'Unknown call outcome.' using errcode = '22023';
  end if;
  if (new_action is null) <> (target_due_on is null) or (target_due_at is not null and target_due_on is null) then
    raise exception 'A next action needs both what and when.' using errcode = '22023';
  end if;

  select * into e from public.platform_calendar_entries where id = target_id for update;
  if not found then
    return false;
  end if;
  if e.kind <> 'call' then
    raise exception 'Only a call has an outcome.' using errcode = '22023';
  end if;
  if e.status <> 'scheduled' then
    raise exception 'This call is already closed.' using errcode = '22023';
  end if;

  update public.platform_calendar_entries
  set status = outcome, outcome_at = now(), outcome_by_email = actor
  where id = target_id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (e.relationship_id, 'call_' || outcome, jsonb_build_object(
    'entry_id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at), actor);

  select * into r from public.platform_business_relationships where id = e.relationship_id for update;
  if r.next_action_entry_id = e.id then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (r.id, case when outcome = 'held' then 'next_action_done' else 'next_action_cleared' end,
      jsonb_build_object('next_action', r.next_action, 'due_on', r.next_action_due_on, 'due_at', r.next_action_at),
      actor);
    perform private.next_action_explicit(true);
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on, next_action_at = target_due_at,
      next_action_entry_id = null, next_action_kind = null, next_action_reminders = null
    where id = r.id;
    perform private.next_action_explicit(false);
    if new_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (r.id, 'next_action_set',
        jsonb_build_object('next_action', new_action, 'due_on', target_due_on, 'due_at', target_due_at), actor);
    end if;
  end if;
  return true;
end;
$function$;

-- A Busy block: new when target_id is null, otherwise its time and label change.
create or replace function public.owner_calendar_save_busy(
  actor_email text,
  target_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  target_title text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  saved uuid;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if target_id is null then
    insert into public.platform_calendar_entries (kind, title, starts_at, ends_at, created_by_email)
    values ('busy', nullif(btrim(coalesce(target_title, '')), ''), target_starts_at, target_ends_at, actor)
    returning id into saved;
  else
    update public.platform_calendar_entries
    set title = nullif(btrim(coalesce(target_title, '')), ''), starts_at = target_starts_at, ends_at = target_ends_at
    where id = target_id and kind = 'busy'
    returning id into saved;
  end if;
  return saved;
end;
$function$;

create or replace function public.owner_calendar_delete_busy(target_id uuid)
returns boolean
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with gone as (
    delete from public.platform_calendar_entries where id = target_id and kind = 'busy' returning id
  )
  select exists (select 1 from gone);
$function$;

-- Jafar's time zone and default reminders. Only the values given change.
create or replace function public.owner_calendar_preferences()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'time_zone', (select s.time_zone from public.platform_owner_settings s where s.id),
    'reminder_defaults', p.defaults
  )
  from private.calendar_preferences() p;
$function$;

create or replace function public.owner_calendar_save_preferences(
  target_time_zone text default null,
  target_reminder_defaults jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if target_time_zone is not null then
    perform private.calendar_check_time_zone(target_time_zone);
  end if;
  if target_reminder_defaults is not null then
    if jsonb_typeof(target_reminder_defaults) <> 'object'
      or exists (select 1 from jsonb_object_keys(target_reminder_defaults) k
        where k not in ('call', 'follow_up_day', 'follow_up_timed')) then
      raise exception 'Unknown reminder defaults.' using errcode = '22023';
    end if;
    perform private.calendar_check_reminders(target_reminder_defaults -> 'call', true);
    perform private.calendar_check_reminders(target_reminder_defaults -> 'follow_up_timed', true);
    perform private.calendar_check_reminders(target_reminder_defaults -> 'follow_up_day', false);
  end if;

  insert into public.platform_owner_settings (id, time_zone, reminder_defaults)
  values (true, target_time_zone, target_reminder_defaults)
  on conflict (id) do update
  set time_zone = coalesce(excluded.time_zone, platform_owner_settings.time_zone),
    reminder_defaults = case
      when excluded.reminder_defaults is null then platform_owner_settings.reminder_defaults
      else coalesce(platform_owner_settings.reminder_defaults, '{}'::jsonb) || excluded.reminder_defaults
    end,
    updated_at = now();

  return public.owner_calendar_preferences();
end;
$function$;

-- The Lead's next action may carry a time and its own reminders. Marking a call's next action done records the call
-- as held. Replaces the six-argument version.
drop function public.owner_lead_change(text, uuid, text, text, text, date);

create or replace function public.owner_lead_change(
  actor_email text,
  target_id uuid,
  target_status text default null,
  next_action_mode text default 'keep',
  target_next_action text default null,
  target_due_on date default null,
  target_due_at timestamptz default null,
  target_reminders jsonb default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  current_row public.platform_business_relationships%rowtype;
  new_action text := nullif(btrim(coalesce(target_next_action, '')), '');
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if next_action_mode not in ('keep', 'set', 'done', 'clear') then
    raise exception 'Unknown next action change.' using errcode = '22023';
  end if;
  if (new_action is null) <> (target_due_on is null) then
    raise exception 'A next action needs both what and when.' using errcode = '22023';
  end if;
  if target_due_at is not null and target_due_on is null then
    raise exception 'A next action''s time needs its day.' using errcode = '22023';
  end if;
  if target_reminders is not null and new_action is null then
    raise exception 'Reminders need a next action.' using errcode = '22023';
  end if;
  perform private.calendar_check_reminders(target_reminders, target_due_at is not null);
  if next_action_mode = 'set' and new_action is null then
    raise exception 'Say what the next action is.' using errcode = '22023';
  end if;
  if next_action_mode in ('keep', 'clear') and new_action is not null then
    raise exception 'A new next action is only given when setting one.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return false;
  end if;

  if next_action_mode = 'done' and current_row.next_action is null then
    raise exception 'There is no next action to mark done.' using errcode = '22023';
  end if;
  -- B3: Approved means Jafar approved contact details; only owner_lead_approve sets it.
  if target_status = 'approved' and current_row.lead_status <> 'approved' then
    raise exception 'Approve who to contact from the review queue.' using errcode = '22023';
  end if;

  if target_status is not null and target_status is distinct from current_row.lead_status then
    update public.platform_business_relationships set lead_status = target_status where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'status_changed',
      jsonb_build_object('from', current_row.lead_status, 'to', target_status), actor);
    -- Leaving Approved withdraws the approvals and, unless a next action is given now, the first-contact task.
    if current_row.lead_status = 'approved' then
      perform private.lead_withdraw_approvals(target_id, actor, 'status_changed', false);
      if next_action_mode = 'keep' then
        perform private.lead_clear_first_contact(target_id, actor);
      end if;
    end if;
  end if;

  if next_action_mode = 'clear' then
    if current_row.next_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_cleared',
        jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on,
          'due_at', current_row.next_action_at), actor);
      update public.platform_business_relationships
      set next_action = null, next_action_due_on = null, next_action_kind = null
      where id = target_id;
    end if;
  elsif next_action_mode = 'done' then
    -- A call that was the next action happened.
    if current_row.next_action_entry_id is not null then
      update public.platform_calendar_entries
      set status = 'held', outcome_at = now(), outcome_by_email = actor
      where id = current_row.next_action_entry_id and status = 'scheduled';
      if found then
        insert into public.platform_business_history (relationship_id, kind, details, actor_email)
        select target_id, 'call_held', jsonb_build_object(
          'entry_id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at), actor
        from public.platform_calendar_entries e where e.id = current_row.next_action_entry_id;
      end if;
    end if;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'next_action_done',
      jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on,
        'due_at', current_row.next_action_at), actor);
    perform private.next_action_explicit(true);
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on, next_action_at = target_due_at,
      next_action_entry_id = null, next_action_reminders = target_reminders, next_action_kind = null
    where id = target_id;
    perform private.next_action_explicit(false);
    if new_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_set',
        jsonb_build_object('next_action', new_action, 'due_on', target_due_on, 'due_at', target_due_at), actor);
    end if;
  elsif next_action_mode = 'set'
    and (new_action, target_due_on, target_due_at, target_reminders)
      is distinct from (current_row.next_action, current_row.next_action_due_on, current_row.next_action_at,
        current_row.next_action_reminders) then
    perform private.next_action_explicit(true);
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on, next_action_at = target_due_at,
      next_action_entry_id = null, next_action_reminders = target_reminders, next_action_kind = null
    where id = target_id;
    perform private.next_action_explicit(false);
    if (new_action, target_due_on, target_due_at)
      is distinct from (current_row.next_action, current_row.next_action_due_on, current_row.next_action_at) then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_set',
        jsonb_build_object('next_action', new_action, 'due_on', target_due_on, 'due_at', target_due_at), actor);
    end if;
  end if;

  return true;
end;
$function$;

-- The Lead page also carries the next action's time, its reminder choice, and the business's calls.
create or replace function public.owner_lead_page(target_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'lead', jsonb_build_object(
      'id', r.id,
      'business_name', r.business_name,
      'country_code', r.country_code,
      'trade', r.trade,
      'source', r.source,
      'source_detail', r.source_detail,
      'website', r.website,
      'website_host', r.website_host,
      'contact_name', r.contact_name,
      'fit_notes', r.fit_notes,
      'lead_status', r.lead_status,
      'next_action', r.next_action,
      'next_action_due_on', r.next_action_due_on,
      'next_action_kind', r.next_action_kind,
      'next_action_at', r.next_action_at,
      'next_action_entry_id', r.next_action_entry_id,
      'next_action_reminders', r.next_action_reminders,
      'do_not_contact', case when r.do_not_contact_at is null then null else jsonb_build_object(
        'at', r.do_not_contact_at, 'by', r.do_not_contact_by_email, 'reason', r.do_not_contact_reason
      ) end,
      'is_client', private.lead_is_client(r.id),
      'created_by_email', r.created_by_email,
      'created_at', r.created_at,
      'updated_at', r.updated_at
    ),
    'contact_methods', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', m.id, 'kind', m.kind, 'value', m.value, 'found_at', m.found_at,
            'approved_at', m.approved_at, 'whatsapp_permission', m.whatsapp_permission
          )
          order by m.position, m.created_at
        )
        from public.platform_business_contact_methods m
        where m.relationship_id = r.id and m.removed_at is null
      ),
      '[]'::jsonb
    ),
    'applications', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', a.id,
            'business_name', a.business_name,
            'main_contact_name', a.main_contact_name,
            'main_contact_email', a.main_contact_email,
            'stage', a.stage,
            'submitted_at', a.submitted_at
          )
          order by a.submitted_at desc
        )
        from public.platform_onboarding_applications a
        where a.business_relationship_id = r.id
      ),
      '[]'::jsonb
    ),
    -- Upcoming calls first, then the ten most recent past ones.
    'calls', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', c.id, 'title', c.title, 'starts_at', c.starts_at, 'ends_at', c.ends_at, 'status', c.status
          )
          order by c.status <> 'scheduled', c.starts_at
        )
        from (
          (select * from public.platform_calendar_entries
            where relationship_id = r.id and status = 'scheduled')
          union all
          (select * from public.platform_calendar_entries
            where relationship_id = r.id and status <> 'scheduled'
            order by starts_at desc limit 10)
        ) c
      ),
      '[]'::jsonb
    ),
    'last_contacted_at', (
      select max(h.occurred_at) from public.platform_business_history h
      where h.relationship_id = r.id and h.kind = 'contact' and h.contact_direction = 'outbound'
    ),
    'last_heard_from_at', (
      select max(h.occurred_at) from public.platform_business_history h
      where h.relationship_id = r.id and h.kind = 'contact' and h.contact_direction = 'inbound'
    ),
    'history', public.owner_lead_history(r.id)
  )
  from public.platform_business_relationships r
  where r.id = target_id;
$function$;

-- The email worker: reminders due now, claimed for five minutes. A reminder more than an hour late is recorded as
-- late and not sent -- a "15 minutes before" alert after the call is noise.
create or replace function public.claim_due_platform_reminders(batch_size integer default 50)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  result jsonb;
begin
  with late as (
    update public.platform_reminders
    set sent_at = now(), outcome = 'late'
    where id in (
      select id from public.platform_reminders
      where sent_at is null and fire_at < now() - interval '60 minutes'
      for update skip locked
    )
    returning id
  ),
  claimed as (
    update public.platform_reminders p
    set claimed_at = now()
    where p.id in (
      select id from public.platform_reminders
      where sent_at is null and fire_at <= now() and fire_at >= now() - interval '60 minutes'
        and (claimed_at is null or claimed_at < now() - interval '5 minutes')
      order by fire_at
      limit least(greatest(coalesce(batch_size, 50), 1), 200)
      for update skip locked
    )
    returning p.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'channel', c.channel, 'fire_at', c.fire_at, 'recipient_member_id', c.recipient_member_id,
    'recipient_email', m.email, 'recipient_name', m.full_name,
    'relationship_id', coalesce(e.relationship_id, c.relationship_id),
    'business_name', b.business_name,
    'call', case when e.id is null then null else jsonb_build_object(
      'id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at) end,
    'follow_up', case when c.relationship_id is null then null else jsonb_build_object(
      'next_action', b.next_action, 'due_on', b.next_action_due_on, 'due_at', b.next_action_at) end,
    'time_zone', (select zone from private.calendar_preferences())
  ) order by c.fire_at), '[]'::jsonb)
  into result
  from claimed c
  left join public.platform_calendar_entries e on e.id = c.entry_id
  left join public.platform_business_relationships b on b.id = coalesce(e.relationship_id, c.relationship_id)
  left join public.platform_team_members m on m.id = c.recipient_member_id;
  return result;
end;
$function$;

-- Records a claimed reminder as sent. False when it was replaced meanwhile (its call moved): nothing to record.
create or replace function public.record_platform_reminder_sent(target_id uuid)
returns boolean
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with done as (
    update public.platform_reminders set sent_at = now(), outcome = 'sent'
    where id = target_id and sent_at is null
    returning id
  )
  select exists (select 1 from done);
$function$;

revoke all on function public.owner_calendar_window(date, date, text) from public, anon, authenticated;
revoke all on function public.owner_calendar_entry(uuid) from public, anon, authenticated;
revoke all on function public.owner_calendar_unclosed_calls(integer) from public, anon, authenticated;
revoke all on function public.owner_calendar_book_call(text, uuid, timestamptz, timestamptz, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.owner_calendar_move(text, uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.owner_calendar_edit(uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.owner_calendar_close_call(text, uuid, text, text, date, timestamptz)
  from public, anon, authenticated;
revoke all on function public.owner_calendar_save_busy(text, uuid, timestamptz, timestamptz, text)
  from public, anon, authenticated;
revoke all on function public.owner_calendar_delete_busy(uuid) from public, anon, authenticated;
revoke all on function public.owner_calendar_preferences() from public, anon, authenticated;
revoke all on function public.owner_calendar_save_preferences(text, jsonb) from public, anon, authenticated;
revoke all on function public.owner_lead_change(text, uuid, text, text, text, date, timestamptz, jsonb)
  from public, anon, authenticated;
revoke all on function public.owner_lead_page(uuid) from public, anon, authenticated;
revoke all on function public.claim_due_platform_reminders(integer) from public, anon, authenticated;
revoke all on function public.record_platform_reminder_sent(uuid) from public, anon, authenticated;

grant execute on function public.owner_calendar_window(date, date, text) to service_role;
grant execute on function public.owner_calendar_entry(uuid) to service_role;
grant execute on function public.owner_calendar_unclosed_calls(integer) to service_role;
grant execute on function public.owner_calendar_book_call(text, uuid, timestamptz, timestamptz, text, text, jsonb)
  to service_role;
grant execute on function public.owner_calendar_move(text, uuid, timestamptz, timestamptz) to service_role;
grant execute on function public.owner_calendar_edit(uuid, text, text, jsonb) to service_role;
grant execute on function public.owner_calendar_close_call(text, uuid, text, text, date, timestamptz) to service_role;
grant execute on function public.owner_calendar_save_busy(text, uuid, timestamptz, timestamptz, text) to service_role;
grant execute on function public.owner_calendar_delete_busy(uuid) to service_role;
grant execute on function public.owner_calendar_preferences() to service_role;
grant execute on function public.owner_calendar_save_preferences(text, jsonb) to service_role;
grant execute on function public.owner_lead_change(text, uuid, text, text, text, date, timestamptz, jsonb)
  to service_role;
grant execute on function public.owner_lead_page(uuid) to service_role;
grant execute on function public.claim_due_platform_reminders(integer) to service_role;
grant execute on function public.record_platform_reminder_sent(uuid) to service_role;

commit;
