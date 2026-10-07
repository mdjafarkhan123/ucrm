-- Jafar business management B2: a Lead's page and its one history.
--
-- 1. platform_business_history: what happened with a business -- notes, contact logged from outside UCRM (an
--    email sent from Gmail, a call, a message, and their replies), status and next-action changes, and
--    Applications linked or unlinked. "Lead added" and "Application submitted" are not stored here: they are
--    read from the relationship and the Application themselves, so the history never disagrees with them.
-- 2. platform_onboarding_applications.business_relationship_id: an Application belongs to at most one
--    relationship, so a business that applies is not a second Lead.
-- 3. owner_lead_history / owner_lead_page: the page in one round trip, and older history by cursor.
-- 4. owner_lead_change: status and next action, each change written to the history in the same transaction.
-- 5. owner_lead_link_application and owner_lead_application_candidates.
--
-- Notes and logged contact are plain rows the server inserts, edits and deletes; the constraints below keep
-- each kind's shape. Only the platform owner's server (service role) reads or writes any of it.
begin;

-- A logged contact may name the detail used ("info@smithplumbing.co.uk"). The composite key lets the history
-- require that the detail belongs to the same business.
alter table public.platform_business_contact_methods
  add constraint platform_business_contact_methods_relationship_id_id_key unique (relationship_id, id);

-- 1. The history ----------------------------------------------------------------------------------------------

create table public.platform_business_history (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references public.platform_business_relationships (id) on delete cascade,
  kind text not null,
  -- When it happened. For logged contact this is the time the person gives (the email went yesterday);
  -- otherwise the time it was recorded. clock_timestamp, not now(): a status change and a next action written in
  -- one transaction still read in the order they happened.
  occurred_at timestamptz not null default clock_timestamp(),
  -- A note's text, or what a logged contact said.
  body text,
  contact_direction text,
  contact_channel text,
  contact_method_id uuid,
  call_outcome text,
  application_id uuid references public.platform_onboarding_applications (id) on delete set null,
  -- Automatic rows: status { from, to }; next action { next_action, due_on }; Application { business_name }
  -- kept so the row still reads correctly after the Application's personal data is removed.
  details jsonb,
  actor_email text not null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  constraint platform_business_history_contact_method_fkey
    foreign key (relationship_id, contact_method_id)
    references public.platform_business_contact_methods (relationship_id, id)
    on delete set null (contact_method_id),
  constraint platform_business_history_kind_check check (
    kind in (
      'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
      'application_linked', 'application_unlinked'
    )
  ),
  constraint platform_business_history_body_check check (
    body is null or (body = btrim(body) and char_length(body) between 1 and 4000)
  ),
  constraint platform_business_history_direction_check check (
    contact_direction is null or contact_direction in ('outbound', 'inbound')
  ),
  constraint platform_business_history_channel_check check (
    contact_channel is null or contact_channel in (
      'email', 'phone', 'text', 'whatsapp', 'instagram', 'facebook', 'linkedin', 'contact_form', 'in_person', 'other'
    )
  ),
  constraint platform_business_history_call_outcome_check check (
    call_outcome is null or call_outcome in ('connected', 'left_voicemail', 'no_answer', 'busy', 'wrong_number')
  ),
  constraint platform_business_history_actor_check check (actor_email = lower(btrim(actor_email))),
  -- Each kind carries exactly its own fields.
  constraint platform_business_history_note_shape check (
    kind <> 'note' or (
      body is not null and contact_direction is null and contact_channel is null and contact_method_id is null
      and call_outcome is null and application_id is null and details is null
    )
  ),
  -- A call we made says how it went; nothing else has a call outcome.
  constraint platform_business_history_contact_shape check (
    kind <> 'contact' or (
      contact_direction is not null and contact_channel is not null and application_id is null and details is null
      and (call_outcome is not null) = (contact_channel = 'phone' and contact_direction = 'outbound')
    )
  ),
  constraint platform_business_history_automatic_shape check (
    kind in ('note', 'contact') or (
      body is null and contact_direction is null and contact_channel is null and contact_method_id is null
      and call_outcome is null and details is not null and edited_at is null
    )
  )
);

comment on table public.platform_business_history is
  'What happened with an Uplift business relationship: notes, contact logged from outside UCRM, and changes. Platform owner only (service role).';

-- The page reads one business's newest entries; "Show older" continues from (occurred_at, id).
create index platform_business_history_relationship_idx
  on public.platform_business_history (relationship_id, occurred_at desc, id desc);
-- Foreign keys whose parent rows can be deleted.
create index platform_business_history_contact_method_idx
  on public.platform_business_history (contact_method_id) where contact_method_id is not null;
create index platform_business_history_application_idx
  on public.platform_business_history (application_id) where application_id is not null;

alter table public.platform_business_history enable row level security;
revoke all on table public.platform_business_history from public, anon, authenticated;
grant all on table public.platform_business_history to service_role;

