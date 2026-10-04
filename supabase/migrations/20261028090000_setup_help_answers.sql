-- Client onboarding C3c: Uplift's to-do — answers Uplift found for questions a client asked help with.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §2 ("Help is a valid answer that creates an
-- Uplift task"), §4 (keep the client's original answer and the final accepted value) and §10 journey 4. Storage:
-- ADR 0005 decision 4 — the to-do is read from the client's "I need Uplift's help" answers in their newest send,
-- never copied into a task record, so an item closes only when this table holds Uplift's answer for it. The
-- client's own "need help" stays in their send, untouched. Jafar's choices of 2026-10-04: Uplift answers in the
-- same kind of box the client had (a written note for photo, file and list questions), and the client sees it.
--
-- 1. organization_setup_help_answers keeps Uplift's latest answer to each question. Every change is also in
--    Jafar's history.
-- 2. public.owner_answer_setup_help records one, only for a question the newest send asked help with.

-- 1. Uplift's answers --------------------------------------------------------------------------------------------

create table public.organization_setup_help_answers (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fact_key text not null check (char_length(fact_key) between 1 and 80),
  -- Stored as the client's own answer to this question would be; null when Uplift wrote a note instead.
  value jsonb,
  -- What Uplift did or found, in words, for questions answered with photos, files or rows.
  note text,
  -- The send whose help request this answers.
  submission_number integer not null,
  recorded_by_email text not null check (char_length(recorded_by_email) between 3 and 320),
  recorded_at timestamptz not null default now(),
  primary key (organization_id, fact_key),
  foreign key (organization_id, submission_number)
    references public.organization_setup_submissions (organization_id, submission_number) on delete cascade,
  constraint organization_setup_help_answers_one_check check (
    (value is not null and jsonb_typeof(value) <> 'null' and note is null)
    or (value is null and note is not null)
  ),
  constraint organization_setup_help_answers_value_size_check check (
    value is null or octet_length(value::text) <= 8000
  ),
  constraint organization_setup_help_answers_note_check check (
    note is null or (note = btrim(note) and char_length(note) between 1 and 2000)
  )
);

comment on table public.organization_setup_help_answers is
  'Uplift''s answer to each setup question a client asked help with (client onboarding C3c). Administrators may read it; rows change only through public.owner_answer_setup_help, and every change is in platform_owner_audit_events.';

alter table public.organization_setup_help_answers enable row level security;
revoke all on table public.organization_setup_help_answers from public, anon, authenticated;
grant select on table public.organization_setup_help_answers to authenticated;
grant all on table public.organization_setup_help_answers to service_role;

-- The client's owners and administrators see what Uplift filled in for them.
create policy "administrators can view their setup help answers"
  on public.organization_setup_help_answers
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 2. Recording an answer ------------------------------------------------------------------------------------------

-- `seen_number` is the send Jafar was looking at; a newer send returns 'stale' and records nothing. The route has
-- already checked the question is in that send and the value suits it. The same answer twice changes nothing.
create function public.owner_answer_setup_help(
  target_organization_id uuid,
  target_fact_key text,
  seen_number integer,
  new_value jsonb,
  new_note text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_value jsonb := case when jsonb_typeof(new_value) = 'null' then null else new_value end;
  clean_note text := nullif(btrim(coalesce(new_note, '')), '');
  latest integer;
  asked text;
  before_row public.organization_setup_help_answers;
  after_row public.organization_setup_help_answers;
begin
  if target_organization_id is null or target_fact_key is null or seen_number is null or clean_email is null then
    raise exception 'Say which question, which send, and who is answering.' using errcode = 'check_violation';
  end if;
  if (clean_value is null) = (clean_note is null) then
    raise exception 'Give Uplift''s answer.' using errcode = 'check_violation';
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

  select answers -> target_fact_key ->> 'availability' into asked
  from public.organization_setup_submissions
  where organization_id = target_organization_id and submission_number = latest;
  if asked is distinct from 'need_help' then
    raise exception 'The client did not ask for help with this question.' using errcode = 'check_violation';
  end if;

  select * into before_row
  from public.organization_setup_help_answers
  where organization_id = target_organization_id and fact_key = target_fact_key
  for update;

  if before_row.fact_key is not null
    and before_row.value is not distinct from clean_value
    and before_row.note is not distinct from clean_note then
    return jsonb_build_object('status', 'unchanged');
  end if;

  insert into public.organization_setup_help_answers (
    organization_id, fact_key, value, note, submission_number, recorded_by_email
  ) values (
    target_organization_id, target_fact_key, clean_value, clean_note, latest, clean_email
  )
  on conflict (organization_id, fact_key) do update
  set value = excluded.value,
      note = excluded.note,
      submission_number = excluded.submission_number,
      recorded_by_email = excluded.recorded_by_email,
      recorded_at = now()
  returning * into after_row;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_help_answered',
    'organization',
    target_organization_id::text,
    case when before_row.fact_key is null then null else jsonb_build_object(
      'fact_key', before_row.fact_key,
      'value', before_row.value,
      'note', before_row.note,
      'send', before_row.submission_number
    ) end,
    jsonb_build_object(
      'fact_key', after_row.fact_key,
      'value', after_row.value,
      'note', after_row.note,
      'send', after_row.submission_number
    )
  );

  return jsonb_build_object('status', 'saved', 'recorded_at', after_row.recorded_at);
end;
$$;

revoke all on function public.owner_answer_setup_help(uuid, text, integer, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function public.owner_answer_setup_help(uuid, text, integer, jsonb, text, text)
  to service_role;
