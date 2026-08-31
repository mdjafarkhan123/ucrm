-- Sales Pipeline, Part 4C: current Sales Outcomes -- the Won/Lost tiles and the paged, sortable report.
--
-- Both reads answer from the outcome engine's current-state columns (opportunities.outcome, outcome_at),
-- never from opportunity_outcome_events: current reporting is "what is closed right now", and a reopened
-- Opportunity has to disappear from it the instant Reopen commits, while its Lost and Reopened events stay
-- in permanent history untouched. Nothing here reads the event table.
--
-- Same security-definer shape as pipeline_board_page / pipeline_stage_counts: RLS does not run for a
-- definer function, so tenant, pipeline.view, pipeline.view_value and customers.view are all re-applied by
-- hand, exactly as those two functions already do.

-- 1. Indexes -------------------------------------------------------------------------------------------
--
-- Rebuilt, not duplicated: opportunities_outcome_idx already exists from 4A for this exact report, but
-- without an id tiebreaker a keyset cursor cannot use it as a row comparison. Ascending, not descending,
-- so one index serves both directions of Outcome date the way the board's own indexes do -- Postgres reads
-- an ascending index backward for DESC as cheaply as forward for ASC.
drop index if exists public.opportunities_outcome_idx;
create index opportunities_outcome_idx
  on public.opportunities(organization_id, outcome, outcome_at, id)
  where outcome <> 'open';

create index opportunities_outcome_created_idx
  on public.opportunities(organization_id, outcome, created_at, id)
  where outcome <> 'open';

-- Total, split the same two ways the board's value sort already is (20260819002041): the estimated half
-- here, keyset the normal way, ...
create index opportunities_outcome_value_idx
  on public.opportunities(organization_id, outcome, estimated_value, id)
  where outcome <> 'open' and estimated_value is not null;

-- ...and the unestimated half here, so that phase never pays to sort rows it is about to discard. A null
-- estimate cannot sit in a keyset row comparison, which is why Total is paged in two phases below rather
-- than with a plain NULLS LAST.
create index opportunities_outcome_unvalued_idx
  on public.opportunities(organization_id, outcome, id)
  where outcome <> 'open' and estimated_value is null;

-- Title and Client are deliberately left without a dedicated index. Both are report reads, not board
-- reads: closed-opportunity volume is bounded by real deal flow rather than by traffic, so the org+outcome
-- prefix on opportunities_outcome_idx should keep an in-memory sort cheap at real-world scale. Approved
-- 2026-08-19 to measure with EXPLAIN (ANALYZE, BUFFERS) against 50,000 closed opportunities in one
-- organization, including a keyset-paged page beyond the first, before adding anything for a cost that has
-- not been shown yet.

-- 2. Won/Lost tiles --------------------------------------------------------------------------------------
--
-- The board's own past-30-days tiles: two fixed numbers, never filtered by the board's salesperson or date
-- controls, because Jobber's tiles are not either. `tile_from`/`tile_to` are the two instants the caller
-- already resolved in the organization's own timezone, the same as every other Pipeline date boundary.

create or replace function public.pipeline_outcome_tiles(
  target_organization_id uuid,
  tile_from timestamptz,
  tile_to timestamptz
)
returns table (outcome_key text, closed_count bigint, value_total numeric)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  -- Both outcome types are always returned, zero-filled, so a tile with nothing in the window still shows
  -- "Won (0)" instead of going missing.
  return query
  select
    outcome_type.outcome_key,
    coalesce(counted.closed_count, 0)::bigint,
    counted.value_total
  from unnest(array['won', 'lost']) as outcome_type(outcome_key)
  left join (
    select
      opportunity.outcome as outcome_key,
      count(*) as closed_count,
      case when caller_sees_money then sum(opportunity.estimated_value) end as value_total
    from public.opportunities as opportunity
    where opportunity.organization_id = target_organization_id
      and opportunity.outcome in ('won', 'lost')
      and opportunity.outcome_at >= tile_from
      and opportunity.outcome_at < tile_to
    group by opportunity.outcome
  ) as counted on counted.outcome_key = outcome_type.outcome_key;
