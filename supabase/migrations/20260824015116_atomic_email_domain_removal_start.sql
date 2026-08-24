-- Communications Part 2: close the sender-creation/removal race with one short database command.
-- Brevo cleanup deliberately remains outside this transaction.

create or replace function private.validate_communication_email_sender()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  sender_domain public.communication_email_domains;
  membership_status text;
begin
  select * into sender_domain
  from public.communication_email_domains
  where organization_id = new.organization_id and id = new.domain_id
  for share;

  if not found or sender_domain.purpose <> 'sending' or sender_domain.lifecycle_state = 'removed' then
    raise exception 'A sender requires a live sending domain in the same organization.'
      using errcode = 'foreign_key_violation';
  end if;

  if new.lifecycle_state <> 'removed' and sender_domain.lifecycle_state <> 'verified' then
    raise exception 'A live sender requires a verified sending domain.'
      using errcode = 'check_violation';
  end if;

  if split_part(new.email_address, '@', 2) <> sender_domain.domain_name then
    raise exception 'The sender address must use its sending domain.' using errcode = 'check_violation';
  end if;

  if new.assigned_user_id is not null then
    select status into membership_status
    from public.organization_members
    where organization_id = new.organization_id and user_id = new.assigned_user_id;

    if membership_status is distinct from 'active' and new.lifecycle_state = 'enabled' then
      raise exception 'An enabled assigned sender requires an active organization member.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.validate_communication_email_sender()
  from public, anon, authenticated, service_role;

create or replace function public.begin_communication_email_domain_removal(
  target_organization_id uuid,
  target_domain_id uuid,
  expected_live_sender_count integer,
  expected_live_replacement_count integer
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  target_domain public.communication_email_domains;
  actual_live_sender_count integer;
  actual_live_replacement_count integer;
begin
  if expected_live_sender_count < 0 or expected_live_replacement_count < 0 then
    raise exception 'Expected removal impact cannot be negative.' using errcode = 'check_violation';
  end if;

  select * into target_domain
  from public.communication_email_domains
  where organization_id = target_organization_id
    and id = target_domain_id
    and purpose = 'sending'
    and lifecycle_state <> 'removed'
  for update;

  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  select count(*)::integer into actual_live_sender_count
  from public.communication_email_senders
  where organization_id = target_organization_id
    and domain_id = target_domain_id
    and lifecycle_state <> 'removed';

  select count(*)::integer into actual_live_replacement_count
  from public.communication_email_domains
  where organization_id = target_organization_id
    and replacement_of_domain_id = target_domain_id
    and lifecycle_state <> 'removed';

  if actual_live_sender_count <> expected_live_sender_count
    or actual_live_replacement_count <> expected_live_replacement_count then
    return jsonb_build_object(
      'status', 'impact_changed',
      'live_sender_count', actual_live_sender_count,
      'live_replacement_count', actual_live_replacement_count
    );
  end if;

  if actual_live_sender_count > 0 or actual_live_replacement_count > 0 then
    return jsonb_build_object(
      'status', 'blocked',
      'live_sender_count', actual_live_sender_count,
      'live_replacement_count', actual_live_replacement_count
    );
  end if;

  update public.communication_email_domains
  set lifecycle_state = 'removal_pending', provider_cleanup_error = null, updated_at = now()
  where organization_id = target_organization_id and id = target_domain_id;

  return jsonb_build_object(
    'status', 'started',
    'domain_name', target_domain.domain_name,
    'previous_lifecycle_state', target_domain.lifecycle_state,
    'live_sender_count', actual_live_sender_count,
    'live_replacement_count', actual_live_replacement_count
  );
end;
$$;

revoke all on function public.begin_communication_email_domain_removal(uuid, uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.begin_communication_email_domain_removal(uuid, uuid, integer, integer)
  to service_role;

comment on function public.begin_communication_email_domain_removal(uuid, uuid, integer, integer) is
  'Atomically checks the confirmed impact and starts sending-domain removal. Provider cleanup stays outside the transaction.';
