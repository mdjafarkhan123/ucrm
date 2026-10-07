-- Jafar business management B3: approving who to contact.
--
-- 1. Approval belongs to one contact detail: who approved it, when, and the exact text approved. A detail whose
--    text later changes, or that is removed, is no longer approved. A WhatsApp number can only be approved with
--    the business's permission recorded (WhatsApp's own rule).
-- 2. Do not contact covers the whole business, with who set it and when; it withdraws every approval.
-- 3. A Lead becomes 'approved' only through owner_lead_approve. Approving makes the next action a first-contact
--    task, due on the day Jafar picks; logging any outbound contact ticks it off.
-- 4. owner_lead_review_queue: the Leads ready for review, oldest first, with what Jafar needs to decide.
-- Nothing here sends a message.
begin;

-- 1. Columns ------------------------------------------------------------------------------------------------

alter table public.platform_business_contact_methods
  add column approved_at timestamptz,
  add column approved_by_email text,
  -- The text as approved. When `value` no longer matches it, the approval is withdrawn.
  add column approved_value text,
  add column whatsapp_permission boolean not null default false,
  add constraint platform_business_contact_methods_approval_shape check (
    (approved_at is null) = (approved_by_email is null)
    and (approved_at is null) = (approved_value is null)
  ),
  add constraint platform_business_contact_methods_whatsapp_permission_check check (
    not whatsapp_permission or (approved_at is not null and kind = 'whatsapp')
  );

comment on column public.platform_business_contact_methods.approved_at is
  'When Jafar approved this detail for first contact (B3). Null: not approved.';
comment on column public.platform_business_contact_methods.whatsapp_permission is
  'The business asked to talk on WhatsApp; required before a WhatsApp number can be approved.';

alter table public.platform_business_relationships
  add column do_not_contact_at timestamptz,
  add column do_not_contact_by_email text,
  add column do_not_contact_reason text,
  -- 'first_contact': the next action approval created. Any other change to the next action clears it.
  add column next_action_kind text,
  add constraint platform_business_relationships_do_not_contact_shape check (
    (do_not_contact_at is null) = (do_not_contact_by_email is null)
    and (do_not_contact_at is not null or do_not_contact_reason is null)
    and (do_not_contact_reason is null
      or (do_not_contact_reason = btrim(do_not_contact_reason) and char_length(do_not_contact_reason) between 1 and 500))
  ),
  add constraint platform_business_relationships_next_action_kind_check check (
    next_action_kind is null or (next_action_kind = 'first_contact' and next_action is not null)
  );

alter table public.platform_business_relationships drop constraint platform_business_relationships_status_check;
alter table public.platform_business_relationships add constraint platform_business_relationships_status_check check (
  lead_status in ('new', 'researching', 'ready_for_review', 'approved', 'unsuitable', 'later')
  -- A business that asked not to be contacted is never approved for contact.
  and (lead_status <> 'approved' or do_not_contact_at is null)
);

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed',
    'contact_approved', 'approval_withdrawn', 'sent_back', 'do_not_contact_set', 'do_not_contact_cleared'
  )
);

-- The review queue: Leads ready for review, oldest first.
create index platform_business_relationships_review_idx
  on public.platform_business_relationships (created_at, id) where lead_status = 'ready_for_review';

-- 2. Shared steps -------------------------------------------------------------------------------------------

-- Withdraw approvals and record which. only_stale: just those whose text changed or that were removed; if that
-- leaves an Approved Lead with nothing approved, it goes back to Ready for review. Callers hold the Lead's lock.
create or replace function private.lead_withdraw_approvals(
  target_id uuid,
  actor text,
  reason text,
  only_stale boolean
)
returns integer
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  withdrawn jsonb;
  withdrawn_count integer;
