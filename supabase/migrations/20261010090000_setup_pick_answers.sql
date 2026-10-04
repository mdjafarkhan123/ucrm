-- Client onboarding A5f: pick from an earlier list (plan §2.1; the blueprint's "Ordered selection", such as
-- "Which 3–5 services should Uplift promote first?").
--
-- 1. A question that is not built in may pick from the rows of an earlier add-another list question (A5e) —
--    in an earlier stage, or higher in the same stage. Jafar sets the fewest and most picks and whether the
--    client puts them in order. The answer is a JSON array of the picked rows' ids, so a row renamed later is
--    still the one picked and nothing is copied. What a pick may hold is checked in src/lib/setup/picks.ts.
-- 2. The catalogue, the draft copy and the stage save carry it. An answered pick keeps its list.
-- 3. Every pick still names an earlier list question; private.setup_version_rule_problem() says when not.
-- 4. A pick is asked only while its list is asked and has at least one row, so Jafar's onboarding list counts
--    it the same way: public.setup_hidden_fact_keys() learns the condition { fact_key, has_rows: true }.

-- 1. The columns -----------------------------------------------------------------------------------------

alter table public.setup_items drop constraint setup_items_kind_check;
alter table public.setup_items add constraint setup_items_kind_check
	check (kind in (
		'text', 'longtext', 'email', 'phone', 'choice', 'multi_choice', 'yes_no', 'yes_no_unsure', 'date', 'url',
		'number', 'money', 'percentage', 'distance', 'duration', 'colours', 'file', 'list', 'pick'
	));

alter table public.setup_items drop constraint setup_items_max_choices_check;
alter table public.setup_items
	add constraint setup_items_max_choices_check check (
		max_choices is null
		or (kind = 'multi_choice' and max_choices between 1 and jsonb_array_length(options) + allow_other::integer)
		or (kind = 'pick' and max_choices between 1 and 50)
	),
	add column pick_from text,
	add column min_choices smallint,
	add column ordered boolean not null default false,
	add constraint setup_items_pick_from_check check (
		(kind = 'pick') = (pick_from is not null)
		and (pick_from is null or pick_from ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$')
	),
	add constraint setup_items_min_choices_check check (
		min_choices is null or (
			kind = 'pick'
			and min_choices between 1 and 50
			and (max_choices is null or min_choices <= max_choices)
		)
	),
	add constraint setup_items_ordered_check check (not ordered or kind = 'pick');

comment on column public.setup_items.pick_from is
	'A pick question: the fact key of the earlier add-another list whose rows the client picks from.';
comment on column public.setup_items.min_choices is
	'A pick question: the fewest rows a client picks, or every row when the list holds fewer; null asks for one.';
comment on column public.setup_items.max_choices is
	'A tick-several or pick question accepts at most this many; null accepts any number.';
comment on column public.setup_items.ordered is
	'A pick question: the client puts the picked rows in order, most important first.';

-- 2. Carried everywhere a version is read, copied or saved ---------------------------------------------

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
						'allow_other', i.allow_other,
						'max_choices', i.max_choices,
						'file_kinds', to_jsonb(i.file_kinds),
						'max_files', i.max_files,
						'list_fields', i.list_fields,
						'max_rows', i.max_rows,
						'pick_from', i.pick_from,
						'min_choices', i.min_choices,
						'ordered', i.ordered,
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
		options, allow_other, max_choices, file_kinds, max_files, list_fields, max_rows, pick_from, min_choices, ordered, max_length, show_if
	)
	select draft_id, i.stage_key, i.position, i.item_type, i.fact_key, i.label, i.hint, i.built_in, i.required,
		i.can_defer, i.kind, i.options, i.allow_other, i.max_choices, i.file_kinds, i.max_files, i.list_fields,
		i.max_rows, i.pick_from, i.min_choices, i.ordered, i.max_length, i.show_if
	from public.setup_items i where i.version_id = published_id;

	return private.setup_editor_state();
