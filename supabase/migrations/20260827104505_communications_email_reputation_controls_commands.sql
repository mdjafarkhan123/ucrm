-- Communications Part 7.4 (b): owner commands, resume, and the class-aware claim.

create or replace function public.set_communication_email_reputation_threshold(
  p_scope text,
  p_organization_id uuid,
  p_signal text,
  p_window_key text,
  p_window_hours integer,
  p_warn_rate numeric,
  p_pause_rate numeric,
  p_min_sample_recipients integer,
  p_min_event_count integer,
  p_reason text,
  p_actor_email text,
  p_confirm_platform_change boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  ceiling public.communication_email_reputation_thresholds%rowtype;
  existing public.communication_email_reputation_thresholds%rowtype;
  new_id uuid;
  impact_count integer := 0;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if p_scope not in ('platform', 'organization') then
    raise exception 'The threshold scope is invalid.' using errcode = 'check_violation';
  end if;
  if p_signal not in ('complaint', 'hard_bounce', 'unsubscribe')
    or p_window_key not in ('rolling_24h', 'rolling_7d') then
    raise exception 'The reputation signal or window is invalid.' using errcode = 'check_violation';
  end if;

  select * into ceiling
  from public.communication_email_reputation_thresholds
  where scope = 'platform' and signal = p_signal and window_key = p_window_key and effective_to is null
  for update;
  if not found then
    raise exception 'No platform threshold exists for that signal and window.'
      using errcode = 'foreign_key_violation';
  end if;

  if p_scope = 'platform' then
    if not coalesce(p_confirm_platform_change, false) then
      raise exception 'Changing the platform safety ceiling requires explicit confirmation.'
        using errcode = 'check_violation';
    end if;
    if p_organization_id is not null then
      raise exception 'A platform threshold has no organization.' using errcode = 'check_violation';
    end if;
    if p_window_hours is null or p_warn_rate is null or p_pause_rate is null
      or p_min_sample_recipients is null then
      raise exception 'A platform threshold needs a window, both rates, and a sample size.'
        using errcode = 'check_violation';
    end if;

    select count(*)::integer into impact_count
    from public.communication_email_reputation_thresholds org
    where org.scope = 'organization' and org.signal = p_signal
      and org.window_key = p_window_key and org.effective_to is null;

    update public.communication_email_reputation_thresholds
    set effective_to = now() where id = ceiling.id;

    insert into public.communication_email_reputation_thresholds (
      scope, signal, window_key, window_hours, warn_rate, pause_rate, min_sample_recipients,
      min_event_count, reason, actor_owner_email
    ) values (
      'platform', p_signal, p_window_key, p_window_hours, p_warn_rate, p_pause_rate,
      p_min_sample_recipients, p_min_event_count, clean_reason, actor
    )
    returning id into new_id;

    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
      actor, 'communications.email_reputation_platform_threshold_changed',
      'communication_email_reputation_threshold', new_id::text,
      to_jsonb(ceiling) - 'id',
      jsonb_build_object('signal', p_signal, 'window_key', p_window_key, 'window_hours', p_window_hours,
        'warn_rate', p_warn_rate, 'pause_rate', p_pause_rate,
        'min_sample_recipients', p_min_sample_recipients, 'min_event_count', p_min_event_count,
        'reason', clean_reason, 'organization_overrides_affected', impact_count)
    );

    return jsonb_build_object('id', new_id, 'scope', 'platform',
      'organization_overrides_affected', impact_count);
  end if;

  if p_organization_id is null then
    raise exception 'An organization is required for an organization threshold.'
      using errcode = 'check_violation';
  end if;
  if p_window_hours is not null then
    raise exception 'Observation windows are set at the platform level only.'
      using errcode = 'check_violation';
  end if;
  perform 1 from public.organizations where id = p_organization_id;
  if not found then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  select * into existing
  from public.communication_email_reputation_thresholds
  where scope = 'organization' and organization_id = p_organization_id
    and signal = p_signal and window_key = p_window_key and effective_to is null
  for update;

  if num_nonnulls(p_warn_rate, p_pause_rate, p_min_sample_recipients, p_min_event_count) = 0 then
    if not found then
      return jsonb_build_object('id', null, 'scope', 'organization', 'cleared', true);
    end if;
    update public.communication_email_reputation_thresholds
    set effective_to = now() where id = existing.id;
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
      actor, 'communications.email_reputation_organization_threshold_cleared', 'organization',
      p_organization_id::text, to_jsonb(existing) - 'id',
      jsonb_build_object('reason', clean_reason)
    );
    return jsonb_build_object('id', existing.id, 'scope', 'organization', 'cleared', true);
  end if;

  if p_warn_rate is not null and p_warn_rate > ceiling.warn_rate then
    raise exception 'An organization warning rate cannot exceed the platform ceiling of %.',
      ceiling.warn_rate using errcode = 'check_violation';
  end if;
  if p_pause_rate is not null and p_pause_rate > ceiling.pause_rate then
    raise exception 'An organization pause rate cannot exceed the platform ceiling of %.',
      ceiling.pause_rate using errcode = 'check_violation';
  end if;
  if p_min_sample_recipients is not null and p_min_sample_recipients > ceiling.min_sample_recipients then
    raise exception 'An organization sample size cannot exceed the platform ceiling of %.',
      ceiling.min_sample_recipients using errcode = 'check_violation';
  end if;
  if p_min_event_count is not null and ceiling.min_event_count is not null
    and p_min_event_count > ceiling.min_event_count then
    raise exception 'An organization event trigger cannot exceed the platform ceiling of %.',
      ceiling.min_event_count using errcode = 'check_violation';
  end if;
  if p_warn_rate is not null and p_pause_rate is not null and p_warn_rate > p_pause_rate then
    raise exception 'The warning rate must be at or below the pause rate.'
      using errcode = 'check_violation';
  end if;

  if found then
    update public.communication_email_reputation_thresholds
    set effective_to = now() where id = existing.id;
  end if;

  insert into public.communication_email_reputation_thresholds (
    scope, organization_id, signal, window_key, warn_rate, pause_rate, min_sample_recipients,
    min_event_count, reason, actor_owner_email
  ) values (
    'organization', p_organization_id, p_signal, p_window_key, p_warn_rate, p_pause_rate,
    p_min_sample_recipients, p_min_event_count, clean_reason, actor
  )
  returning id into new_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_reputation_organization_threshold_changed', 'organization',
    p_organization_id::text,
    case when existing.id is not null then to_jsonb(existing) - 'id' end,
    jsonb_build_object('threshold_id', new_id, 'signal', p_signal, 'window_key', p_window_key,
      'warn_rate', p_warn_rate, 'pause_rate', p_pause_rate,
      'min_sample_recipients', p_min_sample_recipients, 'min_event_count', p_min_event_count,
      'reason', clean_reason)
  );

  return jsonb_build_object('id', new_id, 'scope', 'organization', 'cleared', false);
