-- 20260910151000 swapped the table-wide select on catalog_items for a column list so unit_cost_minor
-- would leave the authenticated grant, but the list also dropped organization_id. Postgres checks column
-- privilege on every column a query names, WHERE included, and every catalog read filters on the tenant
-- (`.eq('organization_id', …)`), so the Price Book and the line-item picker were refused outright
-- (42501 -> PostgREST 403) for every role, owner included. The tenant id is not sensitive; RLS still
-- decides which rows come back. Cost stays out of the grant.
grant select (organization_id) on public.catalog_items to authenticated;

notify pgrst, 'reload schema';
