-- Client onboarding B1: where the setup wizard keeps a contractor's answers while they are still a draft.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §2 and §3.1. Storage decision:
-- docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md. Industry reference: GOV.UK "Complete
-- multiple tasks" (a task list whose sections are marked done by the person) with per-answer autosave.
--
-- 1. organization_setup: one row per organization — whether the welcome has been shown.
-- 2. organization_setup_answers: one row per fact, the autosaved draft. "I don't have this yet" and "I need
--    Uplift's help" are answers too, stored without a value.
-- 3. organization_setup_sections: a row means the administrator marked that section done.
-- Owners and administrators read all three; nobody writes them directly. Every change arrives through the
-- three commands at the end.
--
-- The submitted snapshot (B13) and Uplift's accepted values (stage C) are separate tables added by those
-- parts; nothing here is ever treated as a final, attested answer.

-- 1. The organization's setup ------------------------------------------------------------------------------

create table public.organization_setup (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  -- Set the first time the welcome is shown, so it greets the administrator once and never again.
  welcome_seen_at timestamptz,
  welcome_seen_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.organization_setup is
  'One row per organization that has opened client setup. Administrators may read it, never write it: changes arrive through public.mark_organization_setup_welcome_seen and public.save_organization_setup_answers.';

create index organization_setup_welcome_seen_by_idx
  on public.organization_setup (welcome_seen_by) where welcome_seen_by is not null;

create trigger organization_setup_set_updated_at
  before update on public.organization_setup
  for each row execute function public.set_updated_at();

-- 2. Draft answers -----------------------------------------------------------------------------------------

create table public.organization_setup_answers (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- Which fact this answers, e.g. 'business.public_phone'. The list of facts, their wording and their
  -- validation live in src/lib/setup/catalogue.ts; a fact is asked once however many services reuse it.
  fact_key text not null,
  availability text not null,
  -- The answer itself when the contractor has it. Shaped by the fact's kind in the catalogue.
  value jsonb,
  -- What the contractor wants Uplift to know when they do not have the fact or need help with it.
  note text,
  updated_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, fact_key),
  constraint organization_setup_answers_fact_key_check check (
    fact_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' and char_length(fact_key) <= 80
  ),
  constraint organization_setup_answers_availability_check check (
    availability in ('have', 'not_yet', 'need_help')
  ),
  -- A value exists exactly when the contractor says they have the fact, so "need help" can never be
  -- mistaken for a completed answer.
  constraint organization_setup_answers_value_check check (
    (availability = 'have') = (value is not null and jsonb_typeof(value) <> 'null')
  ),
  constraint organization_setup_answers_value_size_check check (
    value is null or octet_length(value::text) <= 8000
  ),
  constraint organization_setup_answers_note_check check (
    note is null or (availability <> 'have' and note = btrim(note) and char_length(note) between 1 and 500)
  )
);

comment on table public.organization_setup_answers is
  'The setup wizard''s autosaved draft, one row per fact. Never an attested answer. Administrators may read it, never write it: every change arrives through public.save_organization_setup_answers.';

create index organization_setup_answers_updated_by_idx
  on public.organization_setup_answers (updated_by) where updated_by is not null;

-- 3. Sections marked done ----------------------------------------------------------------------------------

create table public.organization_setup_sections (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  section_key text not null,
  completed_at timestamptz not null default now(),
  completed_by uuid references auth.users (id) on delete set null,
  primary key (organization_id, section_key),
  constraint organization_setup_sections_section_key_check check (
    section_key ~ '^[a-z][a-z0-9_]*$' and char_length(section_key) <= 40
  )
);

comment on table public.organization_setup_sections is
  'A row means the administrator marked that setup section done. Administrators may read it, never write it: changes arrive through public.set_organization_setup_section_done.';

create index organization_setup_sections_completed_by_idx
  on public.organization_setup_sections (completed_by) where completed_by is not null;

-- Access ---------------------------------------------------------------------------------------------------

alter table public.organization_setup enable row level security;
alter table public.organization_setup_answers enable row level security;
alter table public.organization_setup_sections enable row level security;

revoke all on table public.organization_setup from public, anon, authenticated;
revoke all on table public.organization_setup_answers from public, anon, authenticated;
revoke all on table public.organization_setup_sections from public, anon, authenticated;

grant select on table public.organization_setup to authenticated;
grant select on table public.organization_setup_answers to authenticated;
grant select on table public.organization_setup_sections to authenticated;

grant all on table public.organization_setup to service_role;
grant all on table public.organization_setup_answers to service_role;
grant all on table public.organization_setup_sections to service_role;

