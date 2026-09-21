-- CRM launch readiness Part 4, Stage 1: a website inquiry becomes an Automation event.
--
-- Established pattern: HighLevel starts workflows from "Form Submitted" and chat-widget triggers; Zendesk's
-- webhook guidance is that the receiving side must be idempotent. UCRM already runs the transactional outbox +
-- idempotent receiver shape for quote delivery (20260831014256). This migration adds a second event type to
-- that same spine rather than a new mechanism.
--
-- Two moments are an inquiry, matching docs/website-chat-behavior-contract.md:
--   * a public form submission the worker turned into its real outcome (form_submissions -> 'processed');
--   * a Website Chat session created by an accepted first visitor message.
-- Each emits exactly one `website_inquiry.received` event in the same transaction, keyed by the submission or
-- session id, so a retried request or a replayed worker can never produce a second event.
--
-- Emission uses row triggers instead of re-copying submit/accept commands (300+ lines each, one carrying its
-- own statement_timeout): the trigger fires inside the transaction that establishes the fact, which is the
-- outbox guarantee, and it leaves those public commands byte-for-byte unchanged.
--
-- The enrollment subject is the inquiry itself (the submission or the chat session), not the Client: a chat
-- whose identity needs review has no Client yet, and one person can send two genuine inquiries.
--
-- Deliberately NOT here: the contractor-authorable trigger (catalog stays blocked until an inquiry recipe can
-- do something useful), minute waits (Stage 2), reply stop rules (Stage 3), staff alerts (Stage 4), and
-- customer messages (Stage 5). Until then no inquiry recipe can be activated, so no inquiry enrollment exists.

-- ---------------------------------------------------------------------------------------------------
-- 1. The spine accepts the new event, subjects and source modules.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_events
  drop constraint automation_events_event_type_check,
  add constraint automation_events_event_type_check
    check (event_type in ('quote.delivery_succeeded', 'website_inquiry.received')),
  drop constraint automation_events_subject_type_check,
  add constraint automation_events_subject_type_check
    check (subject_type in ('quote', 'form_submission', 'website_chat_session')),
  drop constraint automation_events_source_module_check,
  add constraint automation_events_source_module_check
    check (source_module in ('communications', 'forms', 'website_chat'));

alter table private.automation_enrollments
  drop constraint automation_enrollments_subject_type_check,
  add constraint automation_enrollments_subject_type_check
    check (subject_type in ('quote', 'form_submission', 'website_chat_session'));

-- ---------------------------------------------------------------------------------------------------
-- 2. Emission: a processed form submission.
-- ---------------------------------------------------------------------------------------------------
create function private.emit_form_submission_inquiry_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform private.emit_automation_event(
    new.organization_id,
    'website_inquiry.received',
    'form_submission',
    new.id,
    -- Identifiers only; intake and every later step re-read current truth.
    jsonb_strip_nulls(jsonb_build_object(
      'channel', 'form',
      'form_id', new.form_id,
      'outcome', new.result ->> 'outcome',
      'client_id', new.result ->> 'client_id',
      'request_id', new.result ->> 'request_id',
      'assessment_id', new.result ->> 'assessment_id',
      'job_id', new.result ->> 'job_id'
    )),
    -- The customer's own submit time: a later Wait is measured from when they asked, not from worker lag.
    new.created_at,
    'forms',
    new.id
  );
  return null;
end;
$$;

revoke all on function private.emit_form_submission_inquiry_event() from public, anon, authenticated;

create trigger form_submissions_emit_inquiry_event
  after update of status on private.form_submissions
  for each row
  when (new.status = 'processed' and old.status is distinct from 'processed')
  execute function private.emit_form_submission_inquiry_event();

-- ---------------------------------------------------------------------------------------------------
-- 3. Emission: an accepted Website Chat session.
-- ---------------------------------------------------------------------------------------------------
create function private.emit_website_chat_inquiry_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform private.emit_automation_event(
    new.organization_id,
    'website_inquiry.received',
    'website_chat_session',
    new.id,
    jsonb_strip_nulls(jsonb_build_object(
      'channel', 'website_chat',
      'widget_id', new.widget_id,
      -- Null while the identity needs review; never guessed.
      'client_id', new.client_id,
      'match_status', new.match_status
    )),
    new.created_at,
    'website_chat',
    new.id
  );
  return null;
