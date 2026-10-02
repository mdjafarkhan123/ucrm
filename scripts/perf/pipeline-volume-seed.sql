-- Pipeline volume seed: fake organizations big enough to measure the Pipeline at volume.
--
-- LOCAL REBUILD ONLY. Never run this against the managed or production database: it switches triggers
-- and foreign-key checks off while it loads (session_replication_role = replica) and fills the shared
-- tables with tens of thousands of fake rows.
--
--   docker exec -i supabase_db_ucrm psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < scripts/perf/pipeline-volume-seed.sql
--
-- What one unit of `scale` holds (the big organization is scale 10, the others scale 1):
--   3,000 clients, each with a property, a contact, an email and a phone
--   4,500 Requests   -> 1,000 open on the board, 2,500 turned into Quotes, 600 Lost, 200 Won by a Job,
--                       200 archived without a result
--   3,300 Quotes     -> 1,000 open on the board, 1,400 Won, 700 Lost, 200 abandoned
--     500 Direct jobs
--   so 2,000 open cards and 8,300 cards in all, with their stage history, Tasks, and outcome events.
--
-- Open work is recent (last 120 days) and closed work is spread over three years, the way a real
-- contractor's Pipeline ages. Everything is derived from the row number, so two runs build the same data.

begin;

create schema if not exists perf_seed;

-- A stable pseudo-random number in [0, modulus) for a row number and a salt.
create or replace function perf_seed.pick(n bigint, salt integer, modulus integer)
returns integer language sql immutable as $$
  select ((hashint8(n * 7919 + salt)::bigint & 2147483647) % modulus)::integer;
$$;

create or replace function perf_seed.uid(org uuid, kind text, n bigint)
returns uuid language sql immutable as $$
  select md5(org::text || ':' || kind || ':' || n::text)::uuid;
$$;

create or replace function perf_seed.seed_org(org_name text, org_slug text, scale integer, member_count integer)
returns uuid
language plpgsql
as $seed$
declare
  org uuid := md5('perf-org:' || org_slug)::uuid;
  members uuid[] := '{}';
  member_id uuid;
  stage_request uuid := perf_seed.uid(org, 'stage', 1);
  stage_quote uuid := perf_seed.uid(org, 'stage', 2);
  stage_quote_hold uuid := perf_seed.uid(org, 'stage', 3);
  client_total integer := 3000 * scale;
  first_names text[] := array['James','Maria','Robert','Linda','Michael','Aisha','William','Elena','David','Sofia',
    'Richard','Hannah','Joseph','Priya','Thomas','Olivia','Charles','Mei','Daniel','Fatima','Matthew','Grace',
    'Anthony','Chloe','Mark','Ingrid','Paul','Yuki','Steven','Amelia','Andrew','Nora','Kenneth','Zoe','George',
    'Lucia','Joshua','Freya','Kevin','Isla'];
  last_names text[] := array['Anderson','Bennett','Carter','Dawson','Ellis','Fletcher','Garcia','Hughes','Ivanov',
    'Jensen','Kowalski','Lambert','Murphy','Nguyen','O''Brien','Patel','Quinn','Romero','Schmidt','Tanaka',
    'Ueda','Vasquez','Walker','Xu','Young','Zimmerman','Abbott','Barker','Castillo','Doyle','Eriksen','Fraser',
    'Gallagher','Hoffman','Iqbal','Jacobs','Keller','Lindqvist','Moreau','Novak','Osborne','Pereira','Rossi',
    'Sandoval','Thorne','Underwood','Varga','Whitfield','Yamamoto','Zeller'];
  streets text[] := array['Maple','Oak','Cedar','Birch','Willow','Harbour','Mill','Church','Station','Victoria',
    'Park','Meadow','Riverside','Highland','Orchard','Kingsway','Elm','Chestnut','Lakeshore','Sunset'];
  street_kinds text[] := array['Street','Avenue','Road','Lane','Drive','Court','Crescent','Way'];
  cities text[] := array['Springfield','Riverton','Oakville','Fairview','Georgetown','Kingston','Brighton',
    'Ashford','Milton','Clayton','Burlington','Dover'];
  regions text[] := array['CA','TX','NY','ON','BC','FL','WA','IL'];
  services text[] := array['Roof repair','Kitchen remodel','Bathroom renovation','Lawn care','Fence installation',
    'Gutter cleaning','Deck build','Interior painting','Exterior painting','Driveway sealing','Window replacement',
    'HVAC service','Plumbing repair','Electrical upgrade','Tree removal','Pressure washing','Flooring install',
    'Basement finishing','Siding repair','Landscape design'];
  lead_sources text[] := array['Google','Referral','Facebook','Website','Yard sign','Repeat customer','Nextdoor',
    'Home show','Flyer','Instagram','Angi','Thumbtack'];
  lost_keys text[];
