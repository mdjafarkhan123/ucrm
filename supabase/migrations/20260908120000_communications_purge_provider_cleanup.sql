-- ---------------------------------------------------------------------------------------------------
-- Communications Part 8.4 -- retryable provider (Brevo) cleanup during a permanent purge.
--
-- apply_organization_purge already erases an organization's own database rows in one cascading delete
-- and returns the member Auth user ids so the caller can delete those from the separate Auth system
-- afterward (retry anchor: organization_deletion_receipts.pending_auth_user_ids). The org's Brevo
-- resources -- its sending/receiving domains and sender addresses -- live in that same separate,
-- HTTP-only world: they cannot be deleted from inside Postgres, and the cascade takes their opaque
-- provider identifiers with it. This migration extends the exact same read-out-then-park-then-retry
-- pattern to those resources.
--
-- Two things the contract (docs/contractor-email-contract.md, "Suspension, closure, and deletion")
-- forces here:
--   1. Provider cleanup failure must remain a retryable operation and can never be reported complete.
--   2. The deletion receipt may hold aggregate cleanup results but NO domains, recipients, content, or
--      message identifiers.
-- So the anchor stores only Brevo's opaque provider_domain_id / provider_sender_id handles (like the
-- member uuids already parked for Auth) -- never a domain name or sender address. A later cron sweep
-- lists Brevo, matches by that opaque id, deletes, and clears the anchor.
--
-- State model (unified across BOTH external legs -- Auth and provider -- per Jafar, 2026-08-28):
-- the receipt's top-level status now represents the WHOLE purge including required external cleanup.
--   * in_progress  while any applicable external leg is still pending (completed_at stays null)
--   * failed_partial after any external cleanup failure
--   * completed only when every applicable component has succeeded and both retry anchors are cleared
-- Neither cleanup helper can mark the receipt complete while the other leg is still pending or failed.
-- ---------------------------------------------------------------------------------------------------

alter table public.organization_deletion_receipts
  add column pending_provider_resources jsonb
    check (
      pending_provider_resources is null
      or (
        jsonb_typeof(pending_provider_resources) = 'array'
        and jsonb_array_length(pending_provider_resources) > 0
      )
    );

comment on column public.organization_deletion_receipts.pending_provider_resources is
  'Transient retry anchor for provider (Brevo) cleanup that has not finished: a jsonb array of {kind, provider_id} using only Brevo''s opaque provider ids -- never a domain name or sender address. Cleared to null once provider cleanup succeeds.';

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
  provider_resources jsonb;
  auth_pending boolean;
  provider_pending boolean;
  receipt_status text;
  receipt_completed_at timestamptz;
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
    -- Already purged (or never existed). A retry after a successful purge -- or after only an external
    -- cleanup leg needed a retry -- must not raise here.
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

  -- Read the opaque Brevo identifiers out BEFORE the cascade takes them. Only domains/senders that
  -- still hold a provider id and are not already 'removed' need cleanup -- an earlier per-resource
  -- removal already cleaned up anything in the 'removed' state. Never carry the domain name or sender
  -- address here: only Brevo's opaque provider id, which is not identifying content.
  select coalesce(jsonb_agg(resource order by resource ->> 'kind', resource ->> 'provider_id'), '[]'::jsonb)
  into provider_resources
  from (
    select jsonb_build_object('kind', 'domain', 'provider_id', provider_domain_id::text) as resource
    from public.communication_email_domains
    where organization_id = target_organization_id
      and provider_domain_id is not null
      and lifecycle_state <> 'removed'
    union all
    select jsonb_build_object('kind', 'sender', 'provider_id', provider_sender_id::text) as resource
    from public.communication_email_senders
    where organization_id = target_organization_id
      and provider_sender_id is not null
      and lifecycle_state <> 'removed'
  ) as resources;

  auth_pending := coalesce(array_length(member_user_ids, 1), 0) > 0;
  provider_pending := jsonb_array_length(provider_resources) > 0;

  -- Only when both external legs are inapplicable can the purge stand complete on the spot.
  if auth_pending or provider_pending then
    receipt_status := 'in_progress';
    receipt_completed_at := null;
  else
    receipt_status := 'completed';
    receipt_completed_at := now();
  end if;

  perform set_config('app.organization_purge_in_progress', 'true', true);

  delete from public.organization_package_assignments
  where organization_id = target_organization_id;

  delete from public.organization_free_access_events
  where organization_id = target_organization_id;

  update public.platform_onboarding_application_provisions
  set organization_id = null
  where organization_id = target_organization_id;

  -- One statement: every remaining organization-scoped table cascades from this row, including
  -- organization_closure_records/notices and the communication_email_* rows whose provider ids were
  -- just read out above, so the closure window and the provider bindings are erased with it.
  delete from public.organizations
  where id = target_organization_id;

  insert into public.organization_deletion_receipts (
    trigger_kind, status, completed_at, component_results,
    pending_auth_user_ids, pending_provider_resources
  ) values (
    purge_trigger_kind, receipt_status, receipt_completed_at,
    jsonb_build_object(
      'organization_data', 'succeeded',
      'package_assignments', 'succeeded',
      'free_access_history', 'succeeded',
      'onboarding_provision_unlinked', case when had_onboarding_provision then 'succeeded' else 'not_applicable' end,
      'provider_resources', case when provider_pending then 'pending' else 'not_applicable' end,
      'auth_users', case when auth_pending then 'pending' else 'not_applicable' end
    ),
    case when auth_pending then member_user_ids else null end,
    case when provider_pending then provider_resources else null end
  ) returning * into inserted_receipt;

  return jsonb_build_object(
    'applied', true,
    'operation_id', inserted_receipt.operation_id,
    'member_user_ids', to_jsonb(member_user_ids),
    'provider_resources', provider_resources
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
) is 'Permanently erases an organization''s CRM data and history once its closure window is due or an early manual delete is confirmed. Returns the member Auth user ids and the org''s opaque Brevo provider resources for the caller to clean up from those separate HTTP-only systems afterward, and parks both durably on the receipt (pending_auth_user_ids, pending_provider_resources) so a later crash can still find and retry them. The receipt is completed only once both external legs finish.';
