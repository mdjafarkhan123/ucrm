-- Communications Part 2: provider-confirmed cleanup and its immutable receipt commit together.

create or replace function public.finalize_communication_email_domain_removal(
  target_organization_id uuid,
  target_domain_id uuid,
  actor_owner_email text,
  removal_reason text,
  command_idempotency_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  target_domain public.communication_email_domains;
  existing_event public.communication_email_authority_events;
  removed_at timestamptz := clock_timestamp();
  final_state jsonb;
begin
  if nullif(btrim(actor_owner_email), '') is null then
    raise exception 'Platform owner attribution is required.' using errcode = 'check_violation';
  end if;
  if char_length(btrim(removal_reason)) not between 1 and 500 then
    raise exception 'A valid removal reason is required.' using errcode = 'check_violation';
  end if;
  if char_length(btrim(command_idempotency_key)) not between 1 and 200 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_event
  from public.communication_email_authority_events
  where organization_id = target_organization_id
    and target_id = target_domain_id
    and event_type = 'domain.removed'
    and idempotency_key = command_idempotency_key;

  if found then
    return existing_event.after_state || jsonb_build_object('status', 'replayed');
  end if;

  select * into target_domain
  from public.communication_email_domains
  where organization_id = target_organization_id and id = target_domain_id
  for update;

  if not found or target_domain.purpose <> 'sending' then
    return jsonb_build_object('status', 'not_found');
  end if;
  if target_domain.lifecycle_state <> 'removal_pending' then
    return jsonb_build_object('status', 'not_pending');
  end if;

  final_state := jsonb_build_object(
    'domain_name', target_domain.domain_name,
    'purpose', 'sending',
    'lifecycle_state', 'removed',
    'provider_cleanup_confirmed', true,
    'removed_at', removed_at
  );

  update public.communication_email_domains
  set lifecycle_state = 'removed',
      provider_domain_id = null,
      provider_verified = false,
      provider_authenticated = false,
      ownership_status = 'unchecked',
      dkim_status = 'unchecked',
      dmarc_status = 'unchecked',
      spf_status = 'unchecked',
      dns_records = '[]'::jsonb,
      verified_at = null,
      warmup_started_at = null,
      transition_until = null,
      provider_cleanup_error = null,
      updated_at = removed_at
  where organization_id = target_organization_id and id = target_domain_id;

  insert into public.communication_email_authority_events (
    organization_id, actor_kind, actor_owner_email, event_type, target_type, target_id,
    before_state, after_state, reason, idempotency_key, occurred_at
  ) values (
    target_organization_id, 'platform_owner', btrim(actor_owner_email), 'domain.removed',
    'domain', target_domain_id,
    jsonb_build_object(
      'domain_name', target_domain.domain_name,
      'lifecycle_state', target_domain.lifecycle_state
    ),
    final_state, btrim(removal_reason), command_idempotency_key, removed_at
  );

  return final_state || jsonb_build_object('status', 'completed');
end;
$$;

revoke all on function public.finalize_communication_email_domain_removal(uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_email_domain_removal(uuid, uuid, text, text, text)
  to service_role;

comment on function public.finalize_communication_email_domain_removal(uuid, uuid, text, text, text) is
  'Atomically clears provider authority and writes the immutable receipt after provider-confirmed domain cleanup.';