begin
  -- Triggers stay ON for the organization and its people, so settings, lost reasons, and profiles are
  -- created the real way.
  set local session_replication_role = origin;

  insert into public.organizations (id, name, slug, lifecycle_status)
  values (org, org_name, org_slug, 'active');

  for i in 1..member_count loop
    member_id := perf_seed.uid(org, 'user', i);
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
    values ('00000000-0000-0000-0000-000000000000', member_id, 'authenticated', 'authenticated',
      format('perf+%s-%s@example.com', org_slug, i), '', now(), now(), now(),
      '{"provider":"email","providers":["email"]}', '{}');
    insert into public.profiles (id) values (member_id) on conflict (id) do nothing;
    update public.profiles
      set full_name = first_names[1 + i % 40] || ' ' || last_names[1 + (i * 7) % 50]
      where id = member_id;
    insert into public.organization_members (organization_id, user_id, role, status)
    values (org, member_id, case when i = 1 then 'owner' when i = 2 then 'office' else 'sales' end, 'active');
    members := members || member_id;
  end loop;

  -- The last member keeps the Pipeline but loses "see every client", which is the per-card permission path.
  insert into public.organization_member_permission_overrides
    (organization_id, user_id, permission_key, override_state)
  values (org, members[member_count], 'customers.view', 'deny');

  insert into public.pipeline_custom_stages (id, organization_id, section, name, after_stage, position)
  values
    (stage_request, org, 'request', 'Callback needed', 'new_request', 0),
    (stage_quote, org, 'quote', 'Waiting on customer', 'quote_awaiting_response', 0),
    (stage_quote_hold, org, 'quote', 'Financing check', 'quote_awaiting_response', 1);

  select array_agg(reason.key order by reason.position) into lost_keys
  from public.pipeline_lost_reasons as reason
  where reason.organization_id = org and reason.key <> 'other';

  -- Bulk rows go in with triggers and foreign-key checks off. Every stage, clock, and history row below is
  -- written the way the triggers would have left it.
  set local session_replication_role = replica;

  insert into public.clients (id, organization_id, display_name, company_name, client_type, lead_source, created_at)
  select
    perf_seed.uid(org, 'client', n),
    org,
    first_names[1 + perf_seed.pick(n, 1, 40)] || ' ' || last_names[1 + perf_seed.pick(n, 2, 50)],
    case when n % 6 = 0
      then last_names[1 + perf_seed.pick(n, 3, 50)] || ' ' || (array['Holdings','Properties','Homes','Group'])[1 + n % 4]
    end,
    case when n % 6 = 0 then 'company' else 'person' end,
    case
      when n % 8 = 0 then null
      -- Typed by hand in real life, so the same source arrives in more than one spelling.
      when n % 17 = 0 then upper(lead_sources[1 + perf_seed.pick(n, 4, 12)])
      else lead_sources[1 + perf_seed.pick(n, 4, 12)]
    end,
    now() - make_interval(days => perf_seed.pick(n, 5, 1095))
  from generate_series(1, client_total) as n;

  insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, is_primary)
  select
    perf_seed.uid(org, 'property', n),
    org,
    perf_seed.uid(org, 'client', n),
    (100 + perf_seed.pick(n, 6, 9800))::text || ' ' || streets[1 + perf_seed.pick(n, 7, 20)]
      || ' ' || street_kinds[1 + perf_seed.pick(n, 8, 8)],
    cities[1 + perf_seed.pick(n, 9, 12)],
    regions[1 + perf_seed.pick(n, 10, 8)],
    lpad(perf_seed.pick(n, 11, 99999)::text, 5, '0'),
    true
  from generate_series(1, client_total) as n;

  insert into public.client_contacts (id, organization_id, client_id, first_name, last_name, is_primary)
  select
    perf_seed.uid(org, 'contact', n), org, perf_seed.uid(org, 'client', n),
    first_names[1 + perf_seed.pick(n, 1, 40)], last_names[1 + perf_seed.pick(n, 2, 50)], true
  from generate_series(1, client_total) as n;

  insert into public.client_contact_methods
    (id, organization_id, client_id, client_contact_id, kind, value, is_primary)
  select
    perf_seed.uid(org, 'email', n), org, perf_seed.uid(org, 'client', n), perf_seed.uid(org, 'contact', n),
    'email',
    lower(first_names[1 + perf_seed.pick(n, 1, 40)]) || '.' || n || '@example.com',
    true
  from generate_series(1, client_total) as n
  union all
  select
    perf_seed.uid(org, 'phone', n), org, perf_seed.uid(org, 'client', n), perf_seed.uid(org, 'contact', n),
    'phone',
    format('(%s) %s-%s', 200 + perf_seed.pick(n, 12, 700), lpad((n % 1000)::text, 3, '0'), lpad((n / 1000 + 1000)::text, 4, '0')),
    true
  from generate_series(1, client_total) as n;

  -- One working table for every piece of work, so each record and its card agree on state and dates.
  --   kind 'request': n is the Request number; quote_no is set when it was turned into a Quote.
  --   kind 'quote'  : a Quote created without a Request.
  drop table if exists seed_work;
  create temporary table seed_work on commit drop as
  with requests as (
    select
      n,
      n % 90 as cat,
      -- Which way its Quote went, when it became one. Whole blocks of 90 share an answer.
      (n / 90) % 33 as quote_cat
    from generate_series(1, 4500 * scale) as n
  )
  select
    'request'::text as kind,
    n,
    cat,
    case when cat between 20 and 69 then quote_cat end as quote_cat,
    case when cat between 20 and 69
      then row_number() over (partition by (cat between 20 and 69) order by n) end as quote_no,
    1 + perf_seed.pick(n, 20, client_total) as client_n,
    -- Open work is recent; decided work reaches back three years.
    now() - case
      when cat < 20 or (cat between 20 and 69 and quote_cat < 10)
        then make_interval(days => perf_seed.pick(n, 21, 120), mins => perf_seed.pick(n, 22, 1440))
      else make_interval(days => 20 + perf_seed.pick(n, 21, 1075), mins => perf_seed.pick(n, 22, 1440))
    end as created_at
  from requests
  union all
  select
    'quote',
    k,
    null,
    k % 33,
    2500 * scale + k,
    1 + perf_seed.pick(k, 23, client_total),
    now() - case
      when k % 33 < 10
        then make_interval(days => perf_seed.pick(k, 24, 120), mins => perf_seed.pick(k, 25, 1440))
      else make_interval(days => 20 + perf_seed.pick(k, 24, 1075), mins => perf_seed.pick(k, 25, 1440))
    end
  from generate_series(1, 800 * scale) as k;

  create index on seed_work (kind, n);

  insert into public.requests (id, organization_id, client_id, property_id, title, status, created_at, updated_at)
  select
    perf_seed.uid(org, 'request', n), org,
    perf_seed.uid(org, 'client', client_n), perf_seed.uid(org, 'property', client_n),
    services[1 + perf_seed.pick(n, 26, 20)] || ' — ' || streets[1 + perf_seed.pick(client_n, 7, 20)],
    case
      when cat < 8 then 'new'
      when cat < 17 then 'unscheduled'
      when cat < 20 then 'assessment_completed'
      when cat < 70 then 'converted'
      when cat < 82 then 'archived'
      when cat < 86 then 'converted'
      else 'archived'
    end,
    created_at, created_at
  from seed_work where kind = 'request';

  insert into public.assessments (id, organization_id, request_id, starts_at, ends_at, completed_at, created_at)
  select
    perf_seed.uid(org, 'assessment', n), org, perf_seed.uid(org, 'request', n),
    case when cat >= 12 then created_at + interval '3 days' end,
    case when cat >= 12 then created_at + interval '3 days 1 hour' end,
    case when cat >= 17 then created_at + interval '3 days 2 hours' end,
    created_at + interval '1 day'
  from seed_work
  where kind = 'request' and (cat between 8 and 19 or (cat >= 20 and n % 3 = 0));

  -- Request cards.
  insert into public.opportunities (
    id, organization_id, client_id, property_id, request_id, title, outcome, stage, custom_stage_id,
    created_at, updated_at, stage_entered_at, progress_at, owner_user_id, estimated_value, expected_close_on,
    outcome_at
  )
  select
    perf_seed.uid(org, 'request-card', n), org,
    perf_seed.uid(org, 'client', client_n), perf_seed.uid(org, 'property', client_n),
    perf_seed.uid(org, 'request', n),
    services[1 + perf_seed.pick(n, 26, 20)] || ' — ' || streets[1 + perf_seed.pick(client_n, 7, 20)],
    case when cat between 70 and 81 then 'lost' when cat between 82 and 85 then 'won' else 'open' end,
    case
      when cat < 8 then 'new_request'
      when cat < 12 then 'assessment_unscheduled'
      when cat < 17 then 'assessment_scheduled'
      when cat < 20 then 'assessment_completed'
      else 'request_closed'
    end,
    case when cat < 8 and n % 10 = 0 then stage_request end,
    created_at, created_at,
    entered_at, entered_at,
    case when n % 7 <> 0 then members[1 + perf_seed.pick(n, 27, member_count)] end,
    case when perf_seed.pick(n, 28, 10) < 4 then 500 + perf_seed.pick(n, 29, 49500) end,
    case when cat < 20 and n % 3 = 0 then current_date + perf_seed.pick(n, 30, 90) - 20 end,
    case when cat between 70 and 85 then entered_at end
  from seed_work
  cross join lateral (
    select least(now(), created_at + case
      when cat < 8 then case when n % 10 = 0 then interval '2 days' else interval '0' end
      when cat < 12 then interval '1 day'
      when cat < 17 then interval '2 days'
      when cat < 20 then interval '4 days'
      else make_interval(days => 5 + perf_seed.pick(n, 31, 40))
    end) as entered_at
  ) as clock
  where kind = 'request';

  -- Quotes and their published versions.
  insert into public.quotes (
    id, organization_id, client_id, property_id, request_id, quote_number, title, status, currency_code,
    created_at, updated_at, sent_at, current_published_version_id, decision, decided_at, decision_method,
    archived_at, archive_reason
  )
  select
    perf_seed.uid(org, 'quote', quote_no), org,
    perf_seed.uid(org, 'client', client_n), perf_seed.uid(org, 'property', client_n),
    case when kind = 'request' then perf_seed.uid(org, 'request', n) end,
    quote_no,
    services[1 + perf_seed.pick(quote_no, 32, 20)] || ' quote',
    case
      when quote_cat < 3 then 'draft'
      when quote_cat < 8 then 'awaiting_response'
      when quote_cat < 10 then 'changes_requested'
      when quote_cat < 17 then 'approved'
      when quote_cat < 24 then 'converted'
      when quote_cat < 27 then 'declined'
      else 'archived'
    end,
    'USD',
    quoted_at, quoted_at,
    case when quote_cat >= 3 then quoted_at + interval '1 day' end,
    case when quote_cat >= 3 then perf_seed.uid(org, 'quote-version', quote_no) end,
    case when quote_cat between 10 and 23 then 'approved' when quote_cat between 24 and 26 then 'declined' end,
    case when quote_cat between 10 and 26 then closed_at end,
    case when quote_cat between 10 and 26 then 'online' end,
    case when quote_cat >= 27 then closed_at end,
    case when quote_cat >= 27 then 'No longer needed' end
  from seed_work
  cross join lateral (
    select least(now(), created_at + case when kind = 'request'
      then make_interval(days => 5 + perf_seed.pick(n, 31, 40)) else interval '0' end) as quoted_at
  ) as quote_clock
  cross join lateral (
    select least(now(), quoted_at + make_interval(days => 2 + perf_seed.pick(quote_no, 33, 45))) as closed_at
  ) as close_clock
  where quote_no is not null;

  insert into public.quote_versions (
    id, organization_id, quote_id, version_number, status, currency_code, client_display_name,
    organization_name, subtotal_minor, total_minor, published_at, document_hash
  )
  select
    quote.current_published_version_id, org, quote.id, 1, 'published', 'USD', 'Seeded client', org_name,
    amount, amount, quote.sent_at, md5(quote.id::text) || md5(quote.id::text || 'x')
  from public.quotes as quote
  cross join lateral (
    select (30000 + perf_seed.pick(quote.quote_number, 34, 7970000))::bigint as amount
  ) as money
  where quote.organization_id = org and quote.current_published_version_id is not null;

  -- Quote cards.
  insert into public.opportunities (
    id, organization_id, client_id, property_id, quote_id, title, outcome, stage, custom_stage_id,
    created_at, updated_at, stage_entered_at, progress_at, owner_user_id, estimated_value, expected_close_on,
    outcome_at
  )
  select
    perf_seed.uid(org, 'quote-card', quote.quote_number), org, quote.client_id, quote.property_id, quote.id,
    quote.title,
    case
      when quote.status in ('approved', 'converted') then 'won'
      when quote.status = 'declined' then 'lost'
      -- Archived: two in six were abandoned, the rest marked Lost by staff.
      when quote.status = 'archived' and quote.quote_number % 33 < 31 then 'lost'
      else 'open'
    end,
    case quote.status
      when 'draft' then 'quote_draft'
      when 'awaiting_response' then 'quote_awaiting_response'
      when 'changes_requested' then 'quote_changes_requested'
      else 'request_closed'
    end,
    case
      when quote.status = 'awaiting_response' and quote.quote_number % 10 = 0 then stage_quote
      when quote.status = 'awaiting_response' and quote.quote_number % 25 = 1 then stage_quote_hold
    end,
    quote.created_at, quote.created_at,
    entered_at, entered_at,
    case when quote.quote_number % 9 <> 0 then members[1 + perf_seed.pick(quote.quote_number, 35, member_count)] end,
    case when quote.quote_number % 20 <> 0
      then coalesce(version.total_minor, 30000 + perf_seed.pick(quote.quote_number, 34, 7970000)) / 100.0 end,
    case when quote.status in ('draft', 'awaiting_response', 'changes_requested') and quote.quote_number % 2 = 0
      then current_date + perf_seed.pick(quote.quote_number, 36, 90) - 20 end,
    case when quote.status in ('approved', 'converted', 'declined')
           or (quote.status = 'archived' and quote.quote_number % 33 < 31) then entered_at end
  from public.quotes as quote
  left join public.quote_versions as version on version.id = quote.current_published_version_id
  cross join lateral (
    select coalesce(quote.decided_at, quote.archived_at,
      least(now(), quote.created_at + case quote.status
        when 'draft' then interval '0'
        when 'awaiting_response' then interval '1 day'
        else interval '4 days' end)) as entered_at
  ) as clock
  where quote.organization_id = org;

  -- The seed's quote categories are cut on quote_cat, not on quote_number, so re-derive the two archived
  -- kinds from the quote's own row: abandoned ones keep outcome 'open', the rest are Lost.
  update public.opportunities as card
  set outcome = case when work.quote_cat >= 31 then 'open' else 'lost' end,
      outcome_at = case when work.quote_cat >= 31 then null else card.stage_entered_at end
  from public.quotes as quote
  join seed_work as work on work.quote_no = quote.quote_number
  where card.organization_id = org
    and quote.organization_id = org
    and card.quote_id = quote.id
    and quote.status = 'archived';

  -- Direct jobs: booked work that was never a card on the board.
  insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis,
    currency_code, created_at)
  select
    perf_seed.uid(org, 'job', n), org,
    perf_seed.uid(org, 'client', 1 + perf_seed.pick(n, 37, client_total)),
    perf_seed.uid(org, 'property', 1 + perf_seed.pick(n, 37, client_total)),
    n, services[1 + perf_seed.pick(n, 38, 20)] || ' job', 'one_off', 'job_total', 'USD',
    now() - make_interval(days => perf_seed.pick(n, 39, 1095))
  from generate_series(1, 500 * scale) as n;

  insert into public.opportunities (
    id, organization_id, client_id, property_id, job_id, title, outcome, stage, created_at, updated_at,
    stage_entered_at, progress_at, owner_user_id, estimated_value, outcome_at
  )
  select
    perf_seed.uid(org, 'job-card', job.job_number), org, job.client_id, job.property_id, job.id, job.title,
    'won', 'request_closed', job.created_at, job.created_at, job.created_at, job.created_at,
    members[1 + perf_seed.pick(job.job_number, 40, member_count)],
    case when job.job_number % 5 <> 0 then 200 + perf_seed.pick(job.job_number, 41, 20000) end,
    job.created_at
  from public.jobs as job
  where job.organization_id = org;

  -- Outcome events for every Won and Lost card, with the card pointing at its current one.
  insert into public.opportunity_outcome_events (
    id, organization_id, opportunity_id, event_type, occurred_at, actor_user_id, reason, idempotency_key,
    prior_request_status, prior_quote_status, created_at
  )
  select
    md5(card.id::text || ':outcome')::uuid, org, card.id, card.outcome, card.outcome_at, card.owner_user_id,
    case when card.outcome = 'lost' and hashtext(card.id::text) % 5 <> 0
      then lost_keys[1 + abs(hashtext(card.id::text)) % array_length(lost_keys, 1)] end,
    'seed-' || card.id::text,
    case when card.outcome = 'lost' and card.request_id is not null then 'new' end,
    case when card.outcome = 'lost' and card.quote_id is not null then 'awaiting_response' end,
    card.outcome_at
  from public.opportunities as card
  where card.organization_id = org and card.outcome in ('won', 'lost') and card.job_id is null;

  update public.opportunities as card
  set current_outcome_event_id = md5(card.id::text || ':outcome')::uuid
  where card.organization_id = org and card.outcome in ('won', 'lost') and card.job_id is null;

  -- Stage history. Each row is an arrival; a row whose two stages are equal is a move into a custom stage.
  insert into public.opportunity_stage_events
    (organization_id, opportunity_id, from_stage, to_stage, to_custom_stage_id, actor_user_id, occurred_at)
  select org, card.id, step.from_stage, step.to_stage, step.to_custom_stage_id, card.owner_user_id, step.occurred_at
  from public.opportunities as card
  left join public.assessments as assessment
    on assessment.request_id = card.request_id
  cross join lateral (
    select card.stage_entered_at - card.created_at as span
  ) as life
  cross join lateral (
    -- Requests: New, then the assessment steps it really has, then where it is now.
    select null::text as from_stage, 'new_request' as to_stage, null::uuid as to_custom_stage_id,
           card.created_at as occurred_at
    where card.request_id is not null
    union all
    select 'new_request', 'assessment_unscheduled', null, card.created_at + life.span * 0.25
    where card.request_id is not null and assessment.id is not null
    union all
    select 'assessment_unscheduled', 'assessment_scheduled', null, card.created_at + life.span * 0.5
    where card.request_id is not null and assessment.starts_at is not null
    union all
    select 'assessment_scheduled', 'assessment_completed', null, card.created_at + life.span * 0.75
    where card.request_id is not null and assessment.completed_at is not null
      and card.stage in ('assessment_completed', 'request_closed')
    union all
    select
      case when assessment.completed_at is not null then 'assessment_completed'
           when assessment.starts_at is not null then 'assessment_scheduled'
           when assessment.id is not null then 'assessment_unscheduled'
           else 'new_request' end,
      'request_closed', null, card.stage_entered_at
    where card.request_id is not null and card.stage = 'request_closed'
    union all
    select 'new_request', 'new_request', card.custom_stage_id, card.stage_entered_at
    where card.request_id is not null and card.custom_stage_id is not null
    -- Quotes: Draft, sent, one round of changes for a quarter of them, then where it is now.
    union all
    select null, 'quote_draft', null, card.created_at
    where card.quote_id is not null
    union all
    select 'quote_draft', 'quote_awaiting_response', null, card.created_at + life.span * 0.3
    where card.quote_id is not null and card.stage <> 'quote_draft'
    union all
    select 'quote_awaiting_response', 'quote_changes_requested', null, card.created_at + life.span * 0.5
    where card.quote_id is not null
      and (card.stage = 'quote_changes_requested'
           or (card.stage = 'request_closed' and hashtext(card.id::text) % 4 = 0))
    union all
    select 'quote_changes_requested', 'quote_awaiting_response', null, card.created_at + life.span * 0.7
    where card.quote_id is not null and card.stage = 'request_closed' and hashtext(card.id::text) % 4 = 0
    union all
    select 'quote_awaiting_response', 'request_closed', null, card.stage_entered_at
    where card.quote_id is not null and card.stage = 'request_closed'
    union all
    select 'quote_awaiting_response', 'quote_awaiting_response', card.custom_stage_id, card.stage_entered_at
    where card.quote_id is not null and card.custom_stage_id is not null
  ) as step
  where card.organization_id = org and card.job_id is null;

  -- Tasks. Of the open cards: two in ten have an overdue Task, one due today, two due later, one undated,
  -- and four have none. One card in seven with a Task has a second one.
  insert into public.tasks (id, organization_id, opportunity_id, title, assignee_user_id, due_on, status,
    created_by, created_at)
  select
    md5(card.id::text || ':task:' || slot.number)::uuid, org, card.id,
    (array['Call back','Send revised quote','Confirm measurements','Follow up on financing','Check availability'])
      [1 + abs(hashtext(card.id::text)) % 5],
    card.owner_user_id,
    case
      when bucket.b < 2 then current_date - 1 - (abs(hashtext(card.id::text || 'd')) % 30) + (slot.number - 1) * 40
      when bucket.b = 2 then current_date + (slot.number - 1) * 7
      when bucket.b < 5 then current_date + 1 + (abs(hashtext(card.id::text || 'd')) % 60)
    end,
    'open', card.owner_user_id, card.created_at
  from public.opportunities as card
  cross join lateral (select abs(hashtext(card.id::text || 't')) % 10 as b) as bucket
  cross join lateral (
    select 1 as number
    union all
    select 2 where abs(hashtext(card.id::text || 's')) % 7 = 0
  ) as slot
  where card.organization_id = org and card.outcome = 'open' and card.stage <> 'request_closed'
    and bucket.b < 6;

  insert into public.tasks (id, organization_id, opportunity_id, title, assignee_user_id, due_on, status,
    completed_at, completed_by, created_by, created_at)
  select
    md5(card.id::text || ':done')::uuid, org, card.id, 'First call', card.owner_user_id,
    (card.created_at + interval '1 day')::date, 'completed', card.created_at + interval '1 day',
    card.owner_user_id, card.owner_user_id, card.created_at
  from public.opportunities as card
  where card.organization_id = org and card.job_id is null and abs(hashtext(card.id::text || 'c')) % 2 = 0;

  update public.opportunities as card
  set next_task_due_on = soonest.due_on
  from (
    select task.opportunity_id, min(task.due_on) as due_on
    from public.tasks as task
    where task.organization_id = org and task.status = 'open'
    group by task.opportunity_id
  ) as soonest
  where card.organization_id = org and card.id = soonest.opportunity_id;

  set local session_replication_role = origin;
  return org;
