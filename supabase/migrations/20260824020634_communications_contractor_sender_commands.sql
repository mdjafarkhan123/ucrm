-- Communications Part 2, slice B: atomic contractor sender command boundaries.
-- Provider calls happen between begin/finalize calls and never inside a database transaction.

create or replace function public.begin_communication_email_sender_create(
  target_organization_id uuid,
  target_domain_id uuid,
  target_email_address text,
  target_display_name text,
  target_assigned_user_id uuid,
  target_is_organization_default boolean,
  target_allows_manual boolean,
  target_allows_automated boolean,
  actor_user_id uuid,
  command_idempotency_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  selected_domain public.communication_email_domains;
  selected_sender public.communication_email_senders;
  existing_event public.communication_email_authority_events;
  desired_state jsonb;
begin
  if command_idempotency_key is null or char_length(btrim(command_idempotency_key)) not between 1 and 180 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;

  target_email_address := lower(btrim(target_email_address));
  target_display_name := btrim(target_display_name);
  desired_state := jsonb_build_object(
    'domain_id', target_domain_id,
    'email_address', target_email_address,
    'display_name', target_display_name,
    'assigned_user_id', target_assigned_user_id,
    'is_organization_default', target_is_organization_default,
    'allows_manual', target_allows_manual,
    'allows_automated', target_allows_automated
  );

  select * into existing_event
  from public.communication_email_authority_events
  where organization_id = target_organization_id
    and idempotency_key = command_idempotency_key;

  if found then
    if existing_event.event_type <> 'sender.create.started'
      or existing_event.after_state is distinct from desired_state then
      raise exception 'The idempotency key was already used for another command.'
        using errcode = 'unique_violation';
    end if;

    select * into strict selected_sender
    from public.communication_email_senders
    where organization_id = target_organization_id and id = existing_event.target_id;

    return jsonb_build_object('replayed', true, 'sender', to_jsonb(selected_sender));
  end if;

  select * into selected_domain
  from public.communication_email_domains
  where organization_id = target_organization_id and id = target_domain_id
  for update;

  if not found or selected_domain.purpose <> 'sending'
    or selected_domain.lifecycle_state <> 'verified'
    or not selected_domain.provider_verified
    or not selected_domain.provider_authenticated
    or selected_domain.ownership_status <> 'passing'
    or selected_domain.dkim_status <> 'passing'
    or selected_domain.spf_status <> 'passing' then
    raise exception 'A verified healthy sending domain is required.' using errcode = 'check_violation';
  end if;

  if split_part(target_email_address, '@', 2) <> selected_domain.domain_name then
    raise exception 'The sender address must use the selected sending domain.' using errcode = 'check_violation';
  end if;

  if not target_allows_manual and not target_allows_automated then
    raise exception 'An enabled sender must allow manual or automated email.' using errcode = 'check_violation';
  end if;

  if target_assigned_user_id is not null and not exists (
    select 1 from public.organization_members
    where organization_id = target_organization_id
      and user_id = target_assigned_user_id and status = 'active'
  ) then
    raise exception 'The assigned sender member must be active.' using errcode = 'check_violation';
  end if;

  if target_is_organization_default then
    perform 1 from public.communication_email_senders
    where organization_id = target_organization_id
      and lifecycle_state = 'enabled' and is_organization_default
    for update;
  end if;

  insert into public.communication_email_senders (
    organization_id, domain_id, email_address, display_name, lifecycle_state,
    assigned_user_id, is_organization_default, allows_manual, allows_automated, created_by
  ) values (
    target_organization_id, target_domain_id, target_email_address, target_display_name,
    'pending_verification', target_assigned_user_id, target_is_organization_default,
    target_allows_manual, target_allows_automated, actor_user_id
  ) returning * into selected_sender;

  insert into public.communication_email_authority_events (
    organization_id, actor_kind, actor_user_id, event_type, target_type, target_id,
    after_state, idempotency_key
  ) values (
    target_organization_id, 'contractor_user', actor_user_id, 'sender.create.started',
    'sender', selected_sender.id, desired_state, command_idempotency_key
  );

  return jsonb_build_object('replayed', false, 'sender', to_jsonb(selected_sender));
end;
$$;

create or replace function public.finalize_communication_email_sender_create(
  target_organization_id uuid,
  target_sender_id uuid,
  provider_sender_id bigint,
  actor_user_id uuid,
  command_idempotency_key text
)
returns public.communication_email_senders
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
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
    if selected_sender.provider_sender_id is distinct from provider_sender_id then
      raise exception 'The provider sender outcome conflicts with the stored receipt.'
        using errcode = 'unique_violation';
    end if;
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
  set provider_sender_id = finalize_communication_email_sender_create.provider_sender_id,
      lifecycle_state = 'enabled', provider_cleanup_error = null
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
$$;

create or replace function public.begin_communication_email_sender_update(
  target_organization_id uuid,
  target_sender_id uuid,
  target_display_name text,
  target_assigned_user_id uuid,
  target_is_organization_default boolean,
  target_allows_manual boolean,
  target_allows_automated boolean,
  target_enabled boolean,
  actor_user_id uuid,
  command_idempotency_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  selected_sender public.communication_email_senders;
  selected_domain public.communication_email_domains;
  existing_event public.communication_email_authority_events;
  desired_state jsonb;
begin
  if command_idempotency_key is null or char_length(btrim(command_idempotency_key)) not between 1 and 180 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;

  target_display_name := btrim(target_display_name);
  desired_state := jsonb_build_object(
    'display_name', target_display_name,
    'assigned_user_id', target_assigned_user_id,
    'is_organization_default', target_is_organization_default,
    'allows_manual', target_allows_manual,
    'allows_automated', target_allows_automated,
    'enabled', target_enabled
  );

  select * into existing_event from public.communication_email_authority_events
  where organization_id = target_organization_id and idempotency_key = command_idempotency_key;
  if found then
    if existing_event.event_type <> 'sender.update.started'
      or existing_event.target_id <> target_sender_id
      or existing_event.after_state is distinct from desired_state then
      raise exception 'The idempotency key was already used for another command.'
        using errcode = 'unique_violation';
    end if;
    select * into strict selected_sender
    from public.communication_email_senders
    where organization_id = target_organization_id and id = target_sender_id;
    return jsonb_build_object('replayed', true, 'sender', to_jsonb(selected_sender));
  end if;

  select * into strict selected_sender from public.communication_email_senders
  where organization_id = target_organization_id and id = target_sender_id
  for update;

  if selected_sender.lifecycle_state in ('removal_pending', 'removed') then
    raise exception 'The sender can no longer be changed.' using errcode = 'check_violation';
  end if;

  if target_enabled then
    select * into strict selected_domain from public.communication_email_domains
    where organization_id = target_organization_id and id = selected_sender.domain_id
    for update;
    if selected_domain.lifecycle_state <> 'verified' or not selected_domain.provider_verified
      or not selected_domain.provider_authenticated or selected_domain.ownership_status <> 'passing'
      or selected_domain.dkim_status <> 'passing' or selected_domain.spf_status <> 'passing' then
      raise exception 'A verified healthy sending domain is required.' using errcode = 'check_violation';
    end if;
    if not target_allows_manual and not target_allows_automated then
      raise exception 'An enabled sender must allow manual or automated email.' using errcode = 'check_violation';
    end if;
    if target_assigned_user_id is not null and not exists (
      select 1 from public.organization_members
      where organization_id = target_organization_id
        and user_id = target_assigned_user_id and status = 'active'
    ) then
      raise exception 'The assigned sender member must be active.' using errcode = 'check_violation';
    end if;
  end if;

  insert into public.communication_email_authority_events (
    organization_id, actor_kind, actor_user_id, event_type, target_type, target_id,
    before_state, after_state, idempotency_key
  ) values (
    target_organization_id, 'contractor_user', actor_user_id, 'sender.update.started', 'sender',
    target_sender_id, to_jsonb(selected_sender), desired_state, command_idempotency_key
  );

  return jsonb_build_object('replayed', false, 'sender', to_jsonb(selected_sender));
end;
$$;

create or replace function public.finalize_communication_email_sender_update(
  target_organization_id uuid,
  target_sender_id uuid,
  actor_user_id uuid,
  command_idempotency_key text
)
returns public.communication_email_senders
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  selected_sender public.communication_email_senders;
  desired_state jsonb;
begin
  select after_state into strict desired_state
  from public.communication_email_authority_events
  where organization_id = target_organization_id and target_id = target_sender_id
    and event_type = 'sender.update.started' and idempotency_key = command_idempotency_key;

  select * into strict selected_sender from public.communication_email_senders
  where organization_id = target_organization_id and id = target_sender_id
  for update;

  if exists (
    select 1 from public.communication_email_authority_events
    where organization_id = target_organization_id and target_id = target_sender_id
      and event_type = 'sender.update.completed'
      and idempotency_key = command_idempotency_key || ':complete'
  ) then
    return selected_sender;
  end if;

  if (desired_state ->> 'is_organization_default')::boolean
    and (desired_state ->> 'enabled')::boolean then
    update public.communication_email_senders
    set is_organization_default = false
    where organization_id = target_organization_id and id <> target_sender_id
      and lifecycle_state = 'enabled' and is_organization_default;
  end if;

  update public.communication_email_senders
  set display_name = desired_state ->> 'display_name',
      assigned_user_id = nullif(desired_state ->> 'assigned_user_id', '')::uuid,
      is_organization_default = (desired_state ->> 'is_organization_default')::boolean,
      allows_manual = (desired_state ->> 'allows_manual')::boolean,
      allows_automated = (desired_state ->> 'allows_automated')::boolean,
      lifecycle_state = case when (desired_state ->> 'enabled')::boolean then 'enabled' else 'disabled' end
  where organization_id = target_organization_id and id = target_sender_id
  returning * into selected_sender;

  insert into public.communication_email_authority_events (
    organization_id, actor_kind, actor_user_id, event_type, target_type, target_id,
    after_state, idempotency_key
  ) values (
    target_organization_id, 'contractor_user', actor_user_id, 'sender.update.completed', 'sender',
    target_sender_id, to_jsonb(selected_sender), command_idempotency_key || ':complete'
  );

  return selected_sender;
end;
$$;

revoke all on function public.begin_communication_email_sender_create(
  uuid, uuid, text, text, uuid, boolean, boolean, boolean, uuid, text
) from public, anon, authenticated;
revoke all on function public.finalize_communication_email_sender_create(
  uuid, uuid, bigint, uuid, text
) from public, anon, authenticated;
revoke all on function public.begin_communication_email_sender_update(
  uuid, uuid, text, uuid, boolean, boolean, boolean, boolean, uuid, text
) from public, anon, authenticated;
revoke all on function public.finalize_communication_email_sender_update(
  uuid, uuid, uuid, text
) from public, anon, authenticated;

grant execute on function public.begin_communication_email_sender_create(
  uuid, uuid, text, text, uuid, boolean, boolean, boolean, uuid, text
) to service_role;
grant execute on function public.finalize_communication_email_sender_create(
  uuid, uuid, bigint, uuid, text
) to service_role;
grant execute on function public.begin_communication_email_sender_update(
  uuid, uuid, text, uuid, boolean, boolean, boolean, boolean, uuid, text
) to service_role;
grant execute on function public.finalize_communication_email_sender_update(
  uuid, uuid, uuid, text
) to service_role;
