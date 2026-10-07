-- Jafar business management B1: Uplift's own Leads.
--
-- 1. platform_business_relationships: one row per trade business Uplift has found or heard from. It is the one
--    relationship record the plan describes: today it carries the Lead fields; later parts link its Deal,
--    Application and Client to the same row instead of copying the business. Owner is not stored yet: unassigned
--    work belongs to Jafar, and stage D adds teammates as owners.
-- 2. platform_business_contact_methods: each way to reach the business (email, phone, social profile...) with
--    where it was found. Part B3 approves contact per method, so each method is its own row.
-- 3. owner_lead_list: the Leads list -- filters, search, one page, and the counts -- in one round trip, the same
--    shape as owner_organization_directory.
-- 4. owner_lead_possible_duplicates: Leads, Applications and Organizations that look like the same business,
--    shown for review and never merged.
-- 5. owner_create_lead: the business and its contact methods saved together, or not at all.
--
-- Only the platform owner's server (service role) reads or writes any of it.
begin;

-- Normalizers. Immutable so the stored values below can be generated columns and the duplicate check compares
-- against exactly what is stored.

-- "https://www.SmithPlumbing.co.uk/contact?x=1" -> "smithplumbing.co.uk"
create or replace function private.website_host(value text)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(lower(btrim(coalesce(value, ''))), '^[a-z][a-z0-9+.-]*://', ''),
          '^[^/@]*@', ''),
        '[:/?#].*$', ''),
      '^www\.|\.$', '', 'g'),
    '');
$$;

-- Emails and profile handles compare without case or a leading @; phone numbers by their digits alone.
create or replace function private.contact_method_value(kind text, value text)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $$
  select nullif(
    case
      when kind in ('phone', 'whatsapp') then regexp_replace(coalesce(value, ''), '\D', '', 'g')
      when kind = 'contact_form' then coalesce(private.website_host(value), '')
      else regexp_replace(lower(btrim(coalesce(value, ''))), '^@', '')
    end,
    '');
$$;

revoke all on function private.website_host(text) from public, anon, authenticated;
revoke all on function private.contact_method_value(text, text) from public, anon, authenticated;

-- 1. The business -------------------------------------------------------------------------------------------

create table public.platform_business_relationships (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  -- ISO 3166-1 alpha-2. Country decides which outreach channels can ever be used.
  country_code text not null,
  trade text not null,
  -- How Uplift came across the business. 'contacted_us' keeps a business that reached out first from looking
  -- like cold outreach.
  source text not null,
  source_detail text,
  website text,
  website_host text generated always as (private.website_host(website)) stored,
  contact_name text,
  fit_notes text,
  lead_status text not null default 'new',
  next_action text,
  next_action_due_on date,
  created_by_email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_business_relationships_name_check check (
    business_name = btrim(business_name) and char_length(business_name) between 1 and 200
  ),
  constraint platform_business_relationships_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint platform_business_relationships_trade_check check (
    trade = btrim(trade) and char_length(trade) between 1 and 120
  ),
  constraint platform_business_relationships_source_check check (
    source in ('own_website', 'google_maps', 'directory', 'social', 'referral', 'contacted_us', 'event', 'other')
  ),
  constraint platform_business_relationships_source_detail_check check (
    source_detail is null or (source_detail = btrim(source_detail) and char_length(source_detail) between 1 and 300)
  ),
  constraint platform_business_relationships_website_check check (
    website is null or (website = btrim(website) and char_length(website) between 1 and 300)
  ),
  constraint platform_business_relationships_contact_name_check check (
    contact_name is null or (contact_name = btrim(contact_name) and char_length(contact_name) between 1 and 120)
  ),
  constraint platform_business_relationships_fit_notes_check check (
    fit_notes is null or char_length(fit_notes) between 1 and 4000
  ),
  constraint platform_business_relationships_status_check check (
    lead_status in ('new', 'researching', 'ready_for_review', 'unsuitable', 'later')
  ),
  -- A next action is a dated step: both or neither.
  constraint platform_business_relationships_next_action_check check (
    (next_action is null) = (next_action_due_on is null)
    and (next_action is null or (next_action = btrim(next_action) and char_length(next_action) between 1 and 200))
  )
);

comment on table public.platform_business_relationships is
  'Uplift''s own business relationships (Jafar business management). One row per trade business, from Lead onwards. Platform owner only (service role).';

-- The list's default order and its keyset cursor.
create index platform_business_relationships_created_idx
  on public.platform_business_relationships (created_at desc, id desc);
-- The duplicate check's lookups.
create index platform_business_relationships_website_host_idx
  on public.platform_business_relationships (website_host) where website_host is not null;
create index platform_business_relationships_name_idx
  on public.platform_business_relationships (lower(business_name));

create trigger platform_business_relationships_set_updated_at
  before update on public.platform_business_relationships
  for each row execute function public.set_updated_at();

-- 2. Ways to reach it ---------------------------------------------------------------------------------------