end;
$$;

revoke all on function public.set_communication_email_reputation_threshold(
  text, uuid, text, text, integer, numeric, numeric, integer, integer, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.set_communication_email_reputation_threshold(
  text, uuid, text, text, integer, numeric, numeric, integer, integer, text, text, boolean
) to service_role;

create or replace function public.resume_communication_email_reputation_pause(
  p_organization_id uuid,
  p_reason text,
  p_actor_email text,
  p_confirm_remediation boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  existing public.communication_email_sending_pauses%rowtype;
  still_breaching boolean;
  expired_count integer := 0;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;

  select * into existing
  from public.communication_email_sending_pauses
  where scope = 'organization' and organization_id = p_organization_id
    and source = 'auto_reputation' and released_at is null
  for update;
  if not found then
    return jsonb_build_object('released', false, 'reason_code', 'no_active_reputation_pause');
  end if;

  select exists (
    select 1 from private.communication_email_reputation_metrics(p_organization_id, now()) m
    where m.status = 'pause'
  ) into still_breaching;

  if still_breaching and not coalesce(p_confirm_remediation, false) then
    raise exception 'This organization is still at or above a pause threshold. Confirm remediation review to resume.'
      using errcode = 'check_violation';
  end if;

  update public.communication_email_sending_pauses
  set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
  where id = existing.id;

  with stale as (
    select event.id as event_id, intent.id as intent_id
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.status in ('pending', 'failed')
      and intent.organization_id = p_organization_id
      and intent.allowance_class = 'optional'
      and intent.failure_code = 'sending_paused_reputation'
      and intent.created_at < now() - interval '24 hours'
  ),
  cancelled_intents as (
    update public.communication_delivery_intents intent
    set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = 'optional_expired_during_pause',
      failure_message = 'Optional email expired while sending was paused and was not delivered.'
    from stale
    where intent.id = stale.intent_id
    returning intent.id
  ),
  cancelled_events as (
    update public.communication_outbox_events event
    set status = 'cancelled', claimed_at = null, claim_token = null,
      last_error = 'Optional email expired while sending was paused and was not delivered.'
    from stale
    where event.id = stale.event_id
    returning event.id
  )
  select count(*)::integer into expired_count from cancelled_events;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_reputation_pause_released', 'organization', p_organization_id::text,
    jsonb_build_object('pause_id', existing.id, 'engaged_reason', existing.reason,
      'evidence', existing.evidence),
    jsonb_build_object('released_reason', clean_reason, 'still_breaching', still_breaching,
      'remediation_confirmed', coalesce(p_confirm_remediation, false),
      'expired_optional_messages', expired_count)
  );

  return jsonb_build_object('released', true, 'pause_id', existing.id,
    'still_breaching', still_breaching, 'expired_optional_messages', expired_count);
end;
$$;

revoke all on function public.resume_communication_email_reputation_pause(uuid, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.resume_communication_email_reputation_pause(uuid, text, text, boolean)
  to service_role;

create or replace function public.set_communication_email_organization_pause(
  p_organization_id uuid,
  p_engage boolean,
  p_reason text,
  p_actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  existing public.communication_email_sending_pauses%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organizations where id = p_organization_id;
  if not found then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  select * into existing
  from public.communication_email_sending_pauses
  where scope = 'organization' and organization_id = p_organization_id
    and source = 'manual' and released_at is null
  order by engaged_at desc
  for update;

  if p_engage then
    if found then
      return existing.id;
    end if;
    insert into public.communication_email_sending_pauses (
      scope, organization_id, reason, engaged_by_owner_email, source, applies_to
    )
    values ('organization', p_organization_id, clean_reason, actor, 'manual', 'all')
    returning id into new_id;
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, after_state
    ) values (
      actor, 'communications.email_organization_pause_engaged', 'organization',
      p_organization_id::text, jsonb_build_object('pause_id', new_id, 'reason', clean_reason)
    );
    return new_id;
  end if;

  if not found then
    return null;
  end if;
  update public.communication_email_sending_pauses
  set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
  where id = existing.id;
  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_organization_pause_released', 'organization',
    p_organization_id::text,
    jsonb_build_object('pause_id', existing.id, 'engaged_reason', existing.reason,
      'engaged_by', existing.engaged_by_owner_email),
    jsonb_build_object('released_reason', clean_reason)
  );
  return existing.id;
end;
$$;

revoke all on function public.set_communication_email_organization_pause(uuid, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_organization_pause(uuid, boolean, text, text)
  to service_role;

create or replace function public.get_communication_email_sending_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'platform_pause', (
      select jsonb_build_object(
        'id', p.id, 'reason', p.reason,
        'engaged_by', p.engaged_by_owner_email, 'engaged_at', p.engaged_at
      )
      from public.communication_email_sending_pauses p
      where p.scope = 'platform' and p.released_at is null
      order by p.engaged_at desc
      limit 1
    ),
    'organization_pauses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'organization_id', p.organization_id, 'organization_name', o.name,
        'reason', p.reason, 'engaged_by', p.engaged_by_owner_email, 'engaged_at', p.engaged_at,
        'source', p.source, 'applies_to', p.applies_to, 'evidence', p.evidence
      ) order by p.engaged_at desc)
      from public.communication_email_sending_pauses p
      join public.organizations o on o.id = p.organization_id
      where p.scope = 'organization' and p.released_at is null
    ), '[]'::jsonb),
    'held_email_count', (
      select count(*)
      from public.communication_outbox_events e
      join public.communication_delivery_intents i on i.id = e.delivery_intent_id
      where e.status in ('pending', 'failed')
        and i.failure_code in ('sending_paused_platform', 'sending_paused_organization',
          'sending_paused_reputation')
    ),
    'queued_email_count', (
      select count(*)
      from public.communication_outbox_events e
      where e.status in ('pending', 'failed')
    )
  );