begin
  with w as (
    update public.platform_business_contact_methods m
    set approved_at = null, approved_by_email = null, approved_value = null, whatsapp_permission = false
    where m.relationship_id = target_id and m.approved_at is not null
      and (not only_stale or m.removed_at is not null or m.value is distinct from m.approved_value)
    returning m.kind, m.value, m.position, m.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'value', value) order by position, created_at), '[]'::jsonb),
    count(*)
  into withdrawn, withdrawn_count
  from w;

  if withdrawn_count = 0 then
    return 0;
  end if;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_id, 'approval_withdrawn', jsonb_build_object('reason', reason, 'methods', withdrawn), actor);

  if only_stale and not exists (
    select 1 from public.platform_business_contact_methods
    where relationship_id = target_id and approved_at is not null
  ) and exists (
    select 1 from public.platform_business_relationships where id = target_id and lead_status = 'approved'
  ) then
    update public.platform_business_relationships set lead_status = 'ready_for_review' where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'status_changed', jsonb_build_object('from', 'approved', 'to', 'ready_for_review'), actor);
    perform private.lead_clear_first_contact(target_id, actor);
  end if;

  return withdrawn_count;
end;
$function$;

-- Remove the first-contact task approval created, if it is still the next action.
create or replace function private.lead_clear_first_contact(target_id uuid, actor text)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  current_row public.platform_business_relationships%rowtype;
begin
  select * into current_row from public.platform_business_relationships
  where id = target_id and next_action_kind = 'first_contact';
  if not found then
    return;
  end if;
  update public.platform_business_relationships
  set next_action = null, next_action_due_on = null, next_action_kind = null
  where id = target_id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_id, 'next_action_cleared',
    jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on), actor);
end;
$function$;

-- Is this business already a client: a linked Application that was paid or has its account?
create or replace function private.lead_is_client(target_id uuid)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public'
as $function$
  select exists (
    select 1 from public.platform_onboarding_applications a
    where a.business_relationship_id = target_id and a.stage in ('payment_confirmed', 'account_created')
  );
$function$;

revoke all on function private.lead_withdraw_approvals(uuid, text, text, boolean) from public, anon, authenticated;
revoke all on function private.lead_clear_first_contact(uuid, text) from public, anon, authenticated;
revoke all on function private.lead_is_client(uuid) from public, anon, authenticated;

-- 3. Approving ----------------------------------------------------------------------------------------------

-- Approve exactly these details for first contact (details approved before and not listed lose approval).
-- whatsapp_permission_ids: the WhatsApp numbers whose business asked to talk there. Returns 'approved' or
-- 'lead_not_found'; a refusal is an exception with errcode 22023 and a message for Jafar.
create or replace function public.owner_lead_approve(
  actor_email text,
  target_id uuid,
  method_ids uuid[],
  task_due_on date,
  whatsapp_permission_ids uuid[] default '{}'::uuid[]
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  chosen uuid[] := coalesce(method_ids, '{}'::uuid[]);
  permitted uuid[] := coalesce(whatsapp_permission_ids, '{}'::uuid[]);
  current_row public.platform_business_relationships%rowtype;
  approved jsonb;
  task text;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if cardinality(chosen) = 0 then
    raise exception 'Choose at least one contact detail to approve.' using errcode = '22023';
  end if;
  if task_due_on is null then
    raise exception 'Choose when the first contact is due.' using errcode = '22023';
  end if;
  if not permitted <@ chosen then
    raise exception 'WhatsApp permission can only be recorded for a number being approved.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return 'lead_not_found';
  end if;
  if current_row.do_not_contact_at is not null then
    raise exception 'This business asked not to be contacted.' using errcode = '22023';
  end if;
  if private.lead_is_client(target_id) then
    raise exception 'This business is already a client.' using errcode = '22023';
  end if;
  if (
    select count(*) from public.platform_business_contact_methods
    where relationship_id = target_id and removed_at is null and id = any(chosen)
  ) <> (select count(distinct x) from unnest(chosen) x) then
    raise exception 'A contact detail you chose was just changed or removed. Reload and try again.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.platform_business_contact_methods
    where id = any(chosen) and kind = 'whatsapp' and not (id = any(permitted))
  ) then
    raise exception 'WhatsApp needs their permission first. Tick "They asked to talk on WhatsApp" if they did.'
      using errcode = '22023';
  end if;

  -- Narrowing an earlier approval.
  update public.platform_business_contact_methods
  set approved_at = null, approved_by_email = null, approved_value = null, whatsapp_permission = false
  where relationship_id = target_id and approved_at is not null and not (id = any(chosen));

  update public.platform_business_contact_methods
  set approved_at = now(), approved_by_email = actor, approved_value = value, whatsapp_permission = id = any(permitted)
  where id = any(chosen);

  select
    jsonb_agg(jsonb_build_object('kind', kind, 'value', value, 'whatsapp_permission', whatsapp_permission)
      order by position, created_at),
    'First contact: ' || string_agg(
      case kind
        when 'email' then 'email '
        when 'phone' then 'call '
        when 'whatsapp' then 'WhatsApp '
        when 'instagram' then 'Instagram '
        when 'facebook' then 'Facebook '
        when 'linkedin' then 'LinkedIn '
        when 'contact_form' then 'contact form '
        else ''
      end || value,
      ' or ' order by position, created_at)
  into approved, task
  from public.platform_business_contact_methods
  where id = any(chosen);

  if char_length(task) > 200 then
    task := left(task, 199) || '…';
  end if;

  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_id, 'contact_approved', jsonb_build_object('methods', approved), actor);

  if current_row.lead_status <> 'approved' then
    update public.platform_business_relationships set lead_status = 'approved' where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'status_changed', jsonb_build_object('from', current_row.lead_status, 'to', 'approved'), actor);
  end if;

  update public.platform_business_relationships
  set next_action = task, next_action_due_on = task_due_on, next_action_kind = 'first_contact'
  where id = target_id;
  if (task, task_due_on) is distinct from (current_row.next_action, current_row.next_action_due_on) then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'next_action_set', jsonb_build_object('next_action', task, 'due_on', task_due_on), actor);
  end if;

  return 'approved';
