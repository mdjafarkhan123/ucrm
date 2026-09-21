-- Communications A2 / Stage 3A: contractor-owned registration answers and immutable submissions.
-- The current registration row keeps the editable draft. Each attested submission is copied into an
-- append-only snapshot before the lifecycle moves under review. Provider submission remains a Jafar action.

alter table public.communication_sms_registrations
  add column draft_questionnaire_version integer not null default 1,
  add column draft_answers jsonb not null default '{}'::jsonb,
  add column draft_revision integer not null default 1,
  add column draft_updated_by uuid references auth.users(id) on delete set null,
  add column draft_updated_at timestamptz,
  add constraint communication_sms_registrations_draft_version_check
    check (draft_questionnaire_version >= 1),
  add constraint communication_sms_registrations_draft_answers_check
    check (jsonb_typeof(draft_answers) = 'object' and octet_length(draft_answers::text) <= 65536),
  add constraint communication_sms_registrations_draft_revision_check
    check (draft_revision >= 1);

create index communication_sms_registrations_draft_updated_by_idx
  on public.communication_sms_registrations (draft_updated_by)
  where draft_updated_by is not null;

create table public.communication_sms_registration_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  registration_id uuid not null,
  submission_number integer not null,
  questionnaire_version integer not null,
  answers jsonb not null,
  attestation_version text not null,
  attestation_text text not null,
  attested_by uuid not null,
  attestor_email text not null,
  attested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint communication_sms_registration_submissions_registration_fk
    foreign key (organization_id, registration_id)
    references public.communication_sms_registrations (organization_id, id) on delete cascade,
  constraint communication_sms_registration_submissions_number_key
    unique (registration_id, submission_number),
  constraint communication_sms_registration_submissions_number_check
    check (submission_number >= 1),
  constraint communication_sms_registration_submissions_questionnaire_check
    check (questionnaire_version >= 1),
  constraint communication_sms_registration_submissions_answers_check
    check (jsonb_typeof(answers) = 'object' and answers <> '{}'::jsonb
      and octet_length(answers::text) <= 65536),
  constraint communication_sms_registration_submissions_attestation_version_check
    check (char_length(trim(attestation_version)) between 1 and 100),
  constraint communication_sms_registration_submissions_attestation_text_check
    check (char_length(trim(attestation_text)) between 1 and 2000),
  constraint communication_sms_registration_submissions_attestor_email_check
    check (char_length(trim(attestor_email)) between 3 and 320)
);

create index communication_sms_registration_submissions_history_idx
  on public.communication_sms_registration_submissions
    (organization_id, registration_id, submission_number desc);

comment on table public.communication_sms_registration_submissions is
  'Immutable contractor-attested snapshots of SMS registration answers. Server-owned and append-only; provider '
  'submission remains a separate platform-owner action.';

create or replace function public.communication_sms_save_registration_draft(
  p_organization_id uuid,
  p_registration_id uuid,
  p_expected_revision integer,
  p_questionnaire_version integer,
  p_answers jsonb,
  p_actor uuid
) returns public.communication_sms_registrations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reg public.communication_sms_registrations;
begin
  if p_actor is null then
    raise exception 'a registration draft must record its editor' using errcode = 'P0001';
  end if;
  if p_questionnaire_version is null or p_questionnaire_version < 1 then
    raise exception 'the questionnaire version is invalid' using errcode = 'P0001';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'registration answers must be an object' using errcode = 'P0001';
  end if;

  select * into reg
  from public.communication_sms_registrations
  where id = p_registration_id and organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'registration not found' using errcode = 'P0001';
  end if;
  if reg.status not in ('waiting_for_info', 'action_needed') then
    raise exception 'this registration cannot be edited while it is under review or approved'
      using errcode = 'P0001';
  end if;
  if p_expected_revision is distinct from reg.draft_revision then
    raise exception 'registration draft changed'
      using errcode = 'P0001',
      detail = json_build_object(
        'code', 'revision_conflict',
        'current_revision', reg.draft_revision,
        'updated_by', reg.draft_updated_by,
        'updated_at', reg.draft_updated_at
      )::text;
  end if;

  update public.communication_sms_registrations
  set draft_questionnaire_version = p_questionnaire_version,
      draft_answers = p_answers,
      draft_revision = draft_revision + 1,
      draft_updated_by = p_actor,
      draft_updated_at = now(),
      updated_at = now()
  where id = reg.id
  returning * into reg;

  insert into public.communication_sms_registration_events (
    registration_id, organization_id, event_type, from_status, to_status, detail, created_by
  ) values (
    reg.id, reg.organization_id, 'info_updated', reg.status, reg.status,
    'Contractor registration answers saved', p_actor
  );

  return reg;
