-- Client onboarding C4: Ready for Uplift — the moment Uplift has what it needs and the 7–10 business-day build
-- starts (plan §4–5, §10 journey 7).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §4 (Ready needs every task of the newest
-- send accepted and every help request on a required question answered; the review screen names each blocker)
-- and §5 (the range starts at the recorded Ready time; Monday to Friday in the client's time zone, holidays not
-- skipped; dates fixed when recorded). Jafar's choices of 2026-10-05 are in the plan. Industry reference:
-- GuideCX / Rocketlane project kick-off with a committed target window; shipping "business days" estimates.
--
-- Which tasks and questions a send has, and which are required, live in the app (ADR 0005), so the route works
-- out the full blocker list and refuses Ready while one remains. This function re-checks what the database alone
-- can: the newest send, no task sent back on it, an active account and a payment that stands.
--
-- 1. organization_setup_ready keeps the current Ready for Uplift: when, by whom, on which send, and the dates
--    the client sees. One row per client; taking Ready back deletes it, and both are in Jafar's history.
-- 2. private.setup_add_business_days counts Monday-to-Friday days.
-- 3. public.owner_mark_setup_ready records Ready on the newest send.
-- 4. public.owner_withdraw_setup_ready takes it back, with a reason.
-- 5. public.owner_client_onboarding_list shows Ready clients as Uplift building, with their target dates.

-- 1. The current Ready for Uplift ---------------------------------------------------------------------------

create table public.organization_setup_ready (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  -- The send Uplift accepted as enough to build from.
  submission_number integer not null,
  ready_at timestamptz not null default now(),
  ready_by_email text not null check (char_length(ready_by_email) between 3 and 320),
  -- The client's time zone the dates were counted in.
  time_zone text not null check (char_length(time_zone) between 1 and 64),
  -- The client's own date when Ready was recorded; business day 1 is the next Monday-to-Friday day after it.
  start_date date not null,
  -- The 7th and 10th business days after start_date.
  target_from date not null,
  target_to date not null,
  foreign key (organization_id, submission_number)
    references public.organization_setup_submissions (organization_id, submission_number) on delete cascade,
  constraint organization_setup_ready_dates_check check (start_date < target_from and target_from <= target_to)
);

comment on table public.organization_setup_ready is
  'Client onboarding C4: when Uplift recorded Ready for Uplift for a client, and the 7–10 business-day range the client sees. Administrators may read it; rows change only through public.owner_mark_setup_ready and public.owner_withdraw_setup_ready, and both are in platform_owner_audit_events.';

alter table public.organization_setup_ready enable row level security;
revoke all on table public.organization_setup_ready from public, anon, authenticated;
grant select on table public.organization_setup_ready to authenticated;
grant all on table public.organization_setup_ready to service_role;

-- The client's owners and administrators see their start date and range.
create policy "administrators can view their setup ready"
  on public.organization_setup_ready
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 2. Business days ---------------------------------------------------------------------------------------------

-- The `days`-th Monday-to-Friday day after `from_date`. Mirrors `addBusinessDays` in src/lib/setup/ready.ts.
create function private.setup_add_business_days(from_date date, days integer)
returns date
language sql
immutable
set search_path = ''
as $$
  select day
  from (
    select from_date + step as day
    from pg_catalog.generate_series(1, days * 2 + 7) as step
  ) as calendar
  where extract(isodow from day) < 6
  order by day
  offset days - 1
  limit 1;
$$;

revoke all on function private.setup_add_business_days(date, integer) from public, anon, authenticated;

-- 3. Recording Ready -------------------------------------------------------------------------------------------

