-- Client onboarding E4: launch approval (plan §6, §10 journeys 10 and 14).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §6. Jafar's choices of 2026-10-05: once
-- Uplift's checks are done, Jafar asks for launch approval on the newest released preview. Only the final approver
-- named in the newest send may approve — on the Setup page when signed in with that email, otherwise through a
-- private emailed link that needs no login. They tick one box and press Approve; their name, email, the time, the
-- version, how they approved and the exact wording are kept. "Not yet — talk to Uplift" tells Jafar and never
-- counts as approval. Jafar may record an approval given by phone or email, with a reason. A newer release cancels
-- an open request and marks an approval replaced; the client cannot undo an approval. Industry reference:
-- DocuSign's emailed signing link, Jobber's online quote approval, approvals in Rocketlane and GuideCX.
--
-- 1. organization_setup_launch_approvals keeps every request: the version, the approver it was sent to, the link,
--    and how it ended — approved, or cancelled by a newer release or by the client sending corrections.
-- 2. Who approves, and what they agree to.
-- 3. Jafar's commands: ask, send the link again, record an approval given another way.
-- 4. The approver's commands: approve or "not yet", signed in or through the link.
-- 5. A newer release cancels or replaces; sent corrections cancel; an approved version takes no more notes.
-- 6. public.owner_client_onboarding_list shows an open request as the client's move, and "not yet" and an
--    approval as Uplift's.

-- 1. The requests ---------------------------------------------------------------------------------------------

create table public.organization_setup_launch_approvals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  version integer not null,
  requested_at timestamptz not null default now(),
  requested_by_email text not null check (char_length(requested_by_email) between 3 and 320),
  -- Who it was sent to, from the newest send when Jafar asked.
  approver_name text not null check (char_length(approver_name) between 1 and 320),
  approver_email text not null check (char_length(approver_email) between 3 and 320),
  -- The private link: a SHA-256 of the token, never the token. Sending it again replaces it.
  token_hash bytea not null,
  link_sent_at timestamptz not null default now(),
  link_expires_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'approved', 'cancelled')),
  closed_reason text check (closed_reason in ('new_release', 'corrections_sent')),
  closed_at timestamptz,
  -- "Not yet — talk to Uplift"; the newest press. The request stays open.
  not_yet_at timestamptz,
  not_yet_by_name text check (not_yet_by_name is null or char_length(not_yet_by_name) between 1 and 320),
  not_yet_note text check (not_yet_note is null or char_length(not_yet_note) between 1 and 2000),
  approved_at timestamptz,
  approved_by_name text check (approved_by_name is null or char_length(approved_by_name) between 1 and 320),
  approved_by_email text check (approved_by_email is null or char_length(approved_by_email) between 3 and 320),
  approved_by_user uuid references auth.users (id) on delete set null,
  approval_method text check (approval_method in ('signed_in', 'link', 'recorded')),
  -- The exact sentence the approver agreed to.
  approval_wording text check (approval_wording is null or char_length(approval_wording) between 1 and 500),
  recorded_reason text check (recorded_reason is null or char_length(recorded_reason) between 1 and 500),
  recorded_by_email text check (recorded_by_email is null or char_length(recorded_by_email) between 3 and 320),
  -- A newer release came after this approval.
  replaced_at timestamptz,
  foreign key (organization_id, version)
    references public.organization_setup_previews (organization_id, version) on delete cascade,
  constraint organization_setup_launch_approvals_approved_check check (
    (status = 'approved') = (approved_at is not null)
    and (approved_at is null) = (approved_by_name is null)
    and (approved_at is null) = (approved_by_email is null)
    and (approved_at is null) = (approval_method is null)
    and (approved_at is null) = (approval_wording is null)
  ),
  constraint organization_setup_launch_approvals_closed_check check (
    (status = 'cancelled') = (closed_at is not null)
    and (closed_at is null) = (closed_reason is null)
  ),
  constraint organization_setup_launch_approvals_recorded_check check (
    (approval_method is not distinct from 'recorded') = (recorded_reason is not null)
    and (recorded_reason is null) = (recorded_by_email is null)
  ),
  constraint organization_setup_launch_approvals_replaced_check check (replaced_at is null or status = 'approved')
);