end;
$function$;

revoke all on function public.owner_lead_approve(text, uuid, uuid[], date, uuid[]) from public, anon, authenticated;
grant execute on function public.owner_lead_approve(text, uuid, uuid[], date, uuid[]) to service_role;

-- Send a Lead back to research with a reason. Returns 'sent_back' or 'lead_not_found'.
create or replace function public.owner_lead_send_back(actor_email text, target_id uuid, reason text)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  why text := nullif(btrim(coalesce(reason, '')), '');
  current_row public.platform_business_relationships%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if why is null or char_length(why) > 500 then
    raise exception 'Say what needs fixing, in up to 500 characters.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return 'lead_not_found';
  end if;

  perform private.lead_withdraw_approvals(target_id, actor, 'sent_back', false);
  perform private.lead_clear_first_contact(target_id, actor);
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_id, 'sent_back', jsonb_build_object('reason', why), actor);
  if current_row.lead_status <> 'researching' then
    update public.platform_business_relationships set lead_status = 'researching' where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'status_changed', jsonb_build_object('from', current_row.lead_status, 'to', 'researching'), actor);
  end if;
  return 'sent_back';
end;
$function$;

revoke all on function public.owner_lead_send_back(text, uuid, text) from public, anon, authenticated;
grant execute on function public.owner_lead_send_back(text, uuid, text) to service_role;

-- 4. Do not contact -----------------------------------------------------------------------------------------

-- Turn it on (withdraws every approval and the first-contact task; an Approved Lead becomes Unsuitable) or off.
-- Returns 'updated', 'unchanged' or 'lead_not_found'.
create or replace function public.owner_lead_set_do_not_contact(
  actor_email text,
  target_id uuid,
  turn_on boolean,
  reason text default null
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  why text := nullif(btrim(coalesce(reason, '')), '');
  current_row public.platform_business_relationships%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if turn_on is null then
    raise exception 'Say whether to turn Do not contact on or off.' using errcode = '22023';
  end if;
  if why is not null and char_length(why) > 500 then
    raise exception 'Keep the reason to 500 characters.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return 'lead_not_found';
  end if;
  if (current_row.do_not_contact_at is not null) = turn_on then
    return 'unchanged';
  end if;

  if turn_on then
    perform private.lead_withdraw_approvals(target_id, actor, 'do_not_contact', false);
    perform private.lead_clear_first_contact(target_id, actor);
    if current_row.lead_status = 'approved' then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'status_changed', jsonb_build_object('from', 'approved', 'to', 'unsuitable'), actor);
    end if;
    update public.platform_business_relationships
    set do_not_contact_at = now(), do_not_contact_by_email = actor, do_not_contact_reason = why,
      lead_status = case when lead_status = 'approved' then 'unsuitable' else lead_status end
    where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'do_not_contact_set', jsonb_strip_nulls(jsonb_build_object('reason', why)), actor);
  else
    update public.platform_business_relationships
    set do_not_contact_at = null, do_not_contact_by_email = null, do_not_contact_reason = null
    where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'do_not_contact_cleared', jsonb_strip_nulls(jsonb_build_object('reason', why)), actor);
  end if;
  return 'updated';
