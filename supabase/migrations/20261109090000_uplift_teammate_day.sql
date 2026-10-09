-- Jafar business management D3b: each teammate's own day (plan § 6, Jafar 2026-10-09).
--
-- 1. platform_team_members.time_zone and reminder_defaults: a teammate's own choices in My preferences. Every
--    reminder, and the day a call becomes its business's next action, is worked out in the time zone and defaults of
--    the person it belongs to; Jafar's stay on platform_owner_settings.
-- 2. Changing either person's choices rewrites only that person's reminders still to come.
-- 3. Reads take the viewer: the calendar, the calls waiting for an outcome, and the home show the viewer's own work
--    (null is Jafar's, which is also everything nobody else owns). Jafar's home can show everyone's to-dos.
-- 4. Busy blocks belong to whoever made them; only they see, move or remove them. A removed teammate's scheduled
--    calls come back to Jafar but their Busy blocks do not land on his calendar.
--
-- Nothing here sends anything. Platform owner's server only; it decides who the viewer is from the session.

-- 1. Personal choices -------------------------------------------------------------------------------------------

alter table public.platform_team_members
  add column time_zone text,
  add column reminder_defaults jsonb;

-- The person's time zone and defaults, filled in where nothing was chosen yet. Null is Jafar.
create or replace function private.calendar_preferences_for(target_member_id uuid, out zone text, out defaults jsonb)
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select
    coalesce(
      case when target_member_id is null
        then (select s.time_zone from public.platform_owner_settings s where s.id)
        else (select m.time_zone from public.platform_team_members m where m.id = target_member_id)
      end,
      'UTC'),
    private.calendar_default_reminders()
      || coalesce(
        case when target_member_id is null
          then (select s.reminder_defaults from public.platform_owner_settings s where s.id)
          else (select m.reminder_defaults from public.platform_team_members m where m.id = target_member_id)
        end,
        '{}'::jsonb);
$$;

revoke all on function private.calendar_preferences_for(uuid) from public, anon, authenticated;

-- Jafar's, for anything older that still asks without a person.
create or replace function private.calendar_preferences(out zone text, out defaults jsonb)
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select p.zone, p.defaults from private.calendar_preferences_for(null) p;
$$;

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

  -- D3b: the owner's own time zone and defaults.
  select * into prefs from private.calendar_preferences_for(r.owner_member_id);
  rules := coalesce(
    r.next_action_reminders,
    prefs.defaults -> (case when r.next_action_at is null then 'follow_up_day' else 'follow_up_timed' end)
  );

  insert into public.platform_reminders (relationship_id, channel, fire_at, recipient_member_id)
  select target_relationship_id, x.channel, x.fire_at, r.owner_member_id
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

  rules := coalesce(e.reminders, case when e.kind = 'call'
    then (select defaults -> 'call' from private.calendar_preferences_for(e.owner_member_id)) end);

  insert into public.platform_reminders (entry_id, channel, fire_at, recipient_member_id)
  select target_entry_id, rule->>'channel', e.starts_at - make_interval(mins => (rule->>'minutes_before')::int),
    e.owner_member_id
  from jsonb_array_elements(coalesce(rules, '[]'::jsonb)) rule
  where rule ? 'minutes_before'
    and e.starts_at - make_interval(mins => (rule->>'minutes_before')::int) > now();
end;
$$;

-- Makes the call the business's next action, with its day in the call owner's time zone and its start time.
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
  due := (e.starts_at at time zone (select zone from private.calendar_preferences_for(e.owner_member_id)))::date;
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

-- 2. Changing someone's choices rewrites only their reminders ----------------------------------------------------

create or replace function private.calendar_rebuild_person_reminders(target_member_id uuid)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  target uuid;
begin
  for target in
    select r.id from public.platform_business_relationships r
    where r.owner_member_id is not distinct from target_member_id
      and r.next_action_due_on >= current_date - 1 and r.next_action_entry_id is null
      and (r.next_action_reminders is null or r.next_action_at is null)
  loop
    perform private.calendar_rebuild_follow_up_reminders(target);
  end loop;
  for target in
    select e.id from public.platform_calendar_entries e
    where e.owner_member_id is not distinct from target_member_id
      and e.status = 'scheduled' and e.reminders is null and e.kind = 'call' and e.starts_at > now()
  loop
    perform private.calendar_rebuild_entry_reminders(target);
  end loop;
end;
$$;

revoke all on function private.calendar_rebuild_person_reminders(uuid) from public, anon, authenticated;

create or replace function private.calendar_preferences_changed()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_op = 'UPDATE'
    and (new.time_zone, new.reminder_defaults) is not distinct from (old.time_zone, old.reminder_defaults) then
    return null;
  end if;
  perform private.calendar_rebuild_person_reminders(null);
  return null;
end;
$$;

create or replace function private.team_member_preferences_changed()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if (new.time_zone, new.reminder_defaults) is distinct from (old.time_zone, old.reminder_defaults) then
    perform private.calendar_rebuild_person_reminders(new.id);
  end if;
  return null;
end;
$$;

create trigger platform_team_members_calendar_preferences
  after update of time_zone, reminder_defaults on public.platform_team_members
  for each row execute function private.team_member_preferences_changed();

revoke all on function private.team_member_preferences_changed() from public, anon, authenticated;

-- A removed teammate's scheduled calls come back to Jafar; their Busy blocks stay theirs, off his calendar.
create or replace function private.team_member_removed_returns_work()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  target uuid;
  actor text := coalesce(new.removed_by_email, new.email);
begin
  if new.status <> 'removed' or old.status = 'removed' then
    return null;
  end if;
  for target in select id from public.platform_business_relationships where owner_member_id = new.id loop
    perform private.relationship_change_owner(target, null, actor, 'removed');
  end loop;
  -- Calls of businesses someone else now owns, if any were left with them.
  update public.platform_calendar_entries set owner_member_id = null
  where owner_member_id = new.id and status = 'scheduled' and kind = 'call';
  return null;
end;
$$;

-- 3. Reads, for one viewer -------------------------------------------------------------------------------------

drop function public.owner_calendar_window(date, date, text);

-- Everything on the viewer's calendar between two days (inclusive) in the given time zone: their calls and Busy
-- blocks that overlap it, and their dated next actions that are not a call's. At most 42 days; at most 1,500 of
-- each, flagged when cut. Null viewer is Jafar.
create or replace function public.owner_calendar_window(
  from_date date,
  to_date date,
  zone text,
  viewer_member_id uuid default null
)
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
      and e.owner_member_id is not distinct from viewer_member_id
    order by e.starts_at, e.id
    limit item_limit + 1
  ),
  follow_ups as (
    select r.id, r.business_name, r.next_action, r.next_action_due_on, r.next_action_at, r.next_action_kind
    from public.platform_business_relationships r
    where r.next_action_due_on between from_date and to_date and r.next_action_entry_id is null
      and r.owner_member_id is not distinct from viewer_member_id
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

drop function public.owner_calendar_unclosed_calls(integer);

-- The viewer's calls that have ended and still wait for "How did it go?", oldest first.
create or replace function public.owner_calendar_unclosed_calls(
  limit_count integer default 20,
  viewer_member_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with mine as (
    select * from public.platform_calendar_entries
    where kind = 'call' and status = 'scheduled' and ends_at <= now()
      and owner_member_id is not distinct from viewer_member_id
  )
  select jsonb_build_object(
    'count', (select count(*) from mine),
    'calls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'relationship_id', c.relationship_id, 'business_name', b.business_name, 'title', c.title,
        'starts_at', c.starts_at, 'ends_at', c.ends_at
      ) order by c.ends_at, c.id)
      from (
        select * from mine
        order by ends_at, id
        limit least(greatest(coalesce(limit_count, 20), 1), 100)
      ) c
      join public.platform_business_relationships b on b.id = c.relationship_id
    ), '[]'::jsonb)
  );
