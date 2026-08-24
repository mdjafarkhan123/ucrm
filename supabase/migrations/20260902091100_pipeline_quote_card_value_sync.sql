-- Sales Pipeline, Part 5C-i follow-up: a quote-backed card's money comes from the quote, not a manual
-- guess. Browser verification found every Quote card and column total silently blank -- estimated_value
-- was never written for a quote-backed opportunity by any of create_quote/convert_request_to_quote/the
-- similar-quote clone, despite the 5C-i packet assuming it was. Jobber's own card layout
-- (jobber-02-requests-leads.md 4.6.1) shows the quote's real price in bold on every Quote card, including
-- $0 before anything is priced, so a quote-backed opportunity's estimated_value is no longer a manual
-- field: it is kept in sync with whichever quote_versions row is currently live for its quote (the open
-- draft if there is one, else the published version), the same "draft wins" choice
-- `src/routes/api/quotes/[id]/+server.ts` already makes for its own reads.
--
-- Three write paths keep it current:
--   1. A BEFORE INSERT trigger on opportunities, for the moment create_quote/convert_request_to_quote/the
--      clone command insert the row. Every one of those already points quotes.draft_version_id at a real
--      (zero-totalled at worst) version before that insert runs, so this never sees a quote without one.
--   2. An AFTER UPDATE OF total_minor trigger on quote_versions, for every later price edit
--      (private.refresh_quote_draft_totals only ever updates the version currently being edited).
--   3. An AFTER UPDATE OF draft_version_id, current_published_version_id trigger on quotes, for publish,
--      a new draft revision, and any other moment the "current" version pointer itself moves without its
--      total changing.
-- A Request-backed opportunity's estimated_value is untouched by all three -- they only ever match rows
-- with quote_id set, and pipeline_update_opportunity_details' manual-edit path is untouched for them too.

-- 1. Read the current version's total for one quote -------------------------------------------------------

create or replace function private.quote_current_total_minor(target_quote_id uuid)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select version.total_minor
  from public.quotes as quote
  join public.quote_versions as version
    on version.id = coalesce(quote.draft_version_id, quote.current_published_version_id)
   and version.organization_id = quote.organization_id
  where quote.id = target_quote_id;
$$;

revoke all on function private.quote_current_total_minor(uuid) from public;
revoke execute on function private.quote_current_total_minor(uuid) from anon, authenticated;

-- 2. New rows: the quote already has a version by the time create_quote/convert_request_to_quote insert
--    the opportunity, so this reads it straight through rather than waiting for an UPDATE to arrive later.

create or replace function private.set_opportunity_value_from_quote()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- Only fills a gap. No production insert ever supplies estimated_value for a quote-backed row (the
  -- column is off both the INSERT and UPDATE grant lists for `authenticated`), so this always fires for
  -- real traffic -- the null check just keeps a caller that legitimately knows the answer already, such
  -- as a fixture, from being overwritten.
  if new.quote_id is not null and new.estimated_value is null then
    new.estimated_value := private.quote_current_total_minor(new.quote_id) / 100.0;
  end if;
  return new;
end;
$$;

revoke all on function private.set_opportunity_value_from_quote() from public;

drop trigger if exists opportunities_set_value_from_quote on public.opportunities;

create trigger opportunities_set_value_from_quote
  before insert on public.opportunities
  for each row
  execute function private.set_opportunity_value_from_quote();

