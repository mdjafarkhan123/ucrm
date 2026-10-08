-- Jafar business C1: the onboarding list's "Setups waiting on Uplift" count was slow (about 2 s for 5 clients).
-- Postgres pulled the `hidden` lateral up into the queries that use it, so setup_hidden_fact_keys ran once per
-- question and per required key instead of once per client. `offset 0` keeps it a fence: one call per client.
-- Nothing else changes; the definition is the live one from 20261007140517_uplift_deal_won.

create or replace function public.owner_client_onboarding_list(
  setup_catalogue jsonb,
  search_term text default null,
  waiting_filter text default null,
  cursor_account_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50,
  include_delivered boolean default false,
  only_organization_id uuid default null
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
      handover.live_at,
      handover.delivered_at,
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
    left join public.organization_setup_handover as handover on handover.organization_id = organization.id
    where provision.status = 'succeeded'
      -- E6: a delivered client leaves the list unless Jafar asks for them, before any of the work below.
      and (include_delivered or handover.delivered_at is null)
      -- B5: one client's row for the business page, before any of the work below.
      and (only_organization_id is null or organization.id = only_organization_id)
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
      ready.target_to,
      waits.open_count as waits_open,
      waits.action_count as waits_action,
      waits.changed_at as waits_changed_at,
      preview.version as preview_version,
      preview.released_at as preview_released_at,
      preview.notes_sent_at as preview_sent_at,
      preview.unsorted_count as preview_unsorted,
      approval.status as approval_status,
      approval.requested_at as approval_requested_at,
      approval.not_yet_at as approval_not_yet_at,
      approval.approved_at as approval_approved_at,
      approval.version as approval_version,
      training.meeting_at as training_meeting_at,
      training.skipped_at as training_skipped_at,
      training.details_at as training_details_at
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
      offset 0 -- a fence: evaluate once per client, not once per question that reads it
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
    -- E2: outside waits still open, and those needing the client; at most four rows, keyed by organization.
    cross join lateral (
      select
        (count(*) filter (where wait.status not in ('approved', 'unavailable')))::integer as open_count,
        (count(*) filter (where wait.status = 'action_needed'))::integer as action_count,
        max(wait.updated_at) as changed_at
      from public.organization_setup_provider_waits as wait
      where wait.organization_id = client.id
    ) as waits
    -- E3: the newest released preview, its send, and its sent notes not yet sorted; at most 15 notes.
    left join lateral (
      select
        released.version,
        released.released_at,
        released.notes_sent_at,
        (
          select count(*)::integer
          from public.organization_setup_preview_notes as note
          where note.organization_id = released.organization_id
            and note.version = released.version
            and note.choice <> 'looks_right'
            and note.sorted_kind is null
        ) as unsorted_count
      from public.organization_setup_previews as released
      where released.organization_id = client.id
        and released.released_at is not null
      order by released.version desc
      limit 1
    ) as preview on true
    -- E4: the open launch approval request or the standing approval; at most one of each, keyed by organization.
    left join lateral (
      select request.status, request.requested_at, request.not_yet_at, request.approved_at, request.version
      from public.organization_setup_launch_approvals as request
      where request.organization_id = client.id
        and (request.status = 'open' or (request.status = 'approved' and request.replaced_at is null))
      order by request.requested_at desc
      limit 1
    ) as approval on true
    -- E6: the training row; one primary-key probe.
    left join lateral (
      select
        own_training.meeting_at,
        own_training.skipped_at,
        case when jsonb_array_length(own_training.attendees) > 0 then own_training.details_updated_at end as details_at
      from public.organization_setup_training as own_training
      where own_training.organization_id = client.id
    ) as training on true
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message is Uplift's; a section sent back on the newest send, or an outside wait needing
  -- the client (E2), is the client's; a setup sent to Uplift and a "need Uplift's help" answer are Uplift's;
  -- everything else is the client's.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.delivered_at is not null then 'nobody'
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.waits_action > 0 then 'client'
        -- E6: once live, training details are the client's to give; booking and handing over are Uplift's.
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null and measured.training_details_at is null then 'client'
        when measured.live_at is not null then 'uplift'
        when measured.approval_status = 'approved' then 'uplift'
        when measured.approval_status = 'open' and measured.approval_not_yet_at is not null then 'uplift'
        when measured.approval_status = 'open' then 'client'
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'client'
        when measured.help_count > 0 or measured.sent_number is not null then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.delivered_at is not null then 'delivered'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        when measured.waits_action > 0 then 'provider_action'
        -- E6: live — training settled first, then the handover.
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null and measured.training_details_at is null
          then 'give_training_details'
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null then 'book_training'
        when measured.live_at is not null then 'finish_handover'
        -- E4: an approval is Uplift's to launch; an open request is the approver's, unless they said not yet.
        when measured.approval_status = 'approved' then 'prepare_launch'
        when measured.approval_status = 'open' and measured.approval_not_yet_at is not null then 'approver_not_yet'
        when measured.approval_status = 'open' then 'approve_launch'
        -- E3: a released preview is the client's to review; their notes are Uplift's to sort, then make.
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'review_preview'
        when measured.preview_unsorted > 0 then 'sort_corrections'
        when measured.preview_sent_at is not null then 'make_corrections'
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
        measured.ready_at,
        measured.waits_changed_at,
        measured.preview_released_at,
        measured.preview_sent_at,
        measured.approval_requested_at,
        measured.approval_not_yet_at,
        measured.approval_approved_at,
        measured.live_at,
        measured.delivered_at,
        measured.training_details_at
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
            'provider_waits_open', page.waits_open,
            'provider_waits_action', page.waits_action,
            'preview_version', page.preview_version,
            'preview_released_at', page.preview_released_at,
            'preview_sent_at', page.preview_sent_at,
            'preview_unsorted', coalesce(page.preview_unsorted, 0),
            'approval_status', page.approval_status,
            'approval_version', page.approval_version,
            'approval_requested_at', page.approval_requested_at,
            'approval_not_yet_at', page.approval_not_yet_at,
            'approved_at', page.approval_approved_at,
            'live_at', page.live_at,
            'delivered_at', page.delivered_at,
            'training_booked_at', page.training_meeting_at,
            'training_skipped', page.training_skipped_at is not null,
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
        'matching', (select count(*) from filtered),
        -- E6: delivered clients, counted whether or not they are listed.
        'delivered', (
          select count(*)
          from public.organization_setup_handover as delivered
          join public.platform_onboarding_application_provisions as provision
            on provision.organization_id = delivered.organization_id and provision.status = 'succeeded'
          where delivered.delivered_at is not null
        )
      )
      from tagged
    )
  );
$$;
