-- Quotes Part 6C continued: `ready_for_job` is a status fact, not money -- anyone who may view the quote at
-- all should get the right answer, not just someone who also holds `quotes.view_price`. Computing it from
-- the API's own price-gated selects would give a wrong "ready" answer to a viewer without that permission,
-- so it is computed here instead, authoritatively, the same way the customer document's `satisfied` flag
-- already is. Part 8's real Convert-to-Job route reuses this rather than re-deriving the same fact again.
create or replace function public.quote_ready_for_job(target_quote_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
begin
  select * into quote_row from public.quotes where id = target_quote_id;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view'
  ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status <> 'approved' or quote_row.current_published_version_id is null then
    return false;
  end if;

  select * into version_row
  from public.quote_versions
  where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id;

  if version_row.deposit_type is null or version_row.deposit_required_minor <= 0 then
    return true;
  end if;

  return exists (
    select 1 from public.quote_deposit_events received
    where received.organization_id = version_row.organization_id
      and received.quote_id = version_row.quote_id
      and received.quote_version_id = version_row.id
      and received.event_type = 'received'
      and not exists (
        select 1 from public.quote_deposit_events reversal
        where reversal.organization_id = received.organization_id
          and reversal.reversed_event_id = received.id
      )
  );
end;
$$;

revoke all on function public.quote_ready_for_job(uuid) from public;
revoke execute on function public.quote_ready_for_job(uuid) from anon;
grant execute on function public.quote_ready_for_job(uuid) to authenticated;
