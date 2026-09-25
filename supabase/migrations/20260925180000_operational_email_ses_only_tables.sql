-- Operational email SES Part 6 step 3: contractor email tables are Amazon SES only.
--
-- Contractor email no longer runs on Brevo (Brevo stays only for platform emails, which never touch these
-- tables). This migration:
--   1. deletes the Brevo-era rows (only the Raad LTD test organization has any, approved by Jafar 2026-09-25):
--      Brevo domains and senders, their reply aliases, the emails sent through them, the replies received
--      through them, and Brevo delivery callbacks. Each dependent is deleted explicitly, child before
--      parent, so no RESTRICT foreign key is left to decide the order.
--   2. makes provider = 'ses' the only accepted email value. This also fixes live inserts: the email branch
--      of the callback-events check accepted only 'brevo', so every SES delivery event and inbound reply
--      the new code recorded was refused.
--   3. drops the two Brevo-only id columns (sender id, inbound-parse webhook id).
--   4. makes Remove retire the organization's receiving row with its sending row, and makes the org purge
--      hand the closure sweep one SES organization anchor instead of Brevo ids.

-- 1. Brevo-era rows ------------------------------------------------------------------------------------

create temporary table brevo_senders on commit drop as
select s.organization_id, s.id
from public.communication_email_senders s
join public.communication_email_domains d on d.organization_id = s.organization_id and d.id = s.domain_id
where d.provider = 'brevo';

create temporary table brevo_intents on commit drop as
select i.id
from public.communication_delivery_intents i
where i.channel = 'email'
  and (
    exists (select 1 from brevo_senders b where b.organization_id = i.organization_id and b.id = i.sender_id)
    or exists (
      select 1 from public.communication_provider_callback_events c
      where c.delivery_intent_id = i.id and c.provider = 'brevo'
    )
  );

create temporary table brevo_inbound on commit drop as
select m.organization_id, m.id
from public.communication_inbound_messages m
where m.provider = 'brevo'
   or exists (select 1 from brevo_senders b where b.organization_id = m.organization_id and b.id = m.sender_id);

-- Message history is append-only (an UPDATE guard), so an ON DELETE SET NULL from a deleted message into a
-- surviving event would be refused. Every event that names a deleted message goes first.
delete from public.communication_message_events e
where exists (select 1 from brevo_intents b where b.id in (e.delivery_intent_id, e.related_intent_id))
   or exists (select 1 from brevo_inbound m where m.id = e.related_inbound_message_id);

delete from public.communication_forward_events f
where exists (select 1 from brevo_senders b where b.organization_id = f.organization_id and b.id = f.sender_id)
   or exists (
     select 1 from brevo_inbound m
     where m.organization_id = f.organization_id and m.id = f.source_inbound_message_id
   );

delete from public.communication_inbound_messages m
using brevo_inbound b
where m.organization_id = b.organization_id and m.id = b.id;

delete from public.communication_inbound_attachments where provider = 'brevo';

delete from public.communication_provider_callback_events where provider = 'brevo';

delete from public.communication_delivery_intents i
using brevo_intents b
where i.id = b.id;

delete from public.communication_reply_aliases a
where exists (select 1 from brevo_senders b where b.organization_id = a.organization_id and b.id = a.sender_id)
   or exists (
     select 1 from public.communication_email_domains d
     where d.organization_id = a.organization_id and d.id = a.receiving_domain_id and d.provider = 'brevo'
   );

delete from public.communication_email_senders s
using brevo_senders b
where s.organization_id = b.organization_id and s.id = b.id;

delete from public.communication_email_domains where provider = 'brevo';

-- 2. SES-only provider values --------------------------------------------------------------------------

alter table public.communication_email_domains
  drop constraint communication_email_domains_provider_check,
  add constraint communication_email_domains_provider_check check (provider = 'ses'),
  alter column provider set default 'ses';

