-- Contractor Settings, Part 2A: the Quote/Property tax picker.
--
-- Every write path for tax already exists (rate CRUD, the Business default, `set_quote_draft_tax`), but
-- nothing lets a quote or property editor -- who may hold neither `settings.taxes.manage` nor
-- `settings.business.view` -- read the active rate list or the resolved Business default to populate a
-- picker. `organization_tax_rates` already grants that read to `quotes.edit`/`property.manage` via its own
-- RLS policy, but `organization_settings` is gated to `settings.business.view` only, so the Business
-- default's resolved answer needs one small SECURITY DEFINER seam instead of a direct table read.

create or replace function public.organization_tax_picker(
  target_organization_id uuid,
  target_property_id uuid default null
)
returns table (source text, name text, rate_basis_points integer, rate_id uuid)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  rate_row public.organization_tax_rates;
begin
  if not (
    private.has_permission(target_organization_id, 'quotes.edit')
    or private.has_permission(target_organization_id, 'property.manage')
    or private.has_permission(target_organization_id, 'settings.taxes.manage')
  ) then
    raise exception 'You do not have access to view tax settings.' using errcode = 'insufficient_privilege';
  end if;

  -- A property was named: hand back what it actually resolves to (its own pin, or the Business default
  -- fallback) -- the same answer a new Quote draft would freeze.
  if target_property_id is not null then
    return query select * from private.resolve_property_tax(target_organization_id, target_property_id);
    return;
  end if;

  -- No property in play (a new Quote/Property has none yet): just the Business default alone.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id;

  if settings_row.tax_default_source = 'rate' then
    select * into rate_row
    from public.organization_tax_rates
    where id = settings_row.tax_default_rate_id and organization_id = target_organization_id;

    if rate_row.id is not null then
      return query select 'business_default'::text, rate_row.name, rate_row.rate_basis_points, rate_row.id;
      return;
    end if;
  elsif settings_row.tax_default_source = 'no_tax' then
    return query select 'business_default'::text, null::text, 0, null::uuid;
    return;
  end if;

  return query select 'not_configured'::text, null::text, 0, null::uuid;
end;
$$;

revoke all on function public.organization_tax_picker(uuid, uuid) from public, anon;
grant execute on function public.organization_tax_picker(uuid, uuid) to authenticated;