$$;

revoke all on function public.get_communication_email_sending_health() from public, anon, authenticated;
grant execute on function public.get_communication_email_sending_health() to service_role;

create or replace function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid, delivery_intent_id uuid, claim_token uuid, recipient_email text, subject text,
  html_content text, text_content text, logical_send_key text, sender_id uuid, sender_email text,
  sender_name text, reply_to_email text, reply_to_name text
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  active_allowance record;
  allowance_limit_state text;
  allowance_limit_value integer;
  accepted_recipient_count integer;
  reserved_recipient_count integer;
  new_claim_token uuid;
  alias public.communication_reply_aliases;
  alias_domain public.communication_email_domains;
  holding_pause public.communication_email_sending_pauses%rowtype;
  hold_code text;
  hold_message text;
begin
  if exists (
    select 1 from public.communication_email_sending_pauses
    where scope = 'platform' and released_at is null
  ) then
    return;
  end if;

  for candidate in
    select
      event.id as event_id,
      event.delivery_intent_id,
      intent.organization_id,
      intent.client_id,
      intent.client_contact_method_id,
      intent.recipient_email,
      intent.subject,
      intent.html_content,
      intent.text_content,
      intent.logical_send_key,
      intent.send_kind,
      intent.allowance_class,
      intent.sender_id,
      intent.reply_alias_id,
      intent.created_by
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    current_recipient := null;
    select method.* into current_recipient
    from public.client_contact_methods method
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
    for share;

    if current_recipient.id is null
      or current_recipient.client_id <> candidate.client_id
      or current_recipient.kind <> 'email'
      or current_recipient.normalized_value <> candidate.recipient_email then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    if exists (
      select 1
      from public.communication_email_suppressions suppression
      where suppression.organization_id = candidate.organization_id
        and suppression.recipient_email = candidate.recipient_email
        and suppression.released_at is null
        and (
          suppression.reason = 'hard_bounce'
          or (suppression.reason = 'complaint' and candidate.allowance_class = 'optional')
        )
    ) then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_suppressed',
        failure_message = 'This recipient address is on the organization suppression list.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This recipient address is on the organization suppression list.'
      where id = candidate.event_id;
      continue;
    end if;

    holding_pause := null;
    select pause.* into holding_pause
    from public.communication_email_sending_pauses pause
    where pause.scope = 'organization'
      and pause.organization_id = candidate.organization_id
      and pause.released_at is null
      and (pause.applies_to = 'all' or candidate.allowance_class = 'optional')
    order by case when pause.applies_to = 'all' then 0 else 1 end
    limit 1;

    if holding_pause.id is not null then
      if holding_pause.source = 'auto_reputation' then
        hold_code := 'sending_paused_reputation';
        hold_message := 'Optional email is paused while this organization''s delivery reputation is reviewed.';
      else
        hold_code := 'sending_paused_organization';
        hold_message := 'Sending for this organization is paused. UCRM will retry when it resumes.';
      end if;
      update public.communication_delivery_intents
      set failure_code = hold_code, failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '5 minutes', last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    selected_sender := null;
    if candidate.sender_id is not null then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
      for share;
    elsif candidate.send_kind = 'automated' then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id
        and sender.is_organization_default and sender.lifecycle_state <> 'removed'
      order by sender.created_at, sender.id limit 1 for share;
    end if;

    if selected_sender.id is null then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status from public.organization_members member
      where member.organization_id = selected_sender.organization_id and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;
    sender_domain := null;
    select domain.* into sender_domain from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.lifecycle_state = 'pending_verification'
      or (sender_domain.id is not null and sender_domain.lifecycle_state not in ('removal_pending', 'removed')
        and (sender_domain.lifecycle_state <> 'verified' or not sender_domain.provider_verified
          or not sender_domain.provider_authenticated or sender_domain.ownership_status <> 'passing'
          or sender_domain.dkim_status <> 'passing')) then
      update public.communication_delivery_intents set failure_code = 'sender_domain_temporarily_unavailable',
        failure_message = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if selected_sender.lifecycle_state <> 'enabled'
      or (candidate.send_kind = 'manual' and not selected_sender.allows_manual)
      or (candidate.send_kind = 'automated' and not selected_sender.allows_automated)
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state in ('removal_pending', 'removed') then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    select * into active_allowance
    from private.resolve_communication_email_allowance(candidate.organization_id, now());
    if not found then
      update public.communication_delivery_intents set failure_code = 'email_allowance_period_unavailable',
        failure_message = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if candidate.allowance_class = 'optional' then
      allowance_limit_state := active_allowance.operational_limit_state;
      allowance_limit_value := active_allowance.operational_limit_value;
    else
      allowance_limit_state := active_allowance.essential_limit_state;
      allowance_limit_value := active_allowance.essential_limit_value;
    end if;
    if allowance_limit_state not in ('numeric', 'unlimited')
      or (allowance_limit_state = 'numeric' and allowance_limit_value is null) then
      update public.communication_delivery_intents set failure_code = 'email_allowance_unavailable',
        failure_message = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    insert into public.communication_email_capacity_buckets (
      organization_id, allowance_period_id, allowance_class
    ) values (candidate.organization_id, active_allowance.period_id, candidate.allowance_class)
    on conflict do nothing;
    perform 1 from public.communication_email_capacity_buckets bucket
    where bucket.organization_id = candidate.organization_id
      and bucket.allowance_period_id = active_allowance.period_id
      and bucket.allowance_class = candidate.allowance_class
    for update;

    if allowance_limit_state = 'numeric' then
      select coalesce(sum(usage.recipient_count), 0)::integer into accepted_recipient_count
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.allowance_period_id = active_allowance.period_id
        and usage.allowance_class = candidate.allowance_class;
      select coalesce(sum(reservation.recipient_count), 0)::integer into reserved_recipient_count
      from public.communication_email_capacity_reservations reservation
      where reservation.organization_id = candidate.organization_id
        and reservation.allowance_period_id = active_allowance.period_id
        and reservation.allowance_class = candidate.allowance_class
        and reservation.reservation_state in ('reserved', 'submission_unknown');
      if accepted_recipient_count + reserved_recipient_count >= allowance_limit_value then
        update public.communication_delivery_intents set failure_code = 'email_allowance_exhausted',
          failure_message = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set available_at = now() + interval '15 minutes',
          last_error = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    insert into public.communication_email_capacity_reservations (
      organization_id, delivery_intent_id, allowance_period_id, allowance_class, reservation_state, reserved_at, settled_at
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, active_allowance.period_id,
      candidate.allowance_class, 'reserved', now(), null
    ) on conflict on constraint communication_email_capacity_reservations_delivery_intent_key do update set
      organization_id = excluded.organization_id,
      allowance_period_id = excluded.allowance_period_id,
      allowance_class = excluded.allowance_class,
      reservation_state = 'reserved', reserved_at = now(), settled_at = null
    where public.communication_email_capacity_reservations.reservation_state = 'released';
    if not found then
      raise exception 'The email capacity reservation is not available for this delivery intent.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;

    alias := null;
    alias_domain := null;
    if candidate.reply_alias_id is not null then
      select rep_alias.* into alias from public.communication_reply_aliases rep_alias
      where rep_alias.id = candidate.reply_alias_id and rep_alias.organization_id = candidate.organization_id
      for share;
      if alias.id is not null then
        select * into alias_domain from public.communication_email_domains
        where id = alias.receiving_domain_id and organization_id = candidate.organization_id
        for share;
      end if;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name,
      case when alias.id is not null and alias_domain.id is not null
        then alias.alias_local_part || '@' || alias_domain.domain_name else null end,
      case when alias.id is not null then selected_sender.display_name else null end;
    return;
  end loop;
end;
$function$;

revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;
