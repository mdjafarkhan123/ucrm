-- Client onboarding A5: Jafar edits the questions inside each setup stage, as part of the same draft he
-- edits the stages in (A4), and publishes them together.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §2.1. Decision:
-- docs/adr/0006-setup-questions-live-in-published-versions.md (§Consequences: A5 adds custom answer types and
-- the limits on built-in questions). The "show only if" rule (A5b) and photo or file answers (A5c) follow.
--
-- 1. Two more answer types for questions that are not built in: yes/no and date.
-- 2. An index to ask "has any client answered this question?" without reading every answer.
-- 3. Jafar's editor learns which of the draft's own questions clients have answered.
-- 4. owner_save_setup_draft_stage_items(): saves one stage's headings and questions in order. Rules the
--    database enforces whatever the screen does:
--    - A built-in question can be reworded, given a help line, made required or not, and moved within its
--      stage; it is never removed and never gets an answer type of its own.
--    - A question clients have answered never changes answer type; Jafar adds a new one instead.
--    - A new question's key is made from its stage and wording and is never one any version or any answer
--      has used, so an old answer can never attach itself to a different question.
--    - A removed question disappears from the draft; clients' answers to it stay stored.
-- 5. Publishing checks the answer-type rule again.

-- 1. Answer types ------------------------------------------------------------------------------------------

alter table public.setup_items drop constraint setup_items_kind_check;
alter table public.setup_items add constraint setup_items_kind_check
	check (kind in ('text', 'longtext', 'email', 'phone', 'choice', 'yes_no', 'date'));

-- 2. Answered questions ------------------------------------------------------------------------------------

create index organization_setup_answers_fact_key_idx on public.organization_setup_answers (fact_key);

-- 3. The editor's state ------------------------------------------------------------------------------------
--
-- Same as A4, plus `answered`: the draft's own questions that at least one client has answered, whose answer
-- type is therefore fixed. One indexed probe per question that is not built in.
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
		'answered', coalesce((
			select jsonb_agg(i.fact_key order by i.fact_key)
			from public.setup_items i
			join public.setup_versions v on v.id = i.version_id and v.status = 'draft'
			where i.item_type = 'question'
				and not i.built_in
				and exists (select 1 from public.organization_setup_answers a where a.fact_key = i.fact_key)
		), '[]'::jsonb),
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

-- 4. Saving one stage's items ------------------------------------------------------------------------------
--
-- `new_items` is the stage's whole list in order:
--   [{ "type": "heading", "label": "...", "hint": null },
--    { "type": "question", "fact_key": "business.public_name" | null, "label": "...", "hint": "..." | null,
--      "required": true, "can_defer": false, "kind": "text" | null,
--      "options": [{ "value": "a", "label": "A" }, ...] | null }, ...]
-- A question with no fact_key is new. `kind` and `options` are ignored for a built-in question. The API has
-- already checked lengths and shapes; the table's checks refuse anything it missed.
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

		if existing.built_in then
			insert into public.setup_items (
				version_id, stage_key, position, item_type, fact_key, label, hint, built_in, required, can_defer
			)
			values (
				draft.id, target_stage_key, item_position, 'question', this_key, item_label,
				nullif(btrim(item ->> 'hint'), ''), true, coalesce((item ->> 'required')::boolean, false),
				coalesce((item ->> 'can_defer')::boolean, false)
			);
			kept_keys := kept_keys || this_key;
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
			options, max_length
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
			end
		);
		kept_keys := kept_keys || this_key;
	end loop;

	update public.setup_versions set
		revision = revision + 1,
		updated_by_email = trim(actor_owner_email)
	where id = draft.id;

	return jsonb_build_object('saved', true, 'editor', private.setup_editor_state());
end;
$$;

revoke all on function public.owner_save_setup_draft_stage_items(uuid, integer, text, jsonb, text)
	from public, anon, authenticated;
grant execute on function public.owner_save_setup_draft_stage_items(uuid, integer, text, jsonb, text)
	to service_role;

-- 5. Publishing --------------------------------------------------------------------------------------------
--
-- Same as A4, plus: an answered question still has the answer type clients answered it in. The save refuses
-- this already; checked again because a client may have answered it since the draft was saved.
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

	update public.setup_versions set status = 'superseded', superseded_at = now() where status = 'published';
	update public.setup_versions set
		status = 'published',
		published_at = now(),
		published_by_email = trim(actor_owner_email)
	where id = draft.id;

	return jsonb_build_object('published', true, 'editor', private.setup_editor_state());
end;
$$;
