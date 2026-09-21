-- Marketing (M2): saved customer groups and the exact recipient preview.
--
-- A saved group stores RULES, never a member list, so its count follows CRM truth. The campaign launch
-- (M4) writes its own frozen snapshot, so later Customer/Job edits never rewrite history.
--
-- Rules are compiled to SQL by one whitelist compiler. No customer text ever becomes SQL: the compiler
-- only ever emits fixed fragments, and every value is read at run time out of the single bound `$1`
-- jsonb parameter. An unknown key, operator, or value shape raises instead of widening the query.
--
-- Preview and launch must never disagree about who would receive a campaign, so the matching and
-- eligibility logic lives here once and M4's launch snapshot reuses it.

-- 1. Saved customer groups. -------------------------------------------------------------------------
create table public.marketing_customer_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  description text,
  rules jsonb not null,
  revision integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint marketing_customer_groups_org_id_key unique (organization_id, id),
  constraint marketing_customer_groups_name_check
    check (char_length(btrim(name)) between 1 and 120),
  constraint marketing_customer_groups_description_check
    check (description is null or char_length(btrim(description)) between 1 and 500),
  constraint marketing_customer_groups_rules_check check (jsonb_typeof(rules) = 'object'),
  constraint marketing_customer_groups_revision_check check (revision >= 1)
);

comment on table public.marketing_customer_groups is
  'Saved marketing recipient rules for one organization. Stores rules only; membership is always '
  'recomputed from current CRM data by marketing_preview_counts / marketing_preview_recipients.';
comment on column public.marketing_customer_groups.rules is
  'Rule object validated by Zod in src/lib/marketing/customer-groups.ts and again by '
  'private.marketing_compile_group_rules before any SQL is built.';

-- Enforces one live group name per organization and orders the Customer groups list.
create unique index marketing_customer_groups_name_idx
  on public.marketing_customer_groups (organization_id, normalized_name)
  where archived_at is null;

create index marketing_customer_groups_created_by_idx
  on public.marketing_customer_groups (created_by) where created_by is not null;
create index marketing_customer_groups_updated_by_idx
  on public.marketing_customer_groups (updated_by) where updated_by is not null;