$function$;

drop function public.owner_calendar_preferences();

-- The viewer's time zone and default reminders.
create or replace function public.owner_calendar_preferences(viewer_member_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'time_zone', case when viewer_member_id is null
      then (select s.time_zone from public.platform_owner_settings s where s.id)
      else (select m.time_zone from public.platform_team_members m where m.id = viewer_member_id)
    end,
    'reminder_defaults', p.defaults
  )
  from private.calendar_preferences_for(viewer_member_id) p;
$function$;

drop function public.owner_calendar_save_preferences(text, jsonb);

-- Only the values given change.
create or replace function public.owner_calendar_save_preferences(
  target_time_zone text default null,
  target_reminder_defaults jsonb default null,
  viewer_member_id uuid default null
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

  if viewer_member_id is null then
    insert into public.platform_owner_settings (id, time_zone, reminder_defaults)
    values (true, target_time_zone, target_reminder_defaults)
    on conflict (id) do update
    set time_zone = coalesce(excluded.time_zone, platform_owner_settings.time_zone),
      reminder_defaults = case
        when excluded.reminder_defaults is null then platform_owner_settings.reminder_defaults
        else coalesce(platform_owner_settings.reminder_defaults, '{}'::jsonb) || excluded.reminder_defaults
      end,
      updated_at = now();
  else
    update public.platform_team_members m
    set time_zone = coalesce(target_time_zone, m.time_zone),
      reminder_defaults = case
        when target_reminder_defaults is null then m.reminder_defaults
        else coalesce(m.reminder_defaults, '{}'::jsonb) || target_reminder_defaults
      end
    where m.id = viewer_member_id and m.status = 'active';
    if not found then
      raise exception 'You are no longer on the team.' using errcode = '22023';
    end if;
  end if;

  return public.owner_calendar_preferences(viewer_member_id);
end;
$function$;

drop function public.owner_business_home(date, integer);

-- The home for one viewer: the to-do list and first contacts are the viewer's own (null is Jafar's, which is also
-- everything nobody else owns), or the whole team's when `everyone`. The other counts are business-wide queues; the
-- server leaves out those the viewer may not open. Items carry their owner's name for the whole-team list.
create or replace function public.owner_business_home(
  today_date date,
  agenda_limit integer default 60,
  viewer_member_id uuid default null,
  everyone boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with due as (
    select r.id, r.business_name, r.country_code, r.trade, r.next_action, r.next_action_due_on,
      r.next_action_kind, r.next_action_entry_id, r.owner_member_id
    from public.platform_business_relationships r
    where r.next_action_due_on is not null
      and r.next_action_due_on <= today_date + 7
      and (everyone or r.owner_member_id is not distinct from viewer_member_id)
  ),
  listed as (
    select d.*
    from due d
    order by d.next_action_due_on, d.business_name, d.id
    limit least(greatest(coalesce(agenda_limit, 60), 1), 200)
  )
  select jsonb_build_object(
    'review', (
      select count(*) from public.platform_business_relationships where lead_status = 'ready_for_review'
    ),
    'first_contact', (
      select count(*) from public.platform_business_relationships
      where next_action_kind = 'first_contact'
        and (everyone or owner_member_id is not distinct from viewer_member_id)
    ),
    -- Paid and the payment still stands: the account is Uplift's to make.
    'accounts_to_create', (
      select count(*) from public.platform_onboarding_applications
      where stage = 'payment_confirmed' and payment_reversed_at is null
    ),
    'overdue', (select count(*) from due where next_action_due_on < today_date),
    'today', (select count(*) from due where next_action_due_on = today_date),
    'upcoming', (select count(*) from due where next_action_due_on > today_date),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', l.id,
          'business_name', l.business_name,
          'country_code', l.country_code,
          'trade', l.trade,
          'next_action', l.next_action,
          'due_on', l.next_action_due_on,
          'first_contact', l.next_action_kind = 'first_contact',
          'deal_stage', d.stage,
          'call_id', l.next_action_entry_id,
          'owner_member_id', l.owner_member_id,
          'owner_name', case when m.id is null then null else coalesce(m.full_name, m.email) end
        )
        order by l.next_action_due_on, l.business_name, l.id
      )
      from listed l
      left join public.platform_deals d
        on d.relationship_id = l.id and d.stage not in ('lost', 'won')
      left join public.platform_team_members m on m.id = l.owner_member_id
    ), '[]'::jsonb)
  );
