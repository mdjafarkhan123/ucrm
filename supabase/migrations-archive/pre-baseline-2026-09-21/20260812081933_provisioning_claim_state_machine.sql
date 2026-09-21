-- Atomic claim/resume for provisioning.
--
-- Replaces the previous select-then-insert/update claim in application code (a check-then-act
-- race) with one atomic database function. A caller gets exactly one of three answers, safe
-- under concurrent clicks/retries:
--   'already_succeeded' -- replay the existing organization, do nothing else.
--   'in_progress'       -- another request claimed this application recently; reject cleanly.
--   'claimed'           -- go ahead. administrator_user_id is returned non-null when an earlier,
--                          interrupted attempt already created a login account for this
--                          application -- the caller must reuse it instead of creating a second
--                          one, so a crash between "create login account" and "create company"
--                          can always resume instead of dead-ending.
-- No new columns: reuses the existing administrator_user_id column (for resume) and updated_at
-- (already maintained by the table's own set_updated_at trigger) for staleness detection.
create or replace function public.claim_onboarding_application_provision(
  target_application_id uuid,
  stale_after interval default interval '2 minutes'
)
returns table (
  claim_status text,
  organization_id uuid,
  administrator_user_id uuid,
  attempt_count integer
)
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  did_insert boolean;
  row_data public.platform_onboarding_application_provisions%rowtype;
begin
  insert into public.platform_onboarding_application_provisions (application_id, status, attempt_count)
  values (target_application_id, 'pending', 1)
  on conflict (application_id) do nothing
  returning true into did_insert;

  if did_insert then
    return query select 'claimed'::text, null::uuid, null::uuid, 1;
    return;
  end if;

  select * into row_data
  from public.platform_onboarding_application_provisions
  where application_id = target_application_id
  for update;

  if row_data.status = 'succeeded' then
    return query
      select 'already_succeeded'::text, row_data.organization_id, row_data.administrator_user_id,
        row_data.attempt_count;
    return;
  end if;

  if row_data.status = 'pending' and row_data.updated_at > (now() - stale_after) then
    return query select 'in_progress'::text, null::uuid, null::uuid, row_data.attempt_count;
    return;
  end if;

  update public.platform_onboarding_application_provisions
  set status = 'pending', attempt_count = row_data.attempt_count + 1, last_error = null
  where application_id = target_application_id;

  return query
    select 'claimed'::text, null::uuid, row_data.administrator_user_id, row_data.attempt_count + 1;
end;
$$;

revoke all on function public.claim_onboarding_application_provision(uuid, interval)
  from public, anon, authenticated;
grant execute on function public.claim_onboarding_application_provision(uuid, interval)
  to service_role;
