-- The new Quotes policies repeated a mistake this repository has already corrected twice: calling the
-- membership and permission helpers once per returned row. Measured on the Pipeline board at 50,000 rows,
-- that cost 11 ms and 766 buffers for a 50-row page against 0.18 ms and 5 buffers. The answer is the same
-- for every row in a query, so it is resolved once. A price list is read on every quote screen and a
-- version's lines are read as a whole document, so this is exactly where it would show.
--
-- It also closes the same gap the Task fix closed: private.permitted_organizations requires the
-- organization to still be active, which the per-row helper pair did not check.

-- Request pricing is readable by any member of the organization, with no separate permission key, the
-- same rule public.requests itself uses. There was no set-returning helper for that case yet.
create or replace function private.member_organizations()
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select membership.organization_id
  from public.organization_members as membership
  join public.organizations as organization
    on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid())
    and organization.lifecycle_status = 'active';
$$;

revoke all on function private.member_organizations() from public;
grant execute on function private.member_organizations() to authenticated;

drop policy "permitted members can view catalog items" on public.catalog_items;
drop policy "permitted members can create catalog items" on public.catalog_items;
drop policy "permitted members can update catalog items" on public.catalog_items;
drop policy "members can view request pricing" on public.request_pricing_lines;
drop policy "permitted members can view quotes" on public.quotes;
drop policy "permitted members can view quote versions" on public.quote_versions;
drop policy "permitted members can view quote version lines" on public.quote_version_lines;

create policy "permitted members can view catalog items"
on public.catalog_items for select to authenticated
using (organization_id in (select private.permitted_organizations('catalog.view')));

create policy "permitted members can create catalog items"
on public.catalog_items for insert to authenticated
with check (organization_id in (select private.permitted_organizations('catalog.edit')));

create policy "permitted members can update catalog items"
on public.catalog_items for update to authenticated
using (organization_id in (select private.permitted_organizations('catalog.edit')))
with check (organization_id in (select private.permitted_organizations('catalog.edit')));

create policy "members can view request pricing"
on public.request_pricing_lines for select to authenticated
using (organization_id in (select private.member_organizations()));

create policy "permitted members can view quotes"
on public.quotes for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

create policy "permitted members can view quote versions"
on public.quote_versions for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

create policy "permitted members can view quote version lines"
on public.quote_version_lines for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));
