-- Client onboarding C3a: Uplift reviews a client's sent setup one section at a time.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §4 (accept, ask, or return one section;
-- the client never repeats the whole wizard) and §8 (history). Storage: ADR 0005 — this is the third layer,
-- the accepted value: an accepted section points at the send it accepted, so its accepted answers are that
-- send's answers for the section. Industry reference: Content Snare's approve / send back with a reason, per
-- request; Jafar's choices of 2026-10-04 are in the plan.
--
-- 1. organization_setup_section_reviews keeps Uplift's current decision on each section: accepted or returned,
--    the send it was made on, and for a return the note and the questions to change. One row per section; each
--    decision is also written to Jafar's history, so the row holds only the latest.
-- 2. public.owner_review_setup_section records a decision on the newest send only. A return restarts the
--    client's setup reminders, since the next move is theirs again.
-- 3. public.start_support_thread_by_uplift takes the setup section a chat is about, as the client's Ask Uplift
--    does (20261006190000), so "Ask a question" on a section starts a chat with it attached.

-- 1. Uplift's decision on each section ---------------------------------------------------------------------

create table public.organization_setup_section_reviews (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- A section key from the setup version the send was taken with; the route checks it is a section of that send.
  section_key text not null check (section_key ~ '^[a-z][a-z0-9_]{0,39}$'),
  decision text not null check (decision in ('accepted', 'returned')),
  -- The send the decision was made on. For an acceptance, that send's answers are the accepted values.
  submission_number integer not null,
  -- For a return: what to change, in Jafar's words, and the questions to change (fact keys of the section).
  note text,
  question_keys text[] not null default '{}',
  reviewed_by_email text not null check (char_length(reviewed_by_email) between 3 and 320),
  reviewed_at timestamptz not null default now(),
  primary key (organization_id, section_key),
  foreign key (organization_id, submission_number)
    references public.organization_setup_submissions (organization_id, submission_number) on delete cascade,
  constraint organization_setup_section_reviews_return_check check (
    case decision
      when 'returned' then
        char_length(btrim(coalesce(note, ''))) between 1 and 2000
        and cardinality(question_keys) <= 100
      else note is null and cardinality(question_keys) = 0
    end
  )
);

comment on table public.organization_setup_section_reviews is
  'Uplift''s latest decision on each section of a client''s sent setup (ADR 0005, the accepted layer). Administrators may read it; rows change only through public.owner_review_setup_section, and every decision is in platform_owner_audit_events.';

alter table public.organization_setup_section_reviews enable row level security;
revoke all on table public.organization_setup_section_reviews from public, anon, authenticated;
grant select on table public.organization_setup_section_reviews to authenticated;
grant all on table public.organization_setup_section_reviews to service_role;

-- The client's owners and administrators see what Uplift accepted or sent back (C3b).
create policy "administrators can view their setup reviews"
  on public.organization_setup_section_reviews
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 2. Recording a decision ------------------------------------------------------------------------------------

-- `seen_number` is the send Jafar was looking at. A decision is made on the newest send only: if the client
-- has sent again in the meantime this returns 'stale' and records nothing, so Jafar never accepts answers he
-- has not seen. The same decision made twice (a double press) changes nothing and is recorded once.
create function public.owner_review_setup_section(
  target_organization_id uuid,
  target_section_key text,
  seen_number integer,
  new_decision text,
  return_note text,
  return_question_keys text[],
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_note text := case when new_decision = 'returned' then nullif(btrim(coalesce(return_note, '')), '') end;
  clean_keys text[] := case
    when new_decision = 'returned' then
      array(select distinct key from unnest(coalesce(return_question_keys, '{}')) as key where key is not null order by key)
    else '{}'
  end;
  latest integer;
  before_row public.organization_setup_section_reviews;
  after_row public.organization_setup_section_reviews;
begin
  if target_organization_id is null or target_section_key is null or seen_number is null
    or clean_email is null or new_decision not in ('accepted', 'returned') then
    raise exception 'Say which section, which send, and the decision.' using errcode = 'check_violation';
  end if;
  if new_decision = 'returned' and clean_note is null then
    raise exception 'Say what the client should change.' using errcode = 'check_violation';
  end if;

  -- Takes turns with Send to Uplift, which locks the same row.
  perform 1 from public.organization_setup
  where organization_id = target_organization_id
  for update;

  select max(submission_number) into latest
  from public.organization_setup_submissions
  where organization_id = target_organization_id;
  if latest is null then
    raise exception 'This client has not sent their setup yet.' using errcode = 'no_data_found';
  end if;
  if latest <> seen_number then
    return jsonb_build_object('status', 'stale', 'latest_number', latest);
  end if;

  select * into before_row
  from public.organization_setup_section_reviews
  where organization_id = target_organization_id and section_key = target_section_key
  for update;

  if before_row.decision is not distinct from new_decision
    and before_row.submission_number is not distinct from seen_number
    and before_row.note is not distinct from clean_note
    and before_row.question_keys is not distinct from clean_keys then
    return jsonb_build_object('status', 'unchanged');
  end if;

  insert into public.organization_setup_section_reviews (
    organization_id, section_key, decision, submission_number, note, question_keys, reviewed_by_email
  ) values (
    target_organization_id, target_section_key, new_decision, seen_number, clean_note, clean_keys, clean_email
  )
  on conflict (organization_id, section_key) do update
  set decision = excluded.decision,
      submission_number = excluded.submission_number,
      note = excluded.note,
      question_keys = excluded.question_keys,
      reviewed_by_email = excluded.reviewed_by_email,
      reviewed_at = now()
  returning * into after_row;

  -- The next move is the client's: start a fresh quiet spell, unless Uplift has paused their reminders.
  if new_decision = 'returned' then
    update public.organization_setup_reminders
    set last_activity_at = now(),
        reminders_sent = 0,
        next_due_at = now() + interval '24 hours'
    where organization_id = target_organization_id and paused_at is null;
  end if;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    case new_decision
      when 'accepted' then 'organization.setup_section_accepted'
      else 'organization.setup_section_returned'
    end,
    'organization',
    target_organization_id::text,
    case when before_row.section_key is null then null else jsonb_build_object(
      'section_key', before_row.section_key,
      'decision', before_row.decision,
      'send', before_row.submission_number
    ) end,
    jsonb_build_object(
      'section_key', after_row.section_key,
      'decision', after_row.decision,
      'send', after_row.submission_number,
      'note', after_row.note,
      'question_keys', to_jsonb(after_row.question_keys)
    )
  );

  return jsonb_build_object(
    'status', 'saved',
    'decision', after_row.decision,
    'send', after_row.submission_number,
    'reviewed_at', after_row.reviewed_at
  );
