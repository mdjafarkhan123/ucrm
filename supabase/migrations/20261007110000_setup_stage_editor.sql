-- Client onboarding A4: Jafar edits the setup wizard's stages as a draft and publishes it, and each client
-- sees only the stages their package includes.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §2.1. Decision:
-- docs/adr/0006-setup-questions-live-in-published-versions.md (§Consequences: A4 adds draft creation, publish
-- and the stage editor). The draft-and-publish flow follows the package builder's (ADR 0003): one draft at a
-- time, saved whole with the revision it was loaded at so a second tab cannot silently overwrite the first.
--
-- 1. setup_versions gains a revision and who last saved the draft.
-- 2. private.setup_version_catalogue(): any version in the shape setup_published_catalogue() already returns.
-- 3. setup_organization_service_keys(): the services of the organization's current package edition. A stage
--    tied to a service shows only when this list includes it.
-- 4. Jafar's commands: read the editor, start a draft, save its stages, publish, discard. Rules the database
--    enforces whatever the screen does:
--    - A stage holding a built-in question can be renamed and moved, but never removed or limited to one
--      service: the app copies those answers into CRM settings, so every client must be asked them.
--    - A new stage's key comes from its title and is never one any earlier version used, so a client's old
--      "done" mark or support chat can never attach itself to a different stage.
-- 5. Jafar's onboarding list counts each client's progress against the stages their package includes.

-- 1. Revision -----------------------------------------------------------------------------------------------

alter table public.setup_versions
	add column revision integer not null default 1 check (revision > 0),
	add column updated_by_email text;

-- 2. Any version as a catalogue ----------------------------------------------------------------------------