end;
$function$;

revoke all on function public.owner_lead_set_do_not_contact(text, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.owner_lead_set_do_not_contact(text, uuid, boolean, text) to service_role;

-- 5. Logging the first contact ticks the task off -----------------------------------------------------------

create or replace function private.platform_business_history_first_contact_done()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  current_row public.platform_business_relationships%rowtype;
begin
  select * into current_row from public.platform_business_relationships
  where id = new.relationship_id and next_action_kind = 'first_contact'
  for update;
  if found then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (new.relationship_id, 'next_action_done',
      jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on),
      new.actor_email);
    update public.platform_business_relationships
    set next_action = null, next_action_due_on = null, next_action_kind = null
    where id = new.relationship_id;
  end if;
  return null;
end;
$function$;

revoke all on function private.platform_business_history_first_contact_done() from public, anon, authenticated;

create trigger platform_business_history_first_contact_done
  after insert on public.platform_business_history
  for each row
  when (new.kind = 'contact' and new.contact_direction = 'outbound')
  execute function private.platform_business_history_first_contact_done();

-- 5b. Existing Lead functions ------------------------------------------------------------------------------

-- owner_lead_change: Approved is set only by approval; leaving it withdraws approvals; a next action set by hand
-- is no longer the first-contact task.
create or replace function public.owner_lead_change(
  actor_email text,
  target_id uuid,
  target_status text default null,
  next_action_mode text default 'keep',
  target_next_action text default null,
  target_due_on date default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  current_row public.platform_business_relationships%rowtype;
  new_action text := nullif(btrim(coalesce(target_next_action, '')), '');
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if next_action_mode not in ('keep', 'set', 'done', 'clear') then
    raise exception 'Unknown next action change.' using errcode = '22023';
  end if;
  if (new_action is null) <> (target_due_on is null) then
    raise exception 'A next action needs both what and when.' using errcode = '22023';
  end if;
  if next_action_mode = 'set' and new_action is null then
    raise exception 'Say what the next action is.' using errcode = '22023';
  end if;
  if next_action_mode in ('keep', 'clear') and new_action is not null then
    raise exception 'A new next action is only given when setting one.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return false;
  end if;

  if next_action_mode = 'done' and current_row.next_action is null then
    raise exception 'There is no next action to mark done.' using errcode = '22023';
  end if;
  -- B3: Approved means Jafar approved contact details; only owner_lead_approve sets it.
  if target_status = 'approved' and current_row.lead_status <> 'approved' then
    raise exception 'Approve who to contact from the review queue.' using errcode = '22023';
  end if;

  if target_status is not null and target_status is distinct from current_row.lead_status then
    update public.platform_business_relationships set lead_status = target_status where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'status_changed',
      jsonb_build_object('from', current_row.lead_status, 'to', target_status), actor);
    -- Leaving Approved withdraws the approvals and, unless a next action is given now, the first-contact task.
    if current_row.lead_status = 'approved' then
      perform private.lead_withdraw_approvals(target_id, actor, 'status_changed', false);
      if next_action_mode = 'keep' then
        perform private.lead_clear_first_contact(target_id, actor);
      end if;
    end if;
  end if;

  if next_action_mode = 'clear' then
    if current_row.next_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_cleared',
        jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on), actor);
      update public.platform_business_relationships
      set next_action = null, next_action_due_on = null, next_action_kind = null
      where id = target_id;
    end if;
  elsif next_action_mode = 'done' then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'next_action_done',
      jsonb_build_object('next_action', current_row.next_action, 'due_on', current_row.next_action_due_on), actor);
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on, next_action_kind = null
    where id = target_id;
    if new_action is not null then
      insert into public.platform_business_history (relationship_id, kind, details, actor_email)
      values (target_id, 'next_action_set',
        jsonb_build_object('next_action', new_action, 'due_on', target_due_on), actor);
    end if;
  elsif next_action_mode = 'set'
    and (new_action, target_due_on) is distinct from (current_row.next_action, current_row.next_action_due_on) then
    update public.platform_business_relationships
    set next_action = new_action, next_action_due_on = target_due_on, next_action_kind = null
    where id = target_id;
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (target_id, 'next_action_set',
      jsonb_build_object('next_action', new_action, 'due_on', target_due_on), actor);
  end if;

  return true;