create unique index organization_setup_launch_approvals_token on public.organization_setup_launch_approvals (token_hash);
-- One open request, and one standing approval, per client.
create unique index organization_setup_launch_approvals_one_open
  on public.organization_setup_launch_approvals (organization_id)
  where status = 'open';
create unique index organization_setup_launch_approvals_one_current
  on public.organization_setup_launch_approvals (organization_id)
  where status = 'approved' and replaced_at is null;
create index organization_setup_launch_approvals_history
  on public.organization_setup_launch_approvals (organization_id, requested_at desc);
create index organization_setup_launch_approvals_approved_by_user
  on public.organization_setup_launch_approvals (approved_by_user)
  where approved_by_user is not null;

comment on table public.organization_setup_launch_approvals is
  'Client onboarding E4: each launch approval request and how it ended. Administrators read everything but the link; rows change only through the setup launch approval commands.';

-- An approval is final, and so is a cancelled request; only a newer release may mark an approval replaced.
create function private.refuse_setup_launch_approval_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'cancelled'
    or (old.status = 'approved' and (
      row(new.status, new.approved_at, new.approved_by_name, new.approved_by_email, new.approval_method,
          new.approval_wording, new.recorded_reason, new.version, new.approver_email, new.token_hash)
        is distinct from
      row(old.status, old.approved_at, old.approved_by_name, old.approved_by_email, old.approval_method,
          old.approval_wording, old.recorded_reason, old.version, old.approver_email, old.token_hash)
      or (old.replaced_at is not null and new.replaced_at is distinct from old.replaced_at)
    ))
    or new.version is distinct from old.version
    or new.requested_at is distinct from old.requested_at
  then
    raise exception 'A launch approval cannot be changed.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger organization_setup_launch_approvals_final
  before update on public.organization_setup_launch_approvals
  for each row execute function private.refuse_setup_launch_approval_change();

alter table public.organization_setup_launch_approvals enable row level security;
revoke all on table public.organization_setup_launch_approvals from public, anon, authenticated;
-- Every column but the link.
grant select (
  id, organization_id, version, requested_at, approver_name, approver_email, link_sent_at, link_expires_at,
  status, closed_reason, closed_at, not_yet_at, not_yet_by_name, not_yet_note, approved_at, approved_by_name,
  approved_by_email, approval_method, approval_wording, recorded_reason, replaced_at
) on table public.organization_setup_launch_approvals to authenticated;
grant all on table public.organization_setup_launch_approvals to service_role;

create policy "administrators can view their launch approvals"
  on public.organization_setup_launch_approvals
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 2. Who approves, and what they agree to -----------------------------------------------------------------------

-- The final approver named in the newest send: the named approver when one is given and the main contact did not
-- say they approve, otherwise the main contact. Null when the send names no email.
create function private.setup_launch_approver(target_organization_id uuid)
returns table (approver_name text, approver_email text)
language sql
stable
security definer
set search_path = ''
as $$
  with newest as (
    select submission.answers
    from public.organization_setup_submissions as submission
    where submission.organization_id = target_organization_id
    order by submission.submission_number desc
    limit 1
  ),
  facts as (
    select
      nullif(btrim(newest.answers -> 'business.contact_is_approver' ->> 'value'), '') as contact_approves,
      nullif(btrim(newest.answers -> 'business.contact_name' ->> 'value'), '') as contact_name,
      nullif(lower(btrim(newest.answers -> 'business.contact_email' ->> 'value')), '') as contact_email,
      nullif(btrim(newest.answers -> 'business.approver_name' ->> 'value'), '') as named_name,
      nullif(lower(btrim(newest.answers -> 'business.approver_email' ->> 'value')), '') as named_email
    from newest
  )
  select
    case when facts.named_email is not null and facts.contact_approves is distinct from 'yes'
      then coalesce(facts.named_name, facts.named_email)
      else coalesce(facts.contact_name, facts.contact_email)
    end,
    case when facts.named_email is not null and facts.contact_approves is distinct from 'yes'
      then facts.named_email
      else facts.contact_email
    end
  from facts;
