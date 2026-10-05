-- Client onboarding E2: outside waits — the steps Google, the phone carriers, a client's old phone company or
-- their domain company take, each with its own badge so a wait on them never makes Uplift look late or done
-- (plan §5).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §5 and §8. Jafar's choices of 2026-10-05:
-- four fixed waits, each offered only when the client's package includes its service; Jafar changes them by hand
-- with an optional note; the client sees a wait once Jafar has started it; only "You need to do something"
-- emails the client; waits never move Uplift's dates or block Ready; one where the client must act makes the
-- client's row in Jafar's list the client's move. Industry reference: carrier registration and Google Business
-- Profile verification report their own stage (submitted, in review, action needed, approved, failed);
-- GuideCX and Rocketlane keep external dependencies on their own line, outside the delivery promise.
--
-- 1. organization_setup_provider_waits keeps each started wait's current stage and note. Every change is in
--    platform_owner_audit_events, which is Jafar's history.
-- 2. public.owner_set_setup_provider_wait changes one, or clears it back to not started.
-- 3. public.owner_client_onboarding_list counts each client's open waits, and a wait where the client must act
--    makes the client's row the client's move.

-- 1. The waits -----------------------------------------------------------------------------------------------

create table public.organization_setup_provider_waits (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- Mirrors PROVIDER_WAITS in src/lib/setup/provider-waits.ts.
  wait_key text not null check (
    wait_key in ('google_profile', 'texting_approval', 'number_transfer', 'website_address')
  ),
  status text not null check (
    status in ('waiting_for_access', 'submitted', 'in_review', 'action_needed', 'approved', 'unavailable')
  ),
  -- What the client reads under the badge; for "You need to do something", what to do.
  note text check (note is null or char_length(note) between 1 and 1000),
  updated_at timestamptz not null default now(),
  updated_by_email text not null check (char_length(updated_by_email) between 3 and 320),
  primary key (organization_id, wait_key),
  constraint organization_setup_provider_waits_action_note_check check (status <> 'action_needed' or note is not null)
);

comment on table public.organization_setup_provider_waits is
  'Client onboarding E2: where each outside wait (Google, carriers, number transfer, domain) stands for a client. Administrators may read it; rows change only through public.owner_set_setup_provider_wait, and every change is in platform_owner_audit_events.';

alter table public.organization_setup_provider_waits enable row level security;
revoke all on table public.organization_setup_provider_waits from public, anon, authenticated;
grant select on table public.organization_setup_provider_waits to authenticated;
grant all on table public.organization_setup_provider_waits to service_role;

-- The client's owners and administrators see their waits on the Setup page.
create policy "administrators can view their provider waits"
  on public.organization_setup_provider_waits
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 2. Changing a wait --------------------------------------------------------------------------------------------

-- `new_status` null clears the wait back to not started, which hides it from the client again. Saving what is
-- already there returns 'unchanged', so a double press records nothing twice. 'saved' carries
-- `email_client`: true when the wait has just become "You need to do something", or its note changed while it
-- is — the route then emails the client's owners and administrators once for that change.
create function public.owner_set_setup_provider_wait(
  target_organization_id uuid,
  target_wait_key text,
  new_status text,
  new_note text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_note text := nullif(btrim(coalesce(new_note, '')), '');
  wait_service text;
  before_row public.organization_setup_provider_waits;
  after_row public.organization_setup_provider_waits;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  wait_service := case target_wait_key
    when 'google_profile' then 'google_profile'
    when 'texting_approval' then 'calls_texting'
    when 'number_transfer' then 'calls_texting'
    when 'website_address' then 'website'
  end;
  if wait_service is null then
    raise exception 'That is not one of the outside waits.' using errcode = 'check_violation';
  end if;
  if new_status = 'action_needed' and clean_note is null then
    raise exception 'Say what the client needs to do.' using errcode = 'check_violation';
  end if;
  if clean_note is not null and char_length(clean_note) > 1000 then
    raise exception 'Keep the note to 1000 characters.' using errcode = 'check_violation';
  end if;

  -- Only a wait whose service the client's current package includes.
  if new_status is not null and not exists (
    select 1
    from (
      select edition.included_services
      from public.organization_package_agreements as agreement
      join public.package_editions as edition on edition.id = agreement.edition_id
      where agreement.organization_id = target_organization_id
        and agreement.cancelled_at is null
        and agreement.effective_from <= now()
      order by agreement.effective_from desc, agreement.created_at desc
      limit 1
    ) as current_package
    cross join lateral jsonb_array_elements(current_package.included_services) as service
    where service ->> 'service_key' = wait_service
  ) then
    raise exception 'This client''s package does not include that service.' using errcode = 'check_violation';
  end if;

  select * into before_row
  from public.organization_setup_provider_waits
  where organization_id = target_organization_id and wait_key = target_wait_key
  for update;

  if new_status is null then
    if before_row.organization_id is null then
      return jsonb_build_object('status', 'unchanged');
    end if;
    delete from public.organization_setup_provider_waits
    where organization_id = target_organization_id and wait_key = target_wait_key;
  else
    if before_row.status = new_status and before_row.note is not distinct from clean_note then
      return jsonb_build_object('status', 'unchanged');
    end if;
    insert into public.organization_setup_provider_waits (
      organization_id, wait_key, status, note, updated_by_email
    ) values (
      target_organization_id, target_wait_key, new_status, clean_note, clean_email
    )
    on conflict (organization_id, wait_key) do update
      set status = excluded.status,
          note = excluded.note,
          updated_at = now(),
          updated_by_email = excluded.updated_by_email
    returning * into after_row;
  end if;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_provider_wait',
    'organization',
    target_organization_id::text,
    case when before_row.organization_id is not null then
      jsonb_build_object('wait', target_wait_key, 'status', before_row.status, 'note', before_row.note)
    end,
    case when after_row.organization_id is not null then
      jsonb_build_object('wait', target_wait_key, 'status', after_row.status, 'note', after_row.note)
    else
      jsonb_build_object('wait', target_wait_key, 'status', null)
    end
  );

  return jsonb_build_object(
    'status', 'saved',
    'updated_at', after_row.updated_at,
    'email_client', coalesce(
      after_row.status = 'action_needed'
        and (before_row.status is distinct from 'action_needed' or before_row.note is distinct from after_row.note),
      false
    )
  );
end;
$$;

revoke all on function public.owner_set_setup_provider_wait(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.owner_set_setup_provider_wait(uuid, text, text, text, text) to service_role;

-- 3. Jafar's onboarding list ---------------------------------------------------------------------------------
-- Unchanged from 20261029090000_setup_ready_for_uplift.sql except: each client's open waits (not yet approved
-- or not possible) and those needing the client are counted and returned; a wait needing the client makes the
-- row the client's move ('provider_action') after an unread support message and a section sent back; a wait's
-- change counts as activity.

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
      ready.target_to,
      waits.open_count as waits_open,
      waits.action_count as waits_action,
      waits.changed_at as waits_changed_at
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
    -- E2: outside waits still open, and those needing the client; at most four rows, keyed by organization.
    cross join lateral (
      select
        (count(*) filter (where wait.status not in ('approved', 'unavailable')))::integer as open_count,
        (count(*) filter (where wait.status = 'action_needed'))::integer as action_count,
        max(wait.updated_at) as changed_at
      from public.organization_setup_provider_waits as wait
      where wait.organization_id = client.id
    ) as waits
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
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.waits_action > 0 then 'client'
        when measured.help_count > 0 or measured.sent_number is not null then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        when measured.waits_action > 0 then 'provider_action'
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
        measured.waits_changed_at
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