-- RLS on with no policy: service role only, exactly like the marketing consent tables. Every read and
-- write goes through /api/marketing/* after a permission check.
alter table public.marketing_customer_groups enable row level security;

-- 2. The one index the filter set needs that does not already exist. --------------------------------
-- "Customers who purchased a selected service" walks job line items by catalog item within one
-- organization. Every other filter is served by an existing index (clients_organization_lifecycle_status_idx,
-- tag_assignments_unique, properties_organization_active_idx, jobs_client_idx, jobs_closed_report_idx,
-- job_visits_calendar_idx, client_contact_methods_org_value_unique_idx).
create index job_line_items_catalog_item_idx
  on public.job_line_items (organization_id, source_catalog_item_id)
  where source_catalog_item_id is not null;

-- 3. Rule compiler: validated rule object -> a boolean SQL fragment over `c` (public.clients). -------
create function private.marketing_compile_group_rules(rules jsonb)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, private
as $$
declare
  allowed_keys constant text[] := array[
    'version', 'lifecycle', 'tags', 'cities', 'lead_sources', 'services', 'work_type',
    'last_completed_job', 'upcoming_work', 'include_client_ids', 'exclude_client_ids'
  ];
  rule_key text;
  conditions text[] := array[]::text[];
  predicate text;
  completed_job_mode text;
begin
  if rules is null or jsonb_typeof(rules) <> 'object' then
    raise exception 'Marketing group rules must be an object.' using errcode = '22023';
  end if;

  if coalesce(rules->>'version', '') <> '1' then
    raise exception 'Unsupported marketing group rule version.' using errcode = '22023';
  end if;

  for rule_key in select jsonb_object_keys(rules) loop
    if not (rule_key = any (allowed_keys)) then
      raise exception 'Unknown marketing group filter: %', rule_key using errcode = '22023';
    end if;
  end loop;

  -- Lead or customer state.
  if rules ? 'lifecycle' then
    conditions := array_append(conditions, $frag$
      c.lifecycle_status in (select jsonb_array_elements_text($1->'lifecycle'))$frag$);
  end if;

  -- Tags: the Customer carries at least one of the chosen tags.
  if rules ? 'tags' then
    conditions := array_append(conditions, $frag$
      exists (
        select 1 from public.tag_assignments ta
        where ta.organization_id = c.organization_id
          and ta.entity_type = 'client'
          and ta.entity_id = c.id
          and ta.tag_id in (
            select value::uuid from jsonb_array_elements_text($1->'tags') as chosen(value)
          )
      )$frag$);
  end if;

  -- City or service area: any live property of the Customer is in one of the chosen cities.
  if rules ? 'cities' then
    conditions := array_append(conditions, $frag$
      exists (
        select 1 from public.properties p
        where p.organization_id = c.organization_id
          and p.client_id = c.id
          and p.deleted_at is null
          and lower(btrim(p.city)) in (
            select lower(btrim(value)) from jsonb_array_elements_text($1->'cities') as chosen(value)
          )
      )$frag$);
  end if;

  -- Original lead source.
  if rules ? 'lead_sources' then
    conditions := array_append(conditions, $frag$
      c.lead_source in (select jsonb_array_elements_text($1->'lead_sources'))$frag$);
  end if;

  -- Service or line item used on any of the Customer's Jobs.
  if rules ? 'services' then
    conditions := array_append(conditions, $frag$
      exists (
        select 1
        from public.jobs j
        join public.job_line_items li
          on li.organization_id = j.organization_id and li.job_id = j.id
        where j.organization_id = c.organization_id
          and j.client_id = c.id
          and li.source_catalog_item_id in (
            select value::uuid from jsonb_array_elements_text($1->'services') as chosen(value)
          )
      )$frag$);
  end if;

  -- One-off or recurring work.
  if rules ? 'work_type' then
    if (rules->>'work_type') not in ('one_off', 'recurring') then
      raise exception 'Unknown marketing group work type.' using errcode = '22023';
    end if;
    conditions := array_append(conditions, $frag$
      exists (
        select 1 from public.jobs j
        where j.organization_id = c.organization_id
          and j.client_id = c.id
          and j.job_type = ($1->>'work_type')
      )$frag$);
  end if;

  -- Last completed Job date. A completed Job is a closed Job.
  if rules ? 'last_completed_job' then
    completed_job_mode := rules#>>'{last_completed_job,mode}';
    if completed_job_mode = 'never' then
      conditions := array_append(conditions, $frag$
        not exists (
          select 1 from public.jobs j
          where j.organization_id = c.organization_id
            and j.client_id = c.id
            and j.status = 'closed'
        )$frag$);
    elsif completed_job_mode = 'within_days' then
      conditions := array_append(conditions, $frag$
        exists (
          select 1 from public.jobs j
          where j.organization_id = c.organization_id
            and j.client_id = c.id
            and j.status = 'closed'
            and j.closed_at >= now() - make_interval(
              days => (($1#>>'{last_completed_job,days}')::integer)
            )
        )$frag$);
    elsif completed_job_mode = 'before_days' then
      -- Has finished work, but nothing finished recently.
      conditions := array_append(conditions, $frag$
        exists (
          select 1 from public.jobs j
          where j.organization_id = c.organization_id
            and j.client_id = c.id
            and j.status = 'closed'
        )
        and not exists (
          select 1 from public.jobs j
          where j.organization_id = c.organization_id
            and j.client_id = c.id
            and j.status = 'closed'
            and j.closed_at >= now() - make_interval(
              days => (($1#>>'{last_completed_job,days}')::integer)
            )
        )$frag$);
    else
      raise exception 'Unknown last completed job filter.' using errcode = '22023';
    end if;
  end if;

  -- Whether upcoming work exists: a visit still to happen and not yet completed.
  if rules ? 'upcoming_work' then
    if jsonb_typeof(rules->'upcoming_work') <> 'boolean' then
      raise exception 'Upcoming work filter must be true or false.' using errcode = '22023';
    end if;
    predicate := $frag$
      exists (
        select 1
        from public.job_visits v
        join public.jobs j on j.organization_id = v.organization_id and j.id = v.job_id
        where v.organization_id = c.organization_id
          and j.client_id = c.id
          and v.visit_date >= current_date
          and v.completed_at is null
      )$frag$;
    if (rules->>'upcoming_work')::boolean then
      conditions := array_append(conditions, predicate);
    else
      conditions := array_append(conditions, 'not ' || predicate);
    end if;
  end if;

  if array_length(conditions, 1) is null then
    predicate := 'true';
  else
    predicate := '(' || array_to_string(conditions, ') and (') || ')';
  end if;

  -- Explicitly added Customers join the group whatever the rules say.
  if rules ? 'include_client_ids' then
    predicate := '(' || predicate || $frag$ or c.id in (
      select value::uuid from jsonb_array_elements_text($1->'include_client_ids') as chosen(value)
    ))$frag$;
  end if;

  -- Explicitly removed Customers always lose.
  if rules ? 'exclude_client_ids' then
    predicate := predicate || $frag$ and c.id not in (
      select value::uuid from jsonb_array_elements_text($1->'exclude_client_ids') as chosen(value)
    )$frag$;
  end if;

  return predicate;
end;
$$;

comment on function private.marketing_compile_group_rules(jsonb) is
  'Compiles a validated marketing group rule object into a boolean SQL fragment over public.clients c. '
  'Emits only fixed fragments; every value is read from the bound $1 parameter at run time.';

-- 4. The shared evaluated-recipient query: who matches, and if they are blocked, why. ----------------
-- $1 = rules jsonb, $2 = organization id.
create function private.marketing_evaluated_recipients_sql(rules jsonb)
returns text
language sql
immutable
set search_path = pg_catalog, public, private
as $$
  select format($sql$
    with matched as (
      select c.id, c.organization_id, c.display_name, c.archived_at
      from public.clients c
      where c.organization_id = $2
        and c.deleted_at is null
        and (%s)
    ),
    evaluated as (
      select
        m.id as client_id,
        m.display_name,
        dest.method_id,
        dest.email,
        case
          when m.archived_at is not null then 'inactive_customer'
          when dest.method_id is null then 'missing_email'
          when consent.state = 'opted_out' and consent.source = 'complaint' then 'complaint'
          when consent.state = 'opted_out' then 'unsubscribed'
          when suppression.reason = 'complaint' then 'complaint'
          when suppression.reason = 'hard_bounce' then 'hard_bounce'
          when preference.contact_policy = 'do_not_disturb' then 'do_not_disturb'
          when preference.contact_policy = 'no_marketing' then 'no_marketing'
          when consent.state is distinct from 'opted_in' then 'no_consent'
          else null
        end as blocked_reason
      from matched m
      -- One destination per Customer: the primary email, else the oldest email on record.
      left join lateral (
        select cm.id as method_id, cm.normalized_value as email
        from public.client_contact_methods cm
        where cm.organization_id = m.organization_id
          and cm.client_id = m.id
          and cm.kind = 'email'
        order by cm.is_primary desc, cm.created_at, cm.id
        limit 1
      ) dest on true
      left join lateral (
        select state.state, event.source
        from public.client_marketing_consent_state state
        join public.client_marketing_consent_events event
          on event.organization_id = state.organization_id and event.id = state.source_event_id
        where state.organization_id = m.organization_id
          and state.client_contact_method_id = dest.method_id
      ) consent on true
      left join public.client_communication_preferences preference
        on preference.organization_id = m.organization_id and preference.client_id = m.id
      left join lateral (
        select active.reason
        from public.communication_email_suppressions active
        where active.organization_id = m.organization_id
          and active.recipient_email = dest.email
          and active.released_at is null
        order by case active.reason when 'complaint' then 0 else 1 end
        limit 1
      ) suppression on true
    )
    select client_id, display_name, method_id, email, blocked_reason from evaluated
  $sql$, private.marketing_compile_group_rules(rules));
$$;

comment on function private.marketing_evaluated_recipients_sql(jsonb) is
  'Builds the shared preview query: one row per matched Customer with the single reason, if any, that '
  'stops the campaign reaching them. Reason order puts the customer''s own choice before provider facts. '
  'Sharing one destination between two Customers is the only exclusion this query does not decide, '
  'because it depends on the whole result set; each caller adds it.';

-- 5. Exact counts for the live preview. --------------------------------------------------------------
create function public.marketing_preview_counts(
  target_organization_id uuid,
  rules jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  result jsonb;
begin
  -- Two Customers sharing one email address counts once. Comparing the reachable rows with the distinct
  -- addresses among them answers that with a hash aggregate, so the live count never sorts the whole
  -- organization just to find duplicates the paged list marks individually.
  execute format($sql$
    select jsonb_build_object(
      'matches', count(*),
      'eligible', count(distinct email) filter (where blocked_reason is null),
      'excluded', count(*) - count(distinct email) filter (where blocked_reason is null),
      'excluded_by_reason', jsonb_build_object(
        'inactive_customer', count(*) filter (where blocked_reason = 'inactive_customer'),
        'missing_email', count(*) filter (where blocked_reason = 'missing_email'),
        'unsubscribed', count(*) filter (where blocked_reason = 'unsubscribed'),
        'complaint', count(*) filter (where blocked_reason = 'complaint'),
        'hard_bounce', count(*) filter (where blocked_reason = 'hard_bounce'),
        'do_not_disturb', count(*) filter (where blocked_reason = 'do_not_disturb'),
        'no_marketing', count(*) filter (where blocked_reason = 'no_marketing'),
        'no_consent', count(*) filter (where blocked_reason = 'no_consent'),
        -- Filled in by M4, when launched campaigns give recent marketing a source of truth.
        'recent_marketing', 0,
        'duplicate_destination',
          count(*) filter (where blocked_reason is null) - count(distinct email) filter (where blocked_reason is null)
      )
    )
    from (%s) evaluated
  $sql$, private.marketing_evaluated_recipients_sql(rules))
  into result
  using rules, target_organization_id;

  return result;
end;
$$;

comment on function public.marketing_preview_counts(uuid, jsonb) is
  'Exact matches, eligible recipients, and excluded recipients by reason for one organization and rule '
  'set. Called only by server code that has already checked the marketing permission.';

-- 6. One bounded, keyset-paged page of the matching Customers. ---------------------------------------
create function public.marketing_preview_recipients(
  target_organization_id uuid,
  rules jsonb,
  status_filter text default 'all',
  after_display_name text default null,
  after_client_id uuid default null,
  page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  result jsonb;
  bounded_page_size integer := least(greatest(coalesce(page_size, 50), 1), 200);
begin
  if status_filter is null or status_filter not in ('all', 'eligible', 'excluded') then
    raise exception 'Unknown recipient preview filter.' using errcode = '22023';
  end if;

  -- The page is sorted anyway, so it marks the second and later Customer on a shared address here. The
  -- order matches the count query: the first Customer by name keeps the address.
  execute format($sql$
    select coalesce(jsonb_agg(row_to_json(page) order by page.display_name, page.client_id), '[]'::jsonb)
    from (
      select evaluated.client_id, evaluated.display_name, evaluated.email, evaluated.excluded_reason
      from (
        select
          client_id,
          display_name,
          email,
          coalesce(
            blocked_reason,
            case
              when row_number() over (
                partition by (case when blocked_reason is null then email end)
                order by display_name, client_id
              ) > 1 then 'duplicate_destination'
            end
          ) as excluded_reason
        from (%s) reachable
      ) evaluated
      where ($3 = 'all'
             or ($3 = 'eligible' and evaluated.excluded_reason is null)
             or ($3 = 'excluded' and evaluated.excluded_reason is not null))
        and ($4::text is null
             or (evaluated.display_name, evaluated.client_id) > ($4::text, $5::uuid))
      order by evaluated.display_name, evaluated.client_id
      limit $6
    ) page
  $sql$, private.marketing_evaluated_recipients_sql(rules))
  into result
  using rules, target_organization_id, status_filter, after_display_name, after_client_id,
        bounded_page_size;

  return result;
end;
$$;

comment on function public.marketing_preview_recipients(uuid, jsonb, text, text, uuid, integer) is
  'One bounded keyset page of the Customers a rule set matches, each with the reason it would not reach '
  'them. Ordered by display name then id so paging never repeats or skips a Customer.';

-- 7. Server-side only, like every other marketing function. -------------------------------------------
revoke all on function private.marketing_compile_group_rules(jsonb) from public, anon, authenticated;
revoke all on function private.marketing_evaluated_recipients_sql(jsonb) from public, anon, authenticated;
revoke all on function public.marketing_preview_counts(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.marketing_preview_recipients(uuid, jsonb, text, text, uuid, integer)
  from public, anon, authenticated;
