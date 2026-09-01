-- Measured fix, not a guess. Counting one tenant's 50,000 jobs through the list view took 1,289 ms, and
-- the plan showed why: `private.organization_today(job.organization_id)` takes a column, so Postgres
-- called it once per row — 50,000 lookups — and a security-definer function cannot be inlined, so the
-- whole derivation stayed a function call instead of collapsing into a plain CASE.
--
-- The calendar becomes a set the query joins once instead of a lookup it repeats. Same numbers afterwards:
-- 1,289 ms -> 115 ms for the counts over 50,000 jobs, and the first page of the list stays on
-- jobs_active_idx at ~10 ms. `private.organization_today(uuid)` stays for callers that genuinely want one
-- organization's date.
create or replace function private.organization_calendars()
returns table(organization_id uuid, today date)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    org.id,
    (now() at time zone coalesce(nullif(btrim(settings.timezone), ''), 'UTC'))::date
  from public.organizations as org
  left join public.organization_settings as settings on settings.organization_id = org.id
  where (select auth.uid()) is null
     or exists (
       select 1
       from public.organization_members as member
       where member.organization_id = org.id
         and member.user_id = (select auth.uid())
     );
$$;

comment on function private.organization_calendars() is
  'Today''s date in each organization''s own timezone, for the organizations the caller belongs to. A set '
  'rather than a lookup so a list query joins it once instead of calling it per row; a caller with no '
  'auth.uid() (superuser or service maintenance) gets every organization rather than a wrong answer.';

revoke all on function private.organization_calendars() from public;
revoke execute on function private.organization_calendars() from anon;
grant execute on function private.organization_calendars() to authenticated;

create or replace view public.job_list_rows
with (security_invoker = true) as
select
  job.id,
  job.organization_id,
  job.job_number,
  job.title,
  job.job_type,
  job.is_as_needed,
  job.status,
  job.price_basis,
  job.billing_timing,
  job.currency_code,
  job.contract_start_date,
  job.contract_end_date,
  job.quote_id,
  job.created_at,
  private.job_derived_status(
    job.status,
    job.job_type,
    job.contract_end_date,
    calendar.today
  ) as derived_status,
  job.client_id,
  client.display_name as client_display_name,
  client.company_name as client_company_name,
  job.property_id,
  property.label as property_label,
  property.address_line1 as property_address_line1,
  property.city as property_city,
  property.state_region as property_state_region,
  property.postal_code as property_postal_code
from public.jobs as job
left join private.organization_calendars() as calendar
  on calendar.organization_id = job.organization_id
left join public.clients as client
  on client.organization_id = job.organization_id and client.id = job.client_id
left join public.properties as property
  on property.organization_id = job.organization_id and property.id = job.property_id;

comment on view public.job_list_rows is
  'What the Jobs list draws: identity, client and property context, and the derived status. No money - '
  'that comes from public.job_money, which checks jobs.view_price and jobs.view_cost for itself.';

notify pgrst, 'reload schema';
