-- Jafar business management D3a: every Lead has an owner (plan § 6, Jafar 2026-10-09).
--
-- 1. platform_business_relationships.owner_member_id: null is Jafar. A Lead a teammate adds starts as theirs.
-- 2. owner_lead_set_owner: Jafar or an active teammate takes the business; its scheduled calls move with it and
--    the change is a history line. The server checks the teammate can change Leads & Deals before calling.
-- 3. Reminders follow the owner: a next action's reminders go to the business's owner, a new call belongs to
--    the business's owner, and changing the owner rewrites the unsent reminders.
-- 4. Removing a teammate hands every business and scheduled call they owned back to Jafar, with a history line.
-- 5. platform_owner_notifications.recipient_member_id: null is Jafar's bell; a teammate's in-app reminders land
--    in theirs.
-- 6. Reads: the owner on the Lead page and the Leads list, and the list's owner filter and counts.
--
-- Nothing here sends anything. Platform owner's server only.

-- 1. The owner ------------------------------------------------------------------------------------------------

-- Null is Jafar. Removing a teammate hands their businesses back (section 4), so a removed teammate never owns one.
alter table public.platform_business_relationships
  add column owner_member_id uuid references public.platform_team_members (id) on delete set null;

create index platform_business_relationships_owner_idx
  on public.platform_business_relationships (owner_member_id) where owner_member_id is not null;

-- A Lead a teammate adds is theirs (Pipedrive's default: the creator owns the record). Jafar's email is not a
-- teammate's, so his Leads and anything the public forms create stay his.
create or replace function private.relationship_default_owner()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.owner_member_id is null then
    select m.id into new.owner_member_id
    from public.platform_team_members m
    where m.email = lower(btrim(new.created_by_email)) and m.status = 'active';
  end if;
  return new;
end;
$$;

create trigger platform_business_relationships_default_owner
  before insert on public.platform_business_relationships
  for each row execute function private.relationship_default_owner();

revoke all on function private.relationship_default_owner() from public, anon, authenticated;

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed',
    'contact_approved', 'approval_withdrawn', 'sent_back', 'do_not_contact_set', 'do_not_contact_cleared',
    'deal_started', 'deal_stage_changed', 'pricing_shared', 'deal_lost', 'deal_reopened', 'deal_terms_changed',
    'deal_removed', 'deal_won', 'setup_owner_changed',
    'call_booked', 'call_moved', 'call_held', 'call_no_show', 'call_cancelled',
    'owner_changed'
  )
);

-- 3. Reminders follow the owner -------------------------------------------------------------------------------

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

-- The owner joins what rewrites a next action's reminders.
create or replace function private.relationship_next_action_reminders()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_op = 'INSERT'
    or (new.next_action, new.next_action_due_on, new.next_action_at, new.next_action_entry_id, new.next_action_reminders,
        new.owner_member_id)
      is distinct from
       (old.next_action, old.next_action_due_on, old.next_action_at, old.next_action_entry_id, old.next_action_reminders,
        old.owner_member_id)
  then
    perform private.calendar_rebuild_follow_up_reminders(new.id);
  end if;
  return null;
end;
$$;

drop trigger platform_business_relationships_next_action_reminders on public.platform_business_relationships;
create trigger platform_business_relationships_next_action_reminders
  after insert or update of next_action, next_action_due_on, next_action_at, next_action_entry_id, next_action_reminders,
    owner_member_id
  on public.platform_business_relationships
  for each row execute function private.relationship_next_action_reminders();

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

  -- D3a: the call belongs to whoever owns the business.
  insert into public.platform_calendar_entries (kind, relationship_id, title, notes, starts_at, ends_at, reminders,
    owner_member_id, created_by_email)
  select 'call', target_relationship_id, nullif(btrim(coalesce(target_title, '')), ''),
    nullif(btrim(coalesce(target_notes, '')), ''), target_starts_at, target_ends_at, target_reminders,
    r.owner_member_id, actor
  from public.platform_business_relationships r
  where r.id = target_relationship_id
  returning id into new_id;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_relationship_id, 'call_booked', jsonb_build_object(
    'entry_id', new_id, 'title', nullif(btrim(coalesce(target_title, '')), ''),
    'starts_at', target_starts_at, 'ends_at', target_ends_at), actor);

  perform private.calendar_call_becomes_next_action(new_id, actor);
  return new_id;
end;
$function$;

-- 2. Changing the owner ----------------------------------------------------------------------------------------

-- Hands the business, and every call of it still to happen or to close, to the new owner. Writes one history
-- line. Used by owner_lead_set_owner and by a teammate's removal.
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
  update public.platform_calendar_entries set owner_member_id = target_member_id
  where relationship_id = rel.id and kind = 'call' and status = 'scheduled'
    and owner_member_id is distinct from target_member_id;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (rel.id, 'owner_changed', jsonb_strip_nulls(jsonb_build_object(
    'from', case when previous.id is null then null else coalesce(previous.full_name, previous.email) end,
    'to', case when member.id is null then null else coalesce(member.full_name, member.email) end,
    'reason', reason
  )), actor);