end;
$function$;
-- owner_lead_update_details: an approved detail whose text changed, or that was removed, loses its approval.
create or replace function public.owner_lead_update_details(
  actor_email text,
  target_id uuid,
  fields jsonb default '{}'::jsonb,
  contact_methods jsonb default '{}'::jsonb
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  f jsonb := coalesce(fields, '{}'::jsonb);
  ops jsonb := coalesce(contact_methods, '{}'::jsonb);
  current_row public.platform_business_relationships%rowtype;
  new_row public.platform_business_relationships%rowtype;
  changes jsonb := '[]'::jsonb;
  item jsonb;
  old_method public.platform_business_contact_methods%rowtype;
  next_position smallint;
  active_count integer;
  column_name text;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if jsonb_typeof(f) <> 'object' or jsonb_typeof(ops) <> 'object' then
    raise exception 'The changes are not in the expected shape.' using errcode = '22023';
  end if;

  select * into current_row from public.platform_business_relationships where id = target_id for update;
  if not found then
    return 'lead_not_found';
  end if;

  -- Business and About fields.
  new_row := current_row;
  if f ? 'business_name' then new_row.business_name := btrim(f ->> 'business_name'); end if;
  if f ? 'country_code' then new_row.country_code := upper(btrim(f ->> 'country_code')); end if;
  if f ? 'trade' then new_row.trade := btrim(f ->> 'trade'); end if;
  if f ? 'website' then new_row.website := nullif(btrim(f ->> 'website'), ''); end if;
  if f ? 'contact_name' then new_row.contact_name := nullif(btrim(f ->> 'contact_name'), ''); end if;
  if f ? 'source' then new_row.source := f ->> 'source'; end if;
  if f ? 'source_detail' then new_row.source_detail := nullif(btrim(f ->> 'source_detail'), ''); end if;
  if f ? 'fit_notes' then new_row.fit_notes := nullif(btrim(f ->> 'fit_notes'), ''); end if;

  foreach column_name in array array[
    'business_name', 'country_code', 'trade', 'website', 'contact_name', 'source', 'source_detail', 'fit_notes'
  ] loop
    if (to_jsonb(current_row) -> column_name) is distinct from (to_jsonb(new_row) -> column_name) then
      changes := changes || case
        -- Long notes are not copied into the history line.
        when column_name = 'fit_notes' then jsonb_build_array(jsonb_build_object('field', 'fit_notes'))
        else jsonb_build_array(jsonb_build_object(
          'field', column_name,
          'from', to_jsonb(current_row) -> column_name,
          'to', to_jsonb(new_row) -> column_name
        ))
      end;
    end if;
  end loop;

  if jsonb_array_length(changes) > 0 then
    update public.platform_business_relationships set
      business_name = new_row.business_name,
      country_code = new_row.country_code,
      trade = new_row.trade,
      website = new_row.website,
      contact_name = new_row.contact_name,
      source = new_row.source,
      source_detail = new_row.source_detail,
      fit_notes = new_row.fit_notes
    where id = target_id;
  end if;

  -- Removed details.
  for item in select * from jsonb_array_elements(coalesce(ops -> 'remove', '[]'::jsonb)) loop
    update public.platform_business_contact_methods
    set removed_at = now()
    where relationship_id = target_id and id = (item #>> '{}')::uuid and removed_at is null
    returning * into old_method;
    if found then
      changes := changes || jsonb_build_array(jsonb_build_object(
        'field', 'contact_method', 'action', 'removed', 'kind', old_method.kind, 'value', old_method.value
      ));
    end if;
  end loop;

  -- Corrected details: the same row, so history that used it reads the corrected text.
  for item in select * from jsonb_array_elements(coalesce(ops -> 'change', '[]'::jsonb)) loop
    select * into old_method from public.platform_business_contact_methods
    where relationship_id = target_id and id = (item ->> 'id')::uuid and removed_at is null
    for update;
    if not found then
      raise exception 'A contact detail you edited has just been removed. Reload the Lead and try again.'
        using errcode = '22023';
    end if;
    if old_method.kind is distinct from item ->> 'kind' then
      raise exception 'A contact detail''s type cannot change. Remove it and add the new one.'
        using errcode = '22023';
    end if;
    if (old_method.value, old_method.found_at)
      is distinct from (btrim(item ->> 'value'), btrim(item ->> 'found_at')) then
      update public.platform_business_contact_methods
      set value = btrim(item ->> 'value'), found_at = btrim(item ->> 'found_at')
      where id = old_method.id;
      changes := changes || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'field', 'contact_method', 'action', 'changed', 'kind', old_method.kind,
        'value', btrim(item ->> 'value'),
        'from', case when old_method.value <> btrim(item ->> 'value') then old_method.value end,
        'to', case when old_method.value <> btrim(item ->> 'value') then btrim(item ->> 'value') end,
        'found_at_changed', case when old_method.found_at <> btrim(item ->> 'found_at') then true end
      )));
    end if;
  end loop;

  -- New details, after the ones already there (removed ones included, so positions never repeat).
  select coalesce(max(position), -1) + 1 into next_position
  from public.platform_business_contact_methods where relationship_id = target_id;
  for item in select * from jsonb_array_elements(coalesce(ops -> 'add', '[]'::jsonb)) loop
    insert into public.platform_business_contact_methods (relationship_id, kind, value, found_at, position)
    values (target_id, item ->> 'kind', btrim(item ->> 'value'), btrim(item ->> 'found_at'), next_position);
    next_position := next_position + 1;
    changes := changes || jsonb_build_array(jsonb_build_object(
      'field', 'contact_method', 'action', 'added', 'kind', item ->> 'kind', 'value', btrim(item ->> 'value')
    ));
  end loop;

  select count(*) into active_count from public.platform_business_contact_methods
  where relationship_id = target_id and removed_at is null;
  if active_count > 10 then
    raise exception 'A Lead can have at most ten contact details.' using errcode = '22023';
  end if;

  if jsonb_array_length(changes) = 0 then
    return 'unchanged';
  end if;

  -- The list orders and the page shows "updated" by the business row, so a contact-only change touches it too.
  update public.platform_business_relationships set updated_at = now() where id = target_id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (target_id, 'details_changed', jsonb_build_object('changes', changes), actor);
  -- B3: an approved detail whose text changed, or that was removed, is no longer approved.
  perform private.lead_withdraw_approvals(target_id, actor, 'details_changed', true);
  return 'updated';
