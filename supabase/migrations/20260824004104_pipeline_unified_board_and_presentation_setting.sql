-- Part 5C-iii: one unified board with five visible columns by default, and the Settings toggle that
-- expands Assessment back into its three protected stages.
--
-- Nothing here changes what a stage means, how a card gets into one, or what history records. The three
-- assessment stages remain the stored truth; this migration only teaches the read model to answer for all
-- three at once, and gives the organization one presentation preference.

-- 1. The grouped column's index ---------------------------------------------------------------------------
--
-- Every existing board index is (organization_id, stage, <sort>, id), so a three-stage predicate cannot read
-- one ordered range from any of them: the planner scans the whole group and top-N sorts it on every page.
-- Measured on 60,000 rows (~5,143 open cards in one organization's assessment group): 5,199 buffers and
-- 26.0 ms per page.
--
-- Making the assessment set the index *predicate* takes `stage` out of the key entirely, so all three
-- sub-states sit in one ordered range. Same measurement: 29 buffers and 0.12 ms, no Sort node, and a cursor
-- 2,500 cards deep costs the same 28 buffers as the first page. Postgres proves the implication, so the
-- `stage in (...)` clause drops out of the plan and the (stage_entered_at, id) row comparison folds into the
-- Index Cond.
--
-- Only the default sort gets one. `created_at` and the two value-sort halves keep their sort node (measured
-- at 856, 826 and 449 buffers): the same judgment already recorded for opportunities_board_owner_idx, which
-- covers only the default sort because more indexes on a table every Request writes to must be earned.
-- Revisit if a real assessment group passes a few thousand open cards.
--
-- The predicate is written exactly as the query writes it, because the planner matches the two expressions
-- before it tries to prove anything harder.
create index opportunities_board_assessment_group_idx
  on public.opportunities(organization_id, stage_entered_at, id)
  where outcome = 'open'
    and stage in ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed');

comment on index public.opportunities_board_assessment_group_idx is
  'Part 5C-iii. The collapsed Assessment column reads all three assessment stages as one keyset-ordered '
  'range. The stage set is the predicate rather than the leading key, so no Sort node is needed.';

-- 2. The organization''s presentation preference -----------------------------------------------------------
--
-- Its own revision and editor stamp, matching every other section of this table. Sharing the branding or
-- profile revision would make a Pipeline save collide with an unrelated Business Profile edit.
-- The editor points at auth.users, matching the three sections already on this table. The full name is
-- looked up through public.profiles at read time, which is the same indirection the others use.
alter table public.organization_settings
  add column if not exists pipeline_detailed_assessment_stages boolean not null default false,
  add column if not exists pipeline_revision integer not null default 1,
  add column if not exists pipeline_updated_by uuid references auth.users(id) on delete set null,
  add column if not exists pipeline_updated_at timestamptz;

-- The audit table's section vocabulary is a closed check constraint, so a new section has to be admitted
-- before the save function below can write one. Widened, never relaxed: the list stays exhaustive.
alter table public.organization_settings_audit
  drop constraint if exists organization_settings_audit_section_check;
alter table public.organization_settings_audit
  add constraint organization_settings_audit_section_check
  check (section = any (array['profile'::text, 'branding'::text, 'hours'::text, 'pipeline'::text]));

comment on column public.organization_settings.pipeline_detailed_assessment_stages is
  'Part 5C-iii. False (the default) shows the five-column board with one Assessment column. True expands it '
  'into the three protected assessment stages. Presentation only: it never changes Request state, '
  'transitions, history, or reporting.';

-- New columns are invisible to members until they are granted, the same as every other column on this table.
grant select (
  pipeline_detailed_assessment_stages, pipeline_revision, pipeline_updated_by, pipeline_updated_at
) on public.organization_settings to authenticated;

-- The editor foreign key gets its covering index, matching the profile/branding/hours editor indexes that
-- already exist. This is one row per organization, so the write cost is nothing and the ON DELETE SET NULL
-- path does not have to scan the table when a user is removed. (The board indexes are held to a much higher
-- bar precisely because opportunities gets a row per Request.)
create index if not exists organization_settings_pipeline_editor_idx
  on public.organization_settings(pipeline_updated_by)
  where pipeline_updated_by is not null;

-- 3. Saving it ---------------------------------------------------------------------------------------------
--
-- A direct copy of save_organization_branding's shape: permission first, locked read, revision conflict
-- answered as data rather than an error, then the update, the editor stamp, and an audit row only when the
-- value actually changed.
create or replace function public.save_pipeline_presentation(
  target_organization_id uuid,
  expected_revision integer,
  new_detailed_assessment_stages boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_detailed_assessment_stages is null then
    raise exception 'Choose whether to show the detailed assessment stages.'
      using errcode = 'check_violation';
  end if;

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
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (
      target_organization_id, 'pipeline',
      array['pipeline_detailed_assessment_stages'], (select auth.uid())
    );
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'pipeline_revision', new_revision,
    'pipeline_detailed_assessment_stages', new_detailed_assessment_stages
  );
end;
$$;

revoke all on function public.save_pipeline_presentation(uuid, integer, boolean) from public;
revoke execute on function public.save_pipeline_presentation(uuid, integer, boolean) from anon;
grant execute on function public.save_pipeline_presentation(uuid, integer, boolean) to authenticated;

-- 4. The board read, widened to one logical column -------------------------------------------------------
--
-- `target_stage` gains exactly one new value: 'assessment', the named logical column. It is not an arbitrary
-- stage list -- the route cannot ask for any other combination, so a caller can never invent a grouping the
-- product has not approved.
--
-- The row also gains the assessment appointment. The contract requires the collapsed column to show the real
-- state and, when scheduled, the date and time; the Request status alone cannot say when.

drop function if exists public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
);

