-- A1b slice 2: the Quotes list shows what its Pencil frame shows (classic.pen `TlErE`, Jafar 2026-10-16).
--
-- Two read-only functions, both SECURITY DEFINER because the facts they read sit behind tables the quotes
-- viewer cannot select directly (quote_access_links has RLS with no policy; automation recipes need
-- automations.view; job numbers need jobs.view). Each checks quotes.view itself, withholds money without
-- quotes.view_price, and lives with EXECUTE granted to authenticated only.
--
-- quote_list_overview: the Open quotes card (money per open status, open total), its follow-up strip, and the
-- dark Conversion card. Every read is bounded: the open statuses ride (organization_id, status, ...), the
-- 60-day sent cohort rides the new partial (organization_id, sent_at) index, links ride their
-- (organization_id, quote_id, quote_version_id) index, and the recipe lookup rides the active-trigger index.
--
-- quote_list_activity: the second line under each row's status, for one page of at most 100 quotes.

create index if not exists quotes_organization_sent_idx
  on public.quotes (organization_id, sent_at)
  where sent_at is not null;

create or replace function public.quote_list_overview(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_price boolean;
  today date;
  zone text;
  window_start timestamptz;
  prior_start timestamptz;
  open_money jsonb;
  open_count bigint;
  open_minor bigint;
  sent_count bigint;
  sent_minor bigint;
  converted_count bigint;
  converted_minor bigint;
  prior_sent bigint;
  prior_converted bigint;
  waiting_long bigint;
  not_opened bigint;
  follow_up_days integer[];
begin
  if not private.member_has_permission(target_organization_id, caller, 'quotes.view') then
    raise exception 'You do not have access to these quotes.' using errcode = 'insufficient_privilege';
  end if;
  can_price := private.member_has_permission(target_organization_id, caller, 'quotes.view_price');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  today := private.organization_today(target_organization_id);
  -- The past 30 days are the 30 calendar days ending today where the business is, counted from local
  -- midnight; the 30 before them are the comparison.
  window_start := ((today - 29)::timestamp at time zone zone);
  prior_start := ((today - 59)::timestamp at time zone zone);

  -- Money per open status, from the version each quote is working from (the draft while one is open, else
  -- the published one) -- the same figure the list's Total column shows, so a tile adds up to its rows.
  select
    coalesce(jsonb_object_agg(per_status.status, per_status.total_minor), '{}'::jsonb),
    coalesce(sum(per_status.quote_count), 0),
    coalesce(sum(per_status.total_minor), 0)
  into open_money, open_count, open_minor
  from (
    select quote.status, count(*) as quote_count, coalesce(sum(version.total_minor), 0)::bigint as total_minor
    from public.quotes as quote
    left join public.quote_versions as version
      on version.organization_id = quote.organization_id
     and version.id = coalesce(quote.draft_version_id, quote.current_published_version_id)
    where quote.organization_id = target_organization_id
      and quote.status in ('draft', 'awaiting_response', 'changes_requested', 'approved')
    group by quote.status
  ) as per_status;

  -- Conversion: of the quotes first sent in a window, how many became a job. A cohort, so a quote sent this
  -- month and converted next month still counts for the month it was sent. Money is what the client was
  -- shown: the published version.
  select
    count(*) filter (where cohort.sent_at >= window_start),
    coalesce(sum(cohort.total_minor) filter (where cohort.sent_at >= window_start), 0),
    count(*) filter (where cohort.sent_at >= window_start and cohort.converted),
    coalesce(sum(cohort.total_minor) filter (where cohort.sent_at >= window_start and cohort.converted), 0),
    count(*) filter (where cohort.sent_at < window_start),
    count(*) filter (where cohort.sent_at < window_start and cohort.converted)
  into sent_count, sent_minor, converted_count, converted_minor, prior_sent, prior_converted
  from (
    select
      quote.sent_at,
      version.total_minor,
      exists (
        select 1 from public.jobs as job
        where job.organization_id = quote.organization_id and job.quote_id = quote.id
      ) as converted
    from public.quotes as quote
    left join public.quote_versions as version
      on version.organization_id = quote.organization_id
     and version.id = coalesce(quote.current_published_version_id, quote.draft_version_id)
    where quote.organization_id = target_organization_id
      and quote.sent_at is not null
      and quote.sent_at >= prior_start
      and quote.sent_at <= now()
  ) as cohort;

  -- The follow-up strip: quotes still waiting on the client.
  select
    count(*) filter (where quote.sent_at < now() - interval '7 days'),
    count(*) filter (where not exists (
      select 1 from public.quote_access_links as link
      where link.organization_id = quote.organization_id
        and link.quote_id = quote.id
        and link.quote_version_id = quote.current_published_version_id
        and link.view_count > 0
    ))
  into waiting_long, not_opened
  from public.quotes as quote
  where quote.organization_id = target_organization_id
    and quote.status = 'awaiting_response';

  -- The days the active quote follow-up sends on: the running total of its waits before each email.
  -- The earliest-activated active recipe wins when there is more than one.
  select array_agg(sends.day order by sends.position) into follow_up_days
  from (
    select steps.position, steps.waited_days::integer as day, steps.step ->> 'type' as step_type
    from (
      select
        step.position,
        step.value as step,
        sum(case when step.value ->> 'type' = 'wait' then
          case step.value -> 'config' ->> 'unit'
            when 'days' then (step.value -> 'config' ->> 'amount')::numeric
            when 'hours' then (step.value -> 'config' ->> 'amount')::numeric / 24
            when 'minutes' then (step.value -> 'config' ->> 'amount')::numeric / 1440
            else 0 end
          else 0 end) over (order by step.position) as waited_days
      from (
        select version.definition
        from public.automation_recipes as recipe
        join public.automation_recipe_versions as version on version.id = recipe.current_version_id
        where recipe.organization_id = target_organization_id
          and recipe.status = 'active'
          and recipe.active_trigger_key = 'quote.delivery_succeeded'
        order by version.activated_at, recipe.id
        limit 1
      ) as active_recipe
      cross join lateral jsonb_array_elements(active_recipe.definition -> 'steps')
        with ordinality as step(value, position)
    ) as steps
    where steps.step ->> 'type' = 'action'
      and steps.step ->> 'key' in ('action.send_email', 'action.send_customer_message')
  ) as sends;

  return jsonb_build_object(
    'open_count', open_count,
    'open_minor', case when can_price then open_minor end,
    'status_minor', case when can_price then open_money end,
    'window_start', today - 29,
    'window_end', today,
    'sent_count', sent_count,
    'sent_minor', case when can_price then sent_minor end,
    'converted_count', converted_count,
    'converted_minor', case when can_price then converted_minor end,
    'rate_basis_points', case when sent_count > 0 then (converted_count * 10000 / sent_count) end,
    'prior_rate_basis_points', case when prior_sent > 0 then (prior_converted * 10000 / prior_sent) end,
    'waiting_over_7_days', waiting_long,
    'sent_not_opened', not_opened,
    'follow_up_days', case when follow_up_days is null then null else to_jsonb(follow_up_days) end
  );
end;
$$;

comment on function public.quote_list_overview(uuid) is
  'The Quotes list overview: money per open status, conversion of quotes sent in the past 30 days against the 30 before, and the follow-up facts. Needs quotes.view; money only with quotes.view_price.';

create or replace function public.quote_list_activity(target_organization_id uuid, target_quote_ids uuid[])
returns table (
  quote_id uuid,
  view_count integer,
  changes_requested_at timestamptz,
  job_id uuid,
  job_number integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_see_jobs boolean;
begin
  if not private.member_has_permission(target_organization_id, caller, 'quotes.view') then
    raise exception 'You do not have access to these quotes.' using errcode = 'insufficient_privilege';
  end if;
  if target_quote_ids is null or cardinality(target_quote_ids) = 0 then
    return;
  end if;
  if cardinality(target_quote_ids) > 100 then
    raise exception 'Ask for at most 100 quotes at a time.' using errcode = 'check_violation';
  end if;
  -- A quote viewer who cannot open jobs is told the quote became a job, not which one.
  can_see_jobs := private.member_has_permission(target_organization_id, caller, 'jobs.view');

  return query
  select
    quote.id,
    -- Opens of what the client was last sent: the links issued for the current published version.
    coalesce((
      select sum(link.view_count)::integer
      from public.quote_access_links as link
      where link.organization_id = quote.organization_id
        and link.quote_id = quote.id
        and link.quote_version_id = quote.current_published_version_id
    ), 0),
    (
      select decision.decided_at
      from public.quote_decisions as decision
      where decision.organization_id = quote.organization_id
        and decision.quote_id = quote.id
        and decision.is_current
        and decision.outcome = 'changes_requested'
    ),
    case when can_see_jobs then job.id end,
    case when can_see_jobs then job.job_number end
  from public.quotes as quote
  left join public.jobs as job
    on job.organization_id = quote.organization_id and job.quote_id = quote.id
  where quote.organization_id = target_organization_id
    and quote.id = any(target_quote_ids);
end;
$$;

comment on function public.quote_list_activity(uuid, uuid[]) is
  'Per-row facts for one page of the Quotes list (at most 100): opens of the current sent version, when changes were asked for, and the job a quote became (number only with jobs.view). Needs quotes.view.';

revoke all on function public.quote_list_overview(uuid) from public, anon;
revoke all on function public.quote_list_activity(uuid, uuid[]) from public, anon;
grant execute on function public.quote_list_overview(uuid) to authenticated, service_role;
grant execute on function public.quote_list_activity(uuid, uuid[]) to authenticated, service_role;