end;
$function$;

-- owner_lead_page: approvals, Do not contact, and whether the business is already a client.
create or replace function public.owner_lead_page(target_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'lead', jsonb_build_object(
      'id', r.id,
      'business_name', r.business_name,
      'country_code', r.country_code,
      'trade', r.trade,
      'source', r.source,
      'source_detail', r.source_detail,
      'website', r.website,
      'website_host', r.website_host,
      'contact_name', r.contact_name,
      'fit_notes', r.fit_notes,
      'lead_status', r.lead_status,
      'next_action', r.next_action,
      'next_action_due_on', r.next_action_due_on,
      'next_action_kind', r.next_action_kind,
      'do_not_contact', case when r.do_not_contact_at is null then null else jsonb_build_object(
        'at', r.do_not_contact_at, 'by', r.do_not_contact_by_email, 'reason', r.do_not_contact_reason
      ) end,
      'is_client', private.lead_is_client(r.id),
      'created_by_email', r.created_by_email,
      'created_at', r.created_at,
      'updated_at', r.updated_at
    ),
    'contact_methods', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', m.id, 'kind', m.kind, 'value', m.value, 'found_at', m.found_at,
            'approved_at', m.approved_at, 'whatsapp_permission', m.whatsapp_permission
          )
          order by m.position, m.created_at
        )
        from public.platform_business_contact_methods m
        where m.relationship_id = r.id and m.removed_at is null
      ),
      '[]'::jsonb
    ),
    'applications', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', a.id,
            'business_name', a.business_name,
            'main_contact_name', a.main_contact_name,
            'main_contact_email', a.main_contact_email,
            'stage', a.stage,
            'submitted_at', a.submitted_at
          )
          order by a.submitted_at desc
        )
        from public.platform_onboarding_applications a
        where a.business_relationship_id = r.id
      ),
      '[]'::jsonb
    ),
    'last_contacted_at', (
      select max(h.occurred_at) from public.platform_business_history h
      where h.relationship_id = r.id and h.kind = 'contact' and h.contact_direction = 'outbound'
    ),
    'last_heard_from_at', (
      select max(h.occurred_at) from public.platform_business_history h
      where h.relationship_id = r.id and h.kind = 'contact' and h.contact_direction = 'inbound'
    ),
    'history', public.owner_lead_history(r.id)
  )
  from public.platform_business_relationships r
  where r.id = target_id;
