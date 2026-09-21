-- Part 9, step 7 prep: a durable retry anchor for the Auth-deletion leg of a purge.
--
-- apply_organization_purge already returns member_user_ids so the caller can delete them from
-- Auth right after a successful call. But if that TypeScript-side deletion itself fails partway
-- (network blip, one bad id), the organization row -- and with it organization_closure_records,
-- the only other place member ids could have been read from -- is already gone by then. Without
-- somewhere durable to keep those ids, a failed Auth cleanup could never be retried: there would
-- be no way left to know which Auth users still need deleting. This mirrors the existing
-- platform_onboarding_application_provisions.administrator_user_id pattern -- a transient
-- operational retry anchor, not permanent identifying content -- and is cleared back to null the
-- moment Auth cleanup actually succeeds, so the receipt's steady state stays exactly what the
-- approved behavior requires: no organization name, personal detail, or CRM content, just
-- operation id, timestamps, and component outcomes.

alter table public.organization_deletion_receipts
  add column pending_auth_user_ids uuid[];

create or replace function public.apply_organization_purge(
  target_organization_id uuid,
  purge_trigger_kind text,
  actor_owner_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  organization_row public.organizations%rowtype;
  closure_record public.organization_closure_records%rowtype;
  inserted_receipt public.organization_deletion_receipts%rowtype;
  member_user_ids uuid[];
  had_onboarding_provision boolean;
begin
  if purge_trigger_kind not in ('scheduled', 'early_manual') then
    raise exception 'An invalid purge trigger kind was supplied.' using errcode = 'check_violation';
  end if;
  if purge_trigger_kind = 'early_manual'
    and char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required for an early manual purge.'
      using errcode = 'check_violation';
  end if;

  select * into organization_row
  from public.organizations
  where id = target_organization_id
  for update;

  if not found then
    return jsonb_build_object('applied', false, 'reason', 'already_purged');
  end if;

  select * into closure_record
  from public.organization_closure_records
  where organization_id = target_organization_id
    and status in ('pending_closure', 'purge_in_progress')
  for update;

  if not found then
    raise exception 'No open closure window was found for this organization.'
      using errcode = 'check_violation';
  end if;

  select coalesce(array_agg(distinct organization_members.user_id), array[]::uuid[])
  into member_user_ids
  from public.organization_members
  where organization_members.organization_id = target_organization_id;

  select exists (
    select 1
    from public.platform_onboarding_application_provisions
    where platform_onboarding_application_provisions.organization_id = target_organization_id
  ) into had_onboarding_provision;

  perform set_config('app.organization_purge_in_progress', 'true', true);

  delete from public.organization_package_assignments
  where organization_id = target_organization_id;

  delete from public.organization_free_access_events
  where organization_id = target_organization_id;

  update public.platform_onboarding_application_provisions
  set organization_id = null
  where organization_id = target_organization_id;

  delete from public.organizations
  where id = target_organization_id;

  insert into public.organization_deletion_receipts (
    trigger_kind, status, completed_at, component_results, pending_auth_user_ids
  ) values (
    purge_trigger_kind, 'completed', now(),
    jsonb_build_object(
      'organization_data', 'succeeded',
      'package_assignments', 'succeeded',
      'free_access_history', 'succeeded',
      'onboarding_provision_unlinked', case when had_onboarding_provision then 'succeeded' else 'not_applicable' end,
      'provider_resources', 'not_applicable',
      'auth_users', case when coalesce(array_length(member_user_ids, 1), 0) = 0 then 'not_applicable' else 'pending' end
    ),
    nullif(member_user_ids, array[]::uuid[])
  ) returning * into inserted_receipt;

  return jsonb_build_object(
    'applied', true,
    'operation_id', inserted_receipt.operation_id,
    'member_user_ids', to_jsonb(member_user_ids)
  );
end;
$$;

revoke all on function public.apply_organization_purge(
  uuid, text, text
) from public, anon, authenticated;

grant execute on function public.apply_organization_purge(
  uuid, text, text
) to service_role;

comment on function public.apply_organization_purge(
  uuid, text, text
) is 'Permanently erases an organization''s CRM data and history once its closure window is due or an early manual delete is confirmed. Returns the member Auth user ids for the caller to delete afterward -- Auth deletion cannot happen inside Postgres -- and also durably stores them on the receipt as pending_auth_user_ids so a later crash can still find them and retry.';
