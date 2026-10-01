-- Pipeline part C3: owners set the warning days, and a customer's reply counts as progress.
--
-- Product truth: docs/sales-pipeline-behavior-contract.md, § First-release board — "A separate inactivity
-- warning uses an owner-configurable number of days for each stage" and "The inactivity clock resets only
-- for genuine progress: a customer reply, …". Industry reference: Pipedrive's per-stage "rotting" days, set
-- by an admin in each stage's settings; HubSpot's habit of counting a contact's reply on that contact's open
-- deals. Logged calls wait for the Call button (part E4, Jafar 2026-10-01).
--
-- 1. organization_settings.pipeline_inactivity_days holds the seven built-in stages' days.
-- 2. pipeline_custom_stages.inactivity_days holds each custom stage's own.
-- 3. save_pipeline_settings saves both with the rest of Settings → Pipeline.
-- 4. A customer's email, text, or website chat message restarts the progress clock (`progress_at`, part C2)
--    on that customer's open cards.
--
-- The board still works the warning out in the browser; nothing here rewrites a card because time passed.
-- An on-hold card's quiet spell is worked out there too, from its open Task's due date.

-- 1. The built-in stages' days ------------------------------------------------------------------------------

-- Exactly the seven protected stages, each a whole number of days from 1 to 365.
create function private.pipeline_inactivity_days_valid(days jsonb) returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select jsonb_typeof(days) = 'object'
    and (select array_agg(key order by key) from jsonb_object_keys(days) as key) = array[
      'assessment_completed', 'assessment_scheduled', 'assessment_unscheduled', 'new_request',
      'quote_awaiting_response', 'quote_changes_requested', 'quote_draft'
    ]::text[]
    and not exists (
      select 1
      from jsonb_each(days) as entry
      where jsonb_typeof(entry.value) <> 'number'
        or entry.value::numeric <> trunc(entry.value::numeric)
        or entry.value::numeric not between 1 and 365
    );
$$;

revoke all on function private.pipeline_inactivity_days_valid(jsonb) from public, anon, authenticated;

-- The plan's defaults.
alter table public.organization_settings
  add column pipeline_inactivity_days jsonb not null default '{
    "new_request": 1,
    "assessment_unscheduled": 2,
    "assessment_scheduled": 2,
    "assessment_completed": 2,
    "quote_draft": 2,
    "quote_awaiting_response": 5,
    "quote_changes_requested": 2
  }'::jsonb
  constraint organization_settings_pipeline_inactivity_days_valid
    check (private.pipeline_inactivity_days_valid(pipeline_inactivity_days));

comment on column public.organization_settings.pipeline_inactivity_days is
  'Pipeline part C3. Days without real progress before a card in each built-in stage shows the inactivity warning, by stage. Saved through public.save_pipeline_settings.';

grant select (pipeline_inactivity_days) on table public.organization_settings to authenticated;

-- 2. Each custom stage's days -------------------------------------------------------------------------------

alter table public.pipeline_custom_stages
  add column inactivity_days integer not null default 2
  constraint pipeline_custom_stages_inactivity_days_range check (inactivity_days between 1 and 365);

comment on column public.pipeline_custom_stages.inactivity_days is
  'Pipeline part C3. Days without real progress before a card in this stage shows the inactivity warning. An on-hold stage stays quiet until the card''s open Task falls due, then counts these days as usual.';

-- Until now a card in a custom stage was judged by its real stage. The stage it follows is the nearest
-- honest starting point, and every organization is still on the defaults.
update public.pipeline_custom_stages
set inactivity_days = case after_stage
  when 'new_request' then 1
  when 'quote_awaiting_response' then 5
  else 2
end;

-- 3. Saving Settings → Pipeline -----------------------------------------------------------------------------

-- The 20261001234000 version, with the built-in days as a new argument and each stage's own days. The
-- argument list changes, so the old function goes rather than living on beside it.
drop function public.save_pipeline_settings(uuid, integer, boolean, jsonb);

