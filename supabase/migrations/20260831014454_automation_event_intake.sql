-- Automation Part 6D-1: intake -- turn events into enrollments and one first due-work item.
--
-- Shape: the proven bounded-drain pattern already used by process_communication_provider_callbacks. Claim a
-- small batch of unprocessed events with FOR UPDATE SKIP LOCKED, settle each one inside its own subtransaction
-- so a single poisoned event cannot roll back the batch, and mark it processed. A crash rolls back and the
-- same event replays to the identical result, because every write it makes is keyed.
--
-- Bounded, not long-running: the batch cap is 200 and the default is 25, so the transaction touches tens of
-- rows, never the backlog. Tenant isolation is structural -- every read is filtered by the event's own
-- organization_id, and enrollments can only pin a recipe version of that same organization (composite FK).
--
-- No worker, route, or cron here; 6D-2 owns those.

-- ---------------------------------------------------------------------------------------------------
-- 1. Is Automation actually included for this organization right now?
-- ---------------------------------------------------------------------------------------------------
-- Mirrors resolveOrganizationAccess exactly (src/lib/server/access/effective.ts): an active organization
-- override wins; otherwise the assigned package VERSION's features; otherwise the legacy package_key
-- mapping, honouring a scheduled package that is already due.
create or replace function private.organization_has_automations_feature(
  p_organization_id uuid,
  p_at timestamptz default now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  override_state text;
  assignment_version_id uuid;
  organization_row public.organizations%rowtype;
  effective_package_key text;
begin
  select o.override_state into override_state
  from public.organization_feature_overrides as o
  where o.organization_id = p_organization_id
    and o.feature_key = 'automations'
    and o.starts_at <= p_at
    and (o.expires_at is null or o.expires_at > p_at)
  order by o.starts_at desc
  limit 1;
  if override_state is not null then
    return override_state = 'on';
  end if;

  select a.package_version_id into assignment_version_id
  from public.organization_package_assignments as a
  where a.organization_id = p_organization_id
  order by a.effective_at desc, a.id desc
  limit 1;

  if assignment_version_id is not null then
    return exists (
      select 1
      from public.platform_package_version_features as f
      where f.package_version_id = assignment_version_id
        and f.feature_key = 'automations'
    );
  end if;

  select * into organization_row from public.organizations where id = p_organization_id;
  if not found then
    return false;
  end if;

  effective_package_key := case
    when organization_row.scheduled_package_key is not null
      and organization_row.scheduled_package_effective_at is not null
      and organization_row.scheduled_package_effective_at <= p_at
    then organization_row.scheduled_package_key
    else organization_row.package_key
  end;

  return exists (
    select 1
    from public.package_features as pf
    where pf.package_key = effective_package_key
      and pf.feature_key = 'automations'
  );
end;
$$;

revoke all on function private.organization_has_automations_feature(uuid, timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 2. Condition evaluation for the enabled Quote v1 conditions.
-- ---------------------------------------------------------------------------------------------------
-- Returns 'pass', 'condition_failed', or 'condition_unavailable'. An unknown key fails closed: a definition
-- referring to something this database cannot evaluate never silently behaves as "true".
create or replace function private.automation_conditions_outcome(
  p_definition jsonb,
  p_organization_id uuid,
  p_quote_status text,
  p_payload jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  condition_entry jsonb;
  condition_key text;
begin
  for condition_entry in
    select value from jsonb_array_elements(coalesce(p_definition -> 'conditions', '[]'::jsonb))
  loop
    condition_key := condition_entry ->> 'key';

    if condition_key = 'quote.current_status' then
      if p_quote_status is null or not exists (
        select 1
        from jsonb_array_elements_text(coalesce(condition_entry -> 'config' -> 'statuses', '[]'::jsonb)) as allowed(status)
        where allowed.status = p_quote_status
      ) then
        return 'condition_failed';
      end if;

    elsif condition_key = 'quote.recipient_attached' then
      if not exists (
        select 1
        from public.quote_recipients as r
        where r.organization_id = p_organization_id
          and r.id = (p_payload ->> 'quote_recipient_id')::uuid
      ) or not exists (
        select 1
        from public.client_contact_methods as m
        where m.organization_id = p_organization_id
          and m.id = (p_payload ->> 'client_contact_method_id')::uuid
          and m.kind = 'email'
      ) then
        return 'condition_failed';
      end if;

    else
      return 'condition_unavailable';
    end if;
  end loop;

  return 'pass';
end;
$$;

revoke all on function private.automation_conditions_outcome(jsonb, uuid, text, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. The drain.
-- ---------------------------------------------------------------------------------------------------
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
    order by seq
    limit p_batch_size
    for update skip locked
  loop
    begin
      -- Organization-wide gates, resolved once per event rather than once per recipe.
      select * into authority
      from public.organization_automation_authority
      where organization_id = candidate.organization_id;

      is_entitled := private.organization_has_automations_feature(candidate.organization_id);

      select * into quote_row
      from public.quotes
      where organization_id = candidate.organization_id and id = candidate.subject_id;

      select case when limits.state = 'numeric' then limits.value end
      into duration_days
      from public.effective_automation_limits(candidate.organization_id) as limits
      where limits.limit_key = 'automation_max_enrollment_duration_days';

      enrollment_expires_at := case
        when duration_days is not null and duration_days > 0
        then now() + make_interval(days => duration_days)
      end;

      -- Send-time identity is what makes a repeat delivery of the same document to the same person not a
      -- second reminder sequence.
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
        -- Authoritative: was this delivery already a committed fact when the recipe was activated? Versions
        -- frozen before the engine existed carry no snapshot and fall back to the readable marker. Written
        -- as a plain boolean, not a CASE: PL/pgSQL reads an ELSIF expression up to the first `then`.
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
        else
          match_outcome := private.automation_conditions_outcome(
            match_row.definition, candidate.organization_id, quote_row.status, candidate.payload
          );
          if match_outcome = 'pass' then
            insert into private.automation_enrollments (
              organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
              trigger_event_id, source, re_entry_key, context, expires_at
            ) values (
              candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
              candidate.subject_type, candidate.subject_id, candidate.id, 'event',
              re_entry_key, candidate.payload, enrollment_expires_at
            )
            on conflict do nothing
            returning id into new_enrollment_id;

            if new_enrollment_id is null then
              -- Either this exact event already enrolled, or this quote version and recipient already ran
              -- this recipe once. Both are the same answer to the contractor: no second sequence.
              match_outcome := 'already_enrolled';
            else
              match_outcome := 'enrolled';
              -- One next due transition, nothing pre-expanded. Due now: 6D-2 reads step 0 of the pinned
              -- definition and decides whether it waits or acts.
              insert into private.automation_work_items (
                organization_id, enrollment_id, step_index, due_at
              ) values (
                candidate.organization_id, new_enrollment_id, 0, now()
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
        -- Same recovery contract as the callback drain: count the attempt, keep a sanitized reason, and
        -- park the event once it has failed too often so one bad row cannot block the queue forever.
        update private.automation_events
        set processing_attempts = coalesce(processing_attempts, 0) + 1,
          processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
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
  'item, or a recorded reason why not. Service role only; 6D-2 gives it a worker and a wake.';

revoke all on function public.intake_automation_events(integer) from public, anon, authenticated;
grant execute on function public.intake_automation_events(integer) to service_role;
