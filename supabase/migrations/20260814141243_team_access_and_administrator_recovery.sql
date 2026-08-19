-- Part 7: team access and administrator recovery.
--
-- Three service_role-only functions. auth.users.email itself is never touched here -- that
-- goes through the Supabase Auth admin API (GoTrue) in TypeScript, which keeps identity and
-- confirmation state consistent. These functions handle: a cross-organization email
-- availability check, and the two audit-trail + session-revocation commands that run after a
-- GoTrue email update already succeeded.

-- ---------------------------------------------------------------------------
-- Cross-organization email availability check
-- ---------------------------------------------------------------------------

create or replace function public.owner_email_is_available(candidate_email text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select not exists (
    select 1 from auth.users where lower(email) = lower(candidate_email)
  );
$$;

revoke all on function public.owner_email_is_available(text) from public, anon, authenticated;
grant execute on function public.owner_email_is_available(text) to service_role;

comment on function public.owner_email_is_available(text) is
  'Read-only check for whether an email is free to assign to an administrator during recovery. Part 7.';

-- ---------------------------------------------------------------------------
-- Profile correction (name any role; email non-admin/non-owner only)
-- ---------------------------------------------------------------------------

create or replace function public.apply_organization_member_profile_correction(
  target_organization_id uuid,
  target_user_id uuid,
  new_full_name text,
  email_changed boolean,
  old_email text,
  new_email text,
  private_reason text,
  actor_owner_email text,
  occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members%rowtype;
  inserted_event public.access_audit_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  before_state jsonb;
  after_state jsonb;
begin
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A correction reason is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'A correction cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  select * into membership
  from public.organization_members
  where organization_id = target_organization_id and user_id = target_user_id
  for update;
  if not found then
    raise exception 'Team member was not found in this organization.' using errcode = 'foreign_key_violation';
  end if;

  if email_changed and membership.role in ('owner', 'admin') then
    raise exception 'An administrator email change must use administrator recovery.'
      using errcode = 'check_violation';
  end if;

  before_state := jsonb_build_object('full_name', (select full_name from public.profiles where id = target_user_id));
  after_state := jsonb_build_object('full_name', new_full_name);

  if new_full_name is not null and new_full_name is distinct from (before_state ->> 'full_name') then
    update public.profiles set full_name = new_full_name, updated_at = now() where id = target_user_id;
  end if;

  if email_changed then
    before_state := before_state || jsonb_build_object('email', old_email);
    after_state := after_state || jsonb_build_object('email', new_email);
    delete from auth.sessions where user_id = target_user_id;
  end if;

  insert into public.access_audit_events (
    organization_id, actor_kind, actor_owner_email, event_type, target_type, target_key,
    before_state, after_state
  ) values (
    target_organization_id, 'platform_owner', trim(actor_owner_email),
    'organization_member.profile_corrected', 'organization_member', target_user_id::text,
    before_state, after_state || jsonb_build_object('reason', trim(private_reason))
  ) returning * into inserted_event;

  return jsonb_build_object('event_id', inserted_event.id, 'occurred_at', inserted_event.created_at);
end;
$$;

revoke all on function public.apply_organization_member_profile_correction(uuid, uuid, text, boolean, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.apply_organization_member_profile_correction(uuid, uuid, text, boolean, text, text, text, text, timestamptz) to service_role;

comment on function public.apply_organization_member_profile_correction(uuid, uuid, text, boolean, text, text, text, text, timestamptz) is
  'Records a support correction to a team member''s name and (non-admin only) email; revokes sessions when email changed. Part 7.';

-- ---------------------------------------------------------------------------
-- Administrator email recovery (owner/admin only, step-up enforced in TypeScript)
-- ---------------------------------------------------------------------------

create or replace function public.apply_organization_administrator_email_recovery(
  target_organization_id uuid,
  target_user_id uuid,
  old_email text,
  new_email text,
  evidence_summary text,
  private_reason text,
  actor_owner_email text,
  occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members%rowtype;
  inserted_event public.access_audit_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
begin
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A recovery reason is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(evidence_summary, ''))) not between 1 and 1000 then
    raise exception 'An identity-verification note is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'A recovery cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  select * into membership
  from public.organization_members
  where organization_id = target_organization_id and user_id = target_user_id
  for update;
  if not found then
    raise exception 'Team member was not found in this organization.' using errcode = 'foreign_key_violation';
  end if;
  if membership.role not in ('owner', 'admin') then
    raise exception 'Administrator recovery only applies to an owner or admin.'
      using errcode = 'check_violation';
  end if;

  delete from auth.sessions where user_id = target_user_id;

  insert into public.access_audit_events (
    organization_id, actor_kind, actor_owner_email, event_type, target_type, target_key,
    before_state, after_state
  ) values (
    target_organization_id, 'platform_owner', trim(actor_owner_email),
    'organization_member.administrator_email_recovered', 'organization_member', target_user_id::text,
    jsonb_build_object('email', old_email),
    jsonb_build_object(
      'email', new_email,
      'reason', trim(private_reason),
      'evidence_summary', trim(evidence_summary)
    )
  ) returning * into inserted_event;

  return jsonb_build_object('event_id', inserted_event.id, 'occurred_at', inserted_event.created_at);
end;
$$;

revoke all on function public.apply_organization_administrator_email_recovery(uuid, uuid, text, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.apply_organization_administrator_email_recovery(uuid, uuid, text, text, text, text, text, timestamptz) to service_role;

comment on function public.apply_organization_administrator_email_recovery(uuid, uuid, text, text, text, text, text, timestamptz) is
  'Records administrator email recovery evidence and revokes sessions after a GoTrue email update already succeeded. Part 7.';
