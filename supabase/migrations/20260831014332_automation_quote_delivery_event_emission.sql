-- Automation Part 6D-1: emit the first real domain event, and make the activation cutoff race-proof.
--
-- Both functions below are CREATE OR REPLACE'd from their LIVE definitions (pg_get_functiondef). The only
-- changes are marked with "6D-1"; everything else is byte-for-byte the behavior already in production.

-- ---------------------------------------------------------------------------------------------------
-- 1. Activation records a commit-visibility snapshot, not a clock and not a bare max(seq).
-- ---------------------------------------------------------------------------------------------------
create or replace function public.activate_automation_recipe_version(
  p_organization_id uuid, p_actor_user_id uuid, p_recipe_id uuid, p_expected_revision integer,
  p_schema_version integer, p_definition jsonb, p_definition_hash text, p_trigger_key text,
  p_active_limit integer, p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  existing_receipt public.automation_draft_command_receipts%rowtype;
  recipe public.automation_recipes%rowtype;
  active_count integer;
  next_version_number integer;
  new_version_id uuid;
  next_revision integer;
  command_result jsonb;
  cutoff_sequence bigint;   -- 6D-1
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'An expected revision is required.' using errcode = 'check_violation';
  end if;
  if p_definition is null or jsonb_typeof(p_definition) <> 'object' then
    raise exception 'A recipe definition is required.' using errcode = 'check_violation';
  end if;
  if p_trigger_key is null or char_length(btrim(p_trigger_key)) = 0 then
    raise exception 'A trigger is required to activate.' using errcode = 'check_violation';
  end if;
  if p_definition_hash is null or char_length(btrim(p_definition_hash)) = 0 then
    raise exception 'A definition hash is required.' using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('automation-recipe:' || p_recipe_id::text));

  select * into existing_receipt
  from public.automation_draft_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into recipe
  from public.automation_recipes
  where id = p_recipe_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That automation does not exist.' using errcode = 'no_data_found';
  end if;
  if recipe.status = 'archived' then
    raise exception 'An archived automation is read-only.' using errcode = 'restrict_violation';
  end if;
  if recipe.status not in ('draft', 'active', 'paused') then
    raise exception 'This automation cannot be activated right now.' using errcode = 'restrict_violation';
  end if;

  if recipe.draft_revision <> p_expected_revision then
    return jsonb_build_object(
      'stale', true,
      'current_revision', recipe.draft_revision,
      'draft_updated_at', recipe.draft_updated_at,
      'draft_updated_by', recipe.draft_updated_by
    );
  end if;
  if recipe.draft_definition is null then
    raise exception 'This automation has no draft to activate.' using errcode = 'check_violation';
  end if;

  if p_active_limit is not null and recipe.status <> 'active' then
    select count(*) into active_count
    from public.automation_recipes
    where organization_id = p_organization_id and status = 'active';
    if active_count >= p_active_limit then
      raise exception
        'Activating this automation would pass your plan limit of % active automations. Pause or archive another one first.',
        p_active_limit
        using errcode = 'restrict_violation';
    end if;
  end if;

  select coalesce(max(version_number), 0) + 1 into next_version_number
  from public.automation_recipe_versions
  where recipe_id = p_recipe_id;

  -- 6D-1: the readable marker. Only a marker -- the snapshot below decides eligibility.
  select coalesce(max(seq), 0) into cutoff_sequence from private.automation_events;

  insert into public.automation_recipe_versions (
    recipe_id, organization_id, version_number, schema_version,
    definition, definition_hash, trigger_key, activation_cutoff_sequence,
    activation_cutoff_snapshot, activated_by                              -- 6D-1
  ) values (
    p_recipe_id, p_organization_id, next_version_number, p_schema_version,
    p_definition, p_definition_hash, p_trigger_key, cutoff_sequence,
    pg_current_snapshot(), p_actor_user_id                                -- 6D-1
  ) returning id into new_version_id;

  next_revision := recipe.draft_revision + 1;

  update public.automation_recipes
  set status = 'active',
      current_version_id = new_version_id,
      active_trigger_key = p_trigger_key,
      draft_definition = p_definition,
      draft_revision = next_revision
  where id = p_recipe_id and organization_id = p_organization_id;

  command_result := jsonb_build_object(
    'recipe_id', p_recipe_id,
    'status', 'active',
    'version_id', new_version_id,
    'version_number', next_version_number,
    'draft_revision', next_revision,
    'stale', false
  );

  insert into public.automation_draft_command_receipts (
    organization_id, idempotency_key, command, recipe_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'activate', p_recipe_id, command_result
  );

  return command_result;
end;
$function$;

-- ---------------------------------------------------------------------------------------------------
-- 2. Delivery truth emits the event, in the same transaction, for free.
-- ---------------------------------------------------------------------------------------------------
-- The event is written only when THIS callback actually set the outcome to delivered (the guarded UPDATE
-- returns nothing for a message already terminally bounced, so a stray late 'delivered' cannot un-bounce a
-- message or start a follow-up), and only when the intent carries full send-time quote identity. Intents
-- queued before that identity existed simply produce no event -- silence beats inventing which version was
-- sent. Duplicate and differently-keyed provider callbacks all resolve to the same delivery intent id, so
-- they collapse on the event's source unique key.
create or replace function public.process_communication_provider_callbacks(batch_size integer default 500)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  candidate record;
  norm text;
  processed_count integer := 0;
  max_processing_attempts constant integer := 5;
  applied_outcome text;   -- 6D-1
