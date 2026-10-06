-- Client onboarding E6: training and handover (plan §6, §8, §10 journey 14).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §6. Jafar's choices of 2026-10-06: once the
-- newest preview has standing launch approval and the system has launched, Jafar marks it Live. From Ready for
-- Uplift onward an owner or administrator gives training details — attendees, time zone, preferred times, needs,
-- top tasks and recording consent — and can change them until Jafar books. Jafar books a confirmed time and a
-- Meet or Zoom link; an owner may say "We don't need training" instead. A cancelled booking needs another booking
-- or an owner skip before delivery can close. Consent can be given or withdrawn at any time; a recording link is
-- shown only while consent stands, and a withdrawal leaves Jafar a task to restrict the video at its host. Jafar
-- marks the project delivered once it is Live, training is booked or skipped, and the handover has his access and
-- ownership summary and at least one guide. Industry reference: client tasks and completion milestones in GUIDEcx
-- and Rocketlane.
--
-- 1. organization_setup_training: the client's details, consent, skip, Jafar's booking and the recording link.
-- 2. organization_setup_handover: Live, Jafar's handover summary and guides, and Delivered.
-- 3. organization_setup_handover_events: the history both sides read.
-- 4. The client's commands: save details, skip, give or withdraw consent.
-- 5. Jafar's commands: book or change, cancel, recording link, mark live, save the handover, mark delivered.
-- 6. A live project takes no new preview release.
-- 7. public.owner_client_onboarding_list knows Live and Delivered, and hides delivered clients unless asked.

-- 1. Training ---------------------------------------------------------------------------------------------------

create table public.organization_setup_training (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  -- [{ name, role, email }], 1 to 10 people; mirrors TRAINING_ATTENDEES_MAX in src/lib/setup/training.ts.
  attendees jsonb not null default '[]'::jsonb check (
    jsonb_typeof(attendees) = 'array' and jsonb_array_length(attendees) <= 10
  ),
  time_zone text check (time_zone is null or char_length(time_zone) between 1 and 64),
  preferred_times text check (preferred_times is null or char_length(preferred_times) between 1 and 1000),
  needs text check (needs is null or char_length(needs) between 1 and 1000),
  top_tasks text check (top_tasks is null or char_length(top_tasks) between 1 and 2000),
  details_updated_at timestamptz,
  details_updated_by_name text check (details_updated_by_name is null or char_length(details_updated_by_name) between 1 and 320),
  -- Null until answered.
  recording_consent boolean,
  consent_changed_at timestamptz,
  consent_changed_by_name text check (consent_changed_by_name is null or char_length(consent_changed_by_name) between 1 and 320),
  -- "We don't need training", by an owner.
  skipped_at timestamptz,
  skipped_by_name text check (skipped_by_name is null or char_length(skipped_by_name) between 1 and 320),
  -- Jafar's booking: the confirmed time and the meeting link.
  meeting_at timestamptz,
  meeting_url text check (meeting_url is null or (char_length(meeting_url) <= 500 and meeting_url ~ '^https://\S+$')),
  booked_at timestamptz,
  booked_by_email text check (booked_by_email is null or char_length(booked_by_email) between 3 and 320),
  -- A private video link Jafar adds after training. Clients read it only through the handover route, while
  -- consent stands; it is never emailed.
  recording_url text check (recording_url is null or (char_length(recording_url) <= 500 and recording_url ~ '^https://\S+$')),
  recording_added_at timestamptz,
  constraint organization_setup_training_booking_check check (
    (meeting_at is null) = (meeting_url is null)
    and (meeting_at is null) = (booked_at is null)
    and (meeting_at is null) = (booked_by_email is null)
  ),
  -- A booking settles the requirement instead of a skip.
  constraint organization_setup_training_skip_or_booking_check check (skipped_at is null or meeting_at is null),
  constraint organization_setup_training_skip_check check ((skipped_at is null) = (skipped_by_name is null)),
  constraint organization_setup_training_consent_check check (
    (recording_consent is null) = (consent_changed_at is null)
  ),
  constraint organization_setup_training_recording_check check ((recording_url is null) = (recording_added_at is null))
);

comment on table public.organization_setup_training is
  'Client onboarding E6: the client''s training details, recording consent and skip, Jafar''s booking and the recording link. Administrators read every column but the recording link; rows change only through the setup training commands.';

alter table public.organization_setup_training enable row level security;
revoke all on table public.organization_setup_training from public, anon, authenticated;
grant select (
  organization_id, attendees, time_zone, preferred_times, needs, top_tasks, details_updated_at,
  details_updated_by_name, recording_consent, consent_changed_at, consent_changed_by_name, skipped_at,
  skipped_by_name, meeting_at, meeting_url, booked_at
) on table public.organization_setup_training to authenticated;
grant all on table public.organization_setup_training to service_role;

create policy "administrators can view their setup training"
  on public.organization_setup_training
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 2. Handover ---------------------------------------------------------------------------------------------------

create table public.organization_setup_handover (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  live_at timestamptz,
  -- The approved preview version that went live.
  live_version integer,
  live_by_email text check (live_by_email is null or char_length(live_by_email) between 3 and 320),
  -- Jafar's access and ownership summary: who owns which account, and where the logins live.
  access_summary text check (access_summary is null or char_length(access_summary) between 1 and 4000),
  -- [{ title, url }], up to 20; mirrors HANDOVER_GUIDES_MAX in src/lib/setup/training.ts.
  guides jsonb not null default '[]'::jsonb check (
    jsonb_typeof(guides) = 'array' and jsonb_array_length(guides) <= 20
  ),
  updated_at timestamptz,
  delivered_at timestamptz,
  delivered_by_email text check (delivered_by_email is null or char_length(delivered_by_email) between 3 and 320),
  constraint organization_setup_handover_live_check check (
    (live_at is null) = (live_version is null) and (live_at is null) = (live_by_email is null)
  ),
  constraint organization_setup_handover_delivered_check check (
    (delivered_at is null) = (delivered_by_email is null) and (delivered_at is null or live_at is not null)
  )
);

