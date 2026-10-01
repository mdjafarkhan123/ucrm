-- Pipeline upgrade A1: custom follow-up stages an owner or administrator adds in Settings → Pipeline.
--
-- Product truth: docs/sales-pipeline-behavior-contract.md, "Revision 3 adds section-bound custom follow-up
-- stages". Industry reference: Jobber's Sales Pipeline (up to 25 custom stages, placed inside the Request or
-- the Quote section, protected stages locked).
--
-- 1. pipeline_custom_stages: one row per custom stage. A stage belongs to one section for life and sits
--    after one protected stage (`after_stage`), so the seven protected stages never need rows or positions
--    of their own and can never be reordered by a write here. Members read it; nobody writes it directly.
-- 2. save_pipeline_settings replaces save_pipeline_presentation: the Assessment toggle and the whole stage
--    list are saved together, under the one Pipeline revision, by the one Save button.
--
-- No card can sit in a custom stage yet. That is part A2, which adds the placement to opportunities.

-- 1. Custom stages -----------------------------------------------------------------------------------------

create table public.pipeline_custom_stages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  section text not null,
  name text not null,
  -- The protected stage this one follows on the board. Always a real stage of the same section, so a
  -- custom stage can never land across the Request/Quote line or ahead of a section's first stage.
  after_stage text not null,
  -- Order among the organization's custom stages, as last saved. Read after `after_stage`.
  position integer not null,
  -- Switching a stage off (part A3) keeps the row as the historical name; null means it is on the board.
  disabled_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pipeline_custom_stages_organization_id_unique unique (organization_id, id),
  constraint pipeline_custom_stages_section_check check (section in ('request', 'quote')),
  constraint pipeline_custom_stages_name_check check (
    name = btrim(name) and char_length(name) between 1 and 40
  ),
  constraint pipeline_custom_stages_after_stage_check check (
    (
      section = 'request'
      and after_stage in (
        'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed'
      )
    )
    or (
      section = 'quote'
      and after_stage in ('quote_draft', 'quote_awaiting_response', 'quote_changes_requested')
    )
  ),
  constraint pipeline_custom_stages_position_check check (position >= 0),
  -- One enabled stage per name inside a section, whatever the capitals. An exclusion constraint rather
  -- than a unique index because it has to be both partial and deferrable: two stages swapping names in
  -- one save pass through a moment where both carry the same name. Its index leads with the organization,
  -- so it is also the index every "this organization's enabled stages" read uses.
  constraint pipeline_custom_stages_name_unique exclude using btree (
    organization_id with =,
    section with =,
    (lower(name)) with =
  ) where (disabled_at is null) deferrable initially immediate
);

comment on table public.pipeline_custom_stages is
  'Custom follow-up stages on the Sales Pipeline board. Members may read this table, never write it: every change arrives through public.save_pipeline_settings.';

create index pipeline_custom_stages_created_by_idx
  on public.pipeline_custom_stages (created_by) where created_by is not null;

create trigger pipeline_custom_stages_set_updated_at
  before update on public.pipeline_custom_stages
  for each row execute function public.set_updated_at();

alter table public.pipeline_custom_stages enable row level security;
revoke all on table public.pipeline_custom_stages from public, anon, authenticated;
grant select on table public.pipeline_custom_stages to authenticated;
grant all on table public.pipeline_custom_stages to service_role;

-- The board draws these as columns, and Settings lists them, so either permission is enough to read.
create policy "permitted members can view pipeline custom stages"
  on public.pipeline_custom_stages
  for select
  to authenticated
  using (
    organization_id in (select private.permitted_organizations('pipeline.view'))
    or organization_id in (select private.permitted_organizations('settings.business.view'))
  );

-- 2. Saving Settings → Pipeline ----------------------------------------------------------------------------

drop function public.save_pipeline_presentation(uuid, integer, boolean);

-- `new_stages` is the organization's whole list of enabled custom stages, in board order:
--   [{ "id": uuid or null, "section": "request" | "quote", "name": text, "after_stage": text }, ...]
-- An entry without an id is a new stage. Every enabled stage must be in the list — leaving one out is not
-- how a stage is switched off — so what is saved is always exactly what the person was looking at.
create function public.save_pipeline_settings(
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
    changed := changed || 'pipeline_detailed_assessment_stages';
  end if;
  if updated_count + inserted_count > 0 then
    changed := changed || 'pipeline_custom_stages';
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

revoke all on function public.save_pipeline_settings(uuid, integer, boolean, jsonb) from public, anon;
grant execute on function public.save_pipeline_settings(uuid, integer, boolean, jsonb)
  to authenticated, service_role;
