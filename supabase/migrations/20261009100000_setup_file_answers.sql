-- Client onboarding A5c: a photo or file answer (plan §2.1; docs/client-onboarding-setup-content-blueprint.md).
--
-- 1. A question that is not built in may take files. Jafar picks which kinds it accepts (photos, documents,
--    voice recordings) and how many (1, 5, 10 or 20), the way a Google Forms file question does. The answer is
--    the list of the Files' ids. What it may hold is checked in src/lib/setup/catalogue.ts, as for every type.
-- 2. The catalogue, the draft copy and the stage save carry both settings.
-- 3. The files are ordinary File Manager Files (ADR 0002), uploaded with the role 'setup_answer'. Like a price
--    list item's photo, a File is linked to the organization ("Used in: Business setup") only while one of its
--    setup answers holds it: the answer save links and unlinks, and the processing worker links a File that
--    becomes available after the answer naming it was saved.
-- 4. The File library's "Used in" names it "Business setup" and links to the setup page.

-- 1. The columns -----------------------------------------------------------------------------------------

alter table public.setup_items drop constraint setup_items_kind_check;
alter table public.setup_items add constraint setup_items_kind_check
	check (kind in (
		'text', 'longtext', 'email', 'phone', 'choice', 'multi_choice', 'yes_no', 'yes_no_unsure', 'date', 'url',
		'number', 'money', 'percentage', 'distance', 'duration', 'colours', 'file'
	));

alter table public.setup_items
	add column file_kinds text[],
	add column max_files smallint,
	add constraint setup_items_file_kinds_check check (
		(kind = 'file') = (file_kinds is not null)
		and (file_kinds is null or (
			cardinality(file_kinds) between 1 and 3
			and file_kinds <@ array['photo', 'document', 'audio']
		))
	),
	add constraint setup_items_max_files_check check (
		(kind = 'file') = (max_files is not null)
		and (max_files is null or max_files in (1, 5, 10, 20))
	);

comment on column public.setup_items.file_kinds is
	'A photo or file question: the kinds of file it accepts (photo, document, audio).';
comment on column public.setup_items.max_files is
	'A photo or file question: the most files one answer may hold (1, 5, 10 or 20).';

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
		options, allow_other, max_choices, file_kinds, max_files, max_length, show_if
	)
	select draft_id, i.stage_key, i.position, i.item_type, i.fact_key, i.label, i.hint, i.built_in, i.required,
		i.can_defer, i.kind, i.options, i.allow_other, i.max_choices, i.file_kinds, i.max_files, i.max_length,
		i.show_if
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
			options, allow_other, max_choices, file_kinds, max_files, max_length, show_if
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

-- 3. Setup files in the File Manager ---------------------------------------------------------------------

alter table public.files drop constraint files_origin_role_check;
alter table public.files add constraint files_origin_role_check
	check (origin_role = any (array[
		'attachment', 'line_photo', 'logo', 'campaign_image', 'item_photo', 'note_file', 'setup_answer'
	]));

alter table public.file_links drop constraint file_links_role_check;
alter table public.file_links add constraint file_links_role_check
	check (role = any (array[
		'attachment', 'work_photo', 'report_photo', 'line_photo', 'logo', 'campaign_image', 'item_photo',
		'note_file', 'setup_answer'
	]));

-- One organization's setup Files linked exactly while an answer holds them. An organization has at most a few
-- hundred answers, so this re-reads them all rather than tracking which changed.
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
			where a.organization_id = target_organization_id
				and jsonb_typeof(a.value) = 'array'
				and a.value ? link.file_id::text
		);

	insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
	select f.organization_id, f.id, 'organization', target_organization_id, 'setup_answer', f.uploaded_by
	from public.organization_setup_answers a
	cross join lateral jsonb_array_elements_text(a.value) as held(file_id)
	join public.files f
		-- Tick-several answers are lists too; only an id can name a File.
		on f.id = case
			when held.file_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
			then held.file_id::uuid
		end
	where a.organization_id = target_organization_id
		and jsonb_typeof(a.value) = 'array'
		and f.organization_id = target_organization_id
		and f.origin_role = 'setup_answer'
		and f.processing_state = 'available'
		and f.trashed_at is null
	on conflict (file_id, entity_type, entity_id, role) do nothing;
