-- Business Profile has to tell the truth about currency before the person edits, not after the save
-- fails. Whether a Quote exists is the rule `save_organization_business_settings` enforces, but reading
-- `quotes` directly needs `quotes.view`, which someone allowed to see business settings may not have.
-- Asking through here answers the one yes/no question without handing out any quote rows.

create or replace function public.organization_currency_is_locked(target_organization_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.has_permission(target_organization_id, 'settings.business.view') then
    raise exception 'You do not have access to business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  return exists (select 1 from public.quotes where organization_id = target_organization_id);
end;
$$;

revoke all on function public.organization_currency_is_locked(uuid) from public;
revoke execute on function public.organization_currency_is_locked(uuid) from anon;
grant execute on function public.organization_currency_is_locked(uuid) to authenticated;