create function public.pipeline_board_page(
  target_organization_id uuid,
  target_stage text,
  page_limit integer default 25,
  sort_key text default 'stage_entered_at',
  sort_direction text default 'desc',
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null,
  cursor_sort_key text default null,
  cursor_phase integer default null,
  cursor_timestamp timestamptz default null,
  cursor_value numeric default null,
  cursor_id uuid default null
)
returns table (
  id uuid,
  title text,
  stage text,
  stage_entered_at timestamptz,
  outcome text,
  created_at timestamptz,
  request_id uuid,
  request_status text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  property_id uuid,
  property_label text,
  property_address_line1 text,
  property_city text,
  property_state_region text,
  property_postal_code text,
  owner_user_id uuid,
  owner_full_name text,
  owner_avatar_url text,
  estimated_value numeric,
  expected_close_on date,
  next_follow_up_on date,
  task_id uuid,
  task_title text,
  task_due_on date,
  quote_id uuid,
  quote_status text,
  assessment_starts_at timestamptz,
  assessment_ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  sorting_by_value boolean;
  phase integer;
  select_body text;
  stage_predicate text;
  filters text := '';
  keyset text;
  ordering text;
  fetched integer;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  -- One named logical column plus the seven real stages. Written out rather than assembled from a caller's
  -- list, so 'assessment' is the only grouping that exists and no other combination is reachable.
  if target_stage = 'assessment' then
    -- Spelled exactly as opportunities_board_assessment_group_idx spells it: the planner matches the two
    -- expressions before attempting a harder proof, and a mismatch here silently costs the index.
    stage_predicate :=
      $p$ and opportunity.stage in
        ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed')$p$;
  elsif target_stage in (
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed',
    'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
  ) then
    stage_predicate := format(' and opportunity.stage = %L', target_stage);
  else
    raise exception 'That is not a board column.' using errcode = 'invalid_parameter_value';
  end if;

  if sort_key not in ('stage_entered_at', 'created_at', 'estimated_value')
     or sort_direction not in ('asc', 'desc')
     or owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to sort or filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat cards, so it is refused instead. The column a cursor belongs to is
  -- checked by the route, which is the only place that knows the logical-column vocabulary.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- One row over the asked-for page is how the caller detects there is more, so the cap is 50 plus one.
  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Asked once for the whole page. can_view_client is still called per row underneath, but only for a
  -- caller who lacks the blanket permission, so the ordinary page pays nothing for it.
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  sorting_by_value := sort_key = 'estimated_value';

  -- Ordering by money is reading money. Withholding the amounts while handing over the ranking would
  -- give the column away one comparison at a time.
  if sorting_by_value and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.stage,
      opportunity.stage_entered_at,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.request_id,
      request.status,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      opportunity.property_id,
      case when client_visible.allowed then property.label end,
      case when client_visible.allowed then property.address_line1 end,
      case when client_visible.allowed then property.city end,
      case when client_visible.allowed then property.state_region end,
      case when client_visible.allowed then property.postal_code end,
      opportunity.owner_user_id,
      case when owner_is_teammate.yes then owner_profile.full_name end,
      case when owner_is_teammate.yes then owner_profile.avatar_url end,
      case when %L::boolean then opportunity.estimated_value end,
      opportunity.expected_close_on,
      opportunity.next_follow_up_on,
      open_task.id,
      open_task.title,
      open_task.due_on,
      opportunity.quote_id,
      quote.status,
      assessment.starts_at,
      assessment.ends_at
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    cross join lateral (
      select exists (
        select 1
        from public.organization_members as owner_membership
        where owner_membership.organization_id = opportunity.organization_id
          and owner_membership.user_id = opportunity.owner_user_id
      ) as yes
    ) as owner_is_teammate
    left join lateral (
      select task.id, task.title, task.due_on
      from public.tasks as task
      where task.organization_id = opportunity.organization_id
        and task.opportunity_id = opportunity.id
        and task.status = 'open'
      order by task.due_on nulls last, task.created_at, task.id
      limit 1
    ) as open_task on true
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.properties as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join public.requests as request
      on request.id = opportunity.request_id
     and request.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.profiles as owner_profile
      on owner_profile.id = opportunity.owner_user_id
    left join public.assessments as assessment
      on assessment.request_id = opportunity.request_id
     and assessment.organization_id = opportunity.organization_id
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
  $body$, caller_sees_money, caller_sees_clients, target_organization_id) || stage_predicate;

  -- Only the clauses this request actually needs. "Or the filter is null" reads the same and costs the
  -- index scan.
  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants. The upper bound is exclusive: it is the first moment of the day after.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  if not sorting_by_value then
    -- Ties break the same way the sort runs, so the pair reads as one index range rather than as a
    -- filter over everything above it. This is also what keeps the grouped column's order globally
    -- correct: one keyset across all three assessment states, never three lists stitched together.
    if sort_direction = 'desc' then
      ordering := format(' order by opportunity.%1$I desc, opportunity.id desc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by opportunity.%1$I asc, opportunity.id asc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    end if;

    return query execute select_body || filters || keyset || ordering
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Value sorting, phase by phase. Phase 1 is the estimated cards in the caller's chosen direction;
  -- phase 2 is the unestimated ones, always oldest id first, which is the order they already sit in.
  phase := coalesce(cursor_phase, 1);
  if phase not in (1, 2) then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  if phase = 1 then
    if sort_direction = 'desc' then
      ordering := ' order by opportunity.estimated_value desc, opportunity.id desc';
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
      end;
    else
      ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
      end;
    end if;

    return query execute select_body || filters
      || ' and opportunity.estimated_value is not null' || keyset || ordering
      || format(' limit %s', resolved_limit);
    get diagnostics fetched = row_count;

    -- The estimated side is finished, so the rest of this page comes from the unestimated side, from its
    -- beginning. No unestimated card can have been returned before this point, so there is nothing to
    -- page past.
    if fetched < resolved_limit then
      return query execute select_body || filters
        || ' and opportunity.estimated_value is null'
        || ' order by opportunity.id asc'
        || format(' limit %s', resolved_limit - fetched);
    end if;
    return;
  end if;

  return query execute select_body || filters
    || ' and opportunity.estimated_value is null'
    || case when cursor_id is null then ''
            else format(' and opportunity.id > %L::uuid', cursor_id) end
    || ' order by opportunity.id asc'
    || format(' limit %s', resolved_limit);
end;
$function$;

revoke all on function public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
) from public;
revoke execute on function public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
) from anon;
grant execute on function public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
) to authenticated;