$function$;

-- 4. Busy blocks are personal ----------------------------------------------------------------------------------

drop function public.owner_calendar_save_busy(text, uuid, timestamptz, timestamptz, text);

-- A Busy block: new when target_id is null, otherwise its time and label change. Only its owner's own.
create or replace function public.owner_calendar_save_busy(
  actor_email text,
  target_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  target_title text default null,
  viewer_member_id uuid default null
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
    insert into public.platform_calendar_entries (kind, title, starts_at, ends_at, owner_member_id, created_by_email)
    values ('busy', nullif(btrim(coalesce(target_title, '')), ''), target_starts_at, target_ends_at,
      viewer_member_id, actor)
    returning id into saved;
  else
    update public.platform_calendar_entries
    set title = nullif(btrim(coalesce(target_title, '')), ''), starts_at = target_starts_at, ends_at = target_ends_at
    where id = target_id and kind = 'busy' and owner_member_id is not distinct from viewer_member_id
    returning id into saved;
  end if;
  return saved;
end;
$function$;

drop function public.owner_calendar_delete_busy(uuid);

create or replace function public.owner_calendar_delete_busy(target_id uuid, viewer_member_id uuid default null)
returns boolean
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with gone as (
    delete from public.platform_calendar_entries
    where id = target_id and kind = 'busy' and owner_member_id is not distinct from viewer_member_id
    returning id
  )
  select exists (select 1 from gone);
$function$;

-- The email worker: reminders due now, claimed for five minutes, each with its recipient's own time zone. A
-- reminder more than an hour late is recorded as late and not sent.
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
    'time_zone', (select zone from private.calendar_preferences_for(c.recipient_member_id))
  ) order by c.fire_at), '[]'::jsonb)
  into result
  from claimed c
  left join public.platform_calendar_entries e on e.id = c.entry_id
  left join public.platform_business_relationships b on b.id = coalesce(e.relationship_id, c.relationship_id)
  left join public.platform_team_members m on m.id = c.recipient_member_id;
  return result;