end;
$$;

revoke all on function public.owner_review_setup_section(uuid, text, integer, text, text, text[], text)
  from public, anon, authenticated;
grant execute on function public.owner_review_setup_section(uuid, text, integer, text, text, text[], text)
  to service_role;

-- 3. Uplift starts a chat about a setup section -----------------------------------------------------------
-- Unchanged from 20261006160000_support_solved_and_uplift_starts.sql except the new last argument, checked as
-- the client's start_support_thread checks it.

drop function public.start_support_thread_by_uplift(uuid, uuid, text, text, text, uuid, jsonb);

create function public.start_support_thread_by_uplift(
  target_organization_id uuid,
  target_user_id uuid,
  thread_topic text,
  actor_email text,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb,
  thread_context_section text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  clean_body text := btrim(coalesce(message_body, ''));
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_topic text := coalesce(nullif(btrim(thread_topic), ''), 'other');
  clean_context text := nullif(btrim(coalesce(thread_context_section, '')), '');
  responder text;
  file_count smallint;
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if clean_email is null then
    raise exception 'An acting owner email is required to write.' using errcode = 'check_violation';
  end if;

  if message_client_id is null then
    raise exception 'The message is missing its identifier.' using errcode = 'check_violation';
  end if;

  if char_length(clean_body) > 4000 then
    raise exception 'A message can have up to 4000 characters.' using errcode = 'check_violation';
  end if;

  if clean_topic not in ('setup', 'website', 'google_profile', 'crm', 'billing', 'other') then
    raise exception 'Choose one of the listed topics.' using errcode = 'check_violation';
  end if;

  if clean_context is not null and clean_context !~ '^[a-z][a-z0-9_]{0,39}$' then
    raise exception 'That setup section is not recognised.' using errcode = 'check_violation';
  end if;

  select nullif(responder_name, '') into responder
  from public.platform_support_settings
  where id = true;

  if responder is null then
    raise exception 'Add the name clients see on your replies before sending one.'
      using errcode = 'check_violation';
  end if;

  if target_user_id is null or not exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = target_user_id
      and membership.status = 'active'
  ) then
    raise exception 'Choose someone who is on this business''s team.' using errcode = 'check_violation';
  end if;

  file_count := private.check_support_attachments(target_organization_id, message_attachments);

  if clean_body = '' and file_count = 0 then
    raise exception 'Write a message or attach a file first.' using errcode = 'check_violation';
  end if;

  -- Two attempts of the same first message, arriving together, take turns here; the second then finds the
  -- chat the first one made.
  perform pg_advisory_xact_lock(hashtextextended('support-start-uplift:' || message_client_id::text, 0));

  select * into message_row
  from public.support_messages
  where organization_id = target_organization_id
    and client_message_id = message_client_id
    and sender_kind = 'uplift';

  if message_row.id is not null then
    return private.support_message_json(message_row);
  end if;

  insert into public.support_threads (organization_id, started_by_user_id, topic, opened_by, context_section)
  values (target_organization_id, target_user_id, clean_topic, 'uplift', clean_context)
  returning id into thread_id_value;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_owner_email, sender_name, body, client_message_id,
    attachment_count
  )
  values (
    thread_id_value, target_organization_id, 'uplift', clean_email, responder, clean_body,
    message_client_id, file_count
  )
  returning * into message_row;

  perform private.add_support_attachments(message_row, message_attachments);

  return private.support_message_json(message_row);
end;
$$;

revoke all on function public.start_support_thread_by_uplift(uuid, uuid, text, text, text, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.start_support_thread_by_uplift(uuid, uuid, text, text, text, uuid, jsonb, text)
  to service_role;
