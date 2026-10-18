-- The Job details editor saves its scope, discount and tax with one button. A single
-- RPC keeps the existing revision guards and makes all selected changes atomic.
create function public.save_job_pricing(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_lines jsonb,
  new_discount jsonb,
  new_tax jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
  next_revision integer := expected_revision;
begin
  if auth.uid() is null then
    raise exception 'Sign in before changing job pricing.' using errcode = 'insufficient_privilege';
  end if;

  if new_lines is null and new_discount is null and new_tax is null then
    raise exception 'Choose a pricing change to save.' using errcode = 'check_violation';
  end if;

  if new_lines is not null then
    result := public.replace_job_line_items(
      target_organization_id, target_job_id, next_revision, new_lines
    );
    next_revision := (result->>'revision')::integer;
  end if;

  if new_discount is not null then
    result := public.set_job_discount(
      target_organization_id,
      target_job_id,
      next_revision,
      new_discount->>'name',
      new_discount->>'type',
      (new_discount->>'value')::bigint
    );
    next_revision := (result->>'revision')::integer;
  end if;

  if new_tax is not null then
    result := public.set_job_tax(
      target_organization_id,
      target_job_id,
      next_revision,
      new_tax->>'source',
      (new_tax->>'rate_id')::uuid,
      new_tax->>'custom_name',
      (new_tax->>'custom_rate_basis_points')::integer,
      coalesce((new_tax->>'save_as_reusable')::boolean, false)
    );
    next_revision := (result->>'revision')::integer;
  end if;

  return jsonb_build_object('revision', next_revision);
end;
$$;

revoke all on function public.save_job_pricing(uuid, uuid, integer, jsonb, jsonb, jsonb) from public;
revoke all on function public.save_job_pricing(uuid, uuid, integer, jsonb, jsonb, jsonb) from anon;
grant execute on function public.save_job_pricing(uuid, uuid, integer, jsonb, jsonb, jsonb) to authenticated, service_role;

comment on function public.save_job_pricing(uuid, uuid, integer, jsonb, jsonb, jsonb)
  is 'Atomically saves selected job lines, discount and tax using their established permission and revision-guarded commands.';
