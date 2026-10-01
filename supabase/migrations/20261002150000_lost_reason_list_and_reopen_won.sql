-- Pipeline B6: the lost reasons list, and reopening a Won quote.
--
-- Until now every organization chose from one fixed list of seven lost reasons. Owners and administrators
-- now keep their own list (Pipedrive and HubSpot both let the admin edit it):
--
--   * Each organization starts with the seven reasons it already had, so every existing record still reads
--     exactly as before.
--   * Adding a reason puts it on the list straight away. Retiring one takes it off the list for new choices,
--     but every record that already carries it keeps it and reports still show it (the plan: "Removing a
--     reason retires it from future choices without rewriting old reports"). A retired reason can be
--     brought back. "Other" is always offered and always needs a note.
--   * Reasons are never renamed in place: a record lost as "No response" must not quietly start reading as
--     something else. To change wording, add the new reason and retire the old one.
--
-- And a Won quote can be reopened before a Job exists. The approval stays in the quote's history, the quote
-- waits for the customer again, and the card comes back to the board. Once a Job exists, Won is permanent.
--
-- Growth: the list is at most 100 rows per organization (25 offered at once), read whole by its primary
-- key. Every check here is one primary-key or unique-index lookup.

-- ---------------------------------------------------------------------------------------------------------
-- 1. The list
-- ---------------------------------------------------------------------------------------------------------

create table public.pipeline_lost_reasons (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- What a Lost record stores. The seven starting reasons keep the keys records already use; a reason an
  -- organization adds gets an opaque one, so its wording can never collide with a key.
  key text not null,
  label text not null,
  position integer not null,
  is_built_in boolean not null default false,
  retired_at timestamptz,
  retired_by uuid references auth.users (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint pipeline_lost_reasons_pkey primary key (organization_id, key),
  constraint pipeline_lost_reasons_key_check check (key ~ '^[a-z0-9_]{2,64}$'),
  constraint pipeline_lost_reasons_label_check check (
    label = btrim(label) and char_length(label) between 1 and 60
  ),
  constraint pipeline_lost_reasons_other_is_always_offered check (key <> 'other' or retired_at is null),
  constraint pipeline_lost_reasons_retired_by_needs_retired_at check (retired_at is not null or retired_by is null)
);

comment on table public.pipeline_lost_reasons is
  'Each organization''s list of reasons a sale was lost. Owners and administrators add and retire reasons through public.pipeline_add_lost_reason and public.pipeline_set_lost_reason_retired; nothing is ever deleted or renamed, so a Lost record always reads as it did when it was classified.';
comment on column public.pipeline_lost_reasons.retired_at is
  'Set when the reason was taken off the list. Records that already carry it keep it; it is not offered for new choices.';

-- "No response" and "no response " are the same reason, retired or not.
create unique index pipeline_lost_reasons_label_idx
  on public.pipeline_lost_reasons (organization_id, lower(label));

create index pipeline_lost_reasons_created_by_idx
  on public.pipeline_lost_reasons (created_by) where created_by is not null;
create index pipeline_lost_reasons_retired_by_idx
  on public.pipeline_lost_reasons (retired_by) where retired_by is not null;

alter table public.pipeline_lost_reasons enable row level security;

-- Every member may read the list: anyone who can mark a card lost or read Sales Outcomes needs the names,
-- and a reason's name says nothing about any customer.
create policy "members can view lost reasons" on public.pipeline_lost_reasons
  for select to authenticated
  using (private.is_organization_member(organization_id));

revoke all on table public.pipeline_lost_reasons from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.pipeline_lost_reasons from authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 2. The starting list, for every organization that exists and every one created from now on
-- ---------------------------------------------------------------------------------------------------------

create function private.seed_pipeline_lost_reasons(target_organization_id uuid)
returns void
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $$
  insert into public.pipeline_lost_reasons (organization_id, key, label, position, is_built_in)
  values
    (target_organization_id, 'price_too_high', 'Price too high', 1, true),
    (target_organization_id, 'chose_another_contractor', 'Chose another contractor', 2, true),
    (target_organization_id, 'no_response', 'No response', 3, true),
    (target_organization_id, 'project_postponed', 'Project postponed', 4, true),
    (target_organization_id, 'work_not_a_fit', 'Work was not a fit', 5, true),
    (target_organization_id, 'duplicate_or_test_request', 'Duplicate or test request', 6, true),
    (target_organization_id, 'other', 'Other', 7, true)
  on conflict do nothing;
$$;

create function private.create_pipeline_lost_reasons()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform private.seed_pipeline_lost_reasons(new.id);
  return new;
end;
$$;

create trigger organizations_create_pipeline_lost_reasons
  after insert on public.organizations
  for each row execute function private.create_pipeline_lost_reasons();

revoke all on function private.seed_pipeline_lost_reasons(uuid) from public, anon, authenticated;
revoke all on function private.create_pipeline_lost_reasons() from public, anon, authenticated;

select private.seed_pipeline_lost_reasons(organization.id) from public.organizations as organization;

-- ---------------------------------------------------------------------------------------------------------
-- 3. A Lost record's reason is one from its own organization's list
-- ---------------------------------------------------------------------------------------------------------

alter table public.opportunity_outcome_events
  drop constraint opportunity_outcome_events_reason_vocabulary,
  add constraint opportunity_outcome_events_reason_fkey
    foreign key (organization_id, reason)
    references public.pipeline_lost_reasons (organization_id, key);

-- Whether a reason may be chosen now: on this organization's list and not retired.
create function private.pipeline_lost_reason_offered(target_organization_id uuid, target_key text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select exists (
    select 1 from public.pipeline_lost_reasons as lost_reason
    where lost_reason.organization_id = target_organization_id
      and lost_reason.key = target_key
      and lost_reason.retired_at is null
  );
$$;

revoke all on function private.pipeline_lost_reason_offered(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Adding and retiring reasons. Owners and administrators only (settings.business.edit), the same people
--    who change the rest of Settings → Pipeline. Both take the settings row lock every Pipeline settings
--    command takes, so two people adding at once cannot pass the limit together.
-- ---------------------------------------------------------------------------------------------------------

create function public.pipeline_add_lost_reason(target_organization_id uuid, new_label text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  clean_label text := regexp_replace(btrim(coalesce(new_label, '')), '\s+', ' ', 'g');
  existing public.pipeline_lost_reasons;
  offered_count integer;
  total_count integer;
  inserted public.pipeline_lost_reasons;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;
  if char_length(clean_label) = 0 then
    raise exception 'Give the reason a name.' using errcode = 'check_violation';
  end if;
  if char_length(clean_label) > 60 then
    raise exception 'Keep the reason under 60 characters.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organization_settings
  where organization_id = target_organization_id
  for update;

  select * into existing
  from public.pipeline_lost_reasons
  where organization_id = target_organization_id and lower(label) = lower(clean_label);
  if existing.key is not null then
    if existing.retired_at is null then
      raise exception 'You already have a reason called “%”.', existing.label
        using errcode = 'unique_violation';
    end if;
    raise exception '“%” is one of your retired reasons. Bring it back instead.', existing.label
      using errcode = 'unique_violation';
  end if;

  select count(*) filter (where retired_at is null), count(*)
  into offered_count, total_count
  from public.pipeline_lost_reasons
  where organization_id = target_organization_id;

  if offered_count >= 25 then
    raise exception 'You can offer up to 25 reasons. Retire one before adding another.'
      using errcode = 'check_violation';
  end if;
  if total_count >= 100 then
    raise exception 'This list is full. Bring back a retired reason instead of adding a new one.'
      using errcode = 'check_violation';
  end if;

  insert into public.pipeline_lost_reasons (
    organization_id, key, label, position, created_by
  ) values (
    target_organization_id,
    'custom_' || replace(gen_random_uuid()::text, '-', ''),
    clean_label,
    (select coalesce(max(position), 0) + 1 from public.pipeline_lost_reasons
     where organization_id = target_organization_id),
    (select auth.uid())
  ) returning * into inserted;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'pipeline', array['pipeline_lost_reasons'], (select auth.uid()));

  return jsonb_build_object(
    'key', inserted.key, 'label', inserted.label, 'position', inserted.position,
    'is_built_in', inserted.is_built_in, 'retired_at', inserted.retired_at
  );
end;
$$;

comment on function public.pipeline_add_lost_reason(uuid, text) is
  'Adds a lost reason to the organization''s list. Needs settings.business.edit. Refuses a name already on the list, retired or not, and more than 25 offered reasons.';

revoke all on function public.pipeline_add_lost_reason(uuid, text) from public, anon;
grant execute on function public.pipeline_add_lost_reason(uuid, text) to authenticated, service_role;

create function public.pipeline_set_lost_reason_retired(
  target_organization_id uuid,
  target_key text,
  retired boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  reason_row public.pipeline_lost_reasons;
  offered_count integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  perform 1 from public.organization_settings
  where organization_id = target_organization_id
  for update;

  select * into reason_row
  from public.pipeline_lost_reasons
  where organization_id = target_organization_id and key = target_key
  for update;

  if reason_row.key is null then
    raise exception 'That reason could not be found. Refresh the page and try again.'
      using errcode = 'no_data_found';
  end if;
  if reason_row.key = 'other' and retired then
    raise exception '“Other” is always offered, so it cannot be retired.' using errcode = 'check_violation';
  end if;

  -- Already as asked: a double click or a retry changes nothing.
  if (reason_row.retired_at is not null) = retired then
    return jsonb_build_object(
      'key', reason_row.key, 'label', reason_row.label, 'position', reason_row.position,
      'is_built_in', reason_row.is_built_in, 'retired_at', reason_row.retired_at
    );
  end if;

  if not retired then
    select count(*) into offered_count
    from public.pipeline_lost_reasons
    where organization_id = target_organization_id and retired_at is null;
    if offered_count >= 25 then
      raise exception 'You can offer up to 25 reasons. Retire one before bringing this back.'
        using errcode = 'check_violation';
    end if;
  end if;

  update public.pipeline_lost_reasons
  set retired_at = case when retired then now() else null end,
      retired_by = case when retired then (select auth.uid()) else null end
  where organization_id = target_organization_id and key = target_key
  returning * into reason_row;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'pipeline', array['pipeline_lost_reasons'], (select auth.uid()));

  return jsonb_build_object(
    'key', reason_row.key, 'label', reason_row.label, 'position', reason_row.position,
    'is_built_in', reason_row.is_built_in, 'retired_at', reason_row.retired_at
  );
end;
$$;

comment on function public.pipeline_set_lost_reason_retired(uuid, text, boolean) is
  'Retires a lost reason (no longer offered, kept on every record that has it) or brings it back. Needs settings.business.edit. "Other" cannot be retired.';

revoke all on function public.pipeline_set_lost_reason_retired(uuid, text, boolean) from public, anon;
grant execute on function public.pipeline_set_lost_reason_retired(uuid, text, boolean) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 5. Marking lost, and classifying a Lost record afterwards, check the organization's own list.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.pipeline_mark_opportunity_lost(
  target_opportunity_id uuid,
  idempotency_key text,
  reason text default null,
  note text default null,
  occurred_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  request_row public.requests;
  quote_row public.quotes;
  backing_quote_id uuid;
  existing_event public.opportunity_outcome_events;
  inserted_event public.opportunity_outcome_events;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  clean_reason text := nullif(trim(coalesce(reason, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'An outcome cannot be dated in the future.' using errcode = 'check_violation';
  end if;
  if clean_reason = 'other' and clean_note is null then
    raise exception 'Add a short note for "Other".' using errcode = 'check_violation';
  end if;

  -- Every Quote command locks the quote and then its card. Taking the quote first here keeps that one
  -- order, so this cannot deadlock against an archive or a decline landing at the same moment. The id is
  -- read only for a caller who may change this card.
  select opportunity.quote_id into backing_quote_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id
    and private.member_has_permission(opportunity.organization_id, (select auth.uid()), 'pipeline.edit');

  if backing_quote_id is not null then
    select * into quote_row from public.quotes where id = backing_quote_id for update;
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  -- A retry of the same command returns the first result untouched, even if the opportunity has since
  -- moved on. This must run before the "must be open" check below, or a legitimate retry after the first
  -- call already applied would be rejected as a conflicting command instead of recognised as a repeat.
  select * into existing_event
  from public.opportunity_outcome_events
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and opportunity_outcome_events.idempotency_key = pipeline_mark_opportunity_lost.idempotency_key;
  if found then
    return jsonb_build_object(
      'applied', false, 'event_id', existing_event.id, 'outcome', 'lost',
      'outcome_at', existing_event.occurred_at
    );
  end if;

  if opportunity_row.outcome <> 'open' then
    raise exception 'Only an open opportunity can be marked lost.' using errcode = 'check_violation';
  end if;

  -- Only a reason the organization still offers. A retired one stays on old records but is not chosen anew.
  if clean_reason is not null
     and not private.pipeline_lost_reason_offered(opportunity_row.organization_id, clean_reason) then
    raise exception 'Choose a lost reason from the list.' using errcode = 'check_violation';
  end if;

  if opportunity_row.quote_id is not null then
    if quote_row.id is null or quote_row.organization_id <> opportunity_row.organization_id then
      raise exception 'The backing quote could not be found.' using errcode = 'foreign_key_violation';
    end if;
    -- Marking Lost archives the quote, so it asks for what archiving a quote asks for.
    if not private.member_has_permission(
      quote_row.organization_id, (select auth.uid()), 'quotes.edit'
    ) then
      raise exception 'You do not have access to archive this quote.'
        using errcode = 'insufficient_privilege';
    end if;
    if quote_row.sent_at is null then
      raise exception 'This quote was never sent, so there is nothing to lose. Archive it from the quote instead.'
        using errcode = 'check_violation';
    end if;
    if quote_row.status not in ('draft', 'awaiting_response', 'changes_requested') then
      raise exception 'This quote cannot be marked lost right now.' using errcode = 'check_violation';
    end if;

    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      reason, note, prior_quote_status, idempotency_key
    ) values (
      opportunity_row.organization_id, target_opportunity_id, 'lost', command_time, (select auth.uid()),
      clean_reason, clean_note, quote_row.status, idempotency_key
    ) returning * into inserted_event;

    -- The card is decided before the quote is archived, so the quote's own status trigger finds nothing
    -- left to decide and writes no second, reasonless Lost event. It still removes the card's Tasks.
    update public.opportunities
    set outcome = 'lost', outcome_at = command_time, current_outcome_event_id = inserted_event.id,
        estimated_value = private.quote_last_sent_total_minor(quote_row.id) / 100.0
    where id = target_opportunity_id;

    update public.quotes
    set previous_status = quote_row.status,
        status = 'archived',
        archived_at = now(),
        archive_reason = null
    where id = quote_row.id;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      quote_row.organization_id, 'quote', quote_row.id, 'quote.marked_lost',
      'Marked as lost on the Pipeline and archived', (select auth.uid()),
      jsonb_build_object('outcome_event_id', inserted_event.id, 'reason', clean_reason)
    );

    return jsonb_build_object(
      'applied', true, 'event_id', inserted_event.id, 'outcome', 'lost', 'outcome_at', command_time
    );
  end if;

  if opportunity_row.request_id is null then
    -- A Direct job is closed from birth and never open, so this is unreachable; refusing plainly is safer
    -- than guessing.
    raise exception 'This record cannot be marked lost.' using errcode = 'check_violation';
  end if;

  select * into request_row
  from public.requests
  where id = opportunity_row.request_id and organization_id = opportunity_row.organization_id
  for update;

  if request_row.id is null then
    raise exception 'The backing request could not be found.' using errcode = 'foreign_key_violation';
  end if;
  if request_row.status in ('archived', 'converted') then
    raise exception 'This request cannot be marked lost right now.' using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.outcome_transition_request_id', request_row.id::text, true);

  update public.requests
  set status = 'archived'
  where id = request_row.id;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
    reason, note, prior_request_status, idempotency_key
  ) values (
    opportunity_row.organization_id, target_opportunity_id, 'lost', command_time, (select auth.uid()),
    clean_reason, clean_note, request_row.status, idempotency_key
  ) returning * into inserted_event;

  update public.opportunities
  set outcome = 'lost', outcome_at = command_time, current_outcome_event_id = inserted_event.id
  where id = target_opportunity_id;

  -- Only Tasks still open at this moment are this Lost event's to claim. A Task a person already finished
  -- keeps its own completed_by and no event id, so Reopen will never touch it. The five-completed limit is
  -- deliberately not re-checked here: it bounds active board work, and this card is leaving the board.
  update public.tasks
  set status = 'completed', completed_at = command_time, completed_by = null,
      completed_by_outcome_event_id = inserted_event.id
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and status = 'open';

  return jsonb_build_object(
    'applied', true, 'event_id', inserted_event.id, 'outcome', 'lost', 'outcome_at', command_time
  );
end;
$$;

create or replace function public.pipeline_set_lost_reason(
  target_opportunity_id uuid,
  reason text default null,
  note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  clean_reason text := nullif(trim(coalesce(reason, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if clean_reason = 'other' and clean_note is null then
    raise exception 'Add a short note for "Other".' using errcode = 'check_violation';
  end if;
  if char_length(coalesce(clean_note, '')) > 1000 then
    raise exception 'That note is too long.' using errcode = 'check_violation';
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  if opportunity_row.outcome <> 'lost' or opportunity_row.current_outcome_event_id is null then
    raise exception 'Only a lost opportunity has a lost reason.' using errcode = 'check_violation';
  end if;

  -- A record already carrying a reason that has since been retired may keep it, for example while only its
  -- note is being corrected. Any other reason must be one the organization still offers.
  if clean_reason is not null
     and not private.pipeline_lost_reason_offered(opportunity_row.organization_id, clean_reason)
     and clean_reason is distinct from (
       select outcome_event.reason
       from public.opportunity_outcome_events as outcome_event
       where outcome_event.id = opportunity_row.current_outcome_event_id
         and outcome_event.organization_id = opportunity_row.organization_id
     ) then
    raise exception 'Choose a lost reason from the list.' using errcode = 'check_violation';
  end if;

  update public.opportunity_outcome_events
  set reason = clean_reason,
      note = clean_note,
      classified_at = now(),
      classified_by = (select auth.uid())
  where id = opportunity_row.current_outcome_event_id
    and organization_id = opportunity_row.organization_id
    and event_type = 'lost';

  if not found then
    raise exception 'No lost event was found to classify.' using errcode = 'foreign_key_violation';
  end if;

  return jsonb_build_object(
    'event_id', opportunity_row.current_outcome_event_id, 'reason', clean_reason, 'note', clean_note
  );
end;
$$;

comment on function public.pipeline_set_lost_reason(uuid, text, text) is
  'Sets or clears the reason and note on an opportunity''s current Lost event. Needs pipeline.edit. The reason must be on the organization''s list and not retired, unless the record already carries it. Setting the same values again changes nothing but the classified stamp.';

-- ---------------------------------------------------------------------------------------------------------
-- 6. Reopen: a Lost Request or quote as before, and now a Won quote no Job has been made from.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.pipeline_reopen_opportunity(
  target_opportunity_id uuid,
  idempotency_key text,
  reopen_explanation text,
  occurred_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  quote_row public.quotes;
  backing_quote_id uuid;
  restored_status text;
  lost_event public.opportunity_outcome_events;
  won_event public.opportunity_outcome_events;
  existing_event public.opportunity_outcome_events;
  inserted_event public.opportunity_outcome_events;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  clean_explanation text := nullif(trim(coalesce(reopen_explanation, '')), '');
  open_count integer;
  reopening_count integer;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if clean_explanation is null or char_length(clean_explanation) > 500 then
    raise exception 'A short explanation is required to reopen.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'An outcome cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  -- Quote first, then its card: the same order every Quote command takes them in.
  select opportunity.quote_id into backing_quote_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id
    and private.member_has_permission(opportunity.organization_id, (select auth.uid()), 'pipeline.edit');

  if backing_quote_id is not null then
    select * into quote_row from public.quotes where id = backing_quote_id for update;
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  select * into existing_event
  from public.opportunity_outcome_events
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and opportunity_outcome_events.idempotency_key = pipeline_reopen_opportunity.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'outcome', 'open');
  end if;

  -- Reopening Won. Only an approved quote nobody has made a Job from can go back: once a Job exists the win
  -- is permanent, and a Request or Direct job is only ever Won by becoming a Job.
  if opportunity_row.outcome = 'won' then
    if opportunity_row.quote_id is null
       or quote_row.status = 'converted'
       or exists (
         select 1 from public.jobs as job
         where job.organization_id = opportunity_row.organization_id
           and job.quote_id = opportunity_row.quote_id
       ) then
      raise exception 'A job has already been made from this, so the win is final.'
        using errcode = 'check_violation';
    end if;
    if quote_row.id is null or quote_row.organization_id <> opportunity_row.organization_id then
      raise exception 'The backing quote could not be found.' using errcode = 'foreign_key_violation';
    end if;
    if not private.member_has_permission(
      quote_row.organization_id, (select auth.uid()), 'quotes.edit'
    ) then
      raise exception 'You do not have access to change this quote.'
        using errcode = 'insufficient_privilege';
    end if;
    if quote_row.status <> 'approved' then
      raise exception 'This quote has already moved on. Open the quote to carry on with it.'
        using errcode = 'check_violation';
    end if;

    select * into won_event
    from public.opportunity_outcome_events
    where id = opportunity_row.current_outcome_event_id
      and organization_id = opportunity_row.organization_id
    for update;

    if won_event.id is null or won_event.event_type <> 'won' then
      raise exception 'No won event was found to reopen.' using errcode = 'foreign_key_violation';
    end if;

    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      reopen_explanation, restores_event_id, idempotency_key
    ) values (
      opportunity_row.organization_id, target_opportunity_id, 'reopened', command_time, (select auth.uid()),
      clean_explanation, won_event.id, idempotency_key
    ) returning * into inserted_event;

    -- Open before the quote changes, so the quote's own status trigger writes no second Reopened event.
    update public.opportunities
    set outcome = 'open', outcome_at = null, current_outcome_event_id = null,
        estimated_value = private.quote_current_total_minor(quote_row.id) / 100.0
    where id = target_opportunity_id;

    -- The approval and any signature with it stay in the quote's history. They stop being the answer, and
    -- the quote waits for the customer again. A deposit already paid stays recorded against the quote.
    update public.quote_decisions
    set is_current = false
    where organization_id = quote_row.organization_id
      and quote_id = quote_row.id
      and is_current
      and outcome = 'approved';

    update public.quotes
    set status = case when draft_version_id is null then 'awaiting_response' else 'draft' end,
        decision = null, decided_at = null, decision_method = null,
        decision_note = null, decided_by = null
    where id = quote_row.id;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      quote_row.organization_id, 'quote', quote_row.id, 'quote.reopened',
      'Approval withdrawn and reopened from Sales Outcomes', (select auth.uid()),
      jsonb_build_object('outcome_event_id', inserted_event.id, 'explanation', clean_explanation)
    );

    return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'outcome', 'open');
  end if;

  if opportunity_row.outcome <> 'lost' or opportunity_row.current_outcome_event_id is null then
    raise exception 'Only a won or lost opportunity can be reopened.' using errcode = 'check_violation';
  end if;

  select * into lost_event
  from public.opportunity_outcome_events
  where id = opportunity_row.current_outcome_event_id
    and organization_id = opportunity_row.organization_id
  for update;

  if lost_event.id is null then
    raise exception 'No lost event was found to reopen.' using errcode = 'foreign_key_violation';
  end if;

  if opportunity_row.quote_id is not null then
    if quote_row.id is null or quote_row.organization_id <> opportunity_row.organization_id then
      raise exception 'The backing quote could not be found.' using errcode = 'foreign_key_violation';
    end if;
    if not private.member_has_permission(
      quote_row.organization_id, (select auth.uid()), 'quotes.edit'
    ) then
      raise exception 'You do not have access to restore this quote.'
        using errcode = 'insufficient_privilege';
    end if;
    if quote_row.status not in ('archived', 'declined') then
      raise exception 'This quote has already moved on. Open the quote to carry on with it.'
        using errcode = 'check_violation';
    end if;

    -- Back to where it stood the moment before it was lost. An archived quote remembers that itself; a
    -- declined one is remembered by its Lost event.
    restored_status := case
      when quote_row.status = 'archived'
        and quote_row.previous_status in ('draft', 'awaiting_response', 'changes_requested')
        then quote_row.previous_status
      else lost_event.prior_quote_status
    end;
    if restored_status is null
       or restored_status not in ('draft', 'awaiting_response', 'changes_requested') then
      restored_status := 'awaiting_response';
    end if;
    -- A draft needs a draft to edit, and a sent quote has none.
    if restored_status = 'draft' and quote_row.draft_version_id is null then
      restored_status := 'awaiting_response';
    elsif restored_status <> 'draft' and quote_row.draft_version_id is not null then
      restored_status := 'draft';
    end if;

    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      reopen_explanation, restores_event_id, idempotency_key
    ) values (
      opportunity_row.organization_id, target_opportunity_id, 'reopened', command_time, (select auth.uid()),
      clean_explanation, lost_event.id, idempotency_key
    ) returning * into inserted_event;

    -- Open before the quote changes, so the quote's own status trigger writes no second, unexplained
    -- Reopened event. The card goes back to following the quote's live total.
    update public.opportunities
    set outcome = 'open', outcome_at = null, current_outcome_event_id = null,
        estimated_value = private.quote_current_total_minor(quote_row.id) / 100.0
    where id = target_opportunity_id;

    -- The customer's "no" stays in the quote's history. It simply stops being the answer.
    update public.quote_decisions
    set is_current = false
    where organization_id = quote_row.organization_id
      and quote_id = quote_row.id
      and is_current
      and outcome = 'declined';

    update public.quotes
    set status = restored_status,
        previous_status = null,
        archived_at = null,
        archive_reason = null,
        decision = case when decision = 'declined' then null else decision end,
        decided_at = case when decision = 'declined' then null else decided_at end,
        decision_method = case when decision = 'declined' then null else decision_method end,
        decision_note = case when decision = 'declined' then null else decision_note end,
        decided_by = case when decision = 'declined' then null else decided_by end
    where id = quote_row.id;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      quote_row.organization_id, 'quote', quote_row.id, 'quote.reopened',
      'Reopened from Sales Outcomes', (select auth.uid()),
      jsonb_build_object('outcome_event_id', inserted_event.id, 'explanation', clean_explanation)
    );

    return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'outcome', 'open');
  end if;

  if opportunity_row.request_id is null then
    raise exception 'This record cannot be reopened.' using errcode = 'check_violation';
  end if;

  -- Almost always zero: at most five Tasks could have been open when Lost fired. This only fires when
  -- something opened new Tasks on an already-closed card, which the write path does not block today.
  select
    count(*) filter (where status = 'open'),
    count(*) filter (where completed_by_outcome_event_id = lost_event.id)
  into open_count, reopening_count
  from public.tasks
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id;

  if open_count + reopening_count > 5 then
    raise exception 'Reopening would leave more than five open tasks. Close some open tasks first.'
      using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.outcome_transition_request_id', opportunity_row.request_id::text, true);

  update public.requests
  set status = lost_event.prior_request_status
  where id = opportunity_row.request_id;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
    reopen_explanation, restores_event_id, idempotency_key
  ) values (
    opportunity_row.organization_id, target_opportunity_id, 'reopened', command_time, (select auth.uid()),
    clean_explanation, lost_event.id, idempotency_key
  ) returning * into inserted_event;

  update public.opportunities
  set outcome = 'open', outcome_at = null, current_outcome_event_id = null
  where id = target_opportunity_id;

  update public.tasks
  set status = 'open', completed_at = null, completed_by = null, completed_by_outcome_event_id = null
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and completed_by_outcome_event_id = lost_event.id;

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'outcome', 'open');
end;
$$;

comment on function public.pipeline_reopen_opportunity(uuid, text, text, timestamptz) is
  'Reopens a Lost Request or quote to where it stood, or a Won quote that no Job has been made from (its approval stops being current and it waits for the customer again). Needs pipeline.edit, plus quotes.edit for a quote, and a short explanation. Once a Job exists, Won is permanent.';