-- Setup is the administrator's job, and its answers include contact details the rest of the team has no
-- reason to read.
create policy "administrators can view their organization setup"
  on public.organization_setup
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

create policy "administrators can view their setup answers"
  on public.organization_setup_answers
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

create policy "administrators can view their setup sections"
  on public.organization_setup_sections
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- Commands -------------------------------------------------------------------------------------------------

create function private.require_organization_setup_editor(target_organization_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  if not private.is_organization_admin(target_organization_id)
    or not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'Only an owner or administrator can change setup.'
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

revoke all on function private.require_organization_setup_editor(uuid) from public;
grant execute on function private.require_organization_setup_editor(uuid) to authenticated, service_role;

create function public.mark_organization_setup_welcome_seen(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform private.require_organization_setup_editor(target_organization_id);

  -- The first showing is the one that counts; opening the page again changes nothing.
  insert into public.organization_setup (organization_id, welcome_seen_at, welcome_seen_by)
  values (target_organization_id, now(), (select auth.uid()))
  on conflict (organization_id) do update
    set welcome_seen_at = now(),
        welcome_seen_by = (select auth.uid())
    where organization_setup.welcome_seen_at is null;

  return jsonb_build_object('status', 'saved');
end;
$$;

-- `new_answers` is one or more facts from the same autosave:
--   [{ "fact_key": text, "availability": "have" | "not_yet" | "need_help" | null, "value": json, "note": text }]
-- A null availability clears the answer. Each fact is its own row, so two devices filling in different
-- fields never overwrite each other; on the same field the later save wins, which is what a draft is.
create function public.save_organization_setup_answers(
  target_organization_id uuid,
  new_answers jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  saved_at timestamptz := now();
begin
  perform private.require_organization_setup_editor(target_organization_id);

  if new_answers is null
    or jsonb_typeof(new_answers) <> 'array'
    or jsonb_array_length(new_answers) not between 1 and 50 then
    raise exception 'The answers to save are missing.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new_answers) as item(answer)
    group by item.answer ->> 'fact_key'
    having count(*) > 1 or item.answer ->> 'fact_key' is null
  ) then
    raise exception 'Each answer must name one fact, once.' using errcode = 'check_violation';
  end if;

  insert into public.organization_setup (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;

  delete from public.organization_setup_answers as existing
  using jsonb_array_elements(new_answers) as item(answer)
  where existing.organization_id = target_organization_id
    and existing.fact_key = item.answer ->> 'fact_key'
    and item.answer ->> 'availability' is null;

  insert into public.organization_setup_answers as existing (
    organization_id, fact_key, availability, value, note, updated_by, updated_at
  )
  select
    target_organization_id,
    item.answer ->> 'fact_key',
    item.answer ->> 'availability',
    case when item.answer ->> 'availability' = 'have' then item.answer -> 'value' end,
    case
      when item.answer ->> 'availability' <> 'have' then nullif(btrim(item.answer ->> 'note'), '')
    end,
    (select auth.uid()),
    saved_at
  from jsonb_array_elements(new_answers) as item(answer)
  where item.answer ->> 'availability' is not null
  on conflict (organization_id, fact_key) do update
    set availability = excluded.availability,
        value = excluded.value,
        note = excluded.note,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  return jsonb_build_object('status', 'saved', 'saved_at', saved_at);
end;
$$;

create function public.set_organization_setup_section_done(
  target_organization_id uuid,
  target_section_key text,
  is_done boolean
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform private.require_organization_setup_editor(target_organization_id);

  if target_section_key is null or is_done is null then
    raise exception 'Choose a section.' using errcode = 'check_violation';
  end if;

  if is_done then
    insert into public.organization_setup_sections (organization_id, section_key, completed_by)
    values (target_organization_id, target_section_key, (select auth.uid()))
    on conflict (organization_id, section_key) do nothing;
  else
    delete from public.organization_setup_sections
    where organization_id = target_organization_id
      and section_key = target_section_key;
  end if;

  return jsonb_build_object('status', 'saved', 'done', is_done);
end;
$$;

revoke all on function public.mark_organization_setup_welcome_seen(uuid) from public, anon;
revoke all on function public.save_organization_setup_answers(uuid, jsonb) from public, anon;
revoke all on function public.set_organization_setup_section_done(uuid, text, boolean) from public, anon;

grant execute on function public.mark_organization_setup_welcome_seen(uuid) to authenticated, service_role;
grant execute on function public.save_organization_setup_answers(uuid, jsonb) to authenticated, service_role;
grant execute on function public.set_organization_setup_section_done(uuid, text, boolean)
  to authenticated, service_role;