create function public.save_pipeline_settings(
  target_organization_id uuid,
  expected_revision integer,
  new_detailed_assessment_stages boolean,
  new_stages jsonb,
  new_inactivity_days jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  settings_row public.organization_settings;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
  updated_count integer;
  inserted_count integer;
  changed text[] := '{}';
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_detailed_assessment_stages is null then
    raise exception 'Choose whether to show the detailed assessment stages.'
      using errcode = 'check_violation';
  end if;

  if new_stages is null or jsonb_typeof(new_stages) <> 'array' then
    raise exception 'The list of stages is missing.' using errcode = 'check_violation';
  end if;

  if new_inactivity_days is null or not private.pipeline_inactivity_days_valid(new_inactivity_days) then
    raise exception 'Each stage needs a warning of 1 to 365 days.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ? 'inactivity_days'
      and (
        jsonb_typeof(item.stage -> 'inactivity_days') <> 'number'
        or (item.stage ->> 'inactivity_days')::numeric <> trunc((item.stage ->> 'inactivity_days')::numeric)
        or (item.stage ->> 'inactivity_days')::numeric not between 1 and 365
      )
  ) then
    raise exception 'Each stage needs a warning of 1 to 365 days.' using errcode = 'check_violation';
  end if;

  -- The settings row is the lock: two people saving the pipeline at once go one after the other.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  -- Somebody else saved first. The caller is told who and when, so it can offer to reload rather than
  -- silently overwrite a change it never saw.
  if expected_revision is distinct from settings_row.pipeline_revision then
    select profile.full_name, settings_row.pipeline_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.pipeline_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  -- Jobber's documented ceiling. The list is every enabled stage, so its length is the count.
  if jsonb_array_length(new_stages) > 25 then
    raise exception 'A pipeline can have up to 25 custom stages.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    group by item.stage ->> 'section', lower(btrim(item.stage ->> 'name'))
    having count(*) > 1
  ) then
    raise exception 'Two stages in the same section cannot share a name.'
      using errcode = 'check_violation';
  end if;

  -- Every id has to be one of this organization's enabled stages, named once, and still in its own
  -- section. Every enabled stage has to be named. Either failing means the page was out of date.
  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ->> 'id' is not null
    group by item.stage ->> 'id'
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ->> 'id' is not null
      and not exists (
        select 1
        from public.pipeline_custom_stages as existing
        where existing.organization_id = target_organization_id
          and existing.disabled_at is null
          and existing.id = (item.stage ->> 'id')::uuid
          and existing.section = item.stage ->> 'section'
      )
  ) or exists (
    select 1
    from public.pipeline_custom_stages as existing
    where existing.organization_id = target_organization_id
      and existing.disabled_at is null
      and not exists (
        select 1
        from jsonb_array_elements(new_stages) as item(stage)
        where (item.stage ->> 'id')::uuid = existing.id
      )
  ) then
    raise exception 'These stages changed while you were editing. Refresh the page and try again.'
      using errcode = 'check_violation';
  end if;

  -- Renames are checked once the whole list is in place, so two stages may swap names in one save.
  set constraints public.pipeline_custom_stages_name_unique deferred;

  -- A stage sent without its days keeps the ones it has.
  update public.pipeline_custom_stages as existing
  set
    name = btrim(item.stage ->> 'name'),
    after_stage = item.stage ->> 'after_stage',
    position = (item.ordinal - 1)::integer,
    requires_future_task = coalesce((item.stage ->> 'requires_future_task')::boolean, false),
    inactivity_days = coalesce((item.stage ->> 'inactivity_days')::integer, existing.inactivity_days)
  from jsonb_array_elements(new_stages) with ordinality as item(stage, ordinal)
  where existing.organization_id = target_organization_id
    and existing.disabled_at is null
    and existing.id = (item.stage ->> 'id')::uuid
    and (
      existing.name, existing.after_stage, existing.position, existing.requires_future_task,
      existing.inactivity_days
    ) is distinct from (
      btrim(item.stage ->> 'name'),
      item.stage ->> 'after_stage',
      (item.ordinal - 1)::integer,
      coalesce((item.stage ->> 'requires_future_task')::boolean, false),
      coalesce((item.stage ->> 'inactivity_days')::integer, existing.inactivity_days)
    );
  get diagnostics updated_count = row_count;

  -- A new stage sent without days takes those of the built-in stage it follows.
  insert into public.pipeline_custom_stages (
    organization_id, section, name, after_stage, position, requires_future_task, inactivity_days,
    created_by
  )
  select
    target_organization_id,
    item.stage ->> 'section',
    btrim(item.stage ->> 'name'),
    item.stage ->> 'after_stage',
    (item.ordinal - 1)::integer,
    coalesce((item.stage ->> 'requires_future_task')::boolean, false),
    coalesce(
      (item.stage ->> 'inactivity_days')::integer,
      (new_inactivity_days ->> (item.stage ->> 'after_stage'))::integer
    ),
    (select auth.uid())
  from jsonb_array_elements(new_stages) with ordinality as item(stage, ordinal)
  where item.stage ->> 'id' is null
  order by item.ordinal;
  get diagnostics inserted_count = row_count;

  set constraints public.pipeline_custom_stages_name_unique immediate;

  update public.organization_settings
  set
    pipeline_detailed_assessment_stages = new_detailed_assessment_stages,
    pipeline_inactivity_days = new_inactivity_days,
    pipeline_revision = pipeline_revision + 1,
    pipeline_updated_by = (select auth.uid()),
    pipeline_updated_at = now()
  where organization_id = target_organization_id
  returning pipeline_revision into new_revision;

  if new_detailed_assessment_stages
     is distinct from settings_row.pipeline_detailed_assessment_stages then
    changed := array_append(changed, 'pipeline_detailed_assessment_stages');
  end if;
  if new_inactivity_days is distinct from settings_row.pipeline_inactivity_days then
    changed := array_append(changed, 'pipeline_inactivity_days');
  end if;
  if updated_count + inserted_count > 0 then
    changed := array_append(changed, 'pipeline_custom_stages');
  end if;

  if cardinality(changed) > 0 then
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (target_organization_id, 'pipeline', changed, (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'pipeline_revision', new_revision,
    'pipeline_detailed_assessment_stages', new_detailed_assessment_stages
  );
end;
$$;

revoke all on function public.save_pipeline_settings(uuid, integer, boolean, jsonb, jsonb)
  from public, anon;
grant execute on function public.save_pipeline_settings(uuid, integer, boolean, jsonb, jsonb)
  to authenticated, service_role;

-- 4. A customer's reply is progress -------------------------------------------------------------------------
--
-- Only a real message from a known customer counts: an email or text the inbox accepted as a reply from
-- that client (never an out-of-office, a bounce notice, a mail loop, or one still waiting for somebody to
-- say who sent it), or a website chat message from a visitor who is that client.
--
-- Which cards: a reply to a quote email moves that quote's card; anything else moves every open card the
-- customer has, the way HubSpot counts a contact's reply on their open deals. The clock takes the time the
-- customer wrote, never later than it already reads, so a message matched to its client days afterwards
-- cannot push a card's clock backwards or pretend the customer wrote today.

create function private.opportunity_record_customer_reply() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  replied_quote_id uuid;
begin
  if tg_table_name = 'communication_inbound_messages' and new.in_reply_to_intent_id is not null then
    select intent.quote_id into replied_quote_id
    from public.communication_delivery_intents as intent
    where intent.id = new.in_reply_to_intent_id
      and intent.organization_id = new.organization_id;

    if replied_quote_id is not null then
      update public.opportunities
      set progress_at = greatest(progress_at, new.created_at)
      where organization_id = new.organization_id
        and quote_id = replied_quote_id
        and client_id = new.client_id
        and outcome = 'open';

      if found then
        return null;
      end if;
    end if;
  end if;

  update public.opportunities
  set progress_at = greatest(progress_at, new.created_at)
  where organization_id = new.organization_id
    and client_id = new.client_id
    and outcome = 'open'
    and stage <> 'request_closed'
    and progress_at < new.created_at;

  return null;
end;
$$;

revoke all on function private.opportunity_record_customer_reply() from public, anon, authenticated;

create trigger inbound_messages_record_opportunity_progress
  after insert on public.communication_inbound_messages
  for each row
  when (new.message_kind = 'reply' and new.review_status = 'accepted' and new.client_id is not null)
  execute function private.opportunity_record_customer_reply();

-- A message held for review counts once somebody says which customer sent it.
create trigger inbound_messages_resolved_record_opportunity_progress
  after update of review_status, client_id on public.communication_inbound_messages
  for each row
  when (
    new.message_kind = 'reply'
    and new.review_status = 'accepted'
    and new.client_id is not null
    and (old.review_status <> 'accepted' or old.client_id is distinct from new.client_id)
  )
  execute function private.opportunity_record_customer_reply();

create trigger website_chat_messages_record_opportunity_progress
  after insert on public.website_chat_messages
  for each row
  when (new.sender_type = 'visitor' and new.client_id is not null)
  execute function private.opportunity_record_customer_reply();

-- A chat waiting for review joins its customer later, every message at once.
create trigger website_chat_messages_matched_record_opportunity_progress
  after update of client_id on public.website_chat_messages
  for each row
  when (
    new.sender_type = 'visitor'
    and new.client_id is not null
    and old.client_id is distinct from new.client_id
  )
  execute function private.opportunity_record_customer_reply();