end;
$$;

revoke all on function private.emit_website_chat_inquiry_event() from public, anon, authenticated;

create trigger website_chat_sessions_emit_inquiry_event
  after insert on public.website_chat_sessions
  for each row
  execute function private.emit_website_chat_inquiry_event();

-- ---------------------------------------------------------------------------------------------------
-- 4. Intake understands an inquiry subject.
-- ---------------------------------------------------------------------------------------------------
-- Replaced from the LIVE definition (identical to 20260831103248). Quote handling is unchanged; the only
-- changes are marked "Part 4".
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
  subject_present boolean;   -- Part 4
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

      -- Part 4: resolve the subject for its own type. A quote keeps its 6F-1 resolution exactly.
      quote_row := null;
      wants_follow_ups := true;
      if candidate.subject_type = 'quote' then
        select * into quote_row
        from public.quotes
        where organization_id = candidate.organization_id and id = candidate.subject_id;

        if quote_row.client_id is not null then
          select coalesce(p.quote_follow_ups, true) into wants_follow_ups
          from public.client_communication_preferences as p
          where p.organization_id = candidate.organization_id and p.client_id = quote_row.client_id;
          wants_follow_ups := coalesce(wants_follow_ups, true);
        end if;

        subject_present := quote_row.id is not null and quote_row.archived_at is null;
        re_entry_key := coalesce(candidate.payload ->> 'quote_version_id', '')
          || ':' || coalesce(candidate.payload ->> 'quote_recipient_id', '');
      elsif candidate.subject_type = 'form_submission' then
        select exists (
          select 1 from private.form_submissions as s
          where s.organization_id = candidate.organization_id and s.id = candidate.subject_id
            and s.status = 'processed'
        ) into subject_present;
        -- Once per inquiry: the same submission never starts a recipe twice; a second genuine submission does.
        re_entry_key := 'form_submission:' || candidate.subject_id::text;
      elsif candidate.subject_type = 'website_chat_session' then
        select exists (
          select 1 from public.website_chat_sessions as s
          where s.organization_id = candidate.organization_id and s.id = candidate.subject_id
        ) into subject_present;
        re_entry_key := 'website_chat_session:' || candidate.subject_id::text;
      else
        subject_present := false;
        re_entry_key := candidate.subject_type || ':' || candidate.subject_id::text;
      end if;

      select case when limits.state = 'numeric' then limits.value end
      into duration_days
      from public.effective_automation_limits(candidate.organization_id) as limits
      where limits.limit_key = 'automation_max_enrollment_duration_days';

      enrollment_expires_at := case
        when duration_days is not null and duration_days > 0
        then now() + make_interval(days => duration_days)
      end;

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
        elsif not subject_present then
          match_outcome := 'subject_gone';
        elsif not wants_follow_ups then
          match_outcome := 'follow_ups_declined';
        else
          if candidate.subject_type = 'quote' then
            match_outcome := private.automation_conditions_outcome(
              match_row.definition, candidate.organization_id, quote_row.status, candidate.payload
            );
          -- Part 4: no inquiry condition exists yet, so any condition is honestly unavailable, never skipped.
          elsif jsonb_array_length(coalesce(match_row.definition -> 'conditions', '[]'::jsonb)) > 0 then
            match_outcome := 'condition_unavailable';
          else
            match_outcome := 'pass';
          end if;

          if match_outcome = 'pass' then
            insert into private.automation_enrollments (
              organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
              trigger_event_id, source, re_entry_key, context, expires_at, anchor_at
            ) values (
              candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
              candidate.subject_type, candidate.subject_id, candidate.id, 'event',
              re_entry_key, candidate.payload, enrollment_expires_at,
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
  'item, or a recorded reason why not. Quotes honour the client''s quote-follow-up preference; a website '
  'inquiry (form submission or chat session) enrolls at most once per recipe. Enrollments anchor on the '
  'original fact. Service role only.';

revoke all on function public.intake_automation_events(integer) from public, anon, authenticated;
grant execute on function public.intake_automation_events(integer) to service_role;
