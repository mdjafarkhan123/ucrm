-- Client onboarding A5b: "show this question only if …" (plan §2.1; the approved setup content's Conditional
-- rows, docs/client-onboarding-setup-content-blueprint.md).
--
-- A question may carry up to five conditions, all of which must hold for a client to be asked it:
--   { "fact_key": "<earlier question>", "values": ["yes", ...] }  — that earlier answer is one of these
--   { "service_key": "<service>" }                                — the client's package includes it
-- The earlier question comes before it in the setup (an earlier stage, or higher in the same stage) and is a
-- pick-one or yes/no question, or a built-in choice such as country. When that earlier question is itself
-- hidden, or answered "I don't have this yet" / "I need Uplift's help", the condition does not hold. A hidden
-- question is not asked, counted or required; an answer it already has stays stored.
--
-- 1. setup_items.show_if, with its shape checked.
-- 2. The catalogue, the draft copy and the editor carry it.
-- 3. private.setup_version_rule_problem(): the first broken rule in a version, in words.
-- 4. Saving a stage's questions resolves rules naming a question added in the same save, then checks every
--    rule in the draft. Publishing checks again, because reordering or removing stages can break a rule.
-- 5. public.setup_hidden_fact_keys(): the questions one client is not asked, for Jafar's onboarding list.
--    Built-in choices' own values live in code (ADR 0006 decision 4), so the API checks rules on them.

-- 1. The rule ------------------------------------------------------------------------------------------------

