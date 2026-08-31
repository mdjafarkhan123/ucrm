-- Team & access, part 3A, item 4: the contractor-facing team history, and the allow-list that keeps free
-- text out of it.
--
-- Why a new table when public.access_audit_events already exists: that one is the Platform Owner's support
-- history. Its rows carry private_reason, evidence_summary, and old/new email addresses in free-form
-- before_state/after_state blobs, and it is read by /api/jafar/organizations/[id]/history -- Jafar's screen,
-- not the contractor's. The packet's Permanent removal identity rule says the opposite about team history:
-- "Audit summaries carry no free text, enforced by the shape allow-list, so no email or name can ever enter
-- that table." A table that already stores emails cannot also be the table that can never store one, so
-- these stay separate. Do not merge them later.
--
-- The allow-list is what makes that rule structural instead of a habit. Every event type declares which
-- summary keys it may carry and what kind of value each key holds, and every kind is a closed vocabulary --
-- a role, a membership status, permission keys that must exist, a profile field name, an id. There is no
-- "text" kind at all, so an email or a person's name has nowhere to land: the insert is refused rather than
-- quietly accepted. Attribution comes from profiles.full_name and display_name_at_removal, exactly as the
-- packet requires, never from a string copied into an event.

-- ---------------------------------------------------------------------------
-- The allow-list
-- ---------------------------------------------------------------------------

