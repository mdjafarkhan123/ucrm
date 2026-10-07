-- Jafar business management B2b: editing a Lead's details from its page.
--
-- 1. A contact detail can be removed without disappearing: removed_at hides it from the Lead, the list, the
--    duplicate check and any new logged contact, while history that used it still names it (Jafar, 2026-10-07).
--    Fixing a detail's text keeps the same row, so history follows the corrected spelling.
-- 2. A 'details_changed' history entry: one per save, listing each change.
-- 3. owner_lead_update_details: the business, About, and contact-detail changes saved together with that entry.
-- 4. The read functions skip removed details (bodies otherwise unchanged from B1/B2).
begin;

-- 1. Removed contact details --------------------------------------------------------------------------------

alter table public.platform_business_contact_methods add column removed_at timestamptz;

comment on column public.platform_business_contact_methods.removed_at is
  'When the detail was removed from the Lead. Kept so logged contact that used it still names it; never offered again.';

-- New logged contact, or a changed one, may only name a detail still in use. Keeping an older entry's removed
-- detail while editing its words is fine. The message names the composite key so the API's existing refusal
-- ("That contact detail is no longer on this Lead") applies.
create or replace function private.platform_business_history_active_contact_method()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if new.contact_method_id is not null
    and (tg_op = 'INSERT' or new.contact_method_id is distinct from old.contact_method_id)
    and exists (
      select 1 from public.platform_business_contact_methods m
      where m.id = new.contact_method_id and m.removed_at is not null
    ) then
    raise exception 'platform_business_history_contact_method_fkey: that contact detail was removed.'
      using errcode = '23503';
  end if;
  return new;
end;
$function$;

revoke all on function private.platform_business_history_active_contact_method() from public, anon, authenticated;

create trigger platform_business_history_active_contact_method
  before insert or update of contact_method_id on public.platform_business_history
  for each row execute function private.platform_business_history_active_contact_method();

-- 2. The history entry --------------------------------------------------------------------------------------

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed'
  )
);

-- 3. Saving the details -------------------------------------------------------------------------------------