create or replace function private.setup_show_if_shape_ok(rule jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
	select rule is null or (
		jsonb_typeof(rule) = 'array'
		and jsonb_array_length(rule) between 1 and 5
		and not exists (
			select 1
			from jsonb_array_elements(rule) as c(value)
			where not (
				jsonb_typeof(c.value) = 'object'
				and (
					(
						(select count(*) from jsonb_object_keys(c.value)) = 1
						and jsonb_typeof(c.value -> 'service_key') = 'string'
						and (c.value ->> 'service_key') ~ '^[a-z][a-z0-9_]{1,59}$'
					)
					or (
						(select count(*) from jsonb_object_keys(c.value)) = 2
						and jsonb_typeof(c.value -> 'fact_key') = 'string'
						and (c.value ->> 'fact_key') ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
						and char_length(c.value ->> 'fact_key') <= 80
						and jsonb_typeof(c.value -> 'values') = 'array'
						and jsonb_array_length(c.value -> 'values') between 1 and 60
						and not exists (
							select 1
							from jsonb_array_elements(c.value -> 'values') as v(value)
							where jsonb_typeof(v.value) <> 'string' or char_length(v.value #>> '{}') not between 1 and 120
						)
					)
				)
			)
		)
	);
$$;

revoke all on function private.setup_show_if_shape_ok(jsonb) from public, anon, authenticated;

alter table public.setup_items
	add column show_if jsonb,
	add constraint setup_items_show_if_check check (
		private.setup_show_if_shape_ok(show_if) and (item_type = 'question' or show_if is null)
	);

comment on column public.setup_items.show_if is
	'Null, or up to five conditions that must all hold for a client to be asked this question (client onboarding A5b).';

-- 2. Carried everywhere a version is read or copied ------------------------------------------------------

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
						'max_length', i.max_length,
						'show_if', i.show_if
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
		options, max_length, show_if
	)
	select draft_id, i.stage_key, i.position, i.item_type, i.fact_key, i.label, i.hint, i.built_in, i.required,
		i.can_defer, i.kind, i.options, i.max_length, i.show_if
	from public.setup_items i where i.version_id = published_id;

	return private.setup_editor_state();
end;
$$;

-- 3. The first broken rule in a version --------------------------------------------------------------------

create or replace function private.setup_version_rule_problem(target_version_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
	with questions as (
		select i.fact_key, i.label, i.kind, i.built_in, i.options, i.show_if, s.position as stage_position,
			i.position
		from public.setup_items i
		join public.setup_stages s on s.version_id = i.version_id and s.stage_key = i.stage_key
		where i.version_id = target_version_id and i.item_type = 'question'
	),
	conditions as (
		select q.label, q.stage_position, q.position, c.value as condition
		from questions q
		cross join lateral jsonb_array_elements(q.show_if) as c(value)
		where q.show_if is not null
	),
	problems as (
		select
			c.stage_position,
			c.position,
			case
				when c.condition ? 'service_key' then
					case when not exists (
						select 1 from public.package_services p where p.service_key = c.condition ->> 'service_key'
					) then format('"%s" depends on a service that is not in your service list.', c.label) end
				when source.fact_key is null then
					format('"%s" depends on a question that is no longer in the draft. Change or remove its rule first.',
						c.label)
				when (source.stage_position, source.position) >= (c.stage_position, c.position) then
					format('"%s" depends on "%s", which must come before it. Move it back above, or change the rule.',
						c.label, source.label)
				when not source.built_in and source.kind not in ('choice', 'yes_no') then
					format('"%s" depends on "%s", which is no longer a pick-one or yes/no question. Change the rule first.',
						c.label, source.label)
				when exists (
					select 1
					from jsonb_array_elements_text(c.condition -> 'values') as v(value)
					where (source.kind = 'yes_no' and v.value not in ('yes', 'no'))
						or (source.kind = 'choice' and not exists (
							select 1 from jsonb_array_elements(source.options) as o(value)
							where o.value ->> 'value' = v.value
						))
				) then
					format('"%s" depends on a choice of "%s" that has been removed. Change the rule first.',
						c.label, source.label)
			end as problem
		from conditions c
		left join questions source on source.fact_key = c.condition ->> 'fact_key'
	)
	select p.problem from problems p
	where p.problem is not null
	order by p.stage_position, p.position
	limit 1;
$$;

revoke all on function private.setup_version_rule_problem(uuid) from public, anon, authenticated;

-- 4. Saving and publishing -------------------------------------------------------------------------------
--
-- Each question in `new_items` may now carry `show_if`, as stored, except that a condition may name an
-- earlier row of the same list as { "item": <1-based position>, "values": [...] } — how the editor points at
-- a question added in this save, which has no key yet. Otherwise unchanged from A5.

create or replace function public.owner_save_setup_draft_stage_items(
	target_version_id uuid,
	loaded_revision integer,
	target_stage_key text,
	new_items jsonb,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.setup_versions;
	item jsonb;
	item_position integer := 0;
	this_key text;
	item_label text;
	item_kind text;
	existing public.setup_items;
	base_key text;
	suffix integer;
	kept_keys text[] := '{}';
	refused_label text;
	before_items jsonb;
	-- Each saved row's key by position, so a rule can name a question added in this same save.
	item_keys text[] := '{}';
	item_rule jsonb;
	condition jsonb;
	source_index integer;
	problem text;
begin
	select v.* into draft from public.setup_versions v where v.id = target_version_id for update;
	if draft.id is null or draft.status <> 'draft' then
		raise exception 'This draft no longer exists. It may have been published or discarded in another tab.'
			using errcode = 'P0002';
	end if;
	if draft.revision <> loaded_revision then
		return jsonb_build_object('saved', false, 'reason', 'stale', 'editor', private.setup_editor_state());
	end if;

	if not exists (
		select 1 from public.setup_stages s where s.version_id = draft.id and s.stage_key = target_stage_key
	) then
		raise exception 'This stage is no longer in the draft. Reload the page and try again.'
			using errcode = 'P0002';
	end if;

	if jsonb_typeof(new_items) <> 'array' or jsonb_array_length(new_items) > 80 then
		raise exception 'A stage can hold up to 80 headings and questions.' using errcode = 'check_violation';
	end if;

	if exists (
		select 1 from jsonb_array_elements(new_items) as n(value)
		where n.value ->> 'type' = 'question' and nullif(n.value ->> 'fact_key', '') is not null
		group by n.value ->> 'fact_key' having count(*) > 1
	) then
		raise exception 'A question appears twice. Reload the page and try again.' using errcode = 'unique_violation';
	end if;

	-- A built-in question left out would stop being asked.
	select i.label into refused_label
	from public.setup_items i
	where i.version_id = draft.id
		and i.stage_key = target_stage_key
		and i.built_in
		and not exists (
			select 1 from jsonb_array_elements(new_items) as n(value) where n.value ->> 'fact_key' = i.fact_key
		)
	limit 1;
	if refused_label is not null then
		raise exception '"%" is built in, so it cannot be removed.', refused_label using errcode = 'check_violation';
	end if;

	-- Every question named by key must already be in this stage of the draft.
	select n.value ->> 'label' into refused_label
	from jsonb_array_elements(new_items) as n(value)
	where n.value ->> 'type' = 'question'
		and nullif(n.value ->> 'fact_key', '') is not null
		and not exists (
			select 1 from public.setup_items i
			where i.version_id = draft.id and i.stage_key = target_stage_key and i.fact_key = n.value ->> 'fact_key'
		)
	limit 1;
	if refused_label is not null then
		raise exception '"%" is no longer in this stage. Reload the page and try again.', refused_label
			using errcode = 'P0002';
	end if;

	-- An answered question keeps its answer type.
	select i.label into refused_label
	from jsonb_array_elements(new_items) as n(value)
	join public.setup_items i
		on i.version_id = draft.id and i.stage_key = target_stage_key and i.fact_key = n.value ->> 'fact_key'
	where not i.built_in
		and i.kind is distinct from (n.value ->> 'kind')
		and exists (select 1 from public.organization_setup_answers a where a.fact_key = i.fact_key)
	limit 1;
	if refused_label is not null then
		raise exception 'Clients have answered "%", so its answer type cannot change. Add a new question instead.',
			refused_label using errcode = 'check_violation';
	end if;

	-- Keep what the rewritten list needs from the rows it replaces, then replace them.
	select coalesce(jsonb_object_agg(i.fact_key, to_jsonb(i)), '{}'::jsonb) into before_items
	from public.setup_items i
	where i.version_id = draft.id and i.stage_key = target_stage_key and i.item_type = 'question';

	delete from public.setup_items i where i.version_id = draft.id and i.stage_key = target_stage_key;

	for item in select value from jsonb_array_elements(new_items) loop
		item_position := item_position + 1;
		item_label := btrim(coalesce(item ->> 'label', ''));

		if item ->> 'type' = 'heading' then
			insert into public.setup_items (version_id, stage_key, position, item_type, label, hint)
			values (draft.id, target_stage_key, item_position, 'heading', item_label, nullif(btrim(item ->> 'hint'), ''));
			continue;
		end if;

		if item ->> 'type' <> 'question' then
			raise exception 'An item is neither a heading nor a question.' using errcode = 'check_violation';
		end if;

		this_key := nullif(item ->> 'fact_key', '');
		existing := null;
		if this_key is not null then
			existing := jsonb_populate_record(null::public.setup_items, before_items -> this_key);
		end if;

		-- "Show only if": a condition naming `item` points at an earlier row of this list by its position.
		item_rule := null;
		if jsonb_typeof(item -> 'show_if') = 'array' and jsonb_array_length(item -> 'show_if') > 0 then
			item_rule := '[]'::jsonb;
			for condition in select value from jsonb_array_elements(item -> 'show_if') loop
				if condition ? 'item' then
					source_index := (condition ->> 'item')::integer;
					if source_index < 1 or source_index >= item_position or item_keys[source_index] is null then
						raise exception '"%" can only depend on a question above it.', item_label
							using errcode = 'check_violation';
					end if;
					condition := (condition - 'item') || jsonb_build_object('fact_key', item_keys[source_index]);
				end if;
				item_rule := item_rule || jsonb_build_array(condition);
			end loop;
		end if;

		if existing.built_in then
			insert into public.setup_items (
				version_id, stage_key, position, item_type, fact_key, label, hint, built_in, required, can_defer,
				show_if
			)
			values (
				draft.id, target_stage_key, item_position, 'question', this_key, item_label,
				nullif(btrim(item ->> 'hint'), ''), true, coalesce((item ->> 'required')::boolean, false),
				coalesce((item ->> 'can_defer')::boolean, false), item_rule
			);
			kept_keys := kept_keys || this_key;
			item_keys[item_position] := this_key;
			continue;
		end if;

		item_kind := item ->> 'kind';

		if this_key is null then
			-- A key no version and no answer has ever used.
			base_key := left(trim(both '_' from regexp_replace(lower(item_label), '[^a-z0-9]+', '_', 'g')), 30);
			if base_key !~ '^[a-z][a-z0-9_]*$' then
				base_key := left('question_' || base_key, 30);
				base_key := rtrim(base_key, '_');
			end if;
			base_key := target_stage_key || '.' || base_key;
			this_key := base_key;
			suffix := 1;
			while exists (select 1 from public.setup_items i where i.fact_key = this_key)
				or exists (select 1 from public.organization_setup_answers a where a.fact_key = this_key)
				or this_key = any (kept_keys) loop
				suffix := suffix + 1;
				this_key := base_key || '_' || suffix;
			end loop;
		end if;

		insert into public.setup_items (
			version_id, stage_key, position, item_type, fact_key, label, hint, built_in, required, can_defer, kind,
			options, max_length, show_if
		)
		values (
			draft.id, target_stage_key, item_position, 'question', this_key, item_label,
			nullif(btrim(item ->> 'hint'), ''), false, coalesce((item ->> 'required')::boolean, false),
			coalesce((item ->> 'can_defer')::boolean, false), item_kind,
			case when item_kind = 'choice' then item -> 'options' end,
			-- A question keeps its own length limit while its type stays; a new or retyped one takes the default.
			case
				when existing.fact_key is not null and existing.kind = item_kind then existing.max_length
				when item_kind = 'text' then 200
				when item_kind = 'longtext' then 2000
			end,
			item_rule
		);
		kept_keys := kept_keys || this_key;
		item_keys[item_position] := this_key;
	end loop;

	-- Every rule in the draft still points at an earlier pick-one or yes/no question and its real choices,
	-- including rules in other stages that depend on a question this save removed or retyped.
	problem := private.setup_version_rule_problem(draft.id);
	if problem is not null then
		raise exception '%', problem using errcode = 'check_violation';
	end if;

	update public.setup_versions set
		revision = revision + 1,
		updated_by_email = trim(actor_owner_email)
	where id = draft.id;

	return jsonb_build_object('saved', true, 'editor', private.setup_editor_state());
end;
$$;

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
	retyped_label text;
	problem text;
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

	select d.label into retyped_label
	from public.setup_items d
	join public.setup_items p on p.fact_key = d.fact_key
	join public.setup_versions pv on pv.id = p.version_id and pv.status = 'published'
	where d.version_id = draft.id
		and not d.built_in
		and d.kind is distinct from p.kind
		and exists (select 1 from public.organization_setup_answers a where a.fact_key = d.fact_key)
	limit 1;
	if retyped_label is not null then
		raise exception 'Clients have answered "%", so its answer type cannot change. Add a new question instead.',
			retyped_label using errcode = 'check_violation';
	end if;

	-- Reordering or removing stages can leave a rule pointing at a later or missing question.
	problem := private.setup_version_rule_problem(draft.id);
	if problem is not null then
		raise exception '%', problem using errcode = 'check_violation';
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

-- 5. The questions one client is not asked ---------------------------------------------------------------
--
-- `setup_catalogue` is the onboarding list's catalogue; each entry may carry `rules`, its conditional
-- questions in order: [{ "fact_key": "...", "show_if": [...] }]. Walks them in setup order, so a question
-- whose earlier question is hidden is hidden too. Reads only this client's answers to rule sources, and
-- returns at once when no question has a rule.
create or replace function public.setup_hidden_fact_keys(
	setup_catalogue jsonb,
	client_fact_keys text[],
	target_organization_id uuid,
	client_service_keys text[]
)
returns text[]
language plpgsql
stable
set search_path = ''
as $$
declare
	rules jsonb;
	given jsonb;
	rule jsonb;
	condition jsonb;
	source text;
	answer jsonb;
	shown boolean;
	hidden text[] := '{}';
begin
	select coalesce(jsonb_agg(r.value order by s.position, r.position), '[]'::jsonb) into rules
	from jsonb_array_elements(setup_catalogue) with ordinality as s(value, position)
	cross join lateral jsonb_array_elements(coalesce(s.value -> 'rules', '[]'::jsonb))
		with ordinality as r(value, position)
	where nullif(s.value ->> 'service_key', '') is null
		or s.value ->> 'service_key' = any (client_service_keys);

	if jsonb_array_length(rules) = 0 then
		return hidden;
	end if;

	select coalesce(jsonb_object_agg(a.fact_key, a.value), '{}'::jsonb) into given
	from public.organization_setup_answers a
	where a.organization_id = target_organization_id
		and a.availability = 'have'
		and a.fact_key in (
			select c.value ->> 'fact_key'
			from jsonb_array_elements(rules) as r(value)
			cross join lateral jsonb_array_elements(r.value -> 'show_if') as c(value)
		);

	for rule in select value from jsonb_array_elements(rules) loop
		shown := true;
		for condition in select value from jsonb_array_elements(rule -> 'show_if') loop
			if condition ? 'service_key' then
				shown := coalesce((condition ->> 'service_key') = any (client_service_keys), false);
			else
				source := condition ->> 'fact_key';
				answer := given -> source;
				shown := coalesce(source = any (client_fact_keys), false)
					and not coalesce(source = any (hidden), false)
					and answer is not null
					and case jsonb_typeof(answer)
						when 'string' then (condition -> 'values') ? (answer #>> '{}')
						when 'array' then exists (
							select 1 from jsonb_array_elements_text(answer) as x(value)
							where (condition -> 'values') ? x.value
						)
						else false
					end;
			end if;
			exit when not shown;
		end loop;
		if not shown then
			hidden := hidden || (rule ->> 'fact_key');
		end if;
	end loop;

	return hidden;
end;
$$;

revoke all on function public.setup_hidden_fact_keys(jsonb, text[], uuid, text[]) from public, anon, authenticated;
grant execute on function public.setup_hidden_fact_keys(jsonb, text[], uuid, text[]) to service_role;

-- Jafar's onboarding list counts only the questions each client is asked. Otherwise unchanged from A4.

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