end;
$$;

revoke all on function private.relationship_change_owner(uuid, uuid, text, text) from public, anon, authenticated;

-- Jafar (null) or an active teammate owns the business. Returns false when the business no longer exists.
create or replace function public.owner_lead_set_owner(
  actor_email text,
  target_relationship_id uuid,
  target_member_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if target_member_id is not null and not exists (
    select 1 from public.platform_team_members where id = target_member_id and status = 'active'
  ) then
    raise exception 'That teammate is no longer on the team.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.platform_business_relationships where id = target_relationship_id) then
    return false;
  end if;
  perform private.relationship_change_owner(target_relationship_id, target_member_id, actor);
  return true;
end;
$function$;

revoke all on function public.owner_lead_set_owner(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.owner_lead_set_owner(text, uuid, uuid) to service_role;

-- 4. A removed teammate's work comes back to Jafar --------------------------------------------------------------

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
  where owner_member_id = new.id and status = 'scheduled';
  return null;
end;
$$;

create trigger platform_team_members_removed_returns_work
  after update of status on public.platform_team_members
  for each row execute function private.team_member_removed_returns_work();

revoke all on function private.team_member_removed_returns_work() from public, anon, authenticated;

-- 5. Each person's bell -----------------------------------------------------------------------------------------

alter table public.platform_owner_notifications
  add column recipient_member_id uuid references public.platform_team_members (id);

create index platform_owner_notifications_recipient_idx
  on public.platform_owner_notifications (recipient_member_id, created_at desc) where recipient_member_id is not null;

comment on column public.platform_owner_notifications.recipient_member_id is
  'The teammate whose bell this is in (D3a); null is the platform owner''s.';

create or replace function private.restrict_platform_notification_update()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.id <> old.id
    or new.correlation_id is distinct from old.correlation_id
    or new.kind <> old.kind
    or new.severity <> old.severity
    or new.title <> old.title
    or new.body is distinct from old.body
    or new.target_kind <> old.target_kind
    or new.target_id is distinct from old.target_id
    or new.recipient_member_id is distinct from old.recipient_member_id
    or new.created_at <> old.created_at
  then
    raise exception 'Only the read state of a notification can change.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- The worker's claim tells it whose bell an in-app reminder goes to: recipient_member_id is already in it.

-- 6. Reads ----------------------------------------------------------------------------------------------------

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
      'owner', case when o.id is null then null else jsonb_build_object(
        'id', o.id, 'name', coalesce(o.full_name, o.email), 'avatar_url', o.avatar_url
      ) end,
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
  left join public.platform_team_members o on o.id = r.owner_member_id
  where r.id = target_id;
$function$;

drop function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer, text);

create or replace function public.owner_lead_list(
  search_term text default null,
  status_filter text[] default null,
  country_filter text[] default null,
  source_filter text[] default null,
  sort_order text default 'newest',
  cursor_created_at timestamptz default null,
  cursor_due_on date default null,
  cursor_id uuid default null,
  page_size integer default 50,
  deal_filter text default 'without',
  owner_filter text[] default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with params as (
    select
      nullif(btrim(coalesce(search_term, '')), '') as term,
      least(greatest(coalesce(page_size, 50), 1), 100) as size,
      coalesce(sort_order, 'newest') = 'next_action' as by_due
  ),
  -- B4: a business with a Deal lives on the Deals board; B5: one with a Won Deal is a client.
  scoped as (
    select r.*
    from public.platform_business_relationships r
    where case coalesce(deal_filter, 'without')
      when 'any' then true
      when 'with' then exists (select 1 from public.platform_deals d where d.relationship_id = r.id)
        and not exists (select 1 from public.platform_deals d where d.relationship_id = r.id and d.stage = 'won')
      when 'clients' then exists (
        select 1 from public.platform_deals d where d.relationship_id = r.id and d.stage = 'won'
      )
      else not exists (select 1 from public.platform_deals d where d.relationship_id = r.id)
    end
  ),
  -- Contact details matching the search, read once (not once per Lead).
  method_hits as (
    select m.relationship_id
    from public.platform_business_contact_methods m, params p
    where p.term is not null and m.removed_at is null and m.value ilike '%' || p.term || '%'
  ),
  matching as (
    select r.*, coalesce(r.next_action_due_on, date '0001-01-01') as due_key
    from scoped r, params p
    where p.term is null
      or r.business_name ilike '%' || p.term || '%'
      or r.website_host ilike '%' || p.term || '%'
      or r.contact_name ilike '%' || p.term || '%'
      or r.id in (select relationship_id from method_hits)
  ),
  filtered as (
    select m.*
    from matching m
    where (status_filter is null or cardinality(status_filter) = 0 or m.lead_status = any(status_filter))
      and (country_filter is null or cardinality(country_filter) = 0 or m.country_code = any(country_filter))
      and (source_filter is null or cardinality(source_filter) = 0 or m.source = any(source_filter))
      -- D3a: 'jafar' stands for Leads nobody else owns.
      and (owner_filter is null or cardinality(owner_filter) = 0
        or coalesce(m.owner_member_id::text, 'jafar') = any(owner_filter))
  ),
  page as (
    select f.*
    from filtered f, params p
    where
      case
        when p.by_due then cursor_id is null or (f.due_key, f.id) > (cursor_due_on, cursor_id)
        else cursor_id is null or (f.created_at, f.id) < (cursor_created_at, cursor_id)
      end
    order by
      case when p.by_due then f.due_key end asc,
      case when p.by_due then f.id end asc,
      case when not p.by_due then f.created_at end desc,
      case when not p.by_due then f.id end desc
    limit (select size from params)
  ),
  numbered as (
    select page.*, row_number() over (
      order by
        case when (select by_due from params) then due_key end asc,
        case when (select by_due from params) then id end asc,
        case when not (select by_due from params) then created_at end desc,
        case when not (select by_due from params) then id end desc
    ) as row_index
    from page
  ),
  page_last as (
    select * from numbered order by row_index desc limit 1
  ),
  contact_methods as (
    select
      m.relationship_id,
      jsonb_agg(jsonb_build_object('kind', m.kind, 'value', m.value) order by m.position, m.created_at) as methods
    from public.platform_business_contact_methods m
    where m.relationship_id in (select id from page) and m.removed_at is null
    group by m.relationship_id
  ),
  status_counts as (
    select lead_status, count(*) as n from scoped group by lead_status
  ),
  country_counts as (
    select country_code, count(*) as n from scoped group by country_code
  ),
  source_counts as (
    select source, count(*) as n from scoped group by source
  ),
  owner_counts as (
    select coalesce(owner_member_id::text, 'jafar') as owner_key, count(*) as n from scoped group by 1
  ),
  client_ids as (
    select distinct d.relationship_id from public.platform_deals d where d.stage = 'won'
  )
  select jsonb_build_object(
    'leads', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', n.id,
            'business_name', n.business_name,
            'country_code', n.country_code,
            'trade', n.trade,
            'source', n.source,
            'website_host', n.website_host,
            'contact_name', n.contact_name,
            'contact_methods', coalesce(cm.methods, '[]'::jsonb),
            'lead_status', n.lead_status,
            'next_action', n.next_action,
            'next_action_due_on', n.next_action_due_on,
            'created_at', n.created_at,
            'deal_stage', (
              select d.stage from public.platform_deals d where d.relationship_id = n.id
              order by d.created_at desc limit 1
            ),
            'is_client', n.id in (select relationship_id from client_ids),
            'owner', case when o.id is null then null else jsonb_build_object(
              'id', o.id, 'name', coalesce(o.full_name, o.email), 'avatar_url', o.avatar_url
            ) end
          )
          order by n.row_index
        )
        from numbered n
        left join contact_methods cm on cm.relationship_id = n.id
        left join public.platform_team_members o on o.id = n.owner_member_id
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params)
        then (select jsonb_build_object('created_at', pl.created_at, 'due_on', pl.due_key, 'id', pl.id) from page_last pl)
      else null
    end,
    'totals', jsonb_build_object(
      'all', (select count(*) from scoped),
      'in_deal', (
        select count(distinct d.relationship_id) from public.platform_deals d
        where d.relationship_id not in (select relationship_id from client_ids)
      ),
      'clients', (select count(*) from client_ids),
      'matching', (select count(*) from filtered),
      'statuses', coalesce((select jsonb_object_agg(lead_status, n) from status_counts), '{}'::jsonb),
      'countries', coalesce(
        (select jsonb_agg(jsonb_build_object('code', country_code, 'count', n) order by n desc, country_code)
         from country_counts),
        '[]'::jsonb
      ),
      'sources', coalesce((select jsonb_object_agg(source, n) from source_counts), '{}'::jsonb),
      -- Jafar first, then teammates by name; a removed teammate never owns a business.
      'owners', coalesce(
        (select jsonb_agg(jsonb_build_object('key', oc.owner_key, 'name', coalesce(m.full_name, m.email), 'count', oc.n)
           order by oc.owner_key <> 'jafar', coalesce(m.full_name, m.email))
         from owner_counts oc
         left join public.platform_team_members m on m.id::text = oc.owner_key),
        '[]'::jsonb
      )
    )
  );
$function$;

revoke all on function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer, text, text[]) from public, anon, authenticated;
grant execute on function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer, text, text[]) to service_role;