-- fields: any of business_name, country_code, trade, website, contact_name, source, source_detail, fit_notes;
--   a key left out keeps its value, an empty optional value clears it.
-- contact_methods: { "add": [{kind, value, found_at}], "change": [{id, kind, value, found_at}], "remove": [id] }
--   -- operations, not a whole list, so two people editing at once do not undo each other. A detail's kind never
--   changes (history says "emailed info@..."); removing an already-removed detail does nothing.
-- One 'details_changed' history row lists every real change: { changes: [ {field, from, to} |
--   {field: 'fit_notes'} | {field: 'contact_method', action: added|changed|removed, kind, value, from?, to?,
--   found_at_changed?} ] }. Returns 'updated', 'unchanged' or 'lead_not_found'.
create or replace function public.owner_lead_update_details(
  actor_email text,
  target_id uuid,
  fields jsonb default '{}'::jsonb,
  contact_methods jsonb default '{}'::jsonb
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  f jsonb := coalesce(fields, '{}'::jsonb);
  ops jsonb := coalesce(contact_methods, '{}'::jsonb);
  current_row public.platform_business_relationships%rowtype;
  new_row public.platform_business_relationships%rowtype;
  changes jsonb := '[]'::jsonb;
  item jsonb;
  old_method public.platform_business_contact_methods%rowtype;
  next_position smallint;
  active_count integer;
  column_name text;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if jsonb_typeof(f) <> 'object' or jsonb_typeof(ops) <> 'object' then
    raise exception 'The changes are not in the expected shape.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return 'lead_not_found';
  end if;

  -- Business and About fields.
  new_row := current_row;
  if f ? 'business_name' then new_row.business_name := btrim(f ->> 'business_name'); end if;
  if f ? 'country_code' then new_row.country_code := upper(btrim(f ->> 'country_code')); end if;
  if f ? 'trade' then new_row.trade := btrim(f ->> 'trade'); end if;
  if f ? 'website' then new_row.website := nullif(btrim(f ->> 'website'), ''); end if;
  if f ? 'contact_name' then new_row.contact_name := nullif(btrim(f ->> 'contact_name'), ''); end if;
  if f ? 'source' then new_row.source := f ->> 'source'; end if;
  if f ? 'source_detail' then new_row.source_detail := nullif(btrim(f ->> 'source_detail'), ''); end if;
  if f ? 'fit_notes' then new_row.fit_notes := nullif(btrim(f ->> 'fit_notes'), ''); end if;

  foreach column_name in array array[
    'business_name', 'country_code', 'trade', 'website', 'contact_name', 'source', 'source_detail', 'fit_notes'
  ] loop
    if (to_jsonb(current_row) -> column_name) is distinct from (to_jsonb(new_row) -> column_name) then
      changes := changes || case
        -- Long notes are not copied into the history line.
        when column_name = 'fit_notes' then jsonb_build_array(jsonb_build_object('field', 'fit_notes'))
        else jsonb_build_array(jsonb_build_object(
          'field', column_name,
          'from', to_jsonb(current_row) -> column_name,
          'to', to_jsonb(new_row) -> column_name
        ))
      end;
    end if;
  end loop;

  if jsonb_array_length(changes) > 0 then
    update public.platform_business_relationships set
      business_name = new_row.business_name,
      country_code = new_row.country_code,
      trade = new_row.trade,
      website = new_row.website,
      contact_name = new_row.contact_name,
      source = new_row.source,
      source_detail = new_row.source_detail,
      fit_notes = new_row.fit_notes
    where id = target_id;
  end if;

  -- Removed details.
  for item in select * from jsonb_array_elements(coalesce(ops -> 'remove', '[]'::jsonb)) loop
    update public.platform_business_contact_methods
    set removed_at = now()
    where relationship_id = target_id and id = (item #>> '{}')::uuid and removed_at is null
    returning * into old_method;
    if found then
      changes := changes || jsonb_build_array(jsonb_build_object(
        'field', 'contact_method', 'action', 'removed', 'kind', old_method.kind, 'value', old_method.value
      ));
    end if;
  end loop;

  -- Corrected details: the same row, so history that used it reads the corrected text.
  for item in select * from jsonb_array_elements(coalesce(ops -> 'change', '[]'::jsonb)) loop
    select * into old_method from public.platform_business_contact_methods
    where relationship_id = target_id and id = (item ->> 'id')::uuid and removed_at is null
    for update;
    if not found then
      raise exception 'A contact detail you edited has just been removed. Reload the Lead and try again.'
        using errcode = '22023';
    end if;
    if old_method.kind is distinct from item ->> 'kind' then
      raise exception 'A contact detail''s type cannot change. Remove it and add the new one.'
        using errcode = '22023';
    end if;
    if (old_method.value, old_method.found_at)
      is distinct from (btrim(item ->> 'value'), btrim(item ->> 'found_at')) then
      update public.platform_business_contact_methods
      set value = btrim(item ->> 'value'), found_at = btrim(item ->> 'found_at')
      where id = old_method.id;
      changes := changes || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'field', 'contact_method', 'action', 'changed', 'kind', old_method.kind,
        'value', btrim(item ->> 'value'),
        'from', case when old_method.value <> btrim(item ->> 'value') then old_method.value end,
        'to', case when old_method.value <> btrim(item ->> 'value') then btrim(item ->> 'value') end,
        'found_at_changed', case when old_method.found_at <> btrim(item ->> 'found_at') then true end
      )));
    end if;
  end loop;

  -- New details, after the ones already there (removed ones included, so positions never repeat).
  select coalesce(max(position), -1) + 1 into next_position
  from public.platform_business_contact_methods where relationship_id = target_id;
  for item in select * from jsonb_array_elements(coalesce(ops -> 'add', '[]'::jsonb)) loop
    insert into public.platform_business_contact_methods (relationship_id, kind, value, found_at, position)
    values (target_id, item ->> 'kind', btrim(item ->> 'value'), btrim(item ->> 'found_at'), next_position);
    next_position := next_position + 1;
    changes := changes || jsonb_build_array(jsonb_build_object(
      'field', 'contact_method', 'action', 'added', 'kind', item ->> 'kind', 'value', btrim(item ->> 'value')
    ));
  end loop;

  select count(*) into active_count from public.platform_business_contact_methods
  where relationship_id = target_id and removed_at is null;
  if active_count > 10 then
    raise exception 'A Lead can have at most ten contact details.' using errcode = '22023';
  end if;

  if jsonb_array_length(changes) = 0 then
    return 'unchanged';
  end if;

  -- The list orders and the page shows "updated" by the business row, so a contact-only change touches it too.
  update public.platform_business_relationships set updated_at = now() where id = target_id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_id, 'details_changed', jsonb_build_object('changes', changes), actor);
  return 'updated';