$function$;

-- 6. The review queue ---------------------------------------------------------------------------------------

-- Leads ready for review, oldest first, page_size (max 50) at a time, with their contact details, earlier
-- contact, Do not contact and client state. The page works out exclusions and missing information from these.
create or replace function public.owner_lead_review_queue(
  cursor_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 20
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with params as (
    select least(greatest(coalesce(page_size, 20), 1), 50) as size
  ),
  page as (
    select r.*
    from public.platform_business_relationships r
    where r.lead_status = 'ready_for_review'
      and (cursor_id is null or (r.created_at, r.id) > (cursor_created_at, cursor_id))
    order by r.created_at, r.id
    limit (select size from params)
  )
  select jsonb_build_object(
    'leads', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'business_name', p.business_name,
            'country_code', p.country_code,
            'trade', p.trade,
            'source', p.source,
            'source_detail', p.source_detail,
            'website', p.website,
            'website_host', p.website_host,
            'contact_name', p.contact_name,
            'fit_notes', p.fit_notes,
            'created_at', p.created_at,
            'prepared_by', coalesce(
              (select t.full_name from public.platform_team_members t
               where t.email = p.created_by_email order by t.created_at desc limit 1),
              p.created_by_email
            ),
            'prepared_by_email', p.created_by_email,
            'do_not_contact', case when p.do_not_contact_at is null then null else jsonb_build_object(
              'at', p.do_not_contact_at, 'reason', p.do_not_contact_reason
            ) end,
            'is_client', private.lead_is_client(p.id),
            'contact_methods', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object('id', m.id, 'kind', m.kind, 'value', m.value, 'found_at', m.found_at)
                  order by m.position, m.created_at
                )
                from public.platform_business_contact_methods m
                where m.relationship_id = p.id and m.removed_at is null
              ),
              '[]'::jsonb
            ),
            'contact', (
              select jsonb_build_object(
                'outbound_count', count(*) filter (where h.contact_direction = 'outbound'),
                'inbound_count', count(*) filter (where h.contact_direction = 'inbound'),
                'last_outbound_at', max(h.occurred_at) filter (where h.contact_direction = 'outbound'),
                'last_inbound_at', max(h.occurred_at) filter (where h.contact_direction = 'inbound')
              )
              from public.platform_business_history h
              where h.relationship_id = p.id and h.kind = 'contact'
            ),
            'last_sent_back', (
              select h.details -> 'reason'
              from public.platform_business_history h
              where h.relationship_id = p.id and h.kind = 'sent_back'
              order by h.occurred_at desc, h.id desc
              limit 1
            )
          )
          order by p.created_at, p.id
        )
        from page p
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params) then (
        select jsonb_build_object('created_at', p.created_at, 'id', p.id)
        from page p order by p.created_at desc, p.id desc limit 1
      )
      else null
    end,
    'total', (select count(*) from public.platform_business_relationships where lead_status = 'ready_for_review')
  );
$function$;

revoke all on function public.owner_lead_review_queue(timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function public.owner_lead_review_queue(timestamptz, uuid, integer) to service_role;

commit;