-- 2. Applications belong to a relationship --------------------------------------------------------------------

alter table public.platform_onboarding_applications
  add column business_relationship_id uuid
    references public.platform_business_relationships (id) on delete set null;

create index platform_onboarding_applications_business_relationship_idx
  on public.platform_onboarding_applications (business_relationship_id)
  where business_relationship_id is not null;

-- 3. Reading ---------------------------------------------------------------------------------------------------

-- Newest first, up to page_size entries older than the cursor. Stored rows come from the index; the two read
-- from their own records ("Lead added", each linked Application's submission) are a handful at most.
-- actor_name is the teammate's name; null for the platform owner, whom the server names.
create or replace function public.owner_lead_history(
  target_id uuid,
  cursor_occurred_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with params as (
    select least(greatest(coalesce(page_size, 50), 1), 100) as size
  ),
  stored as (
    select
      h.id, h.kind, h.occurred_at, h.body, h.contact_direction, h.contact_channel, h.contact_method_id,
      h.call_outcome, h.application_id, h.details, h.actor_email, h.edited_at
    from public.platform_business_history h
    where h.relationship_id = target_id
      and (cursor_id is null or (h.occurred_at, h.id) < (cursor_occurred_at, cursor_id))
    order by h.occurred_at desc, h.id desc
    limit (select size from params)
  ),
  derived as (
    select
      r.id, 'lead_added' as kind, r.created_at as occurred_at, null::text as body, null::text as contact_direction,
      null::text as contact_channel, null::uuid as contact_method_id, null::text as call_outcome,
      null::uuid as application_id, jsonb_build_object('source', r.source) as details,
      r.created_by_email as actor_email, null::timestamptz as edited_at
    from public.platform_business_relationships r
    where r.id = target_id
    union all
    select
      a.id, 'application_submitted', a.submitted_at, null, null, null, null, null, a.id,
      jsonb_build_object('business_name', a.business_name), null, null
    from public.platform_onboarding_applications a
    where a.business_relationship_id = target_id
  ),
  page as (
    select * from stored
    union all
    select d.* from derived d
    where cursor_id is null or (d.occurred_at, d.id) < (cursor_occurred_at, cursor_id)
    order by occurred_at desc, id desc
    limit (select size from params)
  )
  select jsonb_build_object(
    'entries', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'kind', p.kind,
            'occurred_at', p.occurred_at,
            'body', p.body,
            'contact_direction', p.contact_direction,
            'contact_channel', p.contact_channel,
            'contact_method', case when m.id is null then null
              else jsonb_build_object('id', m.id, 'kind', m.kind, 'value', m.value) end,
            'call_outcome', p.call_outcome,
            'application_id', p.application_id,
            'details', p.details,
            'actor_email', p.actor_email,
            'actor_name', (
              select t.full_name from public.platform_team_members t
              where t.email = p.actor_email
              order by t.created_at desc
              limit 1
            ),
            'edited_at', p.edited_at
          )
          order by p.occurred_at desc, p.id desc
        )
        from page p
        left join public.platform_business_contact_methods m on m.id = p.contact_method_id
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params) then (
        select jsonb_build_object('occurred_at', p.occurred_at, 'id', p.id)
        from page p order by p.occurred_at asc, p.id asc limit 1
      )
      else null
    end
  );
$function$;

revoke all on function public.owner_lead_history(uuid, timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function public.owner_lead_history(uuid, timestamptz, uuid, integer) to service_role;

-- Everything the Lead page shows, or null when there is no such Lead.
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
      'created_by_email', r.created_by_email,
      'created_at', r.created_at,
      'updated_at', r.updated_at
    ),
    'contact_methods', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object('id', m.id, 'kind', m.kind, 'value', m.value, 'found_at', m.found_at)
          order by m.position, m.created_at
        )
        from public.platform_business_contact_methods m
        where m.relationship_id = r.id
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

revoke all on function public.owner_lead_page(uuid) from public, anon, authenticated;
grant execute on function public.owner_lead_page(uuid) to service_role;

-- 4. Status and next action -----------------------------------------------------------------------------------

-- next_action_mode:
--   'keep'  -- leave the next action as it is;
--   'set'   -- replace it with target_next_action / target_due_on (both required);
--   'done'  -- record the current one as done, then set the given new one or leave none;
--   'clear' -- remove it without calling it done.
-- target_status null keeps the status. Each real change is one history row; an unchanged value writes nothing.
-- Returns false when there is no such Lead.
create or replace function public.owner_lead_change(
  actor_email text,
  target_id uuid,
  target_status text default null,
  next_action_mode text default 'keep',
  target_next_action text default null,
  target_due_on date default null
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

  if target_status is not null and target_status is distinct from current_row.lead_status then
    update public.platform_business_relationships set lead_status = target_status where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'status_changed',
      jsonb_build_object('from', current_row.lead_status, 'to', target_status), actor);
  end if;

  if next_action_mode = 'clear' then
    if current_row.next_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_cleared',
        jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on), actor);
      update public.platform_business_relationships
      set next_action = null, next_action_due_on = null
      where id = target_id;
    end if;
  elsif next_action_mode = 'done' then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'next_action_done',
      jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on), actor);
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on
    where id = target_id;
    if new_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_set',
        jsonb_build_object('next_action', new_action, 'due_on', target_due_on), actor);
    end if;
  elsif next_action_mode = 'set'
    and (new_action, target_due_on) is distinct from (current_row.next_action, current_row.next_action_due_on) then
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on
    where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'next_action_set',
      jsonb_build_object('next_action', new_action, 'due_on', target_due_on), actor);
  end if;

  return true;
