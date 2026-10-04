-- Client onboarding C3b: the client's side of Uplift's review.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §4 (a returned section is the client's to
-- answer; they never repeat the whole wizard) and §5 ("Waiting for your information"). Jafar's choices of
-- 2026-10-04: a return emails the client's owners and administrators straight to that section.
--
-- 1. public.owner_setup_review_recipients lists who is emailed when Uplift sends a section back: the active
--    owners and administrators with an email address. A return is Uplift asking for something, not a reminder,
--    so a reminder opt-out does not hold it back.
-- 2. public.owner_client_onboarding_list: a section sent back on the client's newest send makes it the client's
--    move ("fix_returned"), and the return counts as activity for the quiet filter. Otherwise unchanged from
--    20261025090000_setup_client_page.sql.

-- 1. Who hears about a return ---------------------------------------------------------------------------------

create function public.owner_setup_review_recipients(target_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', membership.user_id,
    'email', account.email,
    'name', private.support_member_name(membership.user_id)
  ) order by membership.created_at, membership.user_id), '[]'::jsonb)
  from public.organization_members as membership
  join auth.users as account on account.id = membership.user_id
  where membership.organization_id = target_organization_id
    and membership.status = 'active'
    and membership.role in ('owner', 'admin')
    and nullif(btrim(account.email), '') is not null;
$$;

revoke all on function public.owner_setup_review_recipients(uuid) from public, anon, authenticated;
grant execute on function public.owner_setup_review_recipients(uuid) to service_role;

-- 2. The onboarding list knows about returns ----------------------------------------------------------------

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
      returns.returned_at
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
        measured.returned_at
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
