-- Automation Part 6F-1: Jobber Quote-follow-up parity.
--
-- Three gaps between the 6D engine and the behaviour Jobber's built-in quote follow-ups actually have:
--
--   1. PREFERENCE. Jobber sends follow-ups only when `outstanding quote follow-ups` is enabled for that
--      client. Our engine never read client_communication_preferences.quote_follow_ups, so a client who had
--      opted out still received reminders. It is now a hard gate at intake (no enrollment, with a recorded
--      reason) and again immediately before every send (the enrollment stops).
--   2. STOP. Jobber's built-in follow-ups run only while the quote is Awaiting response. Ours checked the
--      quote only when a send was reached, and it accepted `changes_requested` and `approved` as sendable --
--      so an approved quote could still get a "still interested?" email, and a stopped sequence sat on a
--      wait for days before noticing. The stop check now runs at every transition, and Awaiting response is
--      the only sendable status.
--   3. TIMING. `wait` steps were scheduled as `now() + delay`, i.e. from whenever a worker happened to reach
--      the step. A slow or backed-up worker silently pushed every later reminder out, and the reminder
--      arrived at a different local time of day than the original quote. Waits are now measured from the
--      original send, cumulatively, in the organization's own timezone -- the shipped preset's 3-day then
--      4-day waits land on day 3 and day 7 after the send, at the send's local time of day, no matter when
--      the worker runs. An already-overdue step stays overdue rather than being pushed forward.
--
-- Unchanged on purpose: the two-reminder preset, the per-step 90-day ceiling, email-only delivery, the
-- logical send key that makes a replay send nothing extra, and tenant isolation (every read here is filtered
-- by the enrollment's own organization).

-- ---------------------------------------------------------------------------------------------------
-- 1. The anchor: what a wait is measured from.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_enrollments
  add column anchor_at timestamptz;

-- Backfill from the fact that started the enrollment (the delivery's occurred_at); a manual enrollment has
-- no event, so it anchors on when it was created.
update private.automation_enrollments as e
set anchor_at = coalesce(
  (select ev.occurred_at from private.automation_events as ev where ev.id = e.trigger_event_id),
  e.created_at)
where anchor_at is null;

alter table private.automation_enrollments
  alter column anchor_at set default now(),
  alter column anchor_at set not null;

comment on column private.automation_enrollments.anchor_at is
  'The original send this enrollment schedules against: the trigger event''s occurred_at, or creation time '
  'for a manual enrollment. Every wait is measured from here, so worker lateness never shifts a reminder.';

-- ---------------------------------------------------------------------------------------------------
-- 2. One domain-owned stop check, used by both the transition and the send.
-- ---------------------------------------------------------------------------------------------------
-- Returns null when the follow-up may still run, or the plain reason it may not. Quote-owned facts only:
-- entitlement, platform authority, and sender readiness stay with the send, which owns them.
create or replace function private.automation_quote_stop_outcome(
  p_organization_id uuid,
  p_quote_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes%rowtype;
  wants_follow_ups boolean;
begin
  select * into quote_row
  from public.quotes
  where organization_id = p_organization_id and id = p_quote_id;

  if not found or quote_row.archived_at is not null then
    return 'quote_not_sendable';
  end if;

  -- Jobber's built-in follow-ups run only while a quote is Awaiting response. Approved, declined, changes
  -- requested, converted, or back to draft all mean the reminder is moot.
  if quote_row.status <> 'awaiting_response' then
    return 'quote_not_awaiting_response';
  end if;

  select p.quote_follow_ups into wants_follow_ups
  from public.client_communication_preferences as p
  where p.organization_id = p_organization_id and p.client_id = quote_row.client_id;

  -- Every client has a preference row; a missing one is treated as consent to the same default the row
  -- carries, so a data gap cannot silently silence every follow-up.
  if not coalesce(wants_follow_ups, true) then
    return 'follow_ups_declined';
  end if;

  return null;
end;
$$;

comment on function private.automation_quote_stop_outcome(uuid, uuid) is
  'Null when a quote follow-up may still run, or the plain reason it may not: the quote is gone/archived, no '
  'longer awaiting a response, or the client turned quote follow-ups off. Used by both the worker transition '
  'and the send.';

revoke all on function private.automation_quote_stop_outcome(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. Intake: the preference is a gate, and the enrollment records its anchor.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_event_matches
  drop constraint automation_event_matches_outcome_check;

alter table private.automation_event_matches
  add constraint automation_event_matches_outcome_check check (outcome in (
    'enrolled', 'already_enrolled', 'before_activation', 'not_entitled', 'authority_blocked',
    'subject_gone', 'condition_failed', 'condition_unavailable', 'follow_ups_declined'
  ));

-- Replaced from the 6D-2 definition. The only changes are marked 6F-1.
create or replace function public.intake_automation_events(p_batch_size integer default 25)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate private.automation_events%rowtype;
  match_row record;
  authority public.organization_automation_authority%rowtype;
  quote_row public.quotes%rowtype;
  is_entitled boolean;
  wants_follow_ups boolean;
  duration_days integer;
  enrollment_expires_at timestamptz;
  re_entry_key text;
  match_outcome text;
  new_enrollment_id uuid;
  processed_count integer := 0;
  max_processing_attempts constant integer := 5;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The intake batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select *
    from private.automation_events
    where processed_at is null
      and available_at <= now()
    order by seq
    limit p_batch_size
    for update skip locked
  loop
    begin
      select * into authority
      from public.organization_automation_authority
      where organization_id = candidate.organization_id;

      is_entitled := private.organization_has_automations_feature(candidate.organization_id);

      select * into quote_row
      from public.quotes
      where organization_id = candidate.organization_id and id = candidate.subject_id;

      -- 6F-1: the client's saved quote-follow-up preference, resolved once per event rather than per recipe.
      wants_follow_ups := true;
      if quote_row.client_id is not null then
        select coalesce(p.quote_follow_ups, true) into wants_follow_ups
        from public.client_communication_preferences as p
        where p.organization_id = candidate.organization_id and p.client_id = quote_row.client_id;
        wants_follow_ups := coalesce(wants_follow_ups, true);
      end if;

      select case when limits.state = 'numeric' then limits.value end
      into duration_days
      from public.effective_automation_limits(candidate.organization_id) as limits
      where limits.limit_key = 'automation_max_enrollment_duration_days';

      enrollment_expires_at := case
        when duration_days is not null and duration_days > 0
        then now() + make_interval(days => duration_days)
      end;

      re_entry_key := coalesce(candidate.payload ->> 'quote_version_id', '')
        || ':' || coalesce(candidate.payload ->> 'quote_recipient_id', '');

      for match_row in
        select
          recipe.id as recipe_id,
          recipe.current_version_id,
          version.definition,
          version.activation_cutoff_snapshot,
          version.activation_cutoff_sequence
        from public.automation_recipes as recipe
        join public.automation_recipe_versions as version
          on version.id = recipe.current_version_id
        where recipe.organization_id = candidate.organization_id
          and recipe.status = 'active'
          and recipe.active_trigger_key = candidate.event_type
        order by recipe.id
      loop
        match_outcome := null;
        new_enrollment_id := null;

        if not is_entitled then
          match_outcome := 'not_entitled';
        elsif authority.organization_id is not null
          and (authority.operational_state <> 'enabled' or authority.security_state <> 'active') then
          match_outcome := 'authority_blocked';
        elsif (
            match_row.activation_cutoff_snapshot is not null
            and pg_visible_in_snapshot(candidate.created_xid, match_row.activation_cutoff_snapshot)
          ) or (
            match_row.activation_cutoff_snapshot is null
            and candidate.seq <= coalesce(match_row.activation_cutoff_sequence, 0)
          ) then
          match_outcome := 'before_activation';
        elsif quote_row.id is null or quote_row.archived_at is not null then
          match_outcome := 'subject_gone';
        -- 6F-1: a client who turned quote follow-ups off never enrolls, and the reason is recorded so
        -- history can answer "why did my automation not run".
        elsif not wants_follow_ups then
          match_outcome := 'follow_ups_declined';
        else
          match_outcome := private.automation_conditions_outcome(
            match_row.definition, candidate.organization_id, quote_row.status, candidate.payload
          );
          if match_outcome = 'pass' then
            insert into private.automation_enrollments (
              organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
              trigger_event_id, source, re_entry_key, context, expires_at, anchor_at
            ) values (
              candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
              candidate.subject_type, candidate.subject_id, candidate.id, 'event',
              re_entry_key, candidate.payload, enrollment_expires_at,
              -- 6F-1: schedule against the original send, never against when intake happened to run.
              candidate.occurred_at
            )
            on conflict do nothing
            returning id into new_enrollment_id;

            if new_enrollment_id is null then
              match_outcome := 'already_enrolled';
            else
              match_outcome := 'enrolled';
              insert into private.automation_work_items (
                organization_id, enrollment_id, step_index, due_at, available_at
              ) values (
                candidate.organization_id, new_enrollment_id, 0, now(), now()
              )
              on conflict do nothing;
            end if;
          end if;
        end if;

        insert into private.automation_event_matches (
          event_id, organization_id, recipe_id, recipe_version_id, outcome, enrollment_id
        ) values (
          candidate.id, candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
          match_outcome, new_enrollment_id
        )
        on conflict (event_id, recipe_id) do nothing;
      end loop;

      update private.automation_events
      set processed_at = now(), processing_error = null
      where id = candidate.id;
      processed_count := processed_count + 1;

    exception
      when others then
        update private.automation_events
        set processing_attempts = coalesce(processing_attempts, 0) + 1,
          processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
          available_at = now() + private.automation_retry_delay(coalesce(processing_attempts, 0) + 1),
          processed_at = case
            when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
            else processed_at
          end
        where id = candidate.id;
    end;
  end loop;

  return processed_count;
end;
$$;

comment on function public.intake_automation_events(integer) is
  'Bounded, replay-safe drain: unprocessed automation events become enrollments plus one first due-work '
  'item, or a recorded reason why not. Honours the client''s saved quote-follow-up preference and anchors '
  'each enrollment on the original send. Service role only.';

revoke all on function public.intake_automation_events(integer) from public, anon, authenticated;
grant execute on function public.intake_automation_events(integer) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. The transition: stop early, and schedule waits from the original send.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.advance_automation_work_item(
  p_work_item_id uuid,
  p_claim_token uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  definition jsonb;
  step jsonb;
  step_type text;
  stop_outcome text;
  organization_timezone text;
  wait_amount integer;
  wait_unit text;
  waited_days integer;
  waited_hours integer;
  next_due timestamptz;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;

  select * into item from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending' for update;
  if not found then return 'claim_lost'; end if;

  select * into enrollment from private.automation_enrollments where id = item.enrollment_id for update;
  if not found or enrollment.state <> 'active' then
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'enrollment_inactive';
  end if;

  if enrollment.expires_at is not null and enrollment.expires_at <= now() then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'enrollment_expired', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'enrollment_expired';
  end if;

  select recipe.status, version.definition into recipe_status, definition
  from private.automation_enrollments as e
  join public.automation_recipes as recipe on recipe.id = e.recipe_id
  join public.automation_recipe_versions as version on version.id = e.recipe_version_id
  where e.id = enrollment.id;

  if recipe_status is distinct from 'active' then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'recipe_not_active', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'recipe_not_active';
  end if;

  step := (definition -> 'steps') -> item.step_index;

  if step is null then
    update private.automation_enrollments
    set state = 'completed', completed_at = now(), current_step_index = item.step_index
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null where id = item.id;
    return 'completed';
  end if;

  -- 6F-1: the domain stop check runs at EVERY transition, not only when a send is reached. A quote that
  -- was approved during a three-day wait stops here instead of sitting in the queue until the wait ends.
  if enrollment.subject_type = 'quote' then
    stop_outcome := private.automation_quote_stop_outcome(enrollment.organization_id, enrollment.subject_id);
    if stop_outcome is not null then
      update private.automation_enrollments
      set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
      update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
      return 'stop_condition_met';
    end if;
  end if;

  step_type := step ->> 'type';

  if step_type = 'wait' then
    wait_unit := step -> 'config' ->> 'unit';
    wait_amount := nullif(step -> 'config' ->> 'amount', '')::integer;
    if wait_unit not in ('hours', 'days') or wait_amount is null or wait_amount < 1 then
      raise exception 'This automation step has an unusable delay.' using errcode = 'check_violation';
    end if;

    -- 6F-1: every wait up to and including this one, summed, and measured from the original send. Waits are
    -- authored relative to the previous step ("then wait 4 more days"), so the running total is what turns
    -- the shipped 3-then-4 preset into day 3 and day 7 after the send. Scheduling from now() instead let a
    -- late worker push every later reminder out by however long it was late.
    select
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'days'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0),
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'hours'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0)
    into waited_days, waited_hours
    from jsonb_array_elements(coalesce(definition -> 'steps', '[]'::jsonb))
      with ordinality as entry(step, position)
    where entry.position - 1 <= item.step_index and entry.step ->> 'type' = 'wait';

    -- Day arithmetic happens in the organization's own timezone, so the reminder lands at the same local
    -- time of day the quote was sent at even across a daylight-saving change.
    select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into organization_timezone
    from public.organization_settings as settings
    where settings.organization_id = enrollment.organization_id;
    organization_timezone := coalesce(organization_timezone, 'UTC');

    next_due := ((enrollment.anchor_at at time zone organization_timezone)
      + make_interval(days => waited_days, hours => waited_hours)) at time zone organization_timezone;

    update private.automation_enrollments
    set current_step_index = item.step_index + 1 where id = enrollment.id;

    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null where id = item.id;

    -- A due time already in the past is correct and stays in the past: the step is simply overdue and the
    -- next claim picks it up immediately, rather than being pushed a further full delay into the future.
    insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at)
    values (enrollment.organization_id, enrollment.id, item.step_index + 1, next_due, next_due)
    on conflict (enrollment_id, step_index) do nothing;

    return 'waiting';
  end if;

  if step_type = 'action' then
    return 'action_due';
  end if;

  raise exception 'This automation step has an unknown type.' using errcode = 'check_violation';
end;
$$;

comment on function public.advance_automation_work_item(uuid, uuid) is
  'Runs one claimed transition: rechecks enrollment, expiry, recipe state, and the domain stop conditions, '
  'then completes, schedules the next step from the original send, or returns action_due for the worker to '
  'run and settle the effect. Claim-token guarded. Service role only.';

revoke all on function public.advance_automation_work_item(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_automation_work_item(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. The send uses the same stop check.
-- ---------------------------------------------------------------------------------------------------
-- Only the quote gate changes: it was an inline status list that accepted `changes_requested` and
-- `approved` and never looked at the client's preference. Everything else is the 6D-3a definition.
create or replace function public.enqueue_automation_quote_email(
  p_organization_id uuid,
  p_quote_id uuid,
  p_logical_send_key text,
  p_subject text,
  p_body text,
  p_quote_url text,
  p_quote_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  quote_row public.quotes;
  version_row public.quote_versions;
  client_row public.clients;
  recipient public.client_contact_methods;
  quote_recipient public.quote_recipients;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  alias public.communication_reply_aliases;
  intent public.communication_delivery_intents;
  access_link_id uuid;
  rendered record;
  customer_name text;
  stop_outcome text;
begin
  if p_quote_url !~ '^https?://[^[:space:]]+$'
    or p_quote_token_hash is null or octet_length(p_quote_token_hash) <> 32 then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_link');
  end if;

  if coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_email_content');
  end if;

  select * into intent from public.communication_delivery_intents
    where organization_id = p_organization_id and logical_send_key = p_logical_send_key for share;
  if intent.id is not null then
    if intent.quote_id is distinct from p_quote_id then
      return jsonb_build_object('status', 'skipped_permanent', 'reason', 'idempotency_conflict');
    end if;
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end if;

  if not private.organization_has_automations_feature(p_organization_id, now()) then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'automations_not_entitled');
  end if;

  select * into authority from public.organization_automation_authority
    where organization_id = p_organization_id;
  if coalesce(authority.operational_state, 'enabled') <> 'enabled'
    or coalesce(authority.security_state, 'active') <> 'active' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'automation_suspended');
  end if;

  -- 6F-1: one shared stop check -- the quote must exist, still be awaiting a response, and belong to a
  -- client who still wants quote follow-ups. Each is permanent, so the caller stops the whole enrollment.
  stop_outcome := private.automation_quote_stop_outcome(p_organization_id, p_quote_id);
  if stop_outcome is not null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', stop_outcome);
  end if;

  select * into quote_row from public.quotes
    where organization_id = p_organization_id and id = p_quote_id for share;
  if quote_row.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'quote_not_sendable');
  end if;

  select * into version_row from public.quote_versions
    where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
      and quote_id = quote_row.id and status = 'published' for share;
  select * into client_row from public.clients
    where organization_id = quote_row.organization_id and id = quote_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = quote_row.organization_id and client_id = quote_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if version_row.id is null or client_row.id is null or recipient.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'recipient_unavailable');
  end if;

  select * into sender from public.communication_email_senders
    where organization_id = quote_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    return jsonb_build_object('status', 'skipped_temporary', 'reason', 'sender_not_ready');
  end if;

  customer_name := coalesce(nullif(btrim(client_row.display_name), ''), recipient.normalized_value);
  select * into rendered from private.render_automation_email(
    p_subject, p_body, customer_name, version_row.organization_name,
    quote_row.quote_number::text, p_quote_url);

  alias := public.ensure_communication_reply_alias(
    quote_row.organization_id, sender.id, quote_row.client_id, recipient.id);

  insert into public.quote_recipients (organization_id, quote_id, display_name, email, created_by)
    values (quote_row.organization_id, quote_row.id, customer_name, recipient.normalized_value, null)
    on conflict (organization_id, quote_id, email) do update set display_name = excluded.display_name
    returning * into quote_recipient;
  update public.quote_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = quote_row.organization_id and quote_id = quote_row.id
      and recipient_id = quote_recipient.id and revoked_at is null;
  insert into public.quote_access_links
    (organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by)
    values (quote_row.organization_id, quote_row.id, version_row.id, quote_recipient.id, p_quote_token_hash, null)
    returning id into access_link_id;

  begin
    insert into public.communication_delivery_intents
      (organization_id, client_id, client_contact_method_id, quote_id, quote_version_id, quote_recipient_id,
       quote_access_link_id, logical_send_key, recipient_email, subject, html_content, text_content,
       send_kind, allowance_class, sender_id, reply_alias_id, created_by)
      values (quote_row.organization_id, quote_row.client_id, recipient.id, quote_row.id, version_row.id,
       quote_recipient.id, access_link_id, p_logical_send_key, recipient.normalized_value,
       rendered.subject, rendered.html_content, rendered.text_content,
       'automated', 'essential', sender.id, alias.id, null)
      returning * into intent;
  exception when unique_violation then
    select * into intent from public.communication_delivery_intents
      where organization_id = p_organization_id and logical_send_key = p_logical_send_key;
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
    values (intent.organization_id, intent.id);

  return jsonb_build_object('status', 'sent', 'reason', 'enqueued', 'intent_id', intent.id);
end;
$$;

comment on function public.enqueue_automation_quote_email(uuid, uuid, text, text, text, text, bytea) is
  'System-authorized automation email send: re-checks entitlement, authority, the quote stop conditions '
  '(awaiting response and the client''s follow-up preference), recipient, and sender readiness, renders safe '
  'copy, and enqueues one delivery intent idempotently on the logical send key. Returns sent / '
  'skipped_permanent / skipped_temporary. Service role only.';

revoke all on function public.enqueue_automation_quote_email(uuid, uuid, text, text, text, text, bytea)
  from public, anon, authenticated;
grant execute on function public.enqueue_automation_quote_email(uuid, uuid, text, text, text, text, bytea)
  to service_role;
