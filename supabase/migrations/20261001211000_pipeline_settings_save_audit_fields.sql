-- Pipeline upgrade A1: save_pipeline_settings failed on any real change. `text[] || 'literal'` reads the
-- bare literal as a second array, not as one more entry, so building the audit row's list of changed fields
-- raised "malformed array literal". array_append says what was meant. Nothing else in the command changes.

create or replace function public.save_pipeline_settings(
  target_organization_id uuid,
  expected_revision integer,
  new_detailed_assessment_stages boolean,
  new_stages jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  settings_row public.organization_settings;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
  updated_count integer;
  inserted_count integer;
  changed text[] := '{}';
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_detailed_assessment_stages is null then
    raise exception 'Choose whether to show the detailed assessment stages.'
      using errcode = 'check_violation';
  end if;

  if new_stages is null or jsonb_typeof(new_stages) <> 'array' then
    raise exception 'The list of stages is missing.' using errcode = 'check_violation';
  end if;

  -- The settings row is the lock: two people saving the pipeline at once go one after the other.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  -- Somebody else saved first. The caller is told who and when, so it can offer to reload rather than
  -- silently overwrite a change it never saw.
  if expected_revision is distinct from settings_row.pipeline_revision then
    select profile.full_name, settings_row.pipeline_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.pipeline_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  -- Jobber's documented ceiling. The list is every enabled stage, so its length is the count.
  if jsonb_array_length(new_stages) > 25 then
    raise exception 'A pipeline can have up to 25 custom stages.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    group by item.stage ->> 'section', lower(btrim(item.stage ->> 'name'))
    having count(*) > 1
  ) then
    raise exception 'Two stages in the same section cannot share a name.'
      using errcode = 'check_violation';
  end if;

  -- Every id has to be one of this organization's enabled stages, named once, and still in its own
  -- section. Every enabled stage has to be named. Either failing means the page was out of date.
  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ->> 'id' is not null
    group by item.stage ->> 'id'
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ->> 'id' is not null
      and not exists (
        select 1
        from public.pipeline_custom_stages as existing
        where existing.organization_id = target_organization_id
          and existing.disabled_at is null
          and existing.id = (item.stage ->> 'id')::uuid
          and existing.section = item.stage ->> 'section'
      )
  ) or exists (
    select 1
    from public.pipeline_custom_stages as existing
    where existing.organization_id = target_organization_id
      and existing.disabled_at is null
      and not exists (
        select 1
        from jsonb_array_elements(new_stages) as item(stage)
        where (item.stage ->> 'id')::uuid = existing.id
      )
  ) then
    raise exception 'These stages changed while you were editing. Refresh the page and try again.'
      using errcode = 'check_violation';
  end if;

  -- Renames are checked once the whole list is in place, so two stages may swap names in one save.
  set constraints public.pipeline_custom_stages_name_unique deferred;

  update public.pipeline_custom_stages as existing
  set
    name = btrim(item.stage ->> 'name'),
    after_stage = item.stage ->> 'after_stage',
    position = (item.ordinal - 1)::integer
  from jsonb_array_elements(new_stages) with ordinality as item(stage, ordinal)
  where existing.organization_id = target_organization_id
    and existing.disabled_at is null
    and existing.id = (item.stage ->> 'id')::uuid
    and (existing.name, existing.after_stage, existing.position) is distinct from (
      btrim(item.stage ->> 'name'), item.stage ->> 'after_stage', (item.ordinal - 1)::integer
    );
  get diagnostics updated_count = row_count;

  insert into public.pipeline_custom_stages (
    organization_id, section, name, after_stage, position, created_by
  )
  select
    target_organization_id,
    item.stage ->> 'section',
    btrim(item.stage ->> 'name'),
    item.stage ->> 'after_stage',
    (item.ordinal - 1)::integer,
    (select auth.uid())
  from jsonb_array_elements(new_stages) with ordinality as item(stage, ordinal)
  where item.stage ->> 'id' is null
  order by item.ordinal;
  get diagnostics inserted_count = row_count;

  set constraints public.pipeline_custom_stages_name_unique immediate;

  update public.organization_settings
  set
    pipeline_detailed_assessment_stages = new_detailed_assessment_stages,
    pipeline_revision = pipeline_revision + 1,
    pipeline_updated_by = (select auth.uid()),
    pipeline_updated_at = now()
  where organization_id = target_organization_id
  returning pipeline_revision into new_revision;

  if new_detailed_assessment_stages
     is distinct from settings_row.pipeline_detailed_assessment_stages then
    changed := array_append(changed, 'pipeline_detailed_assessment_stages');
  end if;
  if updated_count + inserted_count > 0 then
    changed := array_append(changed, 'pipeline_custom_stages');
  end if;

  if cardinality(changed) > 0 then
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (target_organization_id, 'pipeline', changed, (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'pipeline_revision', new_revision,
    'pipeline_detailed_assessment_stages', new_detailed_assessment_stages
  );
end;
$$;