end;
$$;

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
	item_pick_from text;
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

		-- A5f: the earlier list a pick question chooses from, named by key or, when added in this same save, by
		-- the position of a row above it.
		item_pick_from := null;
		if item_kind = 'pick' then
			if item -> 'pick_from' ? 'item' then
				source_index := (item -> 'pick_from' ->> 'item')::integer;
				if source_index < 1 or source_index >= item_position or item_keys[source_index] is null then
					raise exception '"%" can only pick from a list above it.', item_label using errcode = 'check_violation';
				end if;
				item_pick_from := item_keys[source_index];
			else
				item_pick_from := nullif(item -> 'pick_from' ->> 'fact_key', '');
			end if;
			if item_pick_from is null then
				raise exception 'Choose the list "%" picks from.', item_label using errcode = 'check_violation';
			end if;
		end if;

		-- An answered pick keeps its list: its answers name that list's rows.
		if item_kind = 'pick' and existing.kind = 'pick'
			and existing.pick_from is distinct from item_pick_from
			and exists (select 1 from public.organization_setup_answers a where a.fact_key = this_key) then
			raise exception 'Clients have answered "%", so the list it picks from cannot change. Add a new question instead.',
				item_label using errcode = 'check_violation';
		end if;

		-- An answered list keeps every box its rows already hold, with the same type; it may gain boxes and rename them.
		if item_kind = 'list' and existing.kind = 'list'
			and exists (select 1 from public.organization_setup_answers a where a.fact_key = this_key)
			and exists (
				select 1 from jsonb_array_elements(existing.list_fields) as old(value)
				where not exists (
					select 1 from jsonb_array_elements(item -> 'list_fields') as kept(value)
					where kept.value ->> 'key' = old.value ->> 'key' and kept.value ->> 'kind' = old.value ->> 'kind'
				)
			) then
			raise exception 'Clients have answered "%", so its boxes can be renamed and new ones added, but none removed or given a different type. Add a new question instead.',
				item_label using errcode = 'check_violation';
		end if;

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
			options, allow_other, max_choices, file_kinds, max_files, list_fields, max_rows, pick_from, min_choices, ordered, max_length, show_if
		)
		values (
			draft.id, target_stage_key, item_position, 'question', this_key, item_label,
			nullif(btrim(item ->> 'hint'), ''), false, coalesce((item ->> 'required')::boolean, false),
			coalesce((item ->> 'can_defer')::boolean, false), item_kind,
			case when item_kind in ('choice', 'multi_choice') then item -> 'options' end,
			item_kind in ('choice', 'multi_choice') and coalesce((item ->> 'allow_other')::boolean, false),
			case when item_kind in ('multi_choice', 'pick') then (item ->> 'max_choices')::smallint end,
			-- A photo or file question: the kinds of file it accepts, and how many.
			case when item_kind = 'file' then array(
				select distinct k.value from jsonb_array_elements_text(item -> 'file_kinds') as k(value) order by k.value
			) end,
			case when item_kind = 'file' then (item ->> 'max_files')::smallint end,
			-- An add-another list: its boxes, and the most rows a client may add.
			case when item_kind = 'list' then item -> 'list_fields' end,
			case when item_kind = 'list' then (item ->> 'max_rows')::smallint end,
			-- A pick from an earlier list: the list, the fewest picks, and whether the client orders them.
			item_pick_from,
			case when item_kind = 'pick' then (item ->> 'min_choices')::smallint end,
			item_kind = 'pick' and coalesce((item ->> 'ordered')::boolean, false),
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

-- 3. Every rule and every pick still points somewhere real ------------------------------------------------

-- Unchanged from A5d, plus the pick problems: a pick names a list question that comes before it.
create or replace function private.setup_version_rule_problem(target_version_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
	with questions as (
		select i.fact_key, i.label, i.kind, i.built_in, i.options, i.show_if, i.pick_from,
			s.position as stage_position, i.position
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
				when not source.built_in and source.kind not in ('choice', 'multi_choice', 'yes_no', 'yes_no_unsure') then
					format('"%s" depends on "%s", which is no longer a question with choices. Change the rule first.',
						c.label, source.label)
				when exists (
					select 1
					from jsonb_array_elements_text(c.condition -> 'values') as v(value)
					where (source.kind = 'yes_no' and v.value not in ('yes', 'no'))
						or (source.kind = 'yes_no_unsure' and v.value not in ('yes', 'no', 'not_sure'))
						or (source.kind in ('choice', 'multi_choice') and not exists (
							select 1 from jsonb_array_elements(source.options) as o(value)
							where o.value ->> 'value' = v.value
						))
				) then
					format('"%s" depends on a choice of "%s" that has been removed. Change the rule first.',
						c.label, source.label)
			end as problem
		from conditions c
		left join questions source on source.fact_key = c.condition ->> 'fact_key'
		union all
		select
			q.stage_position,
			q.position,
			case
				when source.fact_key is null then
					format('"%s" picks from a list that is no longer in the draft. Choose another list first.', q.label)
				when (source.stage_position, source.position) >= (q.stage_position, q.position) then
					format('"%s" picks from "%s", which must come before it. Move it back above, or choose another list.',
						q.label, source.label)
				when source.kind is distinct from 'list' then
					format('"%s" picks from "%s", which is no longer an add-another list. Choose another list first.',
						q.label, source.label)
			end
		from questions q
		left join questions source on source.fact_key = q.pick_from
		where q.pick_from is not null
	)
	select p.problem from problems p
	where p.problem is not null
	order by p.stage_position, p.position
	limit 1;
$$;

revoke all on function private.setup_version_rule_problem(uuid) from public, anon, authenticated;

-- 4. A pick is asked only while its list has a row -------------------------------------------------------

-- Unchanged from A5b, plus the condition { "fact_key": "<list>", "has_rows": true }: that list is asked and
-- its answer holds at least one row.
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
					and case
						when condition ? 'has_rows' then
							jsonb_typeof(answer) = 'array' and jsonb_array_length(answer) > 0
						when jsonb_typeof(answer) = 'string' then (condition -> 'values') ? (answer #>> '{}')
						when jsonb_typeof(answer) = 'array' then exists (
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