begin
  if batch_size < 1 or batch_size > 2000 then
    raise exception 'The callback batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select
      cb.id,
      cb.event_kind,
      cb.occurred_at,
      cb.received_at,
      cb.processing_attempts,
      cb.delivery_intent_id,
      intent.organization_id,
      intent.recipient_email,
      intent.delivery_outcome as current_outcome,
      -- 6D-1: send-time identity, read once with the row we already have.
      intent.quote_id,
      intent.quote_version_id,
      intent.quote_recipient_id,
      intent.client_id,
      intent.client_contact_method_id
    from public.communication_provider_callback_events cb
    left join public.communication_delivery_intents intent on intent.id = cb.delivery_intent_id
    where cb.processed_at is null
    order by cb.received_at, cb.id
    limit batch_size
    for update of cb skip locked
  loop
    norm := case lower(trim(candidate.event_kind))
      when 'delivered' then 'delivered'
      when 'soft_bounce' then 'soft_bounce'
      when 'hard_bounce' then 'hard_bounce'
      when 'invalid_email' then 'hard_bounce'
      when 'blocked' then 'blocked'
      when 'spam' then 'complaint'
      when 'complaint' then 'complaint'
      when 'deferred' then 'deferred'
      when 'unsubscribed' then 'unsubscribed'
      when 'list_addition' then 'other'
      when 'opened' then 'opened'
      when 'unique_opened' then 'opened'
      when 'click' then 'clicked'
      when 'proxy_open' then 'opened'
      else 'other'
    end;
    applied_outcome := null;   -- 6D-1

    begin
      if candidate.delivery_intent_id is null or candidate.organization_id is null then
        update public.communication_provider_callback_events
        set processed_at = now(), normalized_kind = norm
        where id = candidate.id;
        processed_count := processed_count + 1;
        continue;
      end if;

      if norm in ('delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked', 'unsubscribed') then
        update public.communication_delivery_intents
        set delivery_outcome = norm,
          delivery_outcome_at = coalesce(candidate.occurred_at, candidate.received_at),
          delivery_outcome_detail = nullif(trim(candidate.event_kind), '')
        where id = candidate.delivery_intent_id
          and (
            delivery_outcome is null
            or delivery_outcome not in ('hard_bounce', 'complaint')
            or norm in ('hard_bounce', 'complaint')
          )
        returning delivery_outcome into applied_outcome;   -- 6D-1
      end if;

      -- 6D-1: a confirmed delivery of an identified quote email is an Automation trigger fact.
      if applied_outcome = 'delivered'
        and candidate.quote_id is not null
        and candidate.quote_version_id is not null then
        perform private.emit_automation_event(
          candidate.organization_id,
          'quote.delivery_succeeded',
          'quote',
          candidate.quote_id,
          jsonb_build_object(
            'delivery_intent_id', candidate.delivery_intent_id,
            'quote_id', candidate.quote_id,
            'quote_version_id', candidate.quote_version_id,
            'quote_recipient_id', candidate.quote_recipient_id,
            'client_id', candidate.client_id,
            'client_contact_method_id', candidate.client_contact_method_id
          ),
          coalesce(candidate.occurred_at, candidate.received_at),
          'communications',
          candidate.delivery_intent_id
        );
      end if;

      if norm in ('complaint', 'hard_bounce') then
        insert into public.communication_email_suppressions (
          organization_id, recipient_email, reason, source, source_callback_event_id,
          first_delivery_intent_id, evidence
        ) values (
          candidate.organization_id, candidate.recipient_email, norm, 'provider_callback', candidate.id,
          candidate.delivery_intent_id,
          jsonb_build_object(
            'event_kind', candidate.event_kind,
            'occurred_at', candidate.occurred_at,
            'received_at', candidate.received_at
          )
        )
        on conflict (organization_id, recipient_email, reason) where released_at is null
        do nothing;
      elsif norm = 'unsubscribed' then
        insert into public.communication_email_suppressions (
          organization_id, recipient_email, reason, source, source_callback_event_id,
          first_delivery_intent_id, evidence
        ) values (
          candidate.organization_id, candidate.recipient_email, 'unsubscribe', 'provider_callback',
          candidate.id, candidate.delivery_intent_id,
          jsonb_build_object(
            'event_kind', candidate.event_kind,
            'occurred_at', candidate.occurred_at,
            'received_at', candidate.received_at
          )
        )
        on conflict (organization_id, recipient_email, reason) where released_at is null
        do nothing;
      end if;

      if norm in ('complaint', 'hard_bounce', 'unsubscribed') then
        insert into public.communication_email_reputation_state (organization_id, evaluation_requested_at)
        values (candidate.organization_id, now())
        on conflict (organization_id) do update
        set evaluation_requested_at = excluded.evaluation_requested_at;
      end if;

      update public.communication_provider_callback_events
      set processed_at = now(), normalized_kind = norm, organization_id = candidate.organization_id
      where id = candidate.id;
      processed_count := processed_count + 1;
    exception
      when others then
        update public.communication_provider_callback_events
        set processing_attempts = coalesce(processing_attempts, 0) + 1,
          processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
          normalized_kind = coalesce(normalized_kind, norm),
          processed_at = case
            when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
            else processed_at
          end
        where id = candidate.id;
    end;
  end loop;

  return processed_count;
end;
$function$;