end;
$$;

create or replace function public.communication_sms_submit_registration_answers(
  p_organization_id uuid,
  p_registration_id uuid,
  p_expected_revision integer,
  p_questionnaire_version integer,
  p_answers jsonb,
  p_attestation_version text,
  p_attestation_text text,
  p_attested_by uuid,
  p_attestor_email text
) returns public.communication_sms_registrations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reg public.communication_sms_registrations;
  prior_status text;
  next_submission_number integer;
begin
  if p_attested_by is null then
    raise exception 'a registration submission must be attested by a user' using errcode = 'P0001';
  end if;
  if p_questionnaire_version is null or p_questionnaire_version < 1 then
    raise exception 'the questionnaire version is invalid' using errcode = 'P0001';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' or p_answers = '{}'::jsonb then
    raise exception 'complete registration answers are required' using errcode = 'P0001';
  end if;
  if p_attestation_version is null or char_length(trim(p_attestation_version)) = 0
     or p_attestation_text is null or char_length(trim(p_attestation_text)) = 0 then
    raise exception 'the attestation wording is required' using errcode = 'P0001';
  end if;
  if p_attestor_email is null or char_length(trim(p_attestor_email)) < 3 then
    raise exception 'the authenticated attestor email is required' using errcode = 'P0001';
  end if;

  select * into reg
  from public.communication_sms_registrations
  where id = p_registration_id and organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'registration not found' using errcode = 'P0001';
  end if;
  if reg.status not in ('waiting_for_info', 'action_needed') then
    raise exception 'this registration cannot be submitted while it is under review or approved'
      using errcode = 'P0001';
  end if;
  if p_expected_revision is distinct from reg.draft_revision then
    raise exception 'registration draft changed'
      using errcode = 'P0001',
      detail = json_build_object('code', 'revision_conflict', 'current_revision', reg.draft_revision)::text;
  end if;

  prior_status := reg.status;
  select coalesce(max(submission_number), 0) + 1 into next_submission_number
  from public.communication_sms_registration_submissions
  where registration_id = reg.id;

  insert into public.communication_sms_registration_submissions (
    organization_id, registration_id, submission_number, questionnaire_version, answers,
    attestation_version, attestation_text, attested_by, attestor_email
  ) values (
    reg.organization_id, reg.id, next_submission_number, p_questionnaire_version, p_answers,
    trim(p_attestation_version), trim(p_attestation_text), p_attested_by, lower(trim(p_attestor_email))
  );

  update public.communication_sms_registrations
  set status = 'under_review',
      draft_questionnaire_version = p_questionnaire_version,
      draft_answers = p_answers,
      draft_revision = draft_revision + 1,
      draft_updated_by = p_attested_by,
      draft_updated_at = now(),
      attested_by = p_attested_by,
      attested_at = now(),
      submitted_at = now(),
      required_fixes = null,
      updated_at = now()
  where id = reg.id
  returning * into reg;

  insert into public.communication_sms_registration_events (
    registration_id, organization_id, event_type, from_status, to_status, detail, created_by
  ) values (
    reg.id, reg.organization_id,
    case when prior_status = 'action_needed' then 'resubmitted' else 'submitted' end,
    prior_status, reg.status, 'Contractor submission ' || next_submission_number::text, p_attested_by
  );

  return reg;
end;
$$;

alter table public.communication_sms_registration_submissions enable row level security;

revoke all on table public.communication_sms_registration_submissions from public, anon, authenticated;
revoke all on table public.communication_sms_registration_submissions from service_role;
grant select, insert on table public.communication_sms_registration_submissions to service_role;

revoke all on function public.communication_sms_save_registration_draft(uuid, uuid, integer, integer, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_save_registration_draft(uuid, uuid, integer, integer, jsonb, uuid)
  to service_role;

revoke all on function public.communication_sms_submit_registration_answers(uuid, uuid, integer, integer, jsonb, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_submit_registration_answers(uuid, uuid, integer, integer, jsonb, text, text, uuid, text)
  to service_role;

-- The older provider-oriented submit command cannot preserve the contractor's answers. Keep it for migration
-- history compatibility, but remove the only application role that could call it.
revoke execute on function public.communication_sms_submit_registration(uuid, uuid, text) from service_role;