-- A CHECK constraint cannot contain a subquery, so the value-kind guard lives in an immutable helper that
-- only ever inspects its argument. CASE keeps jsonb_each_text away from a non-object.
create or replace function private.member_access_summary_kinds_are_known(candidate jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when jsonb_typeof(candidate) <> 'object' then false
    else not exists (
      select 1
      from jsonb_each_text(candidate) as entry(summary_key, value_kind)
      where value_kind not in ('role', 'member_status', 'permission_key_list', 'profile_field_list', 'id')
    )
  end;
$$;

comment on function private.member_access_summary_kinds_are_known(jsonb) is
  'True when every value in a shape''s summary_keys map names one of the five closed value kinds. None of '
  'them is free text -- that is the whole point of the allow-list.';

revoke all on function private.member_access_summary_kinds_are_known(jsonb) from public, anon, authenticated;

-- Same reason as above: a CHECK cannot hold `array(select jsonb_object_keys(...))`, so the containment test
-- moves into an immutable helper.
create or replace function private.member_access_required_keys_are_allowed(
  candidate jsonb,
  required_keys text[]
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when jsonb_typeof(candidate) <> 'object' then false
    else required_keys <@ array(select jsonb_object_keys(candidate))
  end;
$$;

comment on function private.member_access_required_keys_are_allowed(jsonb, text[]) is
  'True when every required summary key is also an allowed one. A shape that demands a key it forbids could '
  'never record anything.';

revoke all on function private.member_access_required_keys_are_allowed(jsonb, text[])
  from public, anon, authenticated;

create table public.member_access_event_shapes (
  event_type text primary key check (
    event_type ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' and char_length(event_type) <= 80
  ),
  subject_kind text not null check (subject_kind in ('member', 'invitation', 'organization')),
  summary_keys jsonb not null default '{}'::jsonb,
  required_summary_keys text[] not null default '{}'::text[],
  constraint member_access_event_shapes_summary_kinds_check
    check (private.member_access_summary_kinds_are_known(summary_keys)),
  -- A key cannot be required unless it is also allowed.
  constraint member_access_event_shapes_required_keys_check check (
    private.member_access_required_keys_are_allowed(summary_keys, required_summary_keys)
  )
);

comment on table public.member_access_event_shapes is
  'The allow-list for organization_member_access_events. One row per event type: what the event is about, '
  'which summary keys it may carry, and which of those are required. Reference data -- seeded by migrations, '
  'writable by nobody at runtime.';
comment on column public.member_access_event_shapes.subject_kind is
  'member = the event is about a person''s membership; invitation = about an invitation row; organization = '
  'about the organization itself, with no subject column set.';
comment on column public.member_access_event_shapes.summary_keys is
  'Map of allowed summary key -> value kind. Every kind is a closed vocabulary; there is deliberately no '
  'free-text kind, so no email or name can be stored in an event.';

alter table public.member_access_event_shapes enable row level security;

-- Global reference data, same shape as public.permissions: readable by any signed-in user, written by none.
create policy "authenticated users can view team history shapes"
  on public.member_access_event_shapes
  for select
  to authenticated
  using (true);

revoke all on public.member_access_event_shapes from anon, authenticated;
grant select on public.member_access_event_shapes to authenticated;
grant select on public.member_access_event_shapes to service_role;

-- ---------------------------------------------------------------------------
-- The history itself
-- ---------------------------------------------------------------------------

create table public.organization_member_access_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_type text not null references public.member_access_event_shapes(event_type),
  actor_kind text not null check (actor_kind in ('member', 'system')),
  -- on delete no action, matching the 24 authorship columns already pointing at auth.users: a history line
  -- that forgot who did it is worse than a delete that fails loudly. Nothing deletes a contractor login
  -- except 3B's orphan worker, and an orphan never accepted an invitation, so it is never an actor here.
  actor_user_id uuid references auth.users(id) on delete no action,
  subject_user_id uuid references auth.users(id) on delete no action,
  subject_invitation_id uuid references public.organization_member_invitations(id) on delete no action,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint organization_member_access_events_actor_check check (
    (actor_kind = 'member' and actor_user_id is not null)
    or (actor_kind = 'system' and actor_user_id is null)
  ),
  -- At most one subject column; which one (or neither) must be set is the shape's business, enforced by the
  -- trigger below where the shape is actually in hand.
  constraint organization_member_access_events_subject_check check (
    num_nonnulls(subject_user_id, subject_invitation_id) <= 1
  ),
  constraint organization_member_access_events_summary_object_check check (jsonb_typeof(summary) = 'object')
);

comment on table public.organization_member_access_events is
  'Contractor-facing team history: who changed someone''s access, what changed, and when. Append-only, and '
  'every summary is shape-checked so it can never hold an email or a name. The Platform Owner''s own support '
  'history is public.access_audit_events -- a different table for a different reader.';
comment on column public.organization_member_access_events.actor_kind is
  'member = a teammate did this; system = an automatic sweep did it (expiry, abandonment) and there is no '
  'actor to name.';
comment on column public.organization_member_access_events.summary is
  'Allow-listed keys only, validated against member_access_event_shapes on insert. Free text is rejected, '
  'not sanitised.';

-- The organization's own history list, newest first.
create index organization_member_access_events_organization_created_idx
  on public.organization_member_access_events (organization_id, created_at desc);

-- One member's history on their detail page. Partial, because invitation-subject rows never serve it.
create index organization_member_access_events_subject_user_idx
  on public.organization_member_access_events (organization_id, subject_user_id, created_at desc)
  where subject_user_id is not null;

alter table public.organization_member_access_events enable row level security;

create policy "team managers can view team history"
  on public.organization_member_access_events
  for select
  to authenticated
  using (organization_id in (select private.permitted_organizations('team.manage')));

-- Read-only for authenticated, exactly like the invitations table: every write is a SECURITY DEFINER command
-- (items 5 and 6), so no browser session holds an insert grant.
revoke all on public.organization_member_access_events from anon, authenticated;
grant select on public.organization_member_access_events to authenticated;
grant select, insert on public.organization_member_access_events to service_role;

-- ---------------------------------------------------------------------------
-- The allow-list trigger
-- ---------------------------------------------------------------------------

create or replace function private.member_access_summary_value_fits(value_kind text, candidate jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  case value_kind
    when 'role' then
      return jsonb_typeof(candidate) = 'string'
        and candidate #>> '{}' in ('owner', 'admin', 'office', 'sales', 'field', 'finance');
    when 'member_status' then
      return jsonb_typeof(candidate) = 'string'
        and candidate #>> '{}' in ('pending', 'active', 'deactivated', 'removed');
    when 'permission_key_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or not exists (
            select 1 from public.permissions as permission where permission.key = element.item #>> '{}'
          )
      );
    when 'profile_field_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or element.item #>> '{}' not in ('full_name', 'work_phone', 'job_title', 'schedule_color')
      );
    when 'id' then
      return jsonb_typeof(candidate) = 'string'
        and (candidate #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    else
      -- An unknown kind is a refusal, never a pass. A future kind must be added here on purpose.
      return false;
  end case;
end;
$$;

comment on function private.member_access_summary_value_fits(text, jsonb) is
  'Checks one summary value against its declared kind. Every kind is a closed vocabulary, and permission '
  'keys must name a real row in public.permissions. Anything unrecognised is refused.';

revoke all on function private.member_access_summary_value_fits(text, jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.enforce_member_access_event_shape()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  shape public.member_access_event_shapes%rowtype;
  entry record;
  value_kind text;
  missing_keys text;
begin
  select * into shape
  from public.member_access_event_shapes
  where event_type = new.event_type;

  if not found then
    raise exception 'There is no team history shape for %.', new.event_type using errcode = 'check_violation';
  end if;

  if shape.subject_kind = 'member'
    and (new.subject_user_id is null or new.subject_invitation_id is not null) then
    raise exception '% is about a team member and needs exactly one member subject.', new.event_type
      using errcode = 'check_violation';
  end if;

  if shape.subject_kind = 'invitation'
    and (new.subject_invitation_id is null or new.subject_user_id is not null) then
    raise exception '% is about an invitation and needs exactly one invitation subject.', new.event_type
      using errcode = 'check_violation';
  end if;

  if shape.subject_kind = 'organization'
    and num_nonnulls(new.subject_user_id, new.subject_invitation_id) > 0 then
    raise exception '% is about the organization itself and carries no subject.', new.event_type
      using errcode = 'check_violation';
  end if;

  select string_agg(required_key, ', ' order by required_key) into missing_keys
  from unnest(shape.required_summary_keys) as required_key
  where not new.summary ? required_key;

  if missing_keys is not null then
    raise exception '% is missing %.', new.event_type, missing_keys using errcode = 'check_violation';
  end if;

  for entry in select key, value from jsonb_each(new.summary) loop
    value_kind := shape.summary_keys ->> entry.key;

    if value_kind is null then
      raise exception '% may not carry %.', new.event_type, entry.key using errcode = 'check_violation';
    end if;

    if not private.member_access_summary_value_fits(value_kind, entry.value) then
      raise exception '% has an unusable value for %.', new.event_type, entry.key
        using errcode = 'check_violation';
    end if;
  end loop;

  return new;
end;
$$;

comment on function private.enforce_member_access_event_shape() is
  'Refuses any team history row whose subject or summary does not match its declared shape. This is what '
  'makes "no free text in team history" a database guarantee rather than a convention.';

revoke all on function private.enforce_member_access_event_shape()
  from public, anon, authenticated, service_role;

create trigger organization_member_access_events_shape_check
before insert on public.organization_member_access_events
for each row execute function private.enforce_member_access_event_shape();

-- History is written once. Nothing edits or erases a line after the fact -- including the commands that
-- wrote it, which is why the check covers update as well as delete.
create or replace function private.prevent_member_access_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Team history cannot be changed or deleted once it is recorded.'
    using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_member_access_event_mutation()
  from public, anon, authenticated, service_role;

create trigger organization_member_access_events_immutable
before update or delete on public.organization_member_access_events
for each row execute function private.prevent_member_access_event_mutation();

-- ---------------------------------------------------------------------------
-- The seeded vocabulary
-- ---------------------------------------------------------------------------

-- Everything Part 3 records about access, seeded in one place so items 5 and 6 write commands rather than
-- reopen this table. Note what is absent from every summary: the invitee's email lives on the invitation
-- row the event points at, and a member's name is read from profiles at display time.
insert into public.member_access_event_shapes (event_type, subject_kind, summary_keys, required_summary_keys)
values
  ('invitation.sent', 'invitation', '{"role": "role"}'::jsonb, array['role']),
  ('invitation.resent', 'invitation', '{}'::jsonb, '{}'::text[]),
  ('invitation.cancelled', 'invitation', '{}'::jsonb, '{}'::text[]),
  ('invitation.expired', 'invitation', '{}'::jsonb, '{}'::text[]),
  ('invitation.accepted', 'invitation', '{"role": "role"}'::jsonb, array['role']),
  (
    'member.role_changed', 'member',
    '{"previous_role": "role", "new_role": "role"}'::jsonb,
    array['previous_role', 'new_role']
  ),
  (
    'member.permissions_changed', 'member',
    '{"added_permissions": "permission_key_list", "removed_permissions": "permission_key_list"}'::jsonb,
    '{}'::text[]
  ),
  (
    'member.profile_updated', 'member',
    '{"changed_fields": "profile_field_list"}'::jsonb,
    array['changed_fields']
  ),
  ('member.deactivated', 'member', '{"previous_status": "member_status"}'::jsonb, array['previous_status']),
  ('member.restored', 'member', '{"restored_role": "role"}'::jsonb, array['restored_role']),
  ('member.removed', 'member', '{}'::jsonb, '{}'::text[]),
  ('member.identity_revoked', 'member', '{}'::jsonb, '{}'::text[]),
  ('ownership.transfer_requested', 'member', '{"transfer_id": "id"}'::jsonb, array['transfer_id']),
  ('ownership.transfer_accepted', 'member', '{"transfer_id": "id"}'::jsonb, array['transfer_id']),
  ('ownership.transfer_declined', 'member', '{"transfer_id": "id"}'::jsonb, array['transfer_id']),
  ('ownership.transfer_cancelled', 'member', '{"transfer_id": "id"}'::jsonb, array['transfer_id']);
