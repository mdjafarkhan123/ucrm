-- Pipeline G2: a card that is Won or Lost can no longer be changed through the Brief's commands.
--
-- No screen offers these changes on a closed card, but the commands took its id and went ahead: a frozen Won
-- or Lost value could be rewritten, the card handed to another owner, a new Task started on work that is
-- finished, and Notes written through the Pipeline's own permission. The value on a closed card is the
-- frozen outcome value the reports read, so it must not move (plan § Outcomes).
--
-- One helper says no in one sentence, and each command asks it after its own permission check, so a
-- stranger still learns nothing about whether a card exists. Refused: owner, value and expected close;
-- adding, editing and reopening a Task; adding, editing and deleting a Note. Still allowed: completing or
-- deleting a Task that was left open (it has to be clearable), and logging a call, which never restarts a
-- closed card's clock (20261004130000).
--
-- Every body below is its current definition with only the pipeline_assert_card_open line added, and the
-- details function now locks the card's row so the check and the write see the same outcome.

create function private.pipeline_assert_card_open(target_opportunity_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1
    from public.opportunities as opportunity
    where opportunity.id = target_opportunity_id
      and opportunity.outcome <> 'open'
  ) then
    raise exception 'This card is closed, so it can no longer be changed here.'
      using errcode = 'check_violation', hint = 'card_closed';
  end if;
end;
$$;

revoke all on function private.pipeline_assert_card_open(uuid) from public, anon, authenticated;

-- 1. Owner, value and expected close --------------------------------------------------------------------------