end;
$function$;

revoke all on function public.owner_lead_update_details(text, uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.owner_lead_update_details(text, uuid, jsonb, jsonb) to service_role;

-- 4. Reads skip removed details -----------------------------------------------------------------------------

-- owner_lead_list: removed details are neither shown nor searched.
create or replace function public.owner_lead_list(
  search_term text default null,
  status_filter text[] default null,
  country_filter text[] default null,
  source_filter text[] default null,
  sort_order text default 'newest',
  cursor_created_at timestamptz default null,
  cursor_due_on date default null,
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
    select
      nullif(btrim(coalesce(search_term, '')), '') as term,
      least(greatest(coalesce(page_size, 50), 1), 100) as size,
      coalesce(sort_order, 'newest') = 'next_action' as by_due
  ),
  -- Contact details matching the search, read once (not once per Lead).
  method_hits as (
    select m.relationship_id
    from public.platform_business_contact_methods m, params p
    where p.term is not null and m.removed_at is null and m.value ilike '%' || p.term || '%'
  ),
  matching as (
    select r.*, coalesce(r.next_action_due_on, date '0001-01-01') as due_key
    from public.platform_business_relationships r, params p
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
    select lead_status, count(*) as n from public.platform_business_relationships group by lead_status
  ),
  country_counts as (
    select country_code, count(*) as n from public.platform_business_relationships group by country_code
  ),
  source_counts as (
    select source, count(*) as n from public.platform_business_relationships group by source
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
            'created_at', n.created_at
          )
          order by n.row_index
        )
        from numbered n
        left join contact_methods cm on cm.relationship_id = n.id
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params)
        then (select jsonb_build_object('created_at', pl.created_at, 'due_on', pl.due_key, 'id', pl.id) from page_last pl)
      else null
    end,
    'totals', jsonb_build_object(
      'all', (select count(*) from public.platform_business_relationships),
      'matching', (select count(*) from filtered),
      'statuses', coalesce((select jsonb_object_agg(lead_status, n) from status_counts), '{}'::jsonb),
      'countries', coalesce(
        (select jsonb_agg(jsonb_build_object('code', country_code, 'count', n) order by n desc, country_code)
         from country_counts),
        '[]'::jsonb
      ),
      'sources', coalesce((select jsonb_object_agg(source, n) from source_counts), '{}'::jsonb)
    )
  );
$function$;