create table public.platform_business_contact_methods (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references public.platform_business_relationships (id) on delete cascade,
  kind text not null,
  value text not null,
  normalized_value text generated always as (private.contact_method_value(kind, value)) stored,
  -- Where this detail was found, in the person's own words ("Contact page of their website"). Approval in B3
  -- shows it next to the method.
  found_at text not null,
  position smallint not null default 0,
  created_at timestamptz not null default now(),
  constraint platform_business_contact_methods_kind_check check (
    kind in ('email', 'phone', 'whatsapp', 'instagram', 'facebook', 'linkedin', 'contact_form', 'other')
  ),
  constraint platform_business_contact_methods_value_check check (
    value = btrim(value) and char_length(value) between 1 and 300
  ),
  constraint platform_business_contact_methods_found_at_check check (
    found_at = btrim(found_at) and char_length(found_at) between 1 and 300
  )
);

comment on table public.platform_business_contact_methods is
  'Each way to reach a platform_business_relationships row, with where it was found. Platform owner only (service role).';

create index platform_business_contact_methods_relationship_idx
  on public.platform_business_contact_methods (relationship_id, position);
create index platform_business_contact_methods_value_idx
  on public.platform_business_contact_methods (normalized_value) where normalized_value is not null;

-- Access: nothing for signed-in contractors or the public.
alter table public.platform_business_relationships enable row level security;
alter table public.platform_business_contact_methods enable row level security;
revoke all on table public.platform_business_relationships from public, anon, authenticated;
revoke all on table public.platform_business_contact_methods from public, anon, authenticated;
grant all on table public.platform_business_relationships to service_role;
grant all on table public.platform_business_contact_methods to service_role;

-- 3. The Leads list -----------------------------------------------------------------------------------------

-- sort_order 'newest' (default): newest first, cursor (created_at, id).
-- sort_order 'next_action': leads with no next action first, then the earliest due; cursor (due key, id).
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
    where p.term is not null and m.value ilike '%' || p.term || '%'
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
    where m.relationship_id in (select id from page)
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

revoke all on function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer)
  to service_role;

-- 4. Possible duplicates ------------------------------------------------------------------------------------

-- Anything already on file that shares the website, an email, a phone number, or the business name (in the
-- same country, for Leads). Up to ten, Leads first. Shown to the person adding the Lead; nothing is merged.
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
    where m.normalized_value = any(i.email_keys || i.phone_keys)
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
          where m.relationship_id = r.id and m.kind = 'email' and m.normalized_value = any(i.email_keys)
        ) then 'email' end,
        case when exists (
          select 1 from public.platform_business_contact_methods m
          where m.relationship_id = r.id and m.kind in ('phone', 'whatsapp') and m.normalized_value = any(i.phone_keys)
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

revoke all on function public.owner_lead_possible_duplicates(text, text, text, text[], text[], uuid)
  from public, anon, authenticated;
grant execute on function public.owner_lead_possible_duplicates(text, text, text, text[], text[], uuid)
  to service_role;

-- 5. Adding a Lead ------------------------------------------------------------------------------------------

-- contact_methods: [{ "kind": "email", "value": "...", "found_at": "..." }, ...] in the order shown.
create or replace function public.owner_create_lead(
  actor_email text,
  target_business_name text,
  target_country_code text,
  target_trade text,
  target_source text,
  target_lead_status text,
  target_contact_methods jsonb,
  target_source_detail text default null,
  target_website text default null,
  target_contact_name text default null,
  target_fit_notes text default null,
  target_next_action text default null,
  target_next_action_due_on date default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  new_id uuid;
begin
  if actor_email is null or btrim(actor_email) = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(target_contact_methods, '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(target_contact_methods, '[]'::jsonb)) > 10 then
    raise exception 'Contact methods must be a list of at most ten.' using errcode = '22023';
  end if;

  insert into public.platform_business_relationships (
    business_name, country_code, trade, source, source_detail, website, contact_name, fit_notes,
    lead_status, next_action, next_action_due_on, created_by_email
  ) values (
    btrim(target_business_name), upper(btrim(target_country_code)), btrim(target_trade), target_source,
    nullif(btrim(target_source_detail), ''), nullif(btrim(target_website), ''),
    nullif(btrim(target_contact_name), ''), nullif(btrim(target_fit_notes), ''),
    coalesce(target_lead_status, 'new'), nullif(btrim(target_next_action), ''), target_next_action_due_on,
    lower(btrim(actor_email))
  )
  returning id into new_id;

  insert into public.platform_business_contact_methods (relationship_id, kind, value, found_at, position)
  select new_id, item ->> 'kind', btrim(item ->> 'value'), btrim(item ->> 'found_at'), (ordinality - 1)::smallint
  from jsonb_array_elements(coalesce(target_contact_methods, '[]'::jsonb)) with ordinality as t(item, ordinality);

  return new_id;
end;
$function$;

revoke all on function public.owner_create_lead(text, text, text, text, text, text, jsonb, text, text, text, text, text, date)
  from public, anon, authenticated;
grant execute on function public.owner_create_lead(text, text, text, text, text, text, jsonb, text, text, text, text, text, date)
  to service_role;

commit;
