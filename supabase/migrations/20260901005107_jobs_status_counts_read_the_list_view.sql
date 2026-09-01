-- The overview counts have to reach the derivation rule, and that rule lives in the `private` schema.
-- `authenticated` has no USAGE on `private`, which is deliberate: a view's body resolves its names once,
-- when the view is created, so the list view can call the rule, but a security-invoker SQL function
-- resolves its body as the caller and is refused. Counting the view instead of the table fixes that and
-- is better anyway — a tile and the rows behind it now read the same status from the same place.
--
-- Same body as the corrected function in 20260901004832; this file exists so the applied ledger and the
-- repository stay in step.
create or replace function public.job_status_counts(target_organization_id uuid)
returns table(derived_status text, total bigint)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select listed.derived_status, count(*) as total
  from public.job_list_rows as listed
  where listed.organization_id = target_organization_id
  group by 1;
$$;

comment on function public.job_status_counts(uuid) is
  'Live count of this organization''s jobs by derived status, for the Jobs overview card. Counts the same '
  'view the list draws so a tile and its rows cannot disagree.';

revoke all on function public.job_status_counts(uuid) from public, anon;
grant execute on function public.job_status_counts(uuid) to authenticated;

notify pgrst, 'reload schema';
