-- Client onboarding C2: Jafar's client page — the setup a client sent to Uplift, and a switch to pause their
-- setup reminders.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §8 (submitted sections, history) and §5
-- (reminders stop after "a human deferral"). Storage: ADR 0005 — each send's snapshot is read against the setup
-- version it was taken with, so a question Jafar later rewords or removes still reads as the client saw it.

-- 1. The questions of one setup version ----------------------------------------------------------------------

-- The same shape as public.setup_published_catalogue, for any version, published or retired. Only the server
-- reads it, for Jafar's client page.
create function public.owner_setup_version_catalogue(target_version_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select private.setup_version_catalogue(target_version_id);
$$;

revoke all on function public.owner_setup_version_catalogue(uuid) from public, anon, authenticated;
grant execute on function public.owner_setup_version_catalogue(uuid) to service_role;

-- 2. Pausing setup reminders --------------------------------------------------------------------------------

-- Uplift's deferral: while paused, no setup reminder goes out to this client. Resuming starts a fresh quiet
-- stretch, so the client is not sent a reminder the moment Jafar turns them back on. Recorded in Jafar's
-- history. Returns the reminder state; a business with no timer (one not provisioned as a paid client) raises.
create function public.owner_set_setup_reminders_paused(
	target_organization_id uuid,
	actor_email text,
	pause boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	before_row public.organization_setup_reminders;
	after_row public.organization_setup_reminders;
begin
	if target_organization_id is null or pause is null or coalesce(btrim(actor_email), '') = '' then
		raise exception 'Say which business and whether to pause.' using errcode = 'check_violation';
	end if;

	select * into before_row
	from public.organization_setup_reminders
	where organization_id = target_organization_id
	for update;
	if not found then
		raise exception 'This business has no setup reminders.' using errcode = 'no_data_found';
	end if;

	-- Already as asked: nothing to change or record.
	if (before_row.paused_at is not null) = pause then
		return jsonb_build_object(
			'paused_at', before_row.paused_at,
			'next_due_at', before_row.next_due_at,
			'reminders_sent', before_row.reminders_sent
		);
	end if;

	update public.organization_setup_reminders
	set paused_at = case when pause then now() end,
		last_activity_at = case when pause then last_activity_at else now() end,
		reminders_sent = case when pause then reminders_sent else 0 end,
		next_due_at = case when pause then next_due_at else now() + interval '24 hours' end
	where organization_id = target_organization_id
	returning * into after_row;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, before_state, after_state
	) values (
		btrim(actor_email),
		case when pause then 'organization.setup_reminders_paused' else 'organization.setup_reminders_resumed' end,
		'organization',
		target_organization_id::text,
		jsonb_build_object('paused_at', before_row.paused_at),
		jsonb_build_object('paused_at', after_row.paused_at)
	);

	return jsonb_build_object(
		'paused_at', after_row.paused_at,
		'next_due_at', after_row.next_due_at,
		'reminders_sent', after_row.reminders_sent
	);
end;
$$;

revoke all on function public.owner_set_setup_reminders_paused(uuid, text, boolean)
	from public, anon, authenticated;
grant execute on function public.owner_set_setup_reminders_paused(uuid, text, boolean) to service_role;

-- 3. The onboarding list knows about sends ------------------------------------------------------------------

-- A client who has sent their setup is waiting on Uplift's review, not on themselves. Otherwise unchanged
-- from 20261008100000_setup_show_if.sql.

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
      sent.submitted_at as sent_at
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
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message, a "need Uplift's help" answer and a setup sent to Uplift are Uplift's;
  -- everything else is the client's. Reviewing a send stays Uplift's move until stage C3 records the review.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.unread_count > 0 or measured.help_count > 0 or measured.sent_number is not null
          then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.unread_count > 0 then 'reply_to_support'
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
        measured.sent_at
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