-- 3. Later changes: whichever side moved (a version's total, or which version is current), resync every
--    opportunity that points at the quote -- today that is always at most one row. Two thin trigger
--    functions, one per table, rather than one branching on tg_table_name: plpgsql caches a compiled
--    trigger function's `new`/`old` field lookups per function, and a single function reused across two
--    tables with different row shapes throws "record new has no field ..." the first time the branch not
--    taken on the earlier call is finally the one that runs.

create or replace function private.sync_opportunity_value_for_quote(
  target_organization_id uuid,
  target_quote_id uuid
)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  -- opportunities_quote_unique is (organization_id, quote_id); organization_id has to be in the predicate
  -- for this update to use it as an equality condition, the same reasoning
  -- private.opportunity_resync_from_quote (20260902090700) already documents for the same table.
  update public.opportunities
  set estimated_value = private.quote_current_total_minor(target_quote_id) / 100.0
  where organization_id = target_organization_id
    and quote_id = target_quote_id;
$$;

revoke all on function private.sync_opportunity_value_for_quote(uuid, uuid) from public;

create or replace function private.sync_opportunity_value_from_quote_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform private.sync_opportunity_value_for_quote(
    coalesce(new.organization_id, old.organization_id),
    coalesce(new.id, old.id)
  );
  return null;
end;
$$;

revoke all on function private.sync_opportunity_value_from_quote_row() from public;

create or replace function private.sync_opportunity_value_from_quote_version_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform private.sync_opportunity_value_for_quote(
    coalesce(new.organization_id, old.organization_id),
    coalesce(new.quote_id, old.quote_id)
  );
  return null;
end;
$$;

revoke all on function private.sync_opportunity_value_from_quote_version_row() from public;

drop trigger if exists quote_versions_sync_opportunity_value on public.quote_versions;

create trigger quote_versions_sync_opportunity_value
  after update of total_minor on public.quote_versions
  for each row
  execute function private.sync_opportunity_value_from_quote_version_row();

drop trigger if exists quotes_sync_opportunity_value on public.quotes;

create trigger quotes_sync_opportunity_value
  after update of draft_version_id, current_published_version_id on public.quotes
  for each row
  execute function private.sync_opportunity_value_from_quote_row();

-- 4. The manual editor is no longer a legal way to touch a quote-backed card's value -- same refusal shape
--    as pipeline_mark_opportunity_lost already uses for a quote-backed opportunity's stage.

create or replace function public.pipeline_update_opportunity_details(
  target_opportunity_id uuid,
  set_owner boolean default false,
  new_owner_user_id uuid default null,
  set_value boolean default false,
  new_estimated_value numeric default null,
  set_expected_close boolean default false,
  new_expected_close_on date default null,
  set_next_follow_up boolean default false,
  new_next_follow_up_on date default null
)
returns table (
  id uuid,
  owner_user_id uuid,
  estimated_value numeric,
  expected_close_on date,
  next_follow_up_on date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid;
  target_quote_id uuid;
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  -- Definer rights skip row level security, so membership is checked here by hand rather than assumed.
  select opportunity.organization_id, opportunity.quote_id
  into target_organization_id, target_quote_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id;

  if target_organization_id is null
     or not private.member_has_permission(target_organization_id, caller_id, 'pipeline.edit') then
    -- Same answer either way: a stranger learns nothing about whether the record exists.
    raise exception 'You do not have access to change this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  if set_value and not caller_sees_money then
    raise exception 'You do not have access to change values on the sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if set_value and target_quote_id is not null then
    raise exception 'A quote-backed opportunity''s value comes from the quote and cannot be edited here.'
      using errcode = 'check_violation';
  end if;

  return query
  update public.opportunities as opportunity
  set
    owner_user_id = case when set_owner then new_owner_user_id else opportunity.owner_user_id end,
    estimated_value = case when set_value then new_estimated_value else opportunity.estimated_value end,
    expected_close_on =
      case when set_expected_close then new_expected_close_on else opportunity.expected_close_on end,
    next_follow_up_on =
      case when set_next_follow_up then new_next_follow_up_on else opportunity.next_follow_up_on end
  where opportunity.id = target_opportunity_id
  returning
    opportunity.id,
    opportunity.owner_user_id,
    -- Nothing is returned to somebody who may not see money, not even the value they did not change.
    case when caller_sees_money then opportunity.estimated_value end,
    opportunity.expected_close_on,
    opportunity.next_follow_up_on,
    opportunity.updated_at;
end;
$$;

revoke all on function public.pipeline_update_opportunity_details(
  uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date
) from public;
revoke execute on function public.pipeline_update_opportunity_details(
  uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date
) from anon;
grant execute on function public.pipeline_update_opportunity_details(
  uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date
) to authenticated;

-- 5. Backfill: every quote-backed opportunity that already exists gets its real value immediately, rather
--    than waiting for its quote's next price edit.

update public.opportunities as opportunity
set estimated_value = private.quote_current_total_minor(opportunity.quote_id) / 100.0
where opportunity.quote_id is not null;
