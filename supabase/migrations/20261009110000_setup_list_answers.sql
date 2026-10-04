-- Client onboarding A5e: add-another lists (plan §2.1; docs/client-onboarding-setup-content-blueprint.md
-- "Structured" and "Repeatable" answers).
--
-- 1. A question that is not built in may be a list: rows the client adds, edits and removes, each row a few
--    named boxes Jafar chose (short or long text, phone, email, web link, date, number, money, yes/no, pick
--    one, or one photo or file). A list allowed one row is a plain form, for one person or one address. The
--    answer is stored as JSON: [{"id": "<row id>", "values": {"<box key>": <value>}}]. Each row keeps its id
--    so a later question can pick rows without copying them (A5f). What a row may hold is checked in
--    src/lib/setup/lists.ts, as for every type.
-- 2. The catalogue, the draft copy and the stage save carry the boxes and the row limit. An answered list
--    keeps its boxes and their types, as an answered question keeps its type.
-- 3. A file box's File is linked to the organization exactly as a photo or file answer's is (A5c).

-- 1. The columns -----------------------------------------------------------------------------------------

-- One list's boxes: 1 to 8 of {key, label, kind, required}, plus a pick-one box's choices and a file box's kinds.
create or replace function private.setup_list_fields_ok(fields jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
	select jsonb_typeof(fields) = 'array'
		and jsonb_array_length(fields) between 1 and 8
		and not exists (
			select 1 from jsonb_array_elements(fields) as f(value)
			where jsonb_typeof(f.value) <> 'object'
				or (f.value - array['key', 'label', 'kind', 'required', 'options', 'file_kinds']) <> '{}'::jsonb
				or coalesce(f.value ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,39}$'
				or jsonb_typeof(f.value -> 'label') is distinct from 'string'
				or char_length(btrim(f.value ->> 'label')) not between 1 and 80
				or coalesce(f.value ->> 'kind', '') not in (
					'text', 'longtext', 'phone', 'email', 'url', 'date', 'number', 'money', 'yes_no', 'choice', 'file'
				)
				or jsonb_typeof(f.value -> 'required') is distinct from 'boolean'
				or ((f.value ->> 'kind') = 'choice') <> (f.value ? 'options')
				or ((f.value ->> 'kind') = 'file') <> (f.value ? 'file_kinds')
				or (f.value ? 'options' and (
					jsonb_typeof(f.value -> 'options') <> 'array'
					or jsonb_array_length(f.value -> 'options') not between 2 and 50
					or exists (
						select 1 from jsonb_array_elements(f.value -> 'options') as o(value)
						where coalesce(o.value ->> 'value', '') !~ '^[a-z0-9_]{1,60}$'
							or char_length(btrim(coalesce(o.value ->> 'label', ''))) not between 1 and 100
					)
				))
				or (f.value ? 'file_kinds' and (
					jsonb_typeof(f.value -> 'file_kinds') <> 'array'
					or jsonb_array_length(f.value -> 'file_kinds') not between 1 and 3
					or exists (
						select 1 from jsonb_array_elements(f.value -> 'file_kinds') as k(value)
						where k.value #>> '{}' not in ('photo', 'document', 'audio')
					)
				))
		)
		and (
			select count(distinct f.value ->> 'key') from jsonb_array_elements(fields) as f(value)
		) = jsonb_array_length(fields);
$$;

alter table public.setup_items drop constraint setup_items_kind_check;
alter table public.setup_items add constraint setup_items_kind_check
	check (kind in (
		'text', 'longtext', 'email', 'phone', 'choice', 'multi_choice', 'yes_no', 'yes_no_unsure', 'date', 'url',
		'number', 'money', 'percentage', 'distance', 'duration', 'colours', 'file', 'list'
	));

alter table public.setup_items
	add column list_fields jsonb,
	add column max_rows smallint,
	add constraint setup_items_list_fields_check check (
		(kind = 'list') = (list_fields is not null)
		and (list_fields is null or private.setup_list_fields_ok(list_fields))
	),
	add constraint setup_items_max_rows_check check (
		(kind = 'list') = (max_rows is not null)
		and (max_rows is null or max_rows in (1, 3, 5, 10, 20, 50))
	);

comment on column public.setup_items.list_fields is
	'An add-another list: the boxes each row holds — key, label, kind, required, and choices or file kinds.';
comment on column public.setup_items.max_rows is
	'An add-another list: the most rows one answer may hold (1, 3, 5, 10, 20 or 50). One row is a plain form.';

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
		options, allow_other, max_choices, file_kinds, max_files, list_fields, max_rows, max_length, show_if
	)
	select draft_id, i.stage_key, i.position, i.item_type, i.fact_key, i.label, i.hint, i.built_in, i.required,
		i.can_defer, i.kind, i.options, i.allow_other, i.max_choices, i.file_kinds, i.max_files, i.list_fields,
		i.max_rows, i.max_length, i.show_if
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
			options, allow_other, max_choices, file_kinds, max_files, list_fields, max_rows, max_length, show_if
		)
		values (
			draft.id, target_stage_key, item_position, 'question', this_key, item_label,
			nullif(btrim(item ->> 'hint'), ''), false, coalesce((item ->> 'required')::boolean, false),
			coalesce((item ->> 'can_defer')::boolean, false), item_kind,
			case when item_kind in ('choice', 'multi_choice') then item -> 'options' end,
			item_kind in ('choice', 'multi_choice') and coalesce((item ->> 'allow_other')::boolean, false),
			case when item_kind = 'multi_choice' then (item ->> 'max_choices')::smallint end,
			-- A photo or file question: the kinds of file it accepts, and how many.
			case when item_kind = 'file' then array(
				select distinct k.value from jsonb_array_elements_text(item -> 'file_kinds') as k(value) order by k.value
			) end,
			case when item_kind = 'file' then (item ->> 'max_files')::smallint end,
			-- An add-another list: its boxes, and the most rows a client may add.
			case when item_kind = 'list' then item -> 'list_fields' end,
			case when item_kind = 'list' then (item ->> 'max_rows')::smallint end,
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

-- 3. File boxes ------------------------------------------------------------------------------------------

-- Every File id an answer holds: a photo or file answer's list of ids, or the file boxes in a list's rows.
-- Other answers hold ids too rarely to matter — a tick-several answer's words — and only a setup File of the
-- same organization is ever linked.
create or replace function private.setup_answer_file_ids(answer jsonb)
returns setof text
language sql
immutable
set search_path = ''
as $$
	select held.file_id
	from jsonb_array_elements(case when jsonb_typeof(answer) = 'array' then answer else '[]'::jsonb end) as e(value)
	cross join lateral (
		select e.value #>> '{}' as file_id where jsonb_typeof(e.value) = 'string'
		union all
		select cell.value #>> '{}'
		from jsonb_each(
			case when jsonb_typeof(e.value -> 'values') = 'object' then e.value -> 'values' else '{}'::jsonb end
		) as cell(key, value)
		where jsonb_typeof(cell.value) = 'string'
	) as held
	where held.file_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;

revoke all on function private.setup_answer_file_ids(jsonb) from public, anon, authenticated;

-- Unchanged from A5c except that it reads ids through private.setup_answer_file_ids.
create or replace function private.sync_setup_answer_file_links(target_organization_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
	delete from public.file_links link
	where link.organization_id = target_organization_id
		and link.entity_type = 'organization'
		and link.entity_id = target_organization_id
		and link.role = 'setup_answer'
		and not link.protected
		and not exists (
			select 1 from public.organization_setup_answers a
			cross join lateral private.setup_answer_file_ids(a.value) as held(file_id)
			where a.organization_id = target_organization_id
				and held.file_id = link.file_id::text
		);

	insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
	select distinct f.organization_id, f.id, 'organization', target_organization_id, 'setup_answer', f.uploaded_by
	from public.organization_setup_answers a
	cross join lateral private.setup_answer_file_ids(a.value) as held(file_id)
	join public.files f on f.id = held.file_id::uuid
	where a.organization_id = target_organization_id
		and f.organization_id = target_organization_id
		and f.origin_role = 'setup_answer'
		and f.processing_state = 'available'
		and f.trashed_at is null
	on conflict (file_id, entity_type, entity_id, role) do nothing;
end;
$$;

revoke all on function private.sync_setup_answer_file_links(uuid) from public, anon, authenticated;

-- The worker's finish: unchanged from A5c except that a File in a list's file box counts as held.
create or replace function public.finalize_file_processing(
  target_file_id uuid,
  target_claim_token uuid,
  target_state text,
  target_checksum_sha256 text default null,
  target_error text default null,
  target_thumbnail_object_key text default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed public.files;
  finalized public.files;
begin
  if target_state not in ('available', 'failed', 'quarantined') then
    raise exception 'A file can only finish processing as available, failed or quarantined.'
      using errcode = 'check_violation';
  end if;

  if target_state = 'available' and target_checksum_sha256 is null then
    raise exception 'A file cannot be made available without the checksum from its verification pass.'
      using errcode = 'check_violation';
  end if;

  select * into claimed
  from public.files
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending'
  for update;

  if claimed.id is null then
    raise exception 'That file processing claim is no longer current.'
      using errcode = 'no_data_found';
  end if;

  if target_thumbnail_object_key is not null
     and target_thumbnail_object_key is distinct from claimed.object_key || '.thumb.jpg' then
    raise exception 'That preview does not belong to this file.'
      using errcode = 'check_violation';
  end if;

  if target_state <> 'available' and target_thumbnail_object_key is not null then
    raise exception 'Only an available file can carry a preview.'
      using errcode = 'check_violation';
  end if;

  update public.files
  set processing_state = target_state,
      checksum_sha256 = coalesce(target_checksum_sha256, checksum_sha256),
      thumbnail_object_key = coalesce(target_thumbnail_object_key, thumbnail_object_key),
      scanned_at = case when target_state = 'available' then now() else scanned_at end,
      processing_error = case when target_state = 'available' then null else target_error end,
      claimed_at = null,
      claim_token = null
  where id = claimed.id
  returning * into finalized;

  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_id is not null
    and finalized.origin_role not in ('note_file', 'setup_answer')
    and finalized.origin_type = any (
      array[
        'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization',
        'marketing_campaign'
      ]
    )
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    values (
      finalized.organization_id, finalized.id, finalized.origin_type, finalized.origin_id,
      finalized.origin_role, finalized.uploaded_by
    )
    on conflict (file_id, entity_type, entity_id, role) do nothing;

    -- The logo is a singleton: this File becomes the one the sidebar, quotes and invoices render from, and
    -- whatever File held that job before is unlinked (not trashed -- an already-sent quote freezes its own
    -- copy of the object_key text below, so the old File and its R2 object must survive).
    if finalized.origin_type = 'organization' and finalized.origin_role = 'logo' then
      delete from public.file_links
      where organization_id = finalized.organization_id
        and entity_type = 'organization'
        and role = 'logo'
        and file_id <> finalized.id
        and not protected;

      update public.organization_settings
      set logo_object_key = finalized.object_key,
          branding_revision = branding_revision + 1,
          branding_updated_by = finalized.uploaded_by,
          branding_updated_at = now()
      where organization_id = finalized.organization_id;

      insert into public.organization_settings_audit (
        organization_id, section, changed_fields, actor_user_id
      )
      values (finalized.organization_id, 'branding', array['logo'], finalized.uploaded_by);
    end if;
  end if;

  -- An item photo is linked only while the item still holds it. The item's own trigger links it when the
  -- photo is chosen after this point; a photo picked and then abandoned is never linked at all.
  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_type = 'catalog_item'
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    select finalized.organization_id, finalized.id, 'catalog_item', item.id, 'item_photo', finalized.uploaded_by
    from public.catalog_items item
    where item.organization_id = finalized.organization_id
      and item.id = finalized.origin_id
      and item.image_file_id = finalized.id
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  -- A Note's File, the same way: linked only to the records of the Notes that hold it.
  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_role = 'note_file'
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    select finalized.organization_id, finalized.id, link.entity_type, link.entity_id, 'note_file', held.created_by
    from public.note_files as held
    join public.note_links as link on link.note_id = held.note_id
    where held.organization_id = finalized.organization_id
      and held.file_id = finalized.id
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  -- Client onboarding A5c: a setup File, linked only while one of the organization's answers holds it —
  -- A5e: including a file box in a row of an add-another list.
  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_role = 'setup_answer'
    and exists (
      select 1 from public.organization_setup_answers a
      cross join lateral private.setup_answer_file_ids(a.value) as held(file_id)
      where a.organization_id = finalized.organization_id
        and held.file_id = finalized.id::text
    )
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    values (
      finalized.organization_id, finalized.id, 'organization', finalized.organization_id, 'setup_answer',
      finalized.uploaded_by
    )
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  return finalized;
end;
$$;