-- `seen_number` is the send Jafar was looking at; a newer send returns 'stale' and records nothing. A client
-- already Ready returns 'unchanged' with the dates they already see, so a double press changes nothing.
create function public.owner_mark_setup_ready(
  target_organization_id uuid,
  seen_number integer,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  latest integer;
  zone text;
  today date;
  existing public.organization_setup_ready;
  after_row public.organization_setup_ready;
begin
  if target_organization_id is null or seen_number is null or clean_email is null then
    raise exception 'Say which client, which send, and who is recording it.' using errcode = 'check_violation';
  end if;

  -- Takes turns with Send to Uplift and Uplift's review, which lock the same row.
  perform 1 from public.organization_setup
  where organization_id = target_organization_id
  for update;

  select max(submission_number) into latest
  from public.organization_setup_submissions
  where organization_id = target_organization_id;
  if latest is null then
    raise exception 'This client has not sent their setup yet.' using errcode = 'no_data_found';
  end if;
  if latest <> seen_number then
    return jsonb_build_object('status', 'stale', 'latest_number', latest);
  end if;

  select * into existing
  from public.organization_setup_ready
  where organization_id = target_organization_id;
  if existing.organization_id is not null then
    return jsonb_build_object(
      'status', 'unchanged',
      'ready_at', existing.ready_at,
      'target_from', existing.target_from,
      'target_to', existing.target_to
    );
  end if;

  if not exists (
    select 1 from public.organizations
    where id = target_organization_id and lifecycle_status = 'active'
  ) then
    raise exception 'This account is paused. Resume it before recording Ready for Uplift.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1
    from public.platform_onboarding_application_provisions as provision
    join public.platform_onboarding_applications as application on application.id = provision.application_id
    where provision.organization_id = target_organization_id
      and provision.status = 'succeeded'
      and application.payment_reversed_at is not null
  ) then
    raise exception 'This client''s payment was reversed. Ready for Uplift waits until it is settled.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.organization_setup_section_reviews
    where organization_id = target_organization_id
      and decision = 'returned'
      and submission_number = latest
  ) then
    raise exception 'A task is sent back and waiting for the client.' using errcode = 'check_violation';
  end if;

  -- The client's own date, in the time zone their CRM uses; one Postgres does not know counts in UTC.
  select settings.timezone into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  begin
    today := (now() at time zone zone)::date;
  exception when invalid_parameter_value then
    zone := 'UTC';
    today := (now() at time zone zone)::date;
  end;

  insert into public.organization_setup_ready (
    organization_id, submission_number, ready_by_email, time_zone, start_date, target_from, target_to
  ) values (
    target_organization_id,
    latest,
    clean_email,
    zone,
    today,
    private.setup_add_business_days(today, 7),
    private.setup_add_business_days(today, 10)
  )
  returning * into after_row;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_ready',
    'organization',
    target_organization_id::text,
    null,
    jsonb_build_object(
      'send', after_row.submission_number,
      'time_zone', after_row.time_zone,
      'start_date', after_row.start_date,
      'target_from', after_row.target_from,
      'target_to', after_row.target_to
    )
  );

  return jsonb_build_object(
    'status', 'saved',
    'ready_at', after_row.ready_at,
    'target_from', after_row.target_from,
    'target_to', after_row.target_to
  );
end;
$$;