create or replace function private.setup_version_catalogue(target_version_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
	select jsonb_build_object(
		'version_id', v.id,
		'version_number', v.version_number,
		'stages', coalesce((
			select jsonb_agg(jsonb_build_object(
				'key', s.stage_key,
				'title', s.title,
				'description', s.description,
				'service_key', s.service_key,
				'items', coalesce((
					select jsonb_agg(jsonb_build_object(
						'type', i.item_type,
						'fact_key', i.fact_key,
						'label', i.label,
						'hint', i.hint,
						'built_in', i.built_in,
						'required', i.required,
						'can_defer', i.can_defer,
						'kind', i.kind,
						'options', i.options,
						'max_length', i.max_length
					) order by i.position)
					from public.setup_items i
					where i.version_id = s.version_id and i.stage_key = s.stage_key
				), '[]'::jsonb)
			) order by s.position)
			from public.setup_stages s
			where s.version_id = v.id
		), '[]'::jsonb)
	)
	from public.setup_versions v
	where v.id = target_version_id;
$$;

revoke all on function private.setup_version_catalogue(uuid) from public, anon, authenticated;

-- Same output as before; the body now shares the builder Jafar's editor reads drafts with.
create or replace function public.setup_published_catalogue()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select private.setup_version_catalogue(v.id)
	from public.setup_versions v
	where v.status = 'published';
$$;

-- 3. The organization's services ---------------------------------------------------------------------------
--
-- Security invoker: members already read their own agreements and agreed editions through RLS, and the service
-- role reads every organization's. Anyone else gets an empty list. The current agreement is chosen exactly as
-- private.organization_agreement_edition chooses it.
create or replace function public.setup_organization_service_keys(target_organization_id uuid)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
	select coalesce(array(
		select distinct service ->> 'service_key'
		from public.package_editions e
		cross join lateral jsonb_array_elements(e.included_services) as service
		where e.id = (
			select a.edition_id
			from public.organization_package_agreements a
			where a.organization_id = target_organization_id
				and a.effective_from <= now()
				and a.cancelled_at is null
			order by a.effective_from desc, a.created_at desc
			limit 1
		)
			and service ->> 'service_key' is not null
	), '{}'::text[]);
$$;

revoke all on function public.setup_organization_service_keys(uuid) from public, anon;
grant execute on function public.setup_organization_service_keys(uuid) to authenticated, service_role;

-- 4. Jafar's editor ----------------------------------------------------------------------------------------

create or replace function private.setup_editor_state()
returns jsonb
language sql
stable
set search_path = ''
as $$
	select jsonb_build_object(
		'published', (
			select private.setup_version_catalogue(v.id) || jsonb_build_object(
				'published_at', v.published_at,
				'published_by_email', v.published_by_email
			)
			from public.setup_versions v where v.status = 'published'
		),
		'draft', (
			select private.setup_version_catalogue(v.id) || jsonb_build_object(
				'revision', v.revision,
				'created_at', v.created_at,
				'updated_at', v.updated_at,
				'updated_by_email', v.updated_by_email
			)
			from public.setup_versions v where v.status = 'draft'
		),
		'services', coalesce((
			select jsonb_agg(jsonb_build_object(
				'key', s.service_key,
				'name', s.name,
				'archived', s.archived_at is not null
			) order by s.archived_at nulls first, s.sort_order)
			from public.package_services s
		), '[]'::jsonb),
		'history', coalesce((
			select jsonb_agg(jsonb_build_object(
				'version_number', h.version_number,
				'status', h.status,
				'published_at', h.published_at,
				'published_by_email', h.published_by_email
			) order by h.version_number desc)
			from (
				select * from public.setup_versions v
				where v.status <> 'draft'
				order by v.version_number desc
				limit 10
			) h
		), '[]'::jsonb)
	);
$$;

create or replace function public.owner_setup_editor()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select private.setup_editor_state();
$$;

-- Starts a draft as a copy of the published version, or returns the draft already open.
create or replace function public.owner_start_setup_draft(actor_owner_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	published_id uuid;
	draft_id uuid;
begin
	-- Two tabs pressing Start at once: the second waits here, then finds the first one's draft.
	perform pg_advisory_xact_lock(hashtext('setup_versions_draft'));

	if exists (select 1 from public.setup_versions v where v.status = 'draft') then
		return private.setup_editor_state();
	end if;

	select v.id into published_id from public.setup_versions v where v.status = 'published';
	if published_id is null then
		raise exception 'There is no published setup to start a draft from.' using errcode = 'P0002';
	end if;

	insert into public.setup_versions (version_number, status, updated_by_email)
	values (
		(select max(v.version_number) + 1 from public.setup_versions v),
		'draft',
		trim(actor_owner_email)
	)
	returning id into draft_id;

	insert into public.setup_stages (version_id, stage_key, title, description, service_key, position)
	select draft_id, s.stage_key, s.title, s.description, s.service_key, s.position
	from public.setup_stages s where s.version_id = published_id;

	insert into public.setup_items (
		version_id, stage_key, position, item_type, fact_key, label, hint, built_in, required, can_defer, kind,
		options, max_length
	)
	select draft_id, i.stage_key, i.position, i.item_type, i.fact_key, i.label, i.hint, i.built_in, i.required,
		i.can_defer, i.kind, i.options, i.max_length
	from public.setup_items i where i.version_id = published_id;

	return private.setup_editor_state();
end;
$$;

-- Saves the draft's whole stage list in order. `new_stages` is
--   [{ "key": "business" | null, "title": "...", "description": "...", "service_key": "website" | null }, ...]
-- A stage left out is removed with its questions; a stage with no key is new.
create or replace function public.owner_save_setup_draft_stages(
	target_version_id uuid,
	loaded_revision integer,
	new_stages jsonb,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.setup_versions;
	stage jsonb;
	stage_position integer := 0;
	this_key text;
	stage_title text;
	stage_service text;
	existing public.setup_stages;
	base_key text;
	suffix integer;
	kept_keys text[] := '{}';
	refused_title text;
begin
	select v.* into draft from public.setup_versions v where v.id = target_version_id for update;
	if draft.id is null or draft.status <> 'draft' then
		raise exception 'This draft no longer exists. It may have been published or discarded in another tab.'
			using errcode = 'P0002';
	end if;
	if draft.revision <> loaded_revision then
		return jsonb_build_object('saved', false, 'reason', 'stale', 'editor', private.setup_editor_state());
	end if;

	if jsonb_typeof(new_stages) <> 'array' or jsonb_array_length(new_stages) not between 1 and 30 then
		raise exception 'Setup needs between 1 and 30 stages.' using errcode = 'check_violation';
	end if;

	if exists (
		select 1 from jsonb_array_elements(new_stages) as s(value)
		group by lower(btrim(s.value ->> 'title')) having count(*) > 1
	) then
		raise exception 'Two stages have the same name. Give each stage its own name.'
			using errcode = 'unique_violation';
	end if;

	-- Removed stages first, so a refused removal changes nothing.
	select s.title into refused_title
	from public.setup_stages s
	where s.version_id = draft.id
		and not exists (
			select 1 from jsonb_array_elements(new_stages) as n(value) where n.value ->> 'key' = s.stage_key
		)
		and exists (
			select 1 from public.setup_items i
			where i.version_id = s.version_id and i.stage_key = s.stage_key and i.built_in
		)
	limit 1;
	if refused_title is not null then
		raise exception '"%" holds built-in questions, so it cannot be removed.', refused_title
			using errcode = 'check_violation';
	end if;

	delete from public.setup_stages s
	where s.version_id = draft.id
		and not exists (
			select 1 from jsonb_array_elements(new_stages) as n(value) where n.value ->> 'key' = s.stage_key
		);

	for stage in select value from jsonb_array_elements(new_stages) loop
		stage_position := stage_position + 1;
		this_key := nullif(stage ->> 'key', '');
		stage_title := btrim(coalesce(stage ->> 'title', ''));
		stage_service := nullif(stage ->> 'service_key', '');

		existing := null;
		if this_key is not null then
			select s.* into existing from public.setup_stages s
			where s.version_id = draft.id and s.stage_key = this_key;
			if existing.stage_key is null then
				raise exception 'A stage in this draft no longer exists. Reload the page and try again.'
					using errcode = 'P0002';
			end if;
		end if;

		if stage_service is not null then
			if not exists (select 1 from public.package_services p where p.service_key = stage_service) then
				raise exception 'The service for "%" no longer exists.', stage_title using errcode = 'foreign_key_violation';
			end if;
			-- An archived service may stay on a stage that already had it, but is not offered for new ones.
			if exists (
				select 1 from public.package_services p
				where p.service_key = stage_service and p.archived_at is not null
			) and stage_service is distinct from existing.service_key then
				raise exception 'That service is archived. Choose another for "%".', stage_title
					using errcode = 'check_violation';
			end if;
		end if;

		if existing.stage_key is not null then
			if stage_service is distinct from existing.service_key and exists (
				select 1 from public.setup_items i
				where i.version_id = draft.id and i.stage_key = this_key and i.built_in
			) then
				raise exception '"%" holds built-in questions, so every client must see it.', stage_title
					using errcode = 'check_violation';
			end if;

			update public.setup_stages s set
				title = stage_title,
				description = btrim(coalesce(stage ->> 'description', '')),
				service_key = stage_service,
				position = stage_position
			where s.version_id = draft.id and s.stage_key = this_key;
		else
			-- A key no version has ever used: answers, done marks and support chats refer to stage keys.
			base_key := left(trim(both '_' from regexp_replace(lower(stage_title), '[^a-z0-9]+', '_', 'g')), 34);
			if base_key !~ '^[a-z][a-z0-9_]*$' then
				base_key := left('stage_' || base_key, 34);
			end if;
			this_key := base_key;
			suffix := 1;
			while exists (select 1 from public.setup_stages s where s.stage_key = this_key)
				or this_key = any (kept_keys) loop
				suffix := suffix + 1;
				this_key := base_key || '_' || suffix;
			end loop;

			insert into public.setup_stages (version_id, stage_key, title, description, service_key, position)
			values (
				draft.id, this_key, stage_title, btrim(coalesce(stage ->> 'description', '')), stage_service,
				stage_position
			);
		end if;
		kept_keys := kept_keys || this_key;
	end loop;

	update public.setup_versions set
		revision = revision + 1,
		updated_by_email = trim(actor_owner_email)
	where id = draft.id;

	return jsonb_build_object('saved', true, 'editor', private.setup_editor_state());
end;
$$;

-- Publishes the saved draft exactly as saved. The version clients saw until now becomes history.
create or replace function public.owner_publish_setup_draft(
	target_version_id uuid,
	loaded_revision integer,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.setup_versions;
	missing_fact text;
begin
	select v.* into draft from public.setup_versions v where v.id = target_version_id for update;
	if draft.id is null or draft.status <> 'draft' then
		raise exception 'This draft no longer exists. It may have been published or discarded in another tab.'
			using errcode = 'P0002';
	end if;
	if draft.revision <> loaded_revision then
		return jsonb_build_object('published', false, 'reason', 'stale', 'editor', private.setup_editor_state());
	end if;

	-- The save refuses this already; checked again because a built-in question must never disappear.
	select i.fact_key into missing_fact
	from public.setup_items i
	join public.setup_versions p on p.id = i.version_id and p.status = 'published'
	where i.built_in
		and not exists (
			select 1 from public.setup_items d where d.version_id = draft.id and d.fact_key = i.fact_key
		)
	limit 1;
	if missing_fact is not null then
		raise exception 'The built-in question % is missing from this draft.', missing_fact
			using errcode = 'check_violation';
	end if;

	update public.setup_versions set status = 'superseded', superseded_at = now() where status = 'published';
	update public.setup_versions set
		status = 'published',
		published_at = now(),
		published_by_email = trim(actor_owner_email)
	where id = draft.id;

	return jsonb_build_object('published', true, 'editor', private.setup_editor_state());
end;
$$;

create or replace function public.owner_discard_setup_draft(target_version_id uuid, loaded_revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.setup_versions;
begin
	select v.* into draft from public.setup_versions v where v.id = target_version_id for update;
	if draft.id is null or draft.status <> 'draft' then
		raise exception 'This draft no longer exists. It may have been published or discarded in another tab.'
			using errcode = 'P0002';
	end if;
	if draft.revision <> loaded_revision then
		return jsonb_build_object('discarded', false, 'reason', 'stale', 'editor', private.setup_editor_state());
	end if;
	delete from public.setup_versions where id = draft.id;
	return jsonb_build_object('discarded', true, 'editor', private.setup_editor_state());
end;
$$;

revoke all on function private.setup_editor_state() from public, anon, authenticated;
revoke all on function public.owner_setup_editor() from public, anon, authenticated;
revoke all on function public.owner_start_setup_draft(text) from public, anon, authenticated;
revoke all on function public.owner_save_setup_draft_stages(uuid, integer, jsonb, text) from public, anon, authenticated;
revoke all on function public.owner_publish_setup_draft(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.owner_discard_setup_draft(uuid, integer) from public, anon, authenticated;
grant execute on function public.owner_setup_editor() to service_role;
grant execute on function public.owner_start_setup_draft(text) to service_role;
grant execute on function public.owner_save_setup_draft_stages(uuid, integer, jsonb, text) to service_role;
grant execute on function public.owner_publish_setup_draft(uuid, integer, text) to service_role;
grant execute on function public.owner_discard_setup_draft(uuid, integer) to service_role;

-- 5. Jafar's onboarding list counts only each client's own stages ------------------------------------------
--
-- `setup_catalogue` entries gain `service_key` (null for everyone):
--   [{ "key": "business", "service_key": null, "facts": [...], "required": [...] }, ...]
-- Each client's sections, answers and next step count only the stages whose service their current package
-- edition includes, and the row reports the client's own totals. Otherwise unchanged from C1.

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
      cardinality(own.fact_keys) as facts_total,
      answers.answered,
      answers.help_count,
      answers.last_answer_at,
      sections.done_count,
      sections.next_section_key,
      sections.last_section_at,
      support.unread_count
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
    cross join lateral (
      select
        count(*)::integer as answered,
        (count(*) filter (where answer.availability = 'need_help'))::integer as help_count,
        max(answer.updated_at) as last_answer_at
      from public.organization_setup_answers as answer
      where answer.organization_id = client.id
        and answer.fact_key = any (own.fact_keys)
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
            where not exists (
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
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message and a "need Uplift's help" answer are Uplift's; everything else is the client's.
  -- Send to Uplift arrives with B13; until then a client with every task done is still the one to act.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.unread_count > 0 or measured.help_count > 0 then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.help_count > 0 then 'help_with_answers'
        when measured.welcome_seen_at is null and measured.answered = 0 then 'start_setup'
        when measured.next_section_key is not null then 'finish_section'
        else 'send_to_uplift'
      end as next_action,
      greatest(
        measured.account_created_at,
        measured.welcome_seen_at,
        measured.last_answer_at,
        measured.last_section_at
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