create or replace function public.pipeline_update_opportunity_details(
  target_opportunity_id uuid,
  set_owner boolean default false,
  new_owner_user_id uuid default null,
  set_value boolean default false,
  new_estimated_value numeric default null,
  set_expected_close boolean default false,
  new_expected_close_on date default null
)
returns table (
  id uuid,
  owner_user_id uuid,
  estimated_value numeric,
  expected_close_on date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid;
  target_quote_id uuid;
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  -- Definer rights skip row level security, so membership is checked here by hand rather than assumed.
  select opportunity.organization_id, opportunity.quote_id
  into target_organization_id, target_quote_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id
  for update;

  if target_organization_id is null
     or not private.member_has_permission(target_organization_id, caller_id, 'pipeline.edit') then
    -- Same answer either way: a stranger learns nothing about whether the record exists.
    raise exception 'You do not have access to change this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  if set_value and not caller_sees_money then
    raise exception 'You do not have access to change values on the sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  perform private.pipeline_assert_card_open(target_opportunity_id);

  if set_value and target_quote_id is not null then
    raise exception 'A quote-backed opportunity''s value comes from the quote and cannot be edited here.'
      using errcode = 'check_violation';
  end if;

  return query
  update public.opportunities as opportunity
  set
    owner_user_id = case when set_owner then new_owner_user_id else opportunity.owner_user_id end,
    estimated_value = case when set_value then new_estimated_value else opportunity.estimated_value end,
    expected_close_on =
      case when set_expected_close then new_expected_close_on else opportunity.expected_close_on end
  where opportunity.id = target_opportunity_id
  returning
    opportunity.id,
    opportunity.owner_user_id,
    -- Nothing is returned to somebody who may not see money, not even the value they did not change.
    case when caller_sees_money then opportunity.estimated_value end,
    opportunity.expected_close_on,
    opportunity.updated_at;
end;
$$;

-- 2. Tasks ----------------------------------------------------------------------------------------------------

create or replace function private.pipeline_insert_task(
  target_opportunity_id uuid,
  new_title text,
  new_instructions text,
  new_assignee_user_id uuid,
  new_due_on date
)
returns public.tasks
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid := private.pipeline_lock_task_parent(target_opportunity_id);
  created public.tasks;
begin
  perform private.pipeline_assert_card_open(target_opportunity_id);
  perform private.assert_task_limit(target_opportunity_id, 'open');

  insert into public.tasks as task (
    organization_id, opportunity_id, title, instructions, assignee_user_id, due_on, created_by
  )
  values (
    target_organization_id,
    target_opportunity_id,
    new_title,
    nullif(trim(coalesce(new_instructions, '')), ''),
    new_assignee_user_id,
    new_due_on,
    (select auth.uid())
  )
  returning task.* into created;

  return created;
end;
$$;

create or replace function public.pipeline_update_opportunity_task(
  target_task_id uuid,
  new_title text,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
)
returns table (
  id uuid,
  opportunity_id uuid,
  title text,
  instructions text,
  assignee_user_id uuid,
  due_on date,
  status text,
  completed_at timestamptz,
  completed_by uuid,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  parent_id uuid;
  previous_assignee uuid;
  updated public.tasks;
begin
  select task.opportunity_id into parent_id from public.tasks as task where task.id = target_task_id;
  if parent_id is null then
    raise exception 'You do not have access to change this task.' using errcode = 'insufficient_privilege';
  end if;

  perform private.pipeline_lock_task_parent(parent_id);
  perform private.pipeline_assert_card_open(parent_id);

  -- Read under the parent's lock, so two people reassigning at once each compare with what is really there.
  select task.assignee_user_id into previous_assignee from public.tasks as task where task.id = target_task_id;

  update public.tasks as task
  set
    title = new_title,
    instructions = nullif(trim(coalesce(new_instructions, '')), ''),
    assignee_user_id = new_assignee_user_id,
    due_on = new_due_on
  where task.id = target_task_id
  returning task.* into updated;

  if updated.id is null then
    return;
  end if;

  if updated.assignee_user_id is distinct from previous_assignee then
    perform private.alert_task_assignment(array[updated.id]);
  end if;

  return query select
    updated.id, updated.opportunity_id, updated.title, updated.instructions, updated.assignee_user_id,
    updated.due_on, updated.status, updated.completed_at, updated.completed_by, updated.created_by,
    updated.created_at, updated.updated_at;
end;
$$;

create or replace function public.pipeline_set_task_completed(target_task_id uuid, is_completed boolean)
returns table (
  id uuid,
  opportunity_id uuid,
  title text,
  instructions text,
  assignee_user_id uuid,
  due_on date,
  status text,
  completed_at timestamptz,
  completed_by uuid,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  parent_id uuid;
  current_status text;
  wanted_status text := case when is_completed then 'completed' else 'open' end;
begin
  select task.opportunity_id, task.status
  into parent_id, current_status
  from public.tasks as task
  where task.id = target_task_id;

  if parent_id is null then
    raise exception 'You do not have access to change this task.' using errcode = 'insufficient_privilege';
  end if;

  perform private.pipeline_lock_task_parent(parent_id);

  -- Asking for the state it is already in is not an error. A retried request, or two clicks on the same
  -- button, must not spend one of the five slots or move the completion time.
  if current_status = wanted_status then
    return query
    select
      task.id, task.opportunity_id, task.title, task.instructions, task.assignee_user_id, task.due_on,
      task.status, task.completed_at, task.completed_by, task.created_by, task.created_at, task.updated_at
    from public.tasks as task
    where task.id = target_task_id;
    return;
  end if;

  -- Finishing a Task left open on a closed card is allowed; starting it again is new work on closed work.
  if not is_completed then
    perform private.pipeline_assert_card_open(parent_id);
  end if;

  perform private.assert_task_limit(parent_id, wanted_status);

  return query
  update public.tasks as task
  set
    status = wanted_status,
    completed_at = case when is_completed then now() end,
    completed_by = case when is_completed then (select auth.uid()) end
  where task.id = target_task_id
  returning
    task.id, task.opportunity_id, task.title, task.instructions, task.assignee_user_id, task.due_on,
    task.status, task.completed_at, task.completed_by, task.created_by, task.created_at, task.updated_at;
end;
$$;

-- 3. Notes ----------------------------------------------------------------------------------------------------
--
-- The Request, Quote and Client pages keep their own Notes with their own permission; only the Pipeline's
-- path closes with the card.

create or replace function public.pipeline_create_opportunity_note(
  target_opportunity_id uuid,
  target_entity_type text,
  new_body text,
  new_file_ids uuid[] default '{}'::uuid[],
  new_mention_user_ids uuid[] default '{}'::uuid[]
)
returns table (
  id uuid,
  body text,
  pinned boolean,
  created_by uuid,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  entity_type text,
  entity_id uuid,
  files jsonb,
  mention_user_ids uuid[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  resolved_entity_id uuid;
  inserted_note public.notes;
  inserted_link public.note_links;
begin
  if target_entity_type not in ('request', 'quote', 'client') then
    raise exception 'A Brief Note can only target the Request, the Quote or the Client.'
      using errcode = 'check_violation';
  end if;

  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');
  perform private.pipeline_assert_card_open(target_opportunity_id);

  resolved_entity_id := case target_entity_type
    when 'request' then case when scope.quote_id is null then scope.request_id end
    when 'quote' then scope.quote_id
    else scope.client_id
  end;

  if resolved_entity_id is null then
    raise exception 'This opportunity has no % to attach a note to.', target_entity_type
      using errcode = 'check_violation';
  end if;

  insert into public.notes (organization_id, body, created_by)
  values (scope.organization_id, new_body, (select auth.uid()))
  returning * into inserted_note;

  insert into public.note_links (organization_id, note_id, entity_type, entity_id)
  values (scope.organization_id, inserted_note.id, target_entity_type, resolved_entity_id)
  returning * into inserted_link;

  perform private.pipeline_note_save_extras(
    scope.organization_id, scope.request_id, scope.client_id, scope.quote_id, target_opportunity_id,
    inserted_note.id, coalesce(new_file_ids, '{}'), coalesce(new_mention_user_ids, '{}')
  );

  return query
  select
    inserted_note.id, inserted_note.body, inserted_note.pinned, inserted_note.created_by,
    inserted_note.edited_by, inserted_note.edited_at, inserted_note.created_at, inserted_note.updated_at,
    inserted_link.entity_type, inserted_link.entity_id,
    private.pipeline_note_files_json(inserted_note.id), private.note_mention_ids(inserted_note.id);
end;
$$;

create or replace function public.pipeline_update_opportunity_note(
  target_note_id uuid,
  target_opportunity_id uuid,
  new_body text,
  new_file_ids uuid[] default null,
  new_mention_user_ids uuid[] default null
)
returns table (
  id uuid,
  body text,
  pinned boolean,
  created_by uuid,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  entity_type text,
  entity_id uuid,
  files jsonb,
  mention_user_ids uuid[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  target_link public.note_links;
  updated_note public.notes;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');
  perform private.pipeline_assert_card_open(target_opportunity_id);

  select link.* into target_link
  from public.note_links as link
  where link.note_id = target_note_id
    and link.organization_id = scope.organization_id
    and (
      (link.entity_type = 'request' and link.entity_id = scope.request_id)
      or (link.entity_type = 'quote' and link.entity_id = scope.quote_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  limit 1;

  if target_link.id is null then
    raise exception 'That note is not on this opportunity.' using errcode = 'insufficient_privilege';
  end if;

  -- Only a real change of text marks the Note edited; changing its Files or mentions alone does not.
  update public.notes as note
  set body = new_body,
      edited_by = case when note.body is distinct from new_body then (select auth.uid()) else note.edited_by end,
      edited_at = case when note.body is distinct from new_body then now() else note.edited_at end
  where note.id = target_note_id
  returning * into updated_note;

  perform private.pipeline_note_save_extras(
    scope.organization_id, scope.request_id, scope.client_id, scope.quote_id, target_opportunity_id,
    target_note_id, new_file_ids, new_mention_user_ids
  );

  return query
  select
    updated_note.id, updated_note.body, updated_note.pinned, updated_note.created_by,
    updated_note.edited_by, updated_note.edited_at, updated_note.created_at, updated_note.updated_at,
    target_link.entity_type, target_link.entity_id,
    private.pipeline_note_files_json(updated_note.id), private.note_mention_ids(updated_note.id);
end;
$$;

create or replace function public.pipeline_delete_opportunity_note(
  target_note_id uuid,
  target_opportunity_id uuid,
  target_entity_type text
)
returns table (unlinked boolean, note_deleted boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  resolved_entity_id uuid;
  remaining integer;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');
  perform private.pipeline_assert_card_open(target_opportunity_id);

  resolved_entity_id := case target_entity_type
    when 'request' then scope.request_id
    when 'quote' then scope.quote_id
    when 'client' then scope.client_id
    else null
  end;

  delete from public.note_links as link
  where link.note_id = target_note_id
    and link.organization_id = scope.organization_id
    and link.entity_type = target_entity_type
    and link.entity_id = resolved_entity_id;

  if not found then
    raise exception 'That note is not on this opportunity.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into remaining from public.note_links as link where link.note_id = target_note_id;

  if remaining = 0 then
    delete from public.notes as note where note.id = target_note_id;
    return query select true, true;
  end if;

  return query select true, false;
end;
$$;