-- owner_lead_possible_duplicates: a removed detail no longer makes a match.
create or replace function public.owner_lead_possible_duplicates(
  business_name text default null,
  country_code text default null,
  website text default null,
  emails text[] default null,
  phones text[] default null,
  exclude_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with input as (
    select
      nullif(lower(btrim(coalesce(business_name, ''))), '') as name_key,
      upper(nullif(btrim(coalesce(country_code, '')), '')) as country,
      private.website_host(website) as host,
      coalesce(
        (select array_agg(v) from (
          select private.contact_method_value('email', e) as v from unnest(emails) e
        ) x where v is not null),
        array[]::text[]
      ) as email_keys,
      coalesce(
        (select array_agg(v) from (
          select private.contact_method_value('phone', p) as v from unnest(phones) p
        ) x where v is not null and char_length(v) >= 7),
        array[]::text[]
      ) as phone_keys
  ),
  -- Each way of matching is its own indexed lookup; one OR across them would read every Lead.
  lead_candidates as (
    select r.id from public.platform_business_relationships r, input i
    where i.host is not null and r.website_host = i.host
    union
    select r.id from public.platform_business_relationships r, input i
    where i.name_key is not null and lower(r.business_name) = i.name_key
      and (i.country is null or r.country_code = i.country)
    union
    select m.relationship_id from public.platform_business_contact_methods m, input i
    where m.normalized_value = any(i.email_keys || i.phone_keys) and m.removed_at is null
  ),
  lead_matches as (
    select
      r.id,
      r.business_name,
      r.country_code,
      r.created_at,
      array_remove(array[
        case when i.host is not null and r.website_host = i.host then 'website' end,
        case when exists (
          select 1 from public.platform_business_contact_methods m
          where m.relationship_id = r.id and m.removed_at is null and m.kind = 'email' and m.normalized_value = any(i.email_keys)
        ) then 'email' end,
        case when exists (
          select 1 from public.platform_business_contact_methods m
          where m.relationship_id = r.id and m.removed_at is null and m.kind in ('phone', 'whatsapp') and m.normalized_value = any(i.phone_keys)
        ) then 'phone' end,
        case when i.name_key is not null and lower(r.business_name) = i.name_key
          and (i.country is null or r.country_code = i.country) then 'name' end
      ], null) as matched_on
    from lead_candidates c
    join public.platform_business_relationships r on r.id = c.id
    cross join input i
    where exclude_id is null or r.id <> exclude_id
  ),
  application_matches as (
    select
      a.id,
      a.business_name,
      a.submitted_at,
      array_remove(array[
        case when lower(btrim(a.main_contact_email)) = any(i.email_keys) then 'email' end,
        case when private.contact_method_value('phone', a.main_contact_phone) = any(i.phone_keys) then 'phone' end,
        case when i.name_key is not null and lower(btrim(a.business_name)) = i.name_key then 'name' end
      ], null) as matched_on
    from public.platform_onboarding_applications a, input i
    where lower(btrim(a.main_contact_email)) = any(i.email_keys)
      or private.contact_method_value('phone', a.main_contact_phone) = any(i.phone_keys)
      or (i.name_key is not null and lower(btrim(a.business_name)) = i.name_key)
  ),
  organization_matches as (
    select o.id, o.name, o.created_at
    from public.organizations o, input i
    where i.name_key is not null and lower(btrim(o.name)) = i.name_key
  ),
  combined as (
    select 1 as rank, 'lead' as kind, id, business_name as name, country_code, matched_on, created_at as at
    from lead_matches
    union all
    select 2, 'application', id, business_name, null, matched_on, submitted_at from application_matches
    union all
    select 3, 'organization', id, name, null, array['name'], created_at from organization_matches
  )
  select coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'kind', c.kind,
          'id', c.id,
          'name', c.name,
          'country_code', c.country_code,
          'matched_on', to_jsonb(c.matched_on)
        )
        order by c.rank, c.at desc
      )
      from (select * from combined order by rank, at desc limit 10) c
    ),
    '[]'::jsonb
  );
$function$;

-- owner_lead_history: a logged contact still names the detail it used, saying when it was removed.
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
              else jsonb_build_object('id', m.id, 'kind', m.kind, 'value', m.value, 'removed', m.removed_at is not null) end,
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

-- owner_lead_page: the contact details card lists only details still in use.
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

-- owner_lead_application_candidates: matches on details still in use.
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
    left join public.platform_business_contact_methods m
      on m.relationship_id = r.id and m.removed_at is null
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

commit;
