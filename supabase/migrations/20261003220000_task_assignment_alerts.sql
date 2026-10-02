-- Pipeline E2: Task alerts.
--
-- Giving a Task to someone else -- on creation or by reassigning it -- puts one alert in their bell and sends
-- them one email (Jobber, HubSpot, and Asana all alert the new assignee, and only them). Giving a Task to
-- yourself, editing a Task without changing who has it, or a change nobody made (a migration, the system)
-- sends nothing. The customer is never told: this is an internal team alert and never goes through
-- Communications. A bulk Task given to someone sends them one combined alert, not one per card.
--
-- Push alerts and per-person notification settings are a separate feature (plan, revision 3).

-- 1. Alert kind and subject ---------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check check (kind = any (array[
  'website_inquiry.received', 'website_inquiry.customer_replied', 'invoice.paid_online',
  'invoice.online_payment_failed', 'invoice.online_overpayment', 'quote.deposit_paid_online',
  'quote.deposit_payment_failed', 'quote.deposit_overpaid', 'invoice.online_refund_failed',
  'invoice.payment_disputed', 'quote.deposit_refund_failed', 'quote.deposit_disputed',
  'review.private_feedback', 'quote.delivery_failed', 'quote.customer_declined', 'pipeline.task_assigned'
]));

-- 'opportunity' opens that card's Brief; 'task_batch' (a bulk Task, subject_id is one of its Tasks) opens
-- the board, because the Tasks sit on several cards.
alter table public.team_notifications drop constraint team_notifications_subject_type_check;
alter table public.team_notifications add constraint team_notifications_subject_type_check
  check (subject_type = any (array[
    'form_submission', 'website_chat_session', 'invoice', 'quote', 'review_feedback', 'opportunity', 'task_batch'
  ]));

-- 2. The alert ----------------------------------------------------------------------------------------------
--
-- One alert for the given Tasks, which share an assignee (one Task, or the Tasks one bulk call created).
-- The caller is whoever is signed in; only open Tasks count, so a reassigned finished Task is not news.

create function private.alert_task_assignment(p_task_ids uuid[])
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor uuid := (select auth.uid());
  first_task record;
  task_count integer;
  card_count integer;
  actor_name text;
  due_text text;
  alert_title text;
  alert_body text;
begin
  if actor is null or coalesce(cardinality(p_task_ids), 0) = 0 then
    return;
  end if;

  select task.id, task.organization_id, task.opportunity_id, task.title, task.assignee_user_id, task.due_on,
    opportunity.title as card_title
  into first_task
  from public.tasks as task
  join public.opportunities as opportunity on opportunity.id = task.opportunity_id
  where task.id = any (p_task_ids) and task.status = 'open'
  order by task.created_at, task.id
  limit 1;

  if not found
     or first_task.assignee_user_id is null
     or first_task.assignee_user_id = actor then
    return;
  end if;

  select count(*), count(distinct task.opportunity_id)
  into task_count, card_count
  from public.tasks as task
  where task.id = any (p_task_ids)
    and task.status = 'open'
    and task.assignee_user_id = first_task.assignee_user_id;

  -- Named as the owner menu names a teammate: their name, else their sign-in email.
  select coalesce(
    nullif(btrim(profile.full_name), ''),
    (select account.email::text from auth.users as account where account.id = actor),
    'A teammate'
  )
  into actor_name
  from (select 1) as anchor
  left join public.profiles as profile on profile.id = actor;

  -- Spelled out ("Friday, October 9") so it reads the same in every country this CRM serves.
  due_text := case when first_task.due_on is not null
    then ' Due ' || to_char(first_task.due_on, 'FMDay, FMMonth FMDD') || '.' else '' end;

  if task_count = 1 then
    alert_title := actor_name || ' gave you a Task: ' || btrim(first_task.title);
    alert_body := 'On ' || coalesce(nullif(btrim(first_task.card_title), ''), 'a pipeline card') || '.'
      || due_text;
  else
    alert_title := actor_name || ' gave you ' || task_count || ' new Tasks: ' || btrim(first_task.title);
    alert_body := 'On ' || card_count || ' pipeline cards.' || due_text;
  end if;

  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_state
  ) values (
    first_task.organization_id,
    first_task.assignee_user_id,
    'pipeline.task_assigned',
    case when task_count = 1 then 'opportunity' else 'task_batch' end,
    case when task_count = 1 then first_task.opportunity_id else first_task.id end,
    left(alert_title, 200),
    left(alert_body, 500),
    -- A Task handed away and back again is a new assignment, so the key carries the moment, not only the Task.
    left('task_assigned:' || first_task.id || ':' || first_task.assignee_user_id || ':'
      || extract(epoch from clock_timestamp()), 200),
    'pending'
  )
  on conflict (organization_id, user_id, source_key) do nothing;