end;
$function$;

revoke all on function public.owner_calendar_window(date, date, text, uuid) from public, anon, authenticated;
revoke all on function public.owner_calendar_unclosed_calls(integer, uuid) from public, anon, authenticated;
revoke all on function public.owner_calendar_preferences(uuid) from public, anon, authenticated;
revoke all on function public.owner_calendar_save_preferences(text, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.owner_business_home(date, integer, uuid, boolean) from public, anon, authenticated;
revoke all on function public.owner_calendar_save_busy(text, uuid, timestamptz, timestamptz, text, uuid)
  from public, anon, authenticated;
revoke all on function public.owner_calendar_delete_busy(uuid, uuid) from public, anon, authenticated;

grant execute on function public.owner_calendar_window(date, date, text, uuid) to service_role;
grant execute on function public.owner_calendar_unclosed_calls(integer, uuid) to service_role;
grant execute on function public.owner_calendar_preferences(uuid) to service_role;
grant execute on function public.owner_calendar_save_preferences(text, jsonb, uuid) to service_role;
grant execute on function public.owner_business_home(date, integer, uuid, boolean) to service_role;
grant execute on function public.owner_calendar_save_busy(text, uuid, timestamptz, timestamptz, text, uuid)
  to service_role;
grant execute on function public.owner_calendar_delete_busy(uuid, uuid) to service_role;
