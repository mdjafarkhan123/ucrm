-- Part 9: recoverable closure and strict purge -- the purge RPC.
--
-- Two of the three non-cascade organization_id foreign keys point at tables that are also
-- protected by a "history is append-only" trigger blocking every UPDATE and DELETE
-- (organization_package_assignments, organization_free_access_events). A plain DELETE from the
-- purge RPC would be rejected outright by that trigger, not just leave a dangling reference.
-- Both trigger functions gain a narrow bypass: DELETE is allowed only when the purge RPC itself
-- sets a transaction-local flag immediately before deleting. UPDATE stays blocked unconditionally
-- for every caller including the purge RPC -- history rows are never edited, only ever wholesale
-- removed as part of permanently erasing the organization that owns them.

create or replace function private.prevent_organization_package_assignment_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
    return old;
  end if;
  raise exception 'Organization package assignment history is append-only.' using errcode = 'check_violation';
end;
$$;

create or replace function private.prevent_organization_free_access_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
    return old;
  end if;
  raise exception 'Free access history is append-only.' using errcode = 'check_violation';
end;
$$;

-- ---------------------------------------------------------------------------
-- apply_organization_purge
-- ---------------------------------------------------------------------------
--
-- Permanently erases every live trace of one organization: its CRM data (cascades from the
-- organizations row), the two non-cascade history tables above, and unlinks (never deletes) the
-- standalone onboarding-provisioning row so that operational retry anchor survives. Auth user
-- deletion cannot happen here (no HTTP/Auth-admin context inside Postgres) -- the caller deletes
-- the returned member_user_ids afterward and finishes the receipt's "auth_users" component. This
-- function only ever fully commits or fully rolls back: there is no internal partial state to
-- resume, so a failed call is safely retried by calling it again unchanged. Once the organization
-- row is gone, a repeat call is a harmless no-op -- there is deliberately no way to look up a past
-- receipt from an organization id afterward, since the receipt keeps no organization-identifying
-- field by design.
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
    -- Already purged (or never existed). A retry after a successful purge -- or after only the
    -- Auth-deletion leg needed a retry -- must not raise here.
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

  -- One statement: every remaining organization-scoped table cascades from this row, including
  -- organization_closure_records/notices, so the closure window and its notices are erased with
  -- it. Postgres resolves the whole cascade graph (including the safe_events RESTRICT reference
  -- into commercial_events, which also cascades from organizations) before checking constraints,
  -- so this cannot be split into separate statements without risking an intermediate-state error.
  delete from public.organizations
  where id = target_organization_id;

  insert into public.organization_deletion_receipts (
    trigger_kind, status, completed_at, component_results
  ) values (
    purge_trigger_kind, 'completed', now(),
    jsonb_build_object(
      'organization_data', 'succeeded',
      'package_assignments', 'succeeded',
      'free_access_history', 'succeeded',
      'onboarding_provision_unlinked', case when had_onboarding_provision then 'succeeded' else 'not_applicable' end,
      'provider_resources', 'not_applicable',
      'auth_users', 'pending'
    )
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
) is 'Permanently erases an organization''s CRM data and history once its closure window is due or an early manual delete is confirmed. Returns the member Auth user ids for the caller to delete afterward -- Auth deletion cannot happen inside Postgres.';