end;
$$;

revoke all on function private.sync_setup_answer_file_links(uuid) from public, anon, authenticated;

create or replace function public.save_organization_setup_answers(
  target_organization_id uuid,
  new_answers jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  saved_at timestamptz := now();
begin
  perform private.require_organization_setup_editor(target_organization_id);

  if new_answers is null
    or jsonb_typeof(new_answers) <> 'array'
    or jsonb_array_length(new_answers) not between 1 and 50 then
    raise exception 'The answers to save are missing.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new_answers) as item(answer)
    group by item.answer ->> 'fact_key'
    having count(*) > 1 or item.answer ->> 'fact_key' is null
  ) then
    raise exception 'Each answer must name one fact, once.' using errcode = 'check_violation';
  end if;

  insert into public.organization_setup (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;

  delete from public.organization_setup_answers as existing
  using jsonb_array_elements(new_answers) as item(answer)
  where existing.organization_id = target_organization_id
    and existing.fact_key = item.answer ->> 'fact_key'
    and item.answer ->> 'availability' is null;

  insert into public.organization_setup_answers as existing (
    organization_id, fact_key, availability, value, note, updated_by, updated_at
  )
  select
    target_organization_id,
    item.answer ->> 'fact_key',
    item.answer ->> 'availability',
    case when item.answer ->> 'availability' = 'have' then item.answer -> 'value' end,
    case
      when item.answer ->> 'availability' <> 'have' then nullif(btrim(item.answer ->> 'note'), '')
    end,
    (select auth.uid()),
    saved_at
  from jsonb_array_elements(new_answers) as item(answer)
  where item.answer ->> 'availability' is not null
  on conflict (organization_id, fact_key) do update
    set availability = excluded.availability,
        value = excluded.value,
        note = excluded.note,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  -- Client onboarding A5c: a photo or file answer added or removed a File.
  perform private.sync_setup_answer_file_links(target_organization_id);

  return jsonb_build_object('status', 'saved', 'saved_at', saved_at);
end;
$$;

-- The worker's finish: unchanged except that a setup File is not linked just because it was uploaded for
-- setup — only when an answer still holds it, as a Note's File is only linked to its Note's records.
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

  -- Client onboarding A5c: a setup File, linked only while one of the organization's answers holds it.
  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_role = 'setup_answer'
    and exists (
      select 1 from public.organization_setup_answers a
      where a.organization_id = finalized.organization_id
        and jsonb_typeof(a.value) = 'array'
        and a.value ? finalized.id::text
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

-- 4. "Used in: Business setup" ---------------------------------------------------------------------------
--
-- Unchanged except for the organization's two roles: its logo, and its setup answers, which open the setup page.
CREATE OR REPLACE FUNCTION public.file_usage(target_organization_id uuid, target_file_id uuid, target_limit integer DEFAULT 10, cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, entity_type text, entity_id uuid, role text, protected boolean, customer_received boolean, title text, context text, status text, link_type text, link_id uuid, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select
    link.id,
    link.entity_type,
    link.entity_id,
    link.role,
    link.protected or link.entity_type = 'message' as protected,
    link.entity_type = 'quote' and (
      exists (
        select 1 from public.quote_version_attachments version_attachment
        join public.quote_versions version on version.id = version_attachment.quote_version_id
        where version_attachment.organization_id = link.organization_id
          and version_attachment.quote_id = link.entity_id
          and version_attachment.file_id = link.file_id
          and version.status = 'published'
      )
      or exists (
        select 1 from public.quote_version_lines line
        join public.quote_versions version on version.id = line.quote_version_id
        where line.organization_id = link.organization_id
          and line.quote_id = link.entity_id
          and line.image_file_id = link.file_id
          and version.status = 'published'
      )
    )
    or link.entity_type = 'message'
    or (link.entity_type = 'marketing_campaign' and campaign_record.status in ('sending', 'completed', 'needs_attention'))
    or (link.role = 'report_photo' and link.protected)
    as customer_received,
    case link.entity_type
      when 'client' then client_record.display_name
      when 'property' then coalesce(nullif(btrim(property_record.label), ''), property_record.address_line1)
      when 'request' then request_record.title
      when 'quote' then 'Quote #' || quote_record.quote_number
      when 'invoice' then 'Invoice #' || invoice_record.invoice_number
      when 'job' then 'Job #' || job_record.job_number
      when 'visit' then coalesce(nullif(btrim(visit_record.title), ''), 'Visit')
      when 'job_expense' then expense_record.name
      when 'organization' then
        case when link.role = 'setup_answer' then 'Business setup' else 'Business logo' end
      when 'marketing_campaign' then campaign_record.name
      when 'catalog_item' then catalog_record.name
      when 'message' then
        case message_record.channel
          when 'email' then coalesce(nullif(btrim(message_record.subject), ''), 'Email')
          else 'Text message'
        end
    end as title,
    case link.entity_type
      when 'property' then nullif(btrim(concat_ws(', ', property_record.address_line1, property_record.city)), '')
      when 'quote' then nullif(btrim(quote_record.title), '')
      when 'invoice' then nullif(btrim(invoice_record.subject), '')
      when 'job' then nullif(btrim(job_record.title), '')
      when 'visit' then 'Job #' || visit_job.job_number
      when 'job_expense' then 'Job #' || expense_job.job_number
      when 'message' then message_record.client_name
      when 'catalog_item' then 'Price list'
    end as context,
    case link.entity_type
      when 'client' then client_record.lifecycle_status
      when 'request' then request_record.status
      when 'quote' then quote_record.status
      when 'job' then job_record.status
      when 'message' then message_record.status
      when 'marketing_campaign' then campaign_record.status
    end as status,
    -- A message has no page of its own, so it redirects like a visit or job expense does: into its parent,
    -- here the client's conversation rather than the client's own profile.
    case
      when link.entity_type = 'visit' then 'job'
      when link.entity_type = 'job_expense' then 'job'
      when link.entity_type = 'message' then 'message'
      when link.role = 'setup_answer' then 'setup'
      else link.entity_type
    end as link_type,
    case link.entity_type
      when 'visit' then visit_record.job_id
      when 'job_expense' then expense_record.job_id
      when 'message' then message_record.client_id
      else link.entity_id
    end as link_id,
    link.created_at
  from public.file_links link
  left join public.clients client_record
    on link.entity_type = 'client' and client_record.id = link.entity_id
  left join public.properties property_record
    on link.entity_type = 'property' and property_record.id = link.entity_id
  left join public.requests request_record
    on link.entity_type = 'request' and request_record.id = link.entity_id
  left join public.quotes quote_record
    on link.entity_type = 'quote' and quote_record.id = link.entity_id
  left join public.invoices invoice_record
    on link.entity_type = 'invoice' and invoice_record.id = link.entity_id
  left join public.jobs job_record
    on link.entity_type = 'job' and job_record.id = link.entity_id
  left join public.job_visits visit_record
    on link.entity_type = 'visit' and visit_record.id = link.entity_id
  left join public.jobs visit_job
    on visit_job.id = visit_record.job_id
  left join public.job_expenses expense_record
    on link.entity_type = 'job_expense' and expense_record.id = link.entity_id
  left join public.jobs expense_job
    on expense_job.id = expense_record.job_id
  left join public.catalog_items catalog_record
    on link.entity_type = 'catalog_item' and catalog_record.id = link.entity_id
  left join lateral public.file_link_marketing_campaign(link.organization_id, link.entity_type, link.entity_id) campaign_record
    on true
  left join lateral public.file_link_message(link.organization_id, link.entity_type, link.entity_id) message_record
    on true
  where link.organization_id = target_organization_id
    and link.file_id = target_file_id
    and (
      cursor_created_at is null
      or cursor_id is null
      or (link.created_at, link.id) < (cursor_created_at, cursor_id)
    )
  order by link.created_at desc, link.id desc
  limit least(greatest(coalesce(target_limit, 10), 1), 50);
$function$;