end;
$seed$;

-- One very large contractor, one busy ordinary one, and eight more ordinary ones so the shared tables hold
-- other tenants' rows too.
select perf_seed.seed_org('Volume Contracting', 'perf-volume', 10, 12);
select perf_seed.seed_org('Midsize Renovations', 'perf-midsize', 1, 6);
select perf_seed.seed_org('Filler Contractor ' || n, 'perf-filler-' || n, 1, 3) from generate_series(1, 8) as n;

-- The last member of each organization has "see every client" taken away, so the clients they may see are
-- the ones they hold a visit on. One visit on every twelfth job gives them a crew member's history: about
-- 400 clients in the big organization.
set local session_replication_role = replica;

with restricted as (
  select
    organization.id as organization_id,
    perf_seed.uid(organization.id, 'user', (
      select count(*) from public.organization_members as membership
      where membership.organization_id = organization.id
    )) as user_id
  from public.organizations as organization
  where organization.slug like 'perf-%'
),
picked as (
  select
    job.organization_id,
    job.id as job_id,
    restricted.user_id,
    perf_seed.uid(job.organization_id, 'visit',
      row_number() over (partition by job.organization_id order by job.id)) as visit_id,
    job.created_at
  from public.jobs as job
  join restricted on restricted.organization_id = job.organization_id
  where perf_seed.pick(('x' || substr(md5(job.id::text), 1, 8))::bit(32)::int::bigint, 77, 12) = 0
),
visits as (
  insert into public.job_visits (id, organization_id, job_id, position, visit_date, title, source,
    created_at, updated_at)
  select visit_id, organization_id, job_id, 0, (created_at + interval '3 days')::date, 'Site visit',
    'manual', created_at, created_at
  from picked
)
insert into public.job_visit_assignments (organization_id, visit_id, user_id, job_id, created_at)
select organization_id, visit_id, user_id, job_id, created_at
from picked;

set local session_replication_role = origin;

commit;

analyze;