end;
$function$;

revoke all on function public.owner_lead_change(text, uuid, text, text, text, date) from public, anon, authenticated;
grant execute on function public.owner_lead_change(text, uuid, text, text, text, date) to service_role;

-- 5. Linking Applications -------------------------------------------------------------------------------------

-- Link (target_link true) or unlink an Application. Returns 'linked', 'unlinked', 'unchanged',
-- 'lead_not_found', 'application_not_found', or 'linked_elsewhere' -- an Application already belongs to another
-- business and must be unlinked there first, so nobody moves it by accident.
create or replace function public.owner_lead_link_application(
  actor_email text,
  target_id uuid,
  target_application_id uuid,
  target_link boolean
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  application public.platform_onboarding_applications%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  perform 1 from public.platform_business_relationships where id = target_id for update;
  if not found then
    return 'lead_not_found';
  end if;
  select * into application from public.platform_onboarding_applications
  where id = target_application_id for update;
  if not found then
    return 'application_not_found';
  end if;

  if target_link then
    if application.business_relationship_id = target_id then
      return 'unchanged';
    end if;
    if application.business_relationship_id is not null then
      return 'linked_elsewhere';
    end if;
    update public.platform_onboarding_applications
    set business_relationship_id = target_id
    where id = target_application_id;
  else
    if application.business_relationship_id is distinct from target_id then
      return 'unchanged';
    end if;
    update public.platform_onboarding_applications
    set business_relationship_id = null
    where id = target_application_id;
  end if;

  insert into public.platform_business_history (relationship_id, kind, application_id, details, actor_email)
  values (
    target_id,
    case when target_link then 'application_linked' else 'application_unlinked' end,
    target_application_id,
    jsonb_build_object('business_name', application.business_name),
    actor
  );
  return case when target_link then 'linked' else 'unlinked' end;
end;
$function$;

revoke all on function public.owner_lead_link_application(text, uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.owner_lead_link_application(text, uuid, uuid, boolean) to service_role;

-- Applications to offer in the "Link an Application" picker, up to ten. Without a search: the ones that share
-- this business's email, phone or name (the B1 duplicate rules). With a search: business name, contact name or
-- email containing it. Each says which business, if any, it is already linked to.
create or replace function public.owner_lead_application_candidates(
  target_id uuid,
  search_term text default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with term as (
    select nullif(btrim(coalesce(search_term, '')), '') as value
  ),
  lead as (
    select
      r.id,
      lower(btrim(r.business_name)) as name_key,
      coalesce(array_agg(m.normalized_value) filter (where m.kind = 'email'), array[]::text[]) as email_keys,
      coalesce(
        array_agg(m.normalized_value) filter (where m.kind in ('phone', 'whatsapp') and char_length(m.normalized_value) >= 7),
        array[]::text[]
      ) as phone_keys
    from public.platform_business_relationships r
    left join public.platform_business_contact_methods m on m.relationship_id = r.id
    where r.id = target_id
    group by r.id
  ),
  candidates as (
    select a.*
    from public.platform_onboarding_applications a, term t, lead l
    where (
      t.value is null and (
        lower(btrim(a.business_name)) = l.name_key
        or lower(btrim(a.main_contact_email)) = any(l.email_keys)
        or private.contact_method_value('phone', a.main_contact_phone) = any(l.phone_keys)
      )
    ) or (
      t.value is not null and (
        a.business_name ilike '%' || t.value || '%'
        or a.main_contact_name ilike '%' || t.value || '%'
        or a.main_contact_email ilike '%' || t.value || '%'
      )
    )
    order by a.submitted_at desc, a.id desc
    limit 10
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'business_name', c.business_name,
        'main_contact_name', c.main_contact_name,
        'main_contact_email', c.main_contact_email,
        'stage', c.stage,
        'submitted_at', c.submitted_at,
        'linked_to', case when r.id is null then null
          else jsonb_build_object('id', r.id, 'business_name', r.business_name) end
      )
      order by c.submitted_at desc, c.id desc
    ),
    '[]'::jsonb
  )
  from candidates c
  left join public.platform_business_relationships r on r.id = c.business_relationship_id;
$function$;

revoke all on function public.owner_lead_application_candidates(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_lead_application_candidates(uuid, text) to service_role;

commit;