comment on table public.organization_setup_handover is
  'Client onboarding E6: when the system went live, Jafar''s handover summary and guides, and when the project was delivered. Administrators may read it; rows change only through the setup handover commands.';

-- Live and Delivered are final.
create function private.refuse_setup_handover_undo()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (old.live_at is not null and row(new.live_at, new.live_version, new.live_by_email)
        is distinct from row(old.live_at, old.live_version, old.live_by_email))
    or (old.delivered_at is not null and row(new.delivered_at, new.delivered_by_email)
        is distinct from row(old.delivered_at, old.delivered_by_email)) then
    raise exception 'Live and delivered cannot be changed.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger organization_setup_handover_final
  before update on public.organization_setup_handover
  for each row execute function private.refuse_setup_handover_undo();

alter table public.organization_setup_handover enable row level security;
revoke all on table public.organization_setup_handover from public, anon, authenticated;
grant select on table public.organization_setup_handover to authenticated;
grant all on table public.organization_setup_handover to service_role;

create policy "administrators can view their setup handover"
  on public.organization_setup_handover
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 3. History ----------------------------------------------------------------------------------------------------

create table public.organization_setup_handover_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- Mirrors HANDOVER_EVENT_KINDS in src/lib/setup/training.ts.
  kind text not null check (kind in (
    'live', 'delivered', 'handover_updated', 'training_details', 'training_skipped', 'training_booked',
    'training_changed', 'training_cancelled', 'consent_given', 'consent_withdrawn', 'recording_added',
    'recording_removed'
  )),
  happened_at timestamptz not null default now(),
  -- 'uplift' for Jafar, 'client' for a team member; the client reads Uplift's actions as "Uplift".
  actor_kind text not null check (actor_kind in ('uplift', 'client')),
  actor_name text not null check (char_length(actor_name) between 1 and 320),
  -- Booking times and versions; never a recording link.
  detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object')
);

create index organization_setup_handover_events_history
  on public.organization_setup_handover_events (organization_id, happened_at desc);

comment on table public.organization_setup_handover_events is
  'Client onboarding E6: every training and handover change, for the handover page and Jafar''s panel. Rows are only added, by the setup training and handover commands.';

alter table public.organization_setup_handover_events enable row level security;
revoke all on table public.organization_setup_handover_events from public, anon, authenticated;
grant select on table public.organization_setup_handover_events to authenticated;
grant all on table public.organization_setup_handover_events to service_role;

create policy "administrators can view their setup handover history"
  on public.organization_setup_handover_events
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