$$;

revoke all on function private.setup_launch_approver(uuid) from public;

-- Mirrors launchApprovalWording in src/lib/setup/launch-approval.ts.
create function private.setup_launch_approval_wording(target_version integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select format('I approve this website and system to go live, as shown in preview version %s.', target_version);
$$;

revoke all on function private.setup_launch_approval_wording(integer) from public;

-- Records the approval on an open request. The caller has checked who is approving.
create function private.approve_setup_launch(
  request public.organization_setup_launch_approvals,
  method text,
  by_name text,
  by_email text,
  by_user uuid,
  reason text,
  recorded_by text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  approved public.organization_setup_launch_approvals;
begin
  update public.organization_setup_launch_approvals
  set status = 'approved',
      approved_at = now(),
      approved_by_name = by_name,
      approved_by_email = by_email,
      approved_by_user = by_user,
      approval_method = method,
      approval_wording = private.setup_launch_approval_wording(request.version),
      recorded_reason = reason,
      recorded_by_email = recorded_by
  where id = request.id
  returning * into approved;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    coalesce(recorded_by, by_email),
    'organization.setup_launch_approved',
    'organization',
    request.organization_id::text,
    null,
    jsonb_build_object(
      'request_id', approved.id,
      'version', approved.version,
      'method', method,
      'approved_by_email', by_email,
      'reason', reason
    )
  );

  return jsonb_build_object(
    'status', 'approved',
    'request_id', approved.id,
    'organization_id', approved.organization_id,
    'version', approved.version,
    'approved_at', approved.approved_at
  );
end;
$$;

revoke all on function private.approve_setup_launch(
  public.organization_setup_launch_approvals, text, text, text, uuid, text, text
) from public;

-- Records "Not yet — talk to Uplift" on an open request.
create function private.not_yet_setup_launch(
  request public.organization_setup_launch_approvals,
  by_name text,
  note text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_note text := nullif(btrim(coalesce(note, '')), '');
begin
  if char_length(clean_note) > 2000 then
    raise exception 'Keep the note to 2000 characters.' using errcode = 'check_violation';
  end if;
  update public.organization_setup_launch_approvals
  set not_yet_at = now(), not_yet_by_name = by_name, not_yet_note = clean_note
  where id = request.id;
  return jsonb_build_object(
    'status', 'not_yet',
    'request_id', request.id,
    'organization_id', request.organization_id,
    'version', request.version
  );
end;
$$;

revoke all on function private.not_yet_setup_launch(public.organization_setup_launch_approvals, text, text) from public;

-- 3. Jafar's commands ---------------------------------------------------------------------------------------------

-- Asks the final approver to approve this version. It must be the newest released version, and the client must
-- not have sent corrections on it. Asking again while a request is open, or once approved, changes nothing.
create function public.owner_request_setup_launch_approval(
  target_organization_id uuid,
  target_version integer,
  new_token_hash bytea,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  preview public.organization_setup_previews;
  existing public.organization_setup_launch_approvals;
  approver record;
  created public.organization_setup_launch_approvals;
begin
  if target_organization_id is null or target_version is null or new_token_hash is null or clean_email is null then
    raise exception 'Say which client and who is asking.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organization_setup where organization_id = target_organization_id for update;

  select * into existing from public.organization_setup_launch_approvals
  where organization_id = target_organization_id
    and (status = 'open' or (status = 'approved' and replaced_at is null));
  if existing.id is not null then
    if existing.version = target_version then
      return jsonb_build_object(
        'status', case when existing.status = 'approved' then 'already_approved' else 'already_requested' end,
        'request_id', existing.id
      );
    end if;
    raise exception 'A request for another version is still open.' using errcode = 'check_violation';
  end if;

  select * into preview from public.organization_setup_previews
  where organization_id = target_organization_id and version = target_version and released_at is not null;
  if preview.organization_id is null then
    raise exception 'That preview could not be found.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.organization_setup_previews as newer
    where newer.organization_id = target_organization_id and newer.version > target_version
  ) then
    raise exception 'Ask on the newest preview.' using errcode = 'check_violation';
  end if;
  if preview.notes_sent_at is not null then
    raise exception 'The client sent corrections on this preview. Release a new version first.'
      using errcode = 'check_violation';
  end if;

  select * into approver from private.setup_launch_approver(target_organization_id);
  if approver.approver_email is null then
    raise exception 'The client''s setup names no final approver email.' using errcode = 'check_violation';
  end if;

  insert into public.organization_setup_launch_approvals (
    organization_id, version, requested_by_email, approver_name, approver_email, token_hash, link_expires_at
  ) values (
    target_organization_id, target_version, clean_email, approver.approver_name, approver.approver_email,
    new_token_hash, now() + interval '30 days'
  )
  returning * into created;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_launch_approval_requested',
    'organization',
    target_organization_id::text,
    null,
    jsonb_build_object('request_id', created.id, 'version', target_version, 'approver_email', created.approver_email)
  );

  return jsonb_build_object(
    'status', 'requested',
    'request_id', created.id,
    'approver_name', created.approver_name,
    'approver_email', created.approver_email,
    'link_expires_at', created.link_expires_at
  );
end;
$$;

revoke all on function public.owner_request_setup_launch_approval(uuid, integer, bytea, text) from public, anon, authenticated;
grant execute on function public.owner_request_setup_launch_approval(uuid, integer, bytea, text) to service_role;

-- A fresh link for the open request; the one emailed before stops working.
create function public.owner_resend_setup_launch_approval(
  target_organization_id uuid,
  new_token_hash bytea,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  request public.organization_setup_launch_approvals;
begin
  if target_organization_id is null or new_token_hash is null or clean_email is null then
    raise exception 'Say which client and who is asking.' using errcode = 'check_violation';
  end if;

  update public.organization_setup_launch_approvals
  set token_hash = new_token_hash, link_sent_at = now(), link_expires_at = now() + interval '30 days'
  where organization_id = target_organization_id and status = 'open'
  returning * into request;
  if request.id is null then
    raise exception 'There is no open launch approval request.' using errcode = 'check_violation';
  end if;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_launch_approval_resent',
    'organization',
    target_organization_id::text,
    null,
    jsonb_build_object('request_id', request.id, 'version', request.version)
  );

  return jsonb_build_object(
    'status', 'resent',
    'request_id', request.id,
    'approver_name', request.approver_name,
    'approver_email', request.approver_email,
    'link_expires_at', request.link_expires_at
  );
end;
$$;

revoke all on function public.owner_resend_setup_launch_approval(uuid, bytea, text) from public, anon, authenticated;
grant execute on function public.owner_resend_setup_launch_approval(uuid, bytea, text) to service_role;

-- The approver said yes by phone or email: Jafar records it on the open request, saying how it was given.
create function public.owner_record_setup_launch_approval(
  target_organization_id uuid,
  target_version integer,
  reason text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_reason text := nullif(btrim(coalesce(reason, '')), '');
  request public.organization_setup_launch_approvals;
begin
  if target_organization_id is null or target_version is null or clean_email is null then
    raise exception 'Say which client and who is recording it.' using errcode = 'check_violation';
  end if;
  if clean_reason is null then
    raise exception 'Say how the approval was given.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) > 500 then
    raise exception 'Keep the reason to 500 characters.' using errcode = 'check_violation';
  end if;

  select * into request from public.organization_setup_launch_approvals
  where organization_id = target_organization_id and version = target_version
    and (status = 'open' or (status = 'approved' and replaced_at is null))
  for update;
  if request.id is null then
    raise exception 'Ask for launch approval on this preview first.' using errcode = 'check_violation';
  end if;
  if request.status = 'approved' then
    return jsonb_build_object('status', 'already_approved', 'request_id', request.id);
  end if;

  return private.approve_setup_launch(
    request, 'recorded', request.approver_name, request.approver_email, null, clean_reason, clean_email
  );
end;
$$;

revoke all on function public.owner_record_setup_launch_approval(uuid, integer, text, text) from public, anon, authenticated;
grant execute on function public.owner_record_setup_launch_approval(uuid, integer, text, text) to service_role;

-- 4. The approver's commands -----------------------------------------------------------------------------------

-- Signed in on the Setup page: only the named approver, and only an owner or administrator (the page's own rule).
-- `decision` is 'approve' or 'not_yet'.
create function public.client_decide_setup_launch(
  target_organization_id uuid,
  target_version integer,
  decision text,
  note text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.organization_setup_launch_approvals;
  signed_in_email text;
  signed_in_name text;
begin
  perform private.require_organization_setup_editor(target_organization_id);
  if decision is null or decision not in ('approve', 'not_yet') then
    raise exception 'Choose Approve or Not yet.' using errcode = 'check_violation';
  end if;

  select * into request from public.organization_setup_launch_approvals
  where organization_id = target_organization_id and version = target_version
    and (status = 'open' or (status = 'approved' and replaced_at is null))
  for update;
  if request.id is null then
    raise exception 'This approval request has closed. Reload to see the newest preview.'
      using errcode = 'check_violation';
  end if;
  if request.status = 'approved' then
    return jsonb_build_object('status', 'already_approved', 'request_id', request.id);
  end if;

  select lower(btrim(u.email)), coalesce(nullif(btrim(p.full_name), ''), u.email)
  into signed_in_email, signed_in_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = (select auth.uid());
  if signed_in_email is distinct from lower(request.approver_email) then
    raise exception 'Only % can approve the launch.', request.approver_name using errcode = 'insufficient_privilege';
  end if;

  if decision = 'not_yet' then
    return private.not_yet_setup_launch(request, signed_in_name, note);
  end if;
  return private.approve_setup_launch(
    request, 'signed_in', signed_in_name, signed_in_email, (select auth.uid()), null, null
  );
end;
$$;

revoke all on function public.client_decide_setup_launch(uuid, integer, text, text) from public, anon;
grant execute on function public.client_decide_setup_launch(uuid, integer, text, text) to authenticated, service_role;

-- The private link's request, if it still works: open and not expired, or already approved (its receipt).
create function private.setup_launch_link_request(supplied_token_hash bytea, lock boolean)
returns public.organization_setup_launch_approvals
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.organization_setup_launch_approvals;
begin
  if lock then
    select * into request from public.organization_setup_launch_approvals
    where token_hash = supplied_token_hash for update;
  else
    select * into request from public.organization_setup_launch_approvals
    where token_hash = supplied_token_hash;
  end if;
  if request.id is null
    or request.status = 'cancelled'
    or (request.status = 'open' and request.link_expires_at <= now())
    or request.replaced_at is not null then
    return null;
  end if;
  return request;
end;
$$;

revoke all on function private.setup_launch_link_request(bytea, boolean) from public;

-- What the link page shows: the business, the version's cards (titles, summaries, links) and the request's state.
-- Every way of failing returns null, so the page cannot tell a guessed link from a closed one.
create function public.resolve_setup_launch_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  request public.organization_setup_launch_approvals;
  preview public.organization_setup_previews;
  business_name text;
begin
  request := private.setup_launch_link_request(supplied_token_hash, false);
  if request.id is null then
    return null;
  end if;
  select * into preview from public.organization_setup_previews
  where organization_id = request.organization_id and version = request.version;
  select name into business_name from public.organizations where id = request.organization_id;

  return jsonb_build_object(
    'business_name', business_name,
    'version', request.version,
    'approver_name', request.approver_name,
    'status', request.status,
    'wording', private.setup_launch_approval_wording(request.version),
    'approved_at', request.approved_at,
    'not_yet_at', request.not_yet_at,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', card ->> 'id',
        'title', card ->> 'title',
        'summary', card ->> 'summary',
        'link', card -> 'link'
      ) order by position)
      from jsonb_array_elements(preview.cards) with ordinality as item(card, position)
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.resolve_setup_launch_link(bytea) from public, anon, authenticated;
grant execute on function public.resolve_setup_launch_link(bytea) to service_role;

-- The approver's answer through the link. The link is the proof of who they are, as with an emailed signing link.
create function public.decide_setup_launch_link(
  supplied_token_hash bytea,
  decision text,
  note text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.organization_setup_launch_approvals;
begin
  if decision is null or decision not in ('approve', 'not_yet') then
    raise exception 'Choose Approve or Not yet.' using errcode = 'check_violation';
  end if;
  request := private.setup_launch_link_request(supplied_token_hash, true);
  if request.id is null then
    return null;
  end if;
  if request.status = 'approved' then
    return jsonb_build_object('status', 'already_approved', 'request_id', request.id);
  end if;
  if decision = 'not_yet' then
    return private.not_yet_setup_launch(request, request.approver_name, note);
  end if;
  return private.approve_setup_launch(
    request, 'link', request.approver_name, request.approver_email, null, null, null
  );
end;
$$;

revoke all on function public.decide_setup_launch_link(bytea, text, text) from public, anon, authenticated;
grant execute on function public.decide_setup_launch_link(bytea, text, text) to service_role;

-- 5. Releases and corrections ---------------------------------------------------------------------------------

-- A release cancels the open request and marks a standing approval replaced; sending corrections cancels the
-- request on that version. Sending notes on an approved version is refused.
create function private.setup_preview_launch_approval_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.notes_sent_at is null and new.notes_sent_at is not null then
    if exists (
      select 1 from public.organization_setup_launch_approvals
      where organization_id = new.organization_id and version = new.version
        and status = 'approved' and replaced_at is null
    ) then
      raise exception 'This preview is already approved for launch.' using errcode = 'check_violation';
    end if;
    update public.organization_setup_launch_approvals
    set status = 'cancelled', closed_reason = 'corrections_sent', closed_at = now()
    where organization_id = new.organization_id and version = new.version and status = 'open';
  end if;

  if old.released_at is null and new.released_at is not null then
    update public.organization_setup_launch_approvals
    set status = 'cancelled', closed_reason = 'new_release', closed_at = now()
    where organization_id = new.organization_id and status = 'open';
    update public.organization_setup_launch_approvals
    set replaced_at = now()
    where organization_id = new.organization_id and status = 'approved' and replaced_at is null;
  end if;
  return new;
end;
$$;

revoke all on function private.setup_preview_launch_approval_follow() from public;

create trigger organization_setup_previews_launch_approval
  after update of notes_sent_at, released_at on public.organization_setup_previews
  for each row execute function private.setup_preview_launch_approval_follow();

-- An approved version takes no more notes.
create function private.refuse_note_on_approved_preview()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.organization_setup_launch_approvals
    where organization_id = new.organization_id and version = new.version
      and status = 'approved' and replaced_at is null
  ) then
    raise exception 'This preview is already approved for launch.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.refuse_note_on_approved_preview() from public;

create trigger organization_setup_preview_notes_not_approved
  before insert or update on public.organization_setup_preview_notes
  for each row execute function private.refuse_note_on_approved_preview();

-- 6. Jafar's onboarding list ---------------------------------------------------------------------------------
-- Unchanged from 20261101090000_setup_previews.sql except: the open launch approval request or standing approval
-- is returned; an open request is the client's move ('approve_launch') unless the approver said not yet
-- ('approver_not_yet', Uplift's), and an approval is Uplift's ('prepare_launch'), all after outside waits that
-- need the client; a request, a not yet and an approval count as activity.

create or replace function public.owner_client_onboarding_list(
  setup_catalogue jsonb,
  search_term text default null,
  waiting_filter text default null,
  cursor_account_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50
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
    where provision.status = 'succeeded'
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
      approval.version as approval_version
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
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.waits_action > 0 then 'client'
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
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        when measured.waits_action > 0 then 'provider_action'
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
        measured.approval_approved_at
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
        'matching', (select count(*) from filtered)
      )
      from tagged
    )
  );
$$;