end;
$$;

revoke all on function public.pipeline_outcome_tiles(uuid, timestamptz, timestamptz) from public;
revoke execute on function public.pipeline_outcome_tiles(uuid, timestamptz, timestamptz) from anon;
grant execute on function public.pipeline_outcome_tiles(uuid, timestamptz, timestamptz) to authenticated;

-- 3. Sales Outcomes report page --------------------------------------------------------------------------
--
-- One outcome type per call, matching Jobber's own Type filter -- Won and Lost are never mixed on one
-- page. Title, Client, Created, Outcome date and Total are all sortable, and ordering by either Total or
-- Client is reading privileged data (money, and a client the caller may not otherwise see), so both are
-- refused outright for a caller without the matching permission -- the same rule pipeline_board_page
-- already applies to sorting by value.

create or replace function public.pipeline_outcome_page(
  target_organization_id uuid,
  outcome_type text,
  page_limit integer default 25,
  sort_key text default 'outcome_at',
  sort_direction text default 'desc',
  outcome_from timestamptz default null,
  outcome_to timestamptz default null,
  cursor_sort_key text default null,
  cursor_phase integer default null,
  cursor_timestamp timestamptz default null,
  cursor_numeric numeric default null,
  cursor_text text default null,
  cursor_id uuid default null
)
returns table (
  id uuid,
  title text,
  outcome text,
  created_at timestamptz,
  outcome_at timestamptz,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  estimated_value numeric
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
  select_body text;
  filters text := '';
  keyset text;
  ordering text;
  sort_expr text;
  phase integer;
  fetched integer;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if outcome_type not in ('won', 'lost') then
    raise exception 'That is not a Sales Outcomes type.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_key not in ('title', 'client', 'created', 'outcome_at', 'total')
     or sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a way to sort Sales Outcomes.' using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat rows.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  if sort_key = 'total' and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;
  if sort_key = 'client' and not caller_sees_clients then
    raise exception 'You do not have access to client names on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.outcome_at,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      case when %L::boolean then opportunity.estimated_value end
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    where opportunity.organization_id = %L
      and opportunity.outcome = %L
  $body$, caller_sees_money, caller_sees_clients, target_organization_id, outcome_type);

  if outcome_from is not null then
    filters := filters || format(' and opportunity.outcome_at >= %L', outcome_from);
  end if;
  if outcome_to is not null then
    filters := filters || format(' and opportunity.outcome_at < %L', outcome_to);
  end if;

  -- Total pages in two phases, the same way the board's value sort does: a null estimate cannot sit in a
  -- keyset row comparison, so the estimated rows and the unestimated ones are two separate ordered reads
  -- rather than one NULLS LAST that a cursor could not resume.
  if sort_key = 'total' then
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
            cursor_numeric, cursor_id)
        end;
      else
        ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      end if;

      return query execute select_body || filters
        || ' and opportunity.estimated_value is not null' || keyset || ordering
        || format(' limit %s', resolved_limit);
      get diagnostics fetched = row_count;

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
    return;
  end if;

  -- Every other sort is a single ordered read. Title, Created and Outcome date are never null; Client can
  -- be null only when the backing client row itself has been removed, which NULLS LAST is enough for --
  -- this is a report column, not money, and that edge is rare enough not to earn Total's two-phase split.
  sort_expr := case sort_key
    when 'title' then 'opportunity.title'
    when 'client' then 'client.display_name'
    when 'created' then 'opportunity.created_at'
    else 'opportunity.outcome_at'
  end;

  if sort_key in ('title', 'client') then
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc nulls last, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) < (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc nulls last, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) > (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    end if;
  else
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    end if;
  end if;

  return query execute select_body || filters || keyset || ordering
    || format(' limit %s', resolved_limit);
end;
$function$;

revoke all on function public.pipeline_outcome_page(
  uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid
) from public;
revoke execute on function public.pipeline_outcome_page(
  uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid
) from anon;
grant execute on function public.pipeline_outcome_page(
  uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid
) to authenticated;