-- Senders on an SES domain can still carry the old label (Raad's office@mail. sender predates the cutover).
alter table public.communication_email_senders drop constraint communication_email_senders_provider_check;
update public.communication_email_senders set provider = 'ses' where provider <> 'ses';
alter table public.communication_email_senders
  add constraint communication_email_senders_provider_check check (provider = 'ses'),
  alter column provider set default 'ses';

-- channel defaults to 'email', so the provider default follows it.
alter table public.communication_provider_callback_events
  drop constraint communication_provider_callback_events_provider_channel_check,
  add constraint communication_provider_callback_events_provider_channel_check check (
    (channel = 'email' and provider = 'ses') or (channel = 'sms' and provider = 'twilio')
  ),
  alter column provider set default 'ses';

alter table public.communication_inbound_messages
  drop constraint communication_inbound_messages_channel_provider_check,
  add constraint communication_inbound_messages_channel_provider_check check (
    (channel = 'email' and provider = 'ses') or (channel = 'sms' and provider = 'twilio')
  ),
  alter column provider set default 'ses';

alter table public.communication_inbound_attachments
  drop constraint communication_inbound_attachments_provider_check,
  add constraint communication_inbound_attachments_provider_check check (provider in ('ses', 'twilio')),
  alter column provider set default 'ses';

-- 3. Brevo-only columns --------------------------------------------------------------------------------

alter table public.communication_email_domains
  drop constraint communication_email_domains_inbound_webhook_purpose_check,
  drop column provider_inbound_webhook_id;

-- The only function writing provider_sender_id; SES has no per-address sender registration, so its
-- replacement drops that argument.
drop function public.finalize_communication_email_sender_create(uuid, uuid, bigint, uuid, text);

alter table public.communication_email_senders drop column provider_sender_id;

create function public.finalize_communication_email_sender_create(
  target_organization_id uuid,
  target_sender_id uuid,
  actor_user_id uuid,
  command_idempotency_key text
)
returns public.communication_email_senders
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  selected_sender public.communication_email_senders;
begin
  if not exists (
    select 1 from public.communication_email_authority_events
    where organization_id = target_organization_id and target_id = target_sender_id
      and event_type = 'sender.create.started' and idempotency_key = command_idempotency_key
  ) then
    raise exception 'The sender creation claim was not found.' using errcode = 'invalid_parameter_value';
  end if;

  select * into strict selected_sender
  from public.communication_email_senders
  where organization_id = target_organization_id and id = target_sender_id
  for update;

  if selected_sender.lifecycle_state = 'enabled' then
    return selected_sender;
  end if;

  if selected_sender.lifecycle_state <> 'pending_verification' then
    raise exception 'The sender is not awaiting provider creation.' using errcode = 'check_violation';
  end if;

  if selected_sender.is_organization_default then
    update public.communication_email_senders
    set is_organization_default = false
    where organization_id = target_organization_id and id <> target_sender_id
      and lifecycle_state = 'enabled' and is_organization_default;
  end if;

  update public.communication_email_senders
  set lifecycle_state = 'enabled', provider_cleanup_error = null
  where organization_id = target_organization_id and id = target_sender_id
  returning * into selected_sender;

  insert into public.communication_email_authority_events (
    organization_id, actor_kind, actor_user_id, event_type, target_type, target_id,
    after_state, idempotency_key
  ) values (
    target_organization_id, 'contractor_user', actor_user_id, 'sender.create.completed',
    'sender', target_sender_id, to_jsonb(selected_sender), command_idempotency_key || ':complete'
  ) on conflict (organization_id, idempotency_key) do nothing;

  return selected_sender;
end;
$function$;

revoke all on function public.finalize_communication_email_sender_create(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_email_sender_create(uuid, uuid, uuid, text)
  to service_role;

-- The inbound recorder's provider argument now defaults to the only email provider. (CREATE OR REPLACE
-- keeps the existing service_role-only grants.)
create or replace function public.record_communication_inbound_message(
  target_provider_message_id text default null,
  target_in_reply_to_provider_message_id text default null,
  target_provider_callback_event_id uuid default null,
  target_sender_email text default null,
  target_sender_name text default null,
  target_to_recipients jsonb default null,
  target_cc_recipients jsonb default null,
  target_subject text default null,
  target_html_content text default null,
  target_text_content text default null,
  target_message_kind text default null,
  target_candidate_recipients jsonb default null,
  target_provider text default 'ses'
)
returns public.communication_inbound_messages
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  candidate jsonb;
  matched_domain public.communication_email_domains;
  resolved_organization_id uuid;
  resolved_local_part text;
  alias public.communication_reply_aliases;
  contact_method public.client_contact_methods;
  resolved_client_id uuid;
  resolved_contact_method_id uuid;
  resolved_sender_id uuid;
  resolved_reply_alias_id uuid;
  resolved_review_status text;
  resolved_review_reason text;
  resolved_in_reply_to_intent_id uuid;
  resolved_message_kind text := target_message_kind;
  recent_count integer;
  inserted_row public.communication_inbound_messages;
begin
  for candidate in select value from jsonb_array_elements(target_candidate_recipients)
  loop
    select * into matched_domain from public.communication_email_domains
    where purpose = 'receiving' and lifecycle_state in ('verified', 'pending_dns', 'unhealthy')
      and domain_name = lower(candidate ->> 'domain_name')
    limit 1;

    if matched_domain.id is not null then
      resolved_organization_id := matched_domain.organization_id;
      resolved_local_part := lower(candidate ->> 'local_part');
      exit;
    end if;
  end loop;

  if resolved_organization_id is null then
    return null;
  end if;

  select * into alias from public.communication_reply_aliases
  where receiving_domain_id = matched_domain.id and alias_local_part = resolved_local_part;

  if alias.id is null then
    resolved_review_status := 'pending_review';
    resolved_review_reason := 'unknown_sender';
  elsif alias.expires_at < now() then
    resolved_review_status := 'pending_review';
    resolved_review_reason := 'expired_alias';
  else
    select * into contact_method from public.client_contact_methods
    where organization_id = resolved_organization_id
      and client_id = alias.client_id
      and kind = 'email'
      and normalized_value = lower(target_sender_email);

    if contact_method.id is null then
      resolved_review_status := 'pending_review';
      resolved_review_reason := 'ambiguous_sender';
    else
      resolved_review_status := 'accepted';
      resolved_client_id := alias.client_id;
      resolved_contact_method_id := contact_method.id;
      resolved_sender_id := alias.sender_id;
      resolved_reply_alias_id := alias.id;
    end if;
  end if;

  if target_in_reply_to_provider_message_id is not null then
    select id into resolved_in_reply_to_intent_id from public.communication_delivery_intents
    where organization_id = resolved_organization_id
      and provider_message_id = target_in_reply_to_provider_message_id;
  end if;

  select count(*) into recent_count from public.communication_inbound_messages
  where organization_id = resolved_organization_id
    and lower(sender_email) = lower(target_sender_email)
    and subject = target_subject
    and created_at > now() - interval '10 minutes';

  if recent_count >= 3 then
    resolved_message_kind := 'loop_detected';
  end if;

  insert into public.communication_inbound_messages (
    organization_id, reply_alias_id, client_id, client_contact_method_id, sender_id, provider,
    provider_message_id, in_reply_to_provider_message_id, in_reply_to_intent_id,
    sender_email, sender_name, to_recipients, cc_recipients, subject, html_content, text_content,
    message_kind, review_status, review_reason, automation_suppressed, loop_detected_at,
    provider_callback_event_id
  ) values (
    resolved_organization_id, resolved_reply_alias_id, resolved_client_id, resolved_contact_method_id,
    resolved_sender_id, target_provider, target_provider_message_id, target_in_reply_to_provider_message_id,
    resolved_in_reply_to_intent_id, target_sender_email, target_sender_name, target_to_recipients,
    target_cc_recipients, target_subject, target_html_content, target_text_content,
    resolved_message_kind, resolved_review_status, resolved_review_reason,
    (resolved_message_kind <> 'reply') or (resolved_review_status <> 'accepted'),
    case when resolved_message_kind = 'loop_detected' then now() else null end,
    target_provider_callback_event_id
  )
  on conflict (provider, provider_message_id) where provider_message_id is not null do nothing
  returning * into inserted_row;

  if inserted_row.id is null then
    return null;
  end if;

  return inserted_row;
end;
$function$;

-- 4. Remove and purge ----------------------------------------------------------------------------------

-- Remove tears down replies with sending (teardownOperationalDomain), so finalizing it also retires the
-- organization's receiving row. Otherwise the inbound resolver would keep matching reply.<root> to an
-- organization that no longer receives there.
create or replace function public.finalize_communication_email_domain_removal(
  target_organization_id uuid,
  target_domain_id uuid,
  actor_owner_email text,
  removal_reason text,
  command_idempotency_key text
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
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

  update public.communication_email_domains
  set lifecycle_state = 'removed',
      provider_domain_id = null,
      provider_verified = false,
      ownership_status = 'unchecked',
      inbound_mx_status = 'unchecked',
      dns_records = '[]'::jsonb,
      verified_at = null,
      transition_until = null,
      provider_cleanup_error = null,
      updated_at = removed_at
  where organization_id = target_organization_id
    and purpose = 'receiving'
    and lifecycle_state <> 'removed';

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
$function$;

-- The SES tenant, its identities and configuration sets are all found from the organization id, so the
-- receipt stores one anchor per organization that ever had an email domain (a removed row still counts:
-- the tenant can outlive Remove). The closure sweep treats "already gone" as done.
create or replace function public.apply_organization_purge(
  target_organization_id uuid,
  purge_trigger_kind text,
  actor_owner_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
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

  select case
    when exists (
      select 1 from public.communication_email_domains
      where organization_id = target_organization_id
    )
    then jsonb_build_array(
      jsonb_build_object('kind', 'ses_organization', 'provider_id', target_organization_id::text)
    )
    else '[]'::jsonb
  end
  into provider_resources;

  auth_pending := coalesce(array_length(member_user_ids, 1), 0) > 0;
  provider_pending := jsonb_array_length(provider_resources) > 0;

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
$function$;
