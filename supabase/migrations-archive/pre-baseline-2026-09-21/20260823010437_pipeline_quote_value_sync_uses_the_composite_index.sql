-- opportunities_quote_unique is (organization_id, quote_id). The previous version of this trigger updated
-- opportunities filtered on quote_id alone, which cannot use that composite index as an equality
-- condition and would seq-scan the whole tenant table on every quote price edit -- exactly the mistake
-- private.opportunity_resync_from_quote (20260902090700) already documented and avoided for the same
-- table. Caught in performance review before this ever shipped past the browser-verification session.

create or replace function private.sync_opportunity_value_from_quote()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid;
  target_quote_id uuid;
begin
  target_organization_id := coalesce(new.organization_id, old.organization_id);
  target_quote_id := case tg_table_name
    when 'quotes' then coalesce(new.id, old.id)
    else coalesce(new.quote_id, old.quote_id)
  end;

  update public.opportunities
  set estimated_value = private.quote_current_total_minor(target_quote_id) / 100.0
  where organization_id = target_organization_id
    and quote_id = target_quote_id;

  return null;
end;
$$;