create function private.add_setup_handover_event(
  target_organization_id uuid,
  event_kind text,
  by_kind text,
  by_name text,
  event_detail jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.organization_setup_handover_events (organization_id, kind, actor_kind, actor_name, detail)
  values (target_organization_id, event_kind, by_kind, by_name, coalesce(event_detail, '{}'::jsonb));
$$;

revoke all on function private.add_setup_handover_event(uuid, text, text, text, jsonb) from public;

-- Jafar's actions also go to the platform audit trail.
create function private.audit_setup_handover(
  actor_email text,
  target_organization_id uuid,
  event_type text,
  after_state jsonb
) returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (actor_email, event_type, 'organization', target_organization_id::text, null, after_state);
$$;

revoke all on function private.audit_setup_handover(text, uuid, text, jsonb) from public;

-- 4. The client's commands ------------------------------------------------------------------------------------

-- Who is acting, in the client's words.
create function private.setup_training_actor_name()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select private.support_member_name((select auth.uid()));
$$;

revoke all on function private.setup_training_actor_name() from public;

-- Records a consent change; true when a withdrawal hid a recording link Jafar must now restrict at its host.
create function private.set_setup_training_consent(
  target_organization_id uuid,
  consent boolean,
  by_name text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous public.organization_setup_training;
begin
  select * into previous from public.organization_setup_training
  where organization_id = target_organization_id for update;
  if previous.recording_consent is not distinct from consent then
    return false;
  end if;
  insert into public.organization_setup_training (organization_id, recording_consent, consent_changed_at, consent_changed_by_name)
  values (target_organization_id, consent, now(), by_name)
  on conflict (organization_id) do update
    set recording_consent = excluded.recording_consent,
        consent_changed_at = excluded.consent_changed_at,
        consent_changed_by_name = excluded.consent_changed_by_name;
  perform private.add_setup_handover_event(
    target_organization_id, case when consent then 'consent_given' else 'consent_withdrawn' end, 'client', by_name
  );
  return not consent and previous.recording_url is not null;
end;
$$;

revoke all on function private.set_setup_training_consent(uuid, boolean, text) from public;

-- An owner or administrator gives the training details, from Ready for Uplift until Jafar books. `consent` saves
-- the recording answer with them (null leaves it as it is).
create function public.client_save_setup_training(
  target_organization_id uuid,
  new_attendees jsonb,
  new_time_zone text,
  new_preferred_times text,
  new_needs text,
  new_top_tasks text,
  consent boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current public.organization_setup_training;
  by_name text;
  attendee jsonb;
  restrict_recording boolean := false;
begin
  perform private.require_organization_setup_editor(target_organization_id);
  if not exists (select 1 from public.organization_setup_ready where organization_id = target_organization_id) then
    raise exception 'Training details open once Uplift has accepted your setup.' using errcode = 'check_violation';
  end if;

  select * into current from public.organization_setup_training
  where organization_id = target_organization_id for update;
  if current.meeting_at is not null then
    raise exception 'Your training is booked. Ask Uplift in Chat with Uplift to change it.'
      using errcode = 'check_violation';
  end if;
  if current.skipped_at is not null then
    raise exception 'Your owner said you don''t need training. Ask Uplift in Chat with Uplift if that has changed.'
      using errcode = 'check_violation';
  end if;

  if new_attendees is null or jsonb_typeof(new_attendees) <> 'array'
    or jsonb_array_length(new_attendees) not between 1 and 10 then
    raise exception 'Add between 1 and 10 people.' using errcode = 'check_violation';
  end if;
  for attendee in select value from jsonb_array_elements(new_attendees) loop
    if jsonb_typeof(attendee) <> 'object'
      or char_length(btrim(coalesce(attendee ->> 'name', ''))) not between 1 and 120
      or char_length(coalesce(attendee ->> 'role', '')) > 120
      or coalesce(attendee ->> 'email', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
      or char_length(attendee ->> 'email') > 320 then
      raise exception 'Give each person a name and an email address.' using errcode = 'check_violation';
    end if;
  end loop;
  if nullif(btrim(coalesce(new_time_zone, '')), '') is null then
    raise exception 'Choose your time zone.' using errcode = 'check_violation';
  end if;
  if nullif(btrim(coalesce(new_preferred_times, '')), '') is null then
    raise exception 'Say which days and times suit you.' using errcode = 'check_violation';
  end if;

  by_name := private.setup_training_actor_name();
  insert into public.organization_setup_training (
    organization_id, attendees, time_zone, preferred_times, needs, top_tasks, details_updated_at,
    details_updated_by_name
  ) values (
    target_organization_id, new_attendees, btrim(new_time_zone), btrim(new_preferred_times),
    nullif(btrim(coalesce(new_needs, '')), ''), nullif(btrim(coalesce(new_top_tasks, '')), ''), now(), by_name
  )
  on conflict (organization_id) do update
    set attendees = excluded.attendees,
        time_zone = excluded.time_zone,
        preferred_times = excluded.preferred_times,
        needs = excluded.needs,
        top_tasks = excluded.top_tasks,
        details_updated_at = excluded.details_updated_at,
        details_updated_by_name = excluded.details_updated_by_name;
  perform private.add_setup_handover_event(target_organization_id, 'training_details', 'client', by_name);

  if consent is not null then
    restrict_recording := private.set_setup_training_consent(target_organization_id, consent, by_name);
  end if;
  return jsonb_build_object('status', 'saved', 'restrict_recording', restrict_recording);
end;
$$;

revoke all on function public.client_save_setup_training(uuid, jsonb, text, text, text, text, boolean) from public, anon;
grant execute on function public.client_save_setup_training(uuid, jsonb, text, text, text, text, boolean) to authenticated, service_role;

-- "We don't need training": an owner only, from Ready onward, while nothing is booked.
create function public.client_skip_setup_training(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current public.organization_setup_training;
  by_name text;
begin
  perform private.require_organization_setup_editor(target_organization_id);
  if not exists (
    select 1 from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and membership.role = 'owner'
  ) then
    raise exception 'Only the business owner can say you don''t need training.' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.organization_setup_ready where organization_id = target_organization_id) then
    raise exception 'Training opens once Uplift has accepted your setup.' using errcode = 'check_violation';
  end if;

  select * into current from public.organization_setup_training
  where organization_id = target_organization_id for update;
  if current.skipped_at is not null then
    return jsonb_build_object('status', 'unchanged');
  end if;
  if current.meeting_at is not null then
    raise exception 'Your training is booked. Ask Uplift in Chat with Uplift to cancel it.'
      using errcode = 'check_violation';
  end if;

  by_name := private.setup_training_actor_name();
  insert into public.organization_setup_training (organization_id, skipped_at, skipped_by_name)
  values (target_organization_id, now(), by_name)
  on conflict (organization_id) do update
    set skipped_at = excluded.skipped_at, skipped_by_name = excluded.skipped_by_name;
  perform private.add_setup_handover_event(target_organization_id, 'training_skipped', 'client', by_name);
  return jsonb_build_object('status', 'skipped');
end;
$$;

revoke all on function public.client_skip_setup_training(uuid) from public, anon;
grant execute on function public.client_skip_setup_training(uuid) to authenticated, service_role;

-- Gives or withdraws recording consent at any time from Ready onward, booked, skipped or delivered.
create function public.client_set_setup_training_consent(target_organization_id uuid, consent boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  restrict_recording boolean;
begin
  perform private.require_organization_setup_editor(target_organization_id);
  if consent is null then
    raise exception 'Choose yes or no.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.organization_setup_ready where organization_id = target_organization_id) then
    raise exception 'Training opens once Uplift has accepted your setup.' using errcode = 'check_violation';
  end if;
  restrict_recording := private.set_setup_training_consent(
    target_organization_id, consent, private.setup_training_actor_name()
  );
  return jsonb_build_object('status', 'saved', 'restrict_recording', restrict_recording);
end;
$$;

revoke all on function public.client_set_setup_training_consent(uuid, boolean) from public, anon;
grant execute on function public.client_set_setup_training_consent(uuid, boolean) to authenticated, service_role;

-- 5. Jafar's commands -------------------------------------------------------------------------------------------

-- Books training, or changes the time or link of a booking — before or after delivery. The client must have given
-- at least one attendee, who is emailed the details. A booking replaces an owner's skip.
create function public.owner_book_setup_training(
  target_organization_id uuid,
  new_meeting_at timestamptz,
  new_meeting_url text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_url text := nullif(btrim(coalesce(new_meeting_url, '')), '');
  current public.organization_setup_training;
  booked public.organization_setup_training;
  event_kind text;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is booking.' using errcode = 'check_violation';
  end if;
  if new_meeting_at is null then
    raise exception 'Choose the training time.' using errcode = 'check_violation';
  end if;
  if clean_url is null or clean_url !~ '^https://\S+$' or char_length(clean_url) > 500 then
    raise exception 'Add the Meet or Zoom link, starting with https://.' using errcode = 'check_violation';
  end if;

  select * into current from public.organization_setup_training
  where organization_id = target_organization_id for update;
  if current.organization_id is null or jsonb_array_length(current.attendees) = 0 then
    raise exception 'The client has not said who is coming yet. Ask them to fill in the training details.'
      using errcode = 'check_violation';
  end if;
  if current.meeting_at is not distinct from new_meeting_at and current.meeting_url is not distinct from clean_url then
    return jsonb_build_object('status', 'unchanged');
  end if;
  event_kind := case when current.meeting_at is null then 'training_booked' else 'training_changed' end;

  update public.organization_setup_training
  set meeting_at = new_meeting_at, meeting_url = clean_url, booked_at = now(), booked_by_email = clean_email,
      skipped_at = null, skipped_by_name = null
  where organization_id = target_organization_id
  returning * into booked;

  perform private.add_setup_handover_event(
    target_organization_id, event_kind, 'uplift', clean_email,
    jsonb_build_object('meeting_at', new_meeting_at, 'previous_meeting_at', current.meeting_at)
  );
  perform private.audit_setup_handover(
    clean_email, target_organization_id, 'organization.setup_' || event_kind,
    jsonb_build_object('meeting_at', new_meeting_at)
  );

  return jsonb_build_object(
    'status', case when event_kind = 'training_booked' then 'booked' else 'changed' end,
    'booked_at', booked.booked_at,
    'meeting_at', booked.meeting_at,
    'meeting_url', booked.meeting_url,
    'time_zone', booked.time_zone,
    'attendees', booked.attendees
  );
end;
$$;

revoke all on function public.owner_book_setup_training(uuid, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.owner_book_setup_training(uuid, timestamptz, text, text) to service_role;

-- Cancels a booking. Before delivery, another booking or an owner skip is needed before it can close.
create function public.owner_cancel_setup_training(target_organization_id uuid, actor_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  current public.organization_setup_training;
  event_id bigint;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is cancelling.' using errcode = 'check_violation';
  end if;
  select * into current from public.organization_setup_training
  where organization_id = target_organization_id for update;
  if current.meeting_at is null then
    return jsonb_build_object('status', 'unchanged');
  end if;

  update public.organization_setup_training
  set meeting_at = null, meeting_url = null, booked_at = null, booked_by_email = null
  where organization_id = target_organization_id;

  insert into public.organization_setup_handover_events (organization_id, kind, actor_kind, actor_name, detail)
  values (target_organization_id, 'training_cancelled', 'uplift', clean_email,
    jsonb_build_object('meeting_at', current.meeting_at))
  returning id into event_id;
  perform private.audit_setup_handover(
    clean_email, target_organization_id, 'organization.setup_training_cancelled',
    jsonb_build_object('meeting_at', current.meeting_at)
  );

  return jsonb_build_object(
    'status', 'cancelled',
    'event_id', event_id,
    'meeting_at', current.meeting_at,
    'time_zone', current.time_zone,
    'attendees', current.attendees
  );
end;
$$;

revoke all on function public.owner_cancel_setup_training(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_cancel_setup_training(uuid, text) to service_role;

-- Adds the private recording link after training, only while the client consents; null removes it at any time.
create function public.owner_set_setup_training_recording(
  target_organization_id uuid,
  new_recording_url text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_url text := nullif(btrim(coalesce(new_recording_url, '')), '');
  current public.organization_setup_training;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  select * into current from public.organization_setup_training
  where organization_id = target_organization_id for update;

  if clean_url is null then
    if current.recording_url is null then
      return jsonb_build_object('status', 'unchanged');
    end if;
    update public.organization_setup_training
    set recording_url = null, recording_added_at = null
    where organization_id = target_organization_id;
    perform private.add_setup_handover_event(target_organization_id, 'recording_removed', 'uplift', clean_email);
    perform private.audit_setup_handover(clean_email, target_organization_id, 'organization.setup_training_recording_removed', '{}'::jsonb);
    return jsonb_build_object('status', 'removed');
  end if;

  if clean_url !~ '^https://\S+$' or char_length(clean_url) > 500 then
    raise exception 'Use a full address starting with https://.' using errcode = 'check_violation';
  end if;
  if current.recording_consent is distinct from true then
    raise exception 'The client has not agreed to a recording.' using errcode = 'check_violation';
  end if;
  if current.meeting_at is null or current.meeting_at > now() then
    raise exception 'Add the recording after the training has happened.' using errcode = 'check_violation';
  end if;
  if current.recording_url is not distinct from clean_url then
    return jsonb_build_object('status', 'unchanged');
  end if;

  update public.organization_setup_training
  set recording_url = clean_url, recording_added_at = now()
  where organization_id = target_organization_id;
  perform private.add_setup_handover_event(target_organization_id, 'recording_added', 'uplift', clean_email);
  perform private.audit_setup_handover(clean_email, target_organization_id, 'organization.setup_training_recording_added', '{}'::jsonb);
  return jsonb_build_object('status', 'added');
end;
$$;

revoke all on function public.owner_set_setup_training_recording(uuid, text, text) from public, anon, authenticated;
grant execute on function public.owner_set_setup_training_recording(uuid, text, text) to service_role;

-- Marks the system live: the newest released preview must have the standing launch approval. Once only.
create function public.owner_mark_setup_live(target_organization_id uuid, actor_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  existing public.organization_setup_handover;
  newest integer;
  approved_version integer;
  marked public.organization_setup_handover;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is marking it.' using errcode = 'check_violation';
  end if;
  perform 1 from public.organization_setup where organization_id = target_organization_id for update;

  select * into existing from public.organization_setup_handover where organization_id = target_organization_id;
  if existing.live_at is not null then
    return jsonb_build_object('status', 'unchanged', 'live_at', existing.live_at);
  end if;

  select max(version) into newest from public.organization_setup_previews
  where organization_id = target_organization_id and released_at is not null;
  select version into approved_version from public.organization_setup_launch_approvals
  where organization_id = target_organization_id and status = 'approved' and replaced_at is null;
  if newest is null or approved_version is distinct from newest then
    raise exception 'The newest preview needs launch approval before the system can be marked live.'
      using errcode = 'check_violation';
  end if;

  insert into public.organization_setup_handover (organization_id, live_at, live_version, live_by_email)
  values (target_organization_id, now(), newest, clean_email)
  on conflict (organization_id) do update
    set live_at = excluded.live_at, live_version = excluded.live_version, live_by_email = excluded.live_by_email
  returning * into marked;

  perform private.add_setup_handover_event(
    target_organization_id, 'live', 'uplift', clean_email, jsonb_build_object('version', newest)
  );
  perform private.audit_setup_handover(
    clean_email, target_organization_id, 'organization.setup_live', jsonb_build_object('version', newest)
  );
  return jsonb_build_object('status', 'live', 'live_at', marked.live_at, 'version', newest);
end;
$$;

revoke all on function public.owner_mark_setup_live(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_mark_setup_live(uuid, text) to service_role;

-- Jafar's access and ownership summary and the guides, saved whole; from Ready onward, also after delivery.
create function public.owner_save_setup_handover(
  target_organization_id uuid,
  new_access_summary text,
  new_guides jsonb,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_summary text := nullif(btrim(coalesce(new_access_summary, '')), '');
  guide jsonb;
  existing public.organization_setup_handover;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.organization_setup_ready where organization_id = target_organization_id) then
    raise exception 'Record Ready for Uplift first.' using errcode = 'check_violation';
  end if;
  if char_length(clean_summary) > 4000 then
    raise exception 'Keep the summary to 4000 characters.' using errcode = 'check_violation';
  end if;
  if new_guides is null or jsonb_typeof(new_guides) <> 'array' or jsonb_array_length(new_guides) > 20 then
    raise exception 'Add up to 20 guides.' using errcode = 'check_violation';
  end if;
  for guide in select value from jsonb_array_elements(new_guides) loop
    if jsonb_typeof(guide) <> 'object'
      or char_length(btrim(coalesce(guide ->> 'title', ''))) not between 1 and 120
      or coalesce(guide ->> 'url', '') !~ '^https://\S+$'
      or char_length(guide ->> 'url') > 500 then
      raise exception 'Give each guide a title and an address starting with https://.' using errcode = 'check_violation';
    end if;
  end loop;

  select * into existing from public.organization_setup_handover
  where organization_id = target_organization_id for update;
  if existing.organization_id is not null
    and existing.access_summary is not distinct from clean_summary
    and existing.guides = new_guides then
    return jsonb_build_object('status', 'unchanged');
  end if;

  insert into public.organization_setup_handover (organization_id, access_summary, guides, updated_at)
  values (target_organization_id, clean_summary, new_guides, now())
  on conflict (organization_id) do update
    set access_summary = excluded.access_summary, guides = excluded.guides, updated_at = excluded.updated_at;

  perform private.add_setup_handover_event(
    target_organization_id, 'handover_updated', 'uplift', clean_email,
    jsonb_build_object('guides', jsonb_array_length(new_guides))
  );
  perform private.audit_setup_handover(
    clean_email, target_organization_id, 'organization.setup_handover_saved',
    jsonb_build_object('guides', jsonb_array_length(new_guides), 'has_summary', clean_summary is not null)
  );
  return jsonb_build_object('status', 'saved');
end;
$$;

revoke all on function public.owner_save_setup_handover(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.owner_save_setup_handover(uuid, text, jsonb, text) to service_role;

-- What still stands between Live and Delivered; empty when delivery can close. Mirrors deliveryBlockers in
-- src/lib/setup/training.ts.
create function private.setup_delivery_blockers(target_organization_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[
    case when handover.live_at is null then 'not_live' end,
    case when training.meeting_at is null and training.skipped_at is null then 'training' end,
    case when handover.access_summary is null then 'access_summary' end,
    case when coalesce(jsonb_array_length(handover.guides), 0) = 0 then 'guides' end
  ], null)
  from (select target_organization_id as organization_id) as target
  left join public.organization_setup_handover as handover on handover.organization_id = target.organization_id
  left join public.organization_setup_training as training on training.organization_id = target.organization_id;
$$;

revoke all on function private.setup_delivery_blockers(uuid) from public;

-- Marks the project delivered once nothing blocks it. Open outside waits never block. Once only.
create function public.owner_mark_setup_delivered(target_organization_id uuid, actor_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  existing public.organization_setup_handover;
  blockers text[];
  delivered public.organization_setup_handover;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is marking it.' using errcode = 'check_violation';
  end if;
  perform 1 from public.organization_setup where organization_id = target_organization_id for update;
  perform 1 from public.organization_setup_training where organization_id = target_organization_id for update;

  select * into existing from public.organization_setup_handover
  where organization_id = target_organization_id for update;
  if existing.delivered_at is not null then
    return jsonb_build_object('status', 'unchanged', 'delivered_at', existing.delivered_at);
  end if;

  blockers := private.setup_delivery_blockers(target_organization_id);
  if cardinality(blockers) > 0 then
    raise exception '%', case blockers[1]
      when 'not_live' then 'Mark the system live first.'
      when 'training' then 'Book the training, or wait for the owner to say they don''t need it.'
      when 'access_summary' then 'Write the access and ownership summary first.'
      else 'Add at least one guide first.'
    end using errcode = 'check_violation';
  end if;

  update public.organization_setup_handover
  set delivered_at = now(), delivered_by_email = clean_email
  where organization_id = target_organization_id
  returning * into delivered;

  perform private.add_setup_handover_event(target_organization_id, 'delivered', 'uplift', clean_email);
  perform private.audit_setup_handover(clean_email, target_organization_id, 'organization.setup_delivered', '{}'::jsonb);
  return jsonb_build_object('status', 'delivered', 'delivered_at', delivered.delivered_at);
end;
$$;

revoke all on function public.owner_mark_setup_delivered(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_mark_setup_delivered(uuid, text) to service_role;

-- 6. A live project takes no new preview ------------------------------------------------------------------------
-- After launch, further changes are support requests; a new release would replace the approval that went live.

create function private.refuse_preview_release_after_live()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.released_at is null and new.released_at is not null and exists (
    select 1 from public.organization_setup_handover
    where organization_id = new.organization_id and live_at is not null
  ) then
    raise exception 'The system is live. Handle further changes through Chat with Uplift.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.refuse_preview_release_after_live() from public;

create trigger organization_setup_previews_not_after_live
  before update of released_at on public.organization_setup_previews
  for each row execute function private.refuse_preview_release_after_live();

-- 7. Jafar's onboarding list -----------------------------------------------------------------------------------
-- Unchanged from 20261102090000_setup_launch_approvals.sql except: delivered clients are left out unless
-- `include_delivered`, before the per-client work; Live and Delivered and the training state are returned; a
-- delivered client is nobody's move ('delivered'); once live, missing training details are the client's move
-- ('give_training_details'), then booking ('book_training') and the handover ('finish_handover') are Uplift's;
-- totals count delivered clients. The new argument means the old signature is dropped.

drop function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer);

create function public.owner_client_onboarding_list(
  setup_catalogue jsonb,
  search_term text default null,
  waiting_filter text default null,
  cursor_account_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50,
  include_delivered boolean default false
) returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  with catalogue as (
    select
      section.position,
      section.value ->> 'key' as section_key,
      nullif(section.value ->> 'service_key', '') as service_key,
      array(select jsonb_array_elements_text(section.value -> 'facts')) as fact_keys,
      array(select jsonb_array_elements_text(section.value -> 'required')) as required_keys
    from jsonb_array_elements(setup_catalogue) with ordinality as section(value, position)
  ),
  clients as (
    select
      organization.id,
      organization.name,
      organization.lifecycle_status,
      provision.created_at as account_created_at,
      application.payment_reversed_at,
      handover.live_at,
      handover.delivered_at,
      agreement.package_name,
      coalesce(agreement.service_keys, '{}'::text[]) as service_keys
    from public.platform_onboarding_application_provisions as provision
    join public.platform_onboarding_applications as application on application.id = provision.application_id
    join public.organizations as organization on organization.id = provision.organization_id
    left join lateral (
      select
        edition.name as package_name,
        array(
          select service ->> 'service_key'
          from jsonb_array_elements(edition.included_services) as service
          where service ->> 'service_key' is not null
        ) as service_keys
      from public.organization_package_agreements as current_agreement
      join public.package_editions as edition on edition.id = current_agreement.edition_id
      where current_agreement.organization_id = organization.id
        and current_agreement.cancelled_at is null
        and current_agreement.effective_from <= now()
      order by current_agreement.effective_from desc, current_agreement.created_at desc
      limit 1
    ) as agreement on true
    left join public.organization_setup_handover as handover on handover.organization_id = organization.id
    where provision.status = 'succeeded'
      -- E6: a delivered client leaves the list unless Jafar asks for them, before any of the work below.
      and (include_delivered or handover.delivered_at is null)
  ),
  measured as (
    select
      client.*,
      setup.welcome_seen_at,
      own.sections_total,
      cardinality(shown.fact_keys) as facts_total,
      answers.answered,
      answers.help_count,
      answers.last_answer_at,
      sections.done_count,
      sections.next_section_key,
      sections.last_section_at,
      support.unread_count,
      sent.submission_number as sent_number,
      sent.submitted_at as sent_at,
      returns.returned_count,
      returns.returned_at,
      ready.submission_number as ready_number,
      ready.ready_at,
      ready.target_from,
      ready.target_to,
      waits.open_count as waits_open,
      waits.action_count as waits_action,
      waits.changed_at as waits_changed_at,
      preview.version as preview_version,
      preview.released_at as preview_released_at,
      preview.notes_sent_at as preview_sent_at,
      preview.unsorted_count as preview_unsorted,
      approval.status as approval_status,
      approval.requested_at as approval_requested_at,
      approval.not_yet_at as approval_not_yet_at,
      approval.approved_at as approval_approved_at,
      approval.version as approval_version,
      training.meeting_at as training_meeting_at,
      training.skipped_at as training_skipped_at,
      training.details_at as training_details_at
    from clients as client
    left join public.organization_setup as setup on setup.organization_id = client.id
    cross join lateral (
      -- The stages this client is asked: everyone's, and those of a service their package includes.
      select
        (select count(*)::integer from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys))
          as sections_total,
        array(
          select unnest(catalogue.fact_keys) from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
        ) as fact_keys
    ) as own
    -- Questions an earlier answer or the package hides are neither counted nor required.
    cross join lateral (
      select public.setup_hidden_fact_keys(setup_catalogue, own.fact_keys, client.id, client.service_keys)
        as fact_keys
    ) as hidden
    cross join lateral (
      select array(
        select fact.fact_key from unnest(own.fact_keys) as fact(fact_key)
        where not (fact.fact_key = any (hidden.fact_keys))
      ) as fact_keys
    ) as shown
    cross join lateral (
      select
        count(*)::integer as answered,
        (count(*) filter (where answer.availability = 'need_help'))::integer as help_count,
        max(answer.updated_at) as last_answer_at
      from public.organization_setup_answers as answer
      where answer.organization_id = client.id
        and answer.fact_key = any (shown.fact_keys)
    ) as answers
    cross join lateral (
      select
        (count(*) filter (where status.done))::integer as done_count,
        (array_agg(status.section_key order by status.position) filter (where not status.done))[1]
          as next_section_key,
        max(status.completed_at) as last_section_at
      from (
        select
          catalogue.position,
          catalogue.section_key,
          marked.completed_at,
          marked.completed_at is not null and not exists (
            select 1
            from unnest(catalogue.required_keys) as required(fact_key)
            where not (required.fact_key = any (hidden.fact_keys))
              and not exists (
              select 1
              from public.organization_setup_answers as answer
              where answer.organization_id = client.id
                and answer.fact_key = required.fact_key
            )
          ) as done
        from catalogue
        left join public.organization_setup_sections as marked
          on marked.organization_id = client.id
         and marked.section_key = catalogue.section_key
        where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
      ) as status
    ) as sections
    cross join lateral (
      select count(*)::integer as unread_count
      from public.support_threads as thread
      where thread.organization_id = client.id
        and thread.last_message_sender_kind = 'member'
        and thread.last_message_at > coalesce(thread.uplift_last_read_at, '-infinity'::timestamptz)
    ) as support
    -- The newest Send to Uplift, if any; the (organization, number) key makes this one index probe.
    left join lateral (
      select submission.submission_number, submission.submitted_at
      from public.organization_setup_submissions as submission
      where submission.organization_id = client.id
      order by submission.submission_number desc
      limit 1
    ) as sent on true
    -- Sections Uplift sent back on that send; a later send hands them back to Uplift. Keyed by organization.
    cross join lateral (
      select count(*)::integer as returned_count, max(review.reviewed_at) as returned_at
      from public.organization_setup_section_reviews as review
      where review.organization_id = client.id
        and review.decision = 'returned'
        and review.submission_number = sent.submission_number
    ) as returns
    -- C4: Ready for Uplift, if recorded; one primary-key probe.
    left join public.organization_setup_ready as ready on ready.organization_id = client.id
    -- E2: outside waits still open, and those needing the client; at most four rows, keyed by organization.
    cross join lateral (
      select
        (count(*) filter (where wait.status not in ('approved', 'unavailable')))::integer as open_count,
        (count(*) filter (where wait.status = 'action_needed'))::integer as action_count,
        max(wait.updated_at) as changed_at
      from public.organization_setup_provider_waits as wait
      where wait.organization_id = client.id
    ) as waits
    -- E3: the newest released preview, its send, and its sent notes not yet sorted; at most 15 notes.
    left join lateral (
      select
        released.version,
        released.released_at,
        released.notes_sent_at,
        (
          select count(*)::integer
          from public.organization_setup_preview_notes as note
          where note.organization_id = released.organization_id
            and note.version = released.version
            and note.choice <> 'looks_right'
            and note.sorted_kind is null
        ) as unsorted_count
      from public.organization_setup_previews as released
      where released.organization_id = client.id
        and released.released_at is not null
      order by released.version desc
      limit 1
    ) as preview on true
    -- E4: the open launch approval request or the standing approval; at most one of each, keyed by organization.
    left join lateral (
      select request.status, request.requested_at, request.not_yet_at, request.approved_at, request.version
      from public.organization_setup_launch_approvals as request
      where request.organization_id = client.id
        and (request.status = 'open' or (request.status = 'approved' and request.replaced_at is null))
      order by request.requested_at desc
      limit 1
    ) as approval on true
    -- E6: the training row; one primary-key probe.
    left join lateral (
      select
        own_training.meeting_at,
        own_training.skipped_at,
        case when jsonb_array_length(own_training.attendees) > 0 then own_training.details_updated_at end as details_at
      from public.organization_setup_training as own_training
      where own_training.organization_id = client.id
    ) as training on true
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message is Uplift's; a section sent back on the newest send, or an outside wait needing
  -- the client (E2), is the client's; a setup sent to Uplift and a "need Uplift's help" answer are Uplift's;
  -- everything else is the client's.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.delivered_at is not null then 'nobody'
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.waits_action > 0 then 'client'
        -- E6: once live, training details are the client's to give; booking and handing over are Uplift's.
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null and measured.training_details_at is null then 'client'
        when measured.live_at is not null then 'uplift'
        when measured.approval_status = 'approved' then 'uplift'
        when measured.approval_status = 'open' and measured.approval_not_yet_at is not null then 'uplift'
        when measured.approval_status = 'open' then 'client'
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'client'
        when measured.help_count > 0 or measured.sent_number is not null then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.delivered_at is not null then 'delivered'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        when measured.waits_action > 0 then 'provider_action'
        -- E6: live — training settled first, then the handover.
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null and measured.training_details_at is null
          then 'give_training_details'
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null then 'book_training'
        when measured.live_at is not null then 'finish_handover'
        -- E4: an approval is Uplift's to launch; an open request is the approver's, unless they said not yet.
        when measured.approval_status = 'approved' then 'prepare_launch'
        when measured.approval_status = 'open' and measured.approval_not_yet_at is not null then 'approver_not_yet'
        when measured.approval_status = 'open' then 'approve_launch'
        -- E3: a released preview is the client's to review; their notes are Uplift's to sort, then make.
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'review_preview'
        when measured.preview_unsorted > 0 then 'sort_corrections'
        when measured.preview_sent_at is not null then 'make_corrections'
        -- Ready on the newest send: Uplift builds. A send after Ready has changes to look at first.
        when measured.ready_number = measured.sent_number then 'build_system'
        when measured.sent_number is not null then 'review_setup'
        when measured.help_count > 0 then 'help_with_answers'
        when measured.welcome_seen_at is null and measured.answered = 0 then 'start_setup'
        when measured.next_section_key is not null then 'finish_section'
        else 'send_to_uplift'
      end as next_action,
      greatest(
        measured.account_created_at,
        measured.welcome_seen_at,
        measured.last_answer_at,
        measured.last_section_at,
        measured.sent_at,
        measured.returned_at,
        measured.ready_at,
        measured.waits_changed_at,
        measured.preview_released_at,
        measured.preview_sent_at,
        measured.approval_requested_at,
        measured.approval_not_yet_at,
        measured.approval_approved_at,
        measured.live_at,
        measured.delivered_at,
        measured.training_details_at
      ) as last_activity_at
    from measured
  ),
  tagged as (
    select
      decided.*,
      -- The plan's first reminder goes out after about 24 hours of inactivity and the second at 3 days
      -- (§5); a client quiet for 3 days is the one Jafar should look at himself.
      (decided.waiting_on = 'client' and decided.last_activity_at < now() - interval '3 days') as is_quiet
    from decided
  ),
  matching as (
    select tagged.*
    from tagged
    where search_term is null
      or btrim(search_term) = ''
      or tagged.name ilike '%' || btrim(search_term) || '%'
  ),
  filtered as (
    select matching.*
    from matching
    where waiting_filter is null
      or (waiting_filter = 'quiet' and matching.is_quiet)
      or matching.waiting_on = waiting_filter
  ),
  page as (
    select filtered.*
    from filtered
    where cursor_account_created_at is null
      or (filtered.account_created_at, filtered.id) < (cursor_account_created_at, cursor_id)
    order by filtered.account_created_at desc, filtered.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  )
  select jsonb_build_object(
    'clients', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'name', page.name,
            'lifecycle_status', page.lifecycle_status,
            'package_name', page.package_name,
            'account_created_at', page.account_created_at,
            'payment_reversed', page.payment_reversed_at is not null,
            'welcome_seen', page.welcome_seen_at is not null,
            'sections_done', page.done_count,
            'sections_total', page.sections_total,
            'facts_answered', page.answered,
            'facts_total', page.facts_total,
            'help_count', page.help_count,
            'unread_support', page.unread_count,
            'next_section_key', page.next_section_key,
            'sent_number', page.sent_number,
            'sent_at', page.sent_at,
            'returned_count', page.returned_count,
            'ready_at', page.ready_at,
            'target_from', page.target_from,
            'target_to', page.target_to,
            'provider_waits_open', page.waits_open,
            'provider_waits_action', page.waits_action,
            'preview_version', page.preview_version,
            'preview_released_at', page.preview_released_at,
            'preview_sent_at', page.preview_sent_at,
            'preview_unsorted', coalesce(page.preview_unsorted, 0),
            'approval_status', page.approval_status,
            'approval_version', page.approval_version,
            'approval_requested_at', page.approval_requested_at,
            'approval_not_yet_at', page.approval_not_yet_at,
            'approved_at', page.approval_approved_at,
            'live_at', page.live_at,
            'delivered_at', page.delivered_at,
            'training_booked_at', page.training_meeting_at,
            'training_skipped', page.training_skipped_at is not null,
            'waiting_on', page.waiting_on,
            'next_action', page.next_action,
            'last_activity_at', page.last_activity_at,
            'quiet', page.is_quiet
          )
          order by page.account_created_at desc, page.id desc
        )
        from page
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= least(greatest(coalesce(page_size, 50), 1), 100) then (
        select jsonb_build_object('account_created_at', last.account_created_at, 'id', last.id)
        from page as last
        order by last.account_created_at asc, last.id asc
        limit 1
      )
    end,
    'totals', (
      select jsonb_build_object(
        'all', count(*),
        'uplift', count(*) filter (where tagged.waiting_on = 'uplift'),
        'client', count(*) filter (where tagged.waiting_on = 'client'),
        'quiet', count(*) filter (where tagged.is_quiet),
        'matching', (select count(*) from filtered),
        -- E6: delivered clients, counted whether or not they are listed.
        'delivered', (
          select count(*)
          from public.organization_setup_handover as delivered
          join public.platform_onboarding_application_provisions as provision
            on provision.organization_id = delivered.organization_id and provision.status = 'succeeded'
          where delivered.delivered_at is not null
        )
      )
      from tagged
    )
  );
$$;

comment on function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean) is
  'Jafar''s client onboarding list (client onboarding C1, E6): every paid client with package, setup progress, project state, whose move it is, the next action, last activity, and unread support; delivered clients only when asked. Service role only.';

revoke all on function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean)
  to service_role;
