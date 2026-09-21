-- Part 11a: the job's tax card has to show which of the five options is currently chosen, and 'no tax' and
-- 'never configured' both look like a zero rate from the outside. tax_source and tax_rate_id are the answer,
-- and they sit behind the same jobs.view_price gate as the rest of the money -- a member who may not see
-- prices still sees nothing.
create or replace function public.job_money(target_job_ids uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  if target_job_ids is null or cardinality(target_job_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct job.organization_id) into organizations
  from public.jobs as job
  where job.id = any(target_job_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those jobs do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to these jobs.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(org, caller, 'jobs.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(job.id::text,
      (case when can_price then jsonb_build_object(
         'subtotal_minor', job.subtotal_minor,
         'discount_minor', job.discount_minor,
         'discount_name', job.discount_name,
         'discount_type', job.discount_type,
         'discount_value', job.discount_value,
         'tax_minor', job.tax_minor,
         'tax_name', job.tax_name,
         'tax_source', job.tax_source,
         'tax_rate_id', job.tax_rate_id,
         'tax_rate_basis_points', job.tax_rate_basis_points,
         'total_minor', job.total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'cost_minor', job.cost_minor,
         'profit_minor', job.total_minor - job.tax_minor - job.cost_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.jobs as job
  where job.organization_id = org
    and job.id = any(target_job_ids);

  return answer;
end;
$$;

notify pgrst, 'reload schema';