revoke all on function public.owner_mark_setup_ready(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.owner_mark_setup_ready(uuid, integer, text) to service_role;

-- 4. Taking Ready back -----------------------------------------------------------------------------------------

-- For a Ready recorded by mistake. The reason is kept in Jafar's history; recording Ready again starts a fresh
-- range. Nothing to take back returns 'unchanged'.
create function public.owner_withdraw_setup_ready(
  target_organization_id uuid,
  withdraw_reason text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_reason text := nullif(btrim(coalesce(withdraw_reason, '')), '');
  before_row public.organization_setup_ready;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is taking it back.' using errcode = 'check_violation';
  end if;
  if clean_reason is null or char_length(clean_reason) > 500 then
    raise exception 'Say why, in up to 500 characters.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organization_setup
  where organization_id = target_organization_id
  for update;

  delete from public.organization_setup_ready
  where organization_id = target_organization_id
  returning * into before_row;
  if before_row.organization_id is null then
    return jsonb_build_object('status', 'unchanged');
  end if;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_ready_withdrawn',
    'organization',
    target_organization_id::text,
    jsonb_build_object(
      'send', before_row.submission_number,
      'ready_at', before_row.ready_at,
      'ready_by', before_row.ready_by_email,
      'target_from', before_row.target_from,
      'target_to', before_row.target_to
    ),
    jsonb_build_object('reason', clean_reason)
  );

  return jsonb_build_object('status', 'saved');
end;
$$;

revoke all on function public.owner_withdraw_setup_ready(uuid, text, text) from public, anon, authenticated;
grant execute on function public.owner_withdraw_setup_ready(uuid, text, text) to service_role;

-- 5. Jafar's onboarding list ---------------------------------------------------------------------------------
-- Unchanged from 20261027090000_setup_section_returns.sql except: each client's Ready and target dates are read
-- and returned, Ready on the newest send makes the next action 'build_system', and Ready counts as activity.

create or replace function public.owner_client_onboarding_list(
  setup_catalogue jsonb,
  search_term text default null,
  waiting_filter text default null,
  cursor_account_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50
) returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  with catalogue as (
    select
      section.position,
      section.value ->> 'key' as section_key,
      nullif(section.value ->> 'service_key', '') as service_key,
      array(select jsonb_array_elements_text(section.value -> 'facts')) as fact_keys,
      array(select jsonb_array_elements_text(section.value -> 'required')) as required_keys
    from jsonb_array_elements(setup_catalogue) with ordinality as section(value, position)
  ),
  clients as (
    select
      organization.id,
      organization.name,
      organization.lifecycle_status,
      provision.created_at as account_created_at,
      application.payment_reversed_at,
      agreement.package_name,
      coalesce(agreement.service_keys, '{}'::text[]) as service_keys
    from public.platform_onboarding_application_provisions as provision
    join public.platform_onboarding_applications as application on application.id = provision.application_id
    join public.organizations as organization on organization.id = provision.organization_id
    left join lateral (
      select
        edition.name as package_name,
        array(
          select service ->> 'service_key'
          from jsonb_array_elements(edition.included_services) as service
          where service ->> 'service_key' is not null
        ) as service_keys
      from public.organization_package_agreements as current_agreement
      join public.package_editions as edition on edition.id = current_agreement.edition_id
      where current_agreement.organization_id = organization.id
        and current_agreement.cancelled_at is null
        and current_agreement.effective_from <= now()
      order by current_agreement.effective_from desc, current_agreement.created_at desc
      limit 1
    ) as agreement on true
    where provision.status = 'succeeded'
  ),
  measured as (
    select
      client.*,
      setup.welcome_seen_at,
      own.sections_total,
      cardinality(shown.fact_keys) as facts_total,
      answers.answered,
      answers.help_count,
      answers.last_answer_at,
      sections.done_count,
      sections.next_section_key,
      sections.last_section_at,
      support.unread_count,
      sent.submission_number as sent_number,
      sent.submitted_at as sent_at,
      returns.returned_count,
      returns.returned_at,
      ready.submission_number as ready_number,
      ready.ready_at,
      ready.target_from,
      ready.target_to
    from clients as client
    left join public.organization_setup as setup on setup.organization_id = client.id
    cross join lateral (
      -- The stages this client is asked: everyone's, and those of a service their package includes.
      select
        (select count(*)::integer from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys))
          as sections_total,
        array(
          select unnest(catalogue.fact_keys) from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
        ) as fact_keys
    ) as own
    -- Questions an earlier answer or the package hides are neither counted nor required.
    cross join lateral (
      select public.setup_hidden_fact_keys(setup_catalogue, own.fact_keys, client.id, client.service_keys)
        as fact_keys
    ) as hidden
    cross join lateral (
      select array(
        select fact.fact_key from unnest(own.fact_keys) as fact(fact_key)
        where not (fact.fact_key = any (hidden.fact_keys))
      ) as fact_keys
    ) as shown
    cross join lateral (
      select
        count(*)::integer as answered,
        (count(*) filter (where answer.availability = 'need_help'))::integer as help_count,
        max(answer.updated_at) as last_answer_at
      from public.organization_setup_answers as answer
      where answer.organization_id = client.id
        and answer.fact_key = any (shown.fact_keys)
    ) as answers
    cross join lateral (
      select
        (count(*) filter (where status.done))::integer as done_count,
        (array_agg(status.section_key order by status.position) filter (where not status.done))[1]
          as next_section_key,
        max(status.completed_at) as last_section_at
      from (
        select
          catalogue.position,
          catalogue.section_key,
          marked.completed_at,
          marked.completed_at is not null and not exists (
            select 1
            from unnest(catalogue.required_keys) as required(fact_key)
            where not (required.fact_key = any (hidden.fact_keys))
              and not exists (
              select 1
              from public.organization_setup_answers as answer
              where answer.organization_id = client.id
                and answer.fact_key = required.fact_key
            )
          ) as done
        from catalogue
        left join public.organization_setup_sections as marked
          on marked.organization_id = client.id
         and marked.section_key = catalogue.section_key
        where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
      ) as status
    ) as sections
    cross join lateral (
      select count(*)::integer as unread_count
      from public.support_threads as thread
      where thread.organization_id = client.id
        and thread.last_message_sender_kind = 'member'
        and thread.last_message_at > coalesce(thread.uplift_last_read_at, '-infinity'::timestamptz)
    ) as support
    -- The newest Send to Uplift, if any; the (organization, number) key makes this one index probe.
    left join lateral (
      select submission.submission_number, submission.submitted_at
      from public.organization_setup_submissions as submission
      where submission.organization_id = client.id
      order by submission.submission_number desc
      limit 1
    ) as sent on true
    -- Sections Uplift sent back on that send; a later send hands them back to Uplift. Keyed by organization.
    cross join lateral (
      select count(*)::integer as returned_count, max(review.reviewed_at) as returned_at
      from public.organization_setup_section_reviews as review
      where review.organization_id = client.id
        and review.decision = 'returned'
        and review.submission_number = sent.submission_number
    ) as returns
    -- C4: Ready for Uplift, if recorded; one primary-key probe.
    left join public.organization_setup_ready as ready on ready.organization_id = client.id
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message is Uplift's; a section sent back on the newest send is the client's; a setup sent
  -- to Uplift and a "need Uplift's help" answer are Uplift's; everything else is the client's.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.help_count > 0 or measured.sent_number is not null then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        -- Ready on the newest send: Uplift builds. A send after Ready has changes to look at first.
        when measured.ready_number = measured.sent_number then 'build_system'
        when measured.sent_number is not null then 'review_setup'
        when measured.help_count > 0 then 'help_with_answers'
        when measured.welcome_seen_at is null and measured.answered = 0 then 'start_setup'
        when measured.next_section_key is not null then 'finish_section'
        else 'send_to_uplift'
      end as next_action,
      greatest(
        measured.account_created_at,
        measured.welcome_seen_at,
        measured.last_answer_at,
        measured.last_section_at,
        measured.sent_at,
        measured.returned_at,
        measured.ready_at
      ) as last_activity_at
    from measured
  ),
  tagged as (
    select
      decided.*,
      -- The plan's first reminder goes out after about 24 hours of inactivity and the second at 3 days
      -- (§5); a client quiet for 3 days is the one Jafar should look at himself.
      (decided.waiting_on = 'client' and decided.last_activity_at < now() - interval '3 days') as is_quiet
    from decided
  ),
  matching as (
    select tagged.*
    from tagged
    where search_term is null
      or btrim(search_term) = ''
      or tagged.name ilike '%' || btrim(search_term) || '%'
  ),
  filtered as (
    select matching.*
    from matching
    where waiting_filter is null
      or (waiting_filter = 'quiet' and matching.is_quiet)
      or matching.waiting_on = waiting_filter
  ),
  page as (
    select filtered.*
    from filtered
    where cursor_account_created_at is null
      or (filtered.account_created_at, filtered.id) < (cursor_account_created_at, cursor_id)
    order by filtered.account_created_at desc, filtered.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  )
  select jsonb_build_object(
    'clients', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'name', page.name,
            'lifecycle_status', page.lifecycle_status,
            'package_name', page.package_name,
            'account_created_at', page.account_created_at,
            'payment_reversed', page.payment_reversed_at is not null,
            'welcome_seen', page.welcome_seen_at is not null,
            'sections_done', page.done_count,
            'sections_total', page.sections_total,
            'facts_answered', page.answered,
            'facts_total', page.facts_total,
            'help_count', page.help_count,
            'unread_support', page.unread_count,
            'next_section_key', page.next_section_key,
            'sent_number', page.sent_number,
            'sent_at', page.sent_at,
            'returned_count', page.returned_count,
            'ready_at', page.ready_at,
            'target_from', page.target_from,
            'target_to', page.target_to,
            'waiting_on', page.waiting_on,
            'next_action', page.next_action,
            'last_activity_at', page.last_activity_at,
            'quiet', page.is_quiet
          )
          order by page.account_created_at desc, page.id desc
        )
        from page
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= least(greatest(coalesce(page_size, 50), 1), 100) then (
        select jsonb_build_object('account_created_at', last.account_created_at, 'id', last.id)
        from page as last
        order by last.account_created_at asc, last.id asc
        limit 1
      )
    end,
    'totals', (
      select jsonb_build_object(
        'all', count(*),
        'uplift', count(*) filter (where tagged.waiting_on = 'uplift'),
        'client', count(*) filter (where tagged.waiting_on = 'client'),
        'quiet', count(*) filter (where tagged.is_quiet),
        'matching', (select count(*) from filtered)
      )
      from tagged
    )
  );
$$;
