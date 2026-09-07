-- Duplicating a visit must reproduce that visit's own prices ---------------------------------------------

-- A visit whose lines were customised bills its own numbers, not the job's. Before this, "Duplicate" copied
-- only the schedule, so the copy silently fell back to the job's default prices and would bill the wrong
-- money. A visit element may now carry copy_lines_from_visit_id; the source visit's lines are copied onto
-- the new visit inside the same transaction as the visit itself, so a copy is never half-made.
--
-- No new permission: the caller chooses no numbers and only visit ids come back, so no price is disclosed
-- to someone without price-edit permission. Editing or viewing those prices still costs what it always did.
create or replace function public.add_job_visits(
  target_organization_id uuid,
  target_job_id uuid,
  visits jsonb,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  visit_count integer;
  next_position integer;
  visit_element jsonb;
  new_visit public.job_visits;
  assignee_element jsonb;
  copy_source_id uuid;
  added_ids uuid[] := array[]::uuid[];
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  visit_count := coalesce(jsonb_array_length(visits), 0);
  if visit_count < 1 or visit_count > 20 then
    raise exception 'Between 1 and 20 visits can be added at once.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- The job must exist in this organization and still be open. A closed job is not scheduled against; it is
  -- reopened first, which is an explicit later action. Not found and forbidden read the same to a stranger.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    raise exception 'A closed job cannot be scheduled. Reopen it first.' using errcode = 'P0410';
  end if;

  -- Claim the key before any work. on conflict do nothing waits for a racing transaction to commit and then
  -- returns no row, so the loser reads the winner's committed result instead of adding a second batch.
  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'add_job_visits', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'add_job_visits'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'Those visits were already added with different details.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  -- New visits append after the job's current visits. position orders the job's own list, not the calendar.
  select coalesce(max(visit.position), -1) + 1 into next_position
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id;

  for visit_element in select value from jsonb_array_elements(visits) as v(value)
  loop
    insert into public.job_visits (
      organization_id, job_id, position, visit_date, start_time, end_time, all_day, title, instructions,
      source
    ) values (
      target_organization_id,
      target_job_id,
      next_position,
      nullif(visit_element->>'visit_date', '')::date,
      nullif(visit_element->>'start_time', '')::time,
      nullif(visit_element->>'end_time', '')::time,
      coalesce((visit_element->>'all_day')::boolean, false),
      nullif(trim(visit_element->>'title'), ''),
      nullif(trim(visit_element->>'instructions'), ''),
      coalesce(nullif(visit_element->>'source', ''), 'manual')
    )
    returning * into new_visit;

    next_position := next_position + 1;
    added_ids := array_append(added_ids, new_visit.id);

    if jsonb_typeof(visit_element->'assignee_ids') = 'array' then
      for assignee_element in select value from jsonb_array_elements(visit_element->'assignee_ids') as a(value)
      loop
        insert into public.job_visit_assignments (organization_id, visit_id, user_id)
        values (target_organization_id, new_visit.id, (assignee_element #>> '{}')::uuid)
        on conflict do nothing;
      end loop;
    end if;

    -- A faithful copy of the source visit's own lines, or nothing at all. A source that carries no lines of
    -- its own copies nothing, which is exactly right: the copy then bills the job's lines, as it did.
    copy_source_id := nullif(visit_element->>'copy_lines_from_visit_id', '')::uuid;
    if copy_source_id is not null then
      -- The source must be another visit of this same job in this same organization. Anything else is a
      -- mistake or a probe, and raising rolls the whole add back rather than quietly mispricing the copy.
      if not exists (
        select 1
        from public.job_visits as source
        where source.organization_id = target_organization_id
          and source.job_id = target_job_id
          and source.id = copy_source_id
      ) then
        raise exception 'The visit being copied could not be found.' using errcode = 'P0404';
      end if;

      -- source_job_line_item_id rides along: its uniqueness is scoped to one visit, so the copy's rows
      -- cannot collide with the original's, and the copy keeps the same once-per-visit override provenance.
      insert into public.job_visit_line_items (
        organization_id, job_id, visit_id, position, source_job_line_item_id, source_catalog_item_id,
        line_kind, category, is_labor, name, description, unit_label, quantity, unit_price_minor,
        unit_cost_minor, is_taxable, image_attachment_id
      )
      select
        target_organization_id, target_job_id, new_visit.id, item.position, item.source_job_line_item_id,
        item.source_catalog_item_id, item.line_kind, item.category, item.is_labor, item.name,
        item.description, item.unit_label, item.quantity, item.unit_price_minor,
        item.unit_cost_minor, item.is_taxable, item.image_attachment_id
      from public.job_visit_line_items as item
      where item.organization_id = target_organization_id
        and item.visit_id = copy_source_id
      order by item.position;
    end if;
  end loop;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visits_added',
    caller,
    jsonb_build_object('count', visit_count)
  );

  final_result := jsonb_build_object('applied', true, 'added_count', visit_count, 'visit_ids', to_jsonb(added_ids));
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

comment on function public.add_job_visits(uuid, uuid, jsonb, text, text) is
  'Appends 1-20 visits to an existing open job. Checks jobs.schedule, idempotent by key, appends a '
  'visits_added history row. A visit element may carry copy_lines_from_visit_id to reproduce that visit''s '
  'own lines exactly. Visit shape is guarded by the job_visits table constraints.';