end;
$$;

revoke all on function private.alert_task_assignment(uuid[]) from public, anon, authenticated;

-- 3. Creating a Task ----------------------------------------------------------------------------------------
--
-- The insert moves to a private function so the bulk tool can create its Tasks through the same rules and
-- then send one combined alert. The public function keeps its signature, so its grants stand.

create function private.pipeline_insert_task(
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

revoke all on function private.pipeline_insert_task(uuid, text, text, uuid, date) from public, anon, authenticated;

create or replace function public.pipeline_create_opportunity_task(
  target_opportunity_id uuid,
  new_title text,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
)
returns table (
  id uuid, opportunity_id uuid, title text, instructions text, assignee_user_id uuid, due_on date,
  status text, completed_at timestamptz, completed_by uuid, created_by uuid, created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created public.tasks := private.pipeline_insert_task(
    target_opportunity_id, new_title, new_instructions, new_assignee_user_id, new_due_on
  );
begin
  perform private.alert_task_assignment(array[created.id]);

  return query select
    created.id, created.opportunity_id, created.title, created.instructions, created.assignee_user_id,
    created.due_on, created.status, created.completed_at, created.completed_by, created.created_by,
    created.created_at, created.updated_at;
end;
$$;

-- 4. Editing a Task -----------------------------------------------------------------------------------------
--
-- Unchanged except the alert: it goes out only when the Task now belongs to somebody it did not before.

create or replace function public.pipeline_update_opportunity_task(
  target_task_id uuid,
  new_title text,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
)
returns table (
  id uuid, opportunity_id uuid, title text, instructions text, assignee_user_id uuid, due_on date,
  status text, completed_at timestamptz, completed_by uuid, created_by uuid, created_at timestamptz,
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

-- 5. Bulk Tasks: one combined alert --------------------------------------------------------------------------
--
-- Unchanged from 20261003140000 except that a Task is created through the private insert (no alert per card)
-- and the Tasks that were made are announced once at the end. Same signature, so the grants stand.

create or replace function public.pipeline_bulk_update(
  target_opportunity_ids uuid[],
  bulk_action text,
  new_owner_user_id uuid default null,
  target_custom_stage_id uuid default null,
  new_title text default null,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  card_ids uuid[];
  card_id uuid;
  placed jsonb;
  created_task public.tasks;
  created_task_ids uuid[] := '{}';
  results jsonb := '[]'::jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if bulk_action not in ('owner', 'task', 'place') then
    raise exception 'Unknown bulk change.' using errcode = 'invalid_parameter_value';
  end if;

  select array_agg(distinct listed.id order by listed.id)
  into card_ids
  from unnest(target_opportunity_ids) as listed(id)
  where listed.id is not null;

  if coalesce(cardinality(card_ids), 0) = 0 then
    raise exception 'Pick at least one card.' using errcode = 'invalid_parameter_value';
  end if;
  if cardinality(card_ids) > 50 then
    raise exception 'Change 50 cards or fewer at a time.' using errcode = 'program_limit_exceeded';
  end if;

  foreach card_id in array card_ids loop
    begin
      if bulk_action = 'owner' then
        perform public.pipeline_update_opportunity_details(
          target_opportunity_id => card_id,
          set_owner => true,
          new_owner_user_id => new_owner_user_id
        );
        results := results || jsonb_build_object('id', card_id, 'status', 'done');

      elsif bulk_action = 'task' then
        created_task := private.pipeline_insert_task(
          card_id, new_title, new_instructions, new_assignee_user_id, new_due_on
        );
        created_task_ids := created_task_ids || created_task.id;
        results := results || jsonb_build_object('id', card_id, 'status', 'done');

      else
        placed := public.pipeline_place_opportunity(card_id, target_custom_stage_id);
        results := results || jsonb_build_object(
          'id', card_id,
          'status', case when (placed ->> 'applied')::boolean then 'done' else 'unchanged' end
        );
      end if;
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;

      results := results || jsonb_build_object(
        'id', card_id,
        'status', 'refused',
        -- The single-card refusals written for a person pass through as they are. A missing or foreign
        -- card reads the same as one this person may not change, and anything unexpected is not shown.
        'reason', case
          when failed_state in ('23514', '54000') then failed_message
          when failed_state = '42501' then 'This card could not be found.'
          else 'Something went wrong with this card. Try it on its own.'
        end,
        'code', nullif(failed_hint, '')
      );
    end;
  end loop;

  perform private.alert_task_assignment(created_task_ids);

  return results;
end;
$$;

-- 6. Who is emailed ---------------------------------------------------------------------------------------
--
-- The email worker skipped anyone who could not see every website inquiry -- right for inquiry alerts, but it
-- would have silently dropped every Task email to a salesperson. A Task alert is emailed while its person is
-- still an active member of an active business who may see the Pipeline (the rule every assignee meets).

create function private.member_receives_task_alerts(p_organization_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
      select 1
      from public.organization_members as membership
      join public.organizations as organization on organization.id = membership.organization_id
      where membership.organization_id = p_organization_id
        and membership.user_id = p_user_id
        and membership.status = 'active'
        and organization.lifecycle_status = 'active'
    )
    and private.member_has_permission(p_organization_id, p_user_id, 'pipeline.view');
$$;

revoke all on function private.member_receives_task_alerts(uuid, uuid) from public, anon, authenticated;

-- Unchanged from the baseline except which rule decides who is emailed. Same signature, so the grant stands.
create or replace function public.claim_team_notification_emails(
  p_batch_size integer default 25,
  p_lease_seconds integer default 120
)
returns table (
  notification_id uuid, claim_token uuid, organization_id uuid, organization_name text, recipient_email text,
  kind text, subject_type text, subject_id uuid, title text, body text, attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  token uuid;
  receives boolean;
begin
  if p_batch_size < 1 or p_batch_size > 100 or p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The alert email claim is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select q.id, q.organization_id, q.user_id, q.kind, q.subject_type, q.subject_id, q.title, q.body,
      q.email_attempts, o.name as organization_name, nullif(btrim(u.email), '') as email
    from public.team_notifications as q
    join public.organizations as o on o.id = q.organization_id
    left join auth.users as u on u.id = q.user_id
    where q.email_state = 'pending' and q.email_available_at <= now()
      and (q.email_claimed_until is null or q.email_claimed_until < now())
    order by q.email_available_at, q.id
    limit p_batch_size
    for update of q skip locked
  loop
    -- Set first: PL/pgSQL ends an IF condition at its first THEN, so a CASE cannot sit inside one.
    receives := case when candidate.kind = 'pipeline.task_assigned'
      then private.member_receives_task_alerts(candidate.organization_id, candidate.user_id)
      else private.member_receives_inquiry_alerts(candidate.organization_id, candidate.user_id)
    end;

    if candidate.email is null or not receives then
      update public.team_notifications
      set email_state = 'not_needed', email_claim_token = null, email_claimed_until = null
      where id = candidate.id;
      continue;
    end if;

    token := gen_random_uuid();
    update public.team_notifications
    set email_claim_token = token, email_claimed_until = now() + make_interval(secs => p_lease_seconds)
    where id = candidate.id;

    notification_id := candidate.id;
    claim_token := token;
    organization_id := candidate.organization_id;
    organization_name := candidate.organization_name;
    recipient_email := candidate.email;
    kind := candidate.kind;
    subject_type := candidate.subject_type;
    subject_id := candidate.subject_id;
    title := candidate.title;
    body := candidate.body;
    attempts := candidate.email_attempts;
    return next;
  end loop;
end;
$$;
