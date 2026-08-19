-- Sales Pipeline, Part 3C: Pipeline-scoped Notes.
--
-- The Brief's approved contract is that pipeline.edit authorizes every Note mutation made from the Brief,
-- including a Note targeting the Client -- a salesperson does not need customers.edit to log a call against
-- the deal they own. The generic Notes surface (Request/Client detail pages) keeps its existing
-- customers.edit/property.manage contract untouched; this adds a second, narrower door onto the same
-- `notes`/`note_links` tables, so a Note made from either surface is the same row and shows on both.
--
-- Every function below resolves the Request and Client ids from the Opportunity row itself, never from the
-- caller, so a Note can only ever be read or written against the Request/Client that Opportunity actually
-- points to.

-- 1. The shared guard every Pipeline-scoped Note function goes through --------------------------------

create or replace function private.pipeline_note_scope(
  target_opportunity_id uuid,
  required_permission text
)
returns table (organization_id uuid, request_id uuid, client_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  found record;
begin
  select opportunity.organization_id, opportunity.request_id, opportunity.client_id
  into found
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id;

  -- One answer for "no such card" and "not your card": a stranger learns nothing either way.
  if found.organization_id is null
     or not private.member_has_permission(found.organization_id, (select auth.uid()), required_permission)
  then
    raise exception 'You do not have access to notes on this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  return query select found.organization_id, found.request_id, found.client_id;
end;
$$;

revoke all on function private.pipeline_note_scope(uuid, text) from public;
revoke execute on function private.pipeline_note_scope(uuid, text) from anon, authenticated;

-- 2. Read ------------------------------------------------------------------------------------------------

create or replace function public.pipeline_opportunity_notes(target_opportunity_id uuid)
returns table (
  id uuid,
  body text,
  pinned boolean,
  created_by uuid,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  entity_type text,
  entity_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.view');

  return query
  select
    note.id, note.body, note.pinned, note.created_by, note.edited_by, note.edited_at,
    note.created_at, note.updated_at, link.entity_type, link.entity_id
  from public.note_links as link
  join public.notes as note on note.id = link.note_id
  where link.organization_id = scope.organization_id
    and (
      (link.entity_type = 'request' and link.entity_id = scope.request_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  order by note.pinned desc, note.created_at desc;
end;
$$;

-- 3. Create ------------------------------------------------------------------------------------------------

create or replace function public.pipeline_create_opportunity_note(
  target_opportunity_id uuid,
  target_entity_type text,
  new_body text
)
returns table (
  id uuid,
  body text,
  pinned boolean,
  created_by uuid,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  entity_type text,
  entity_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  resolved_entity_id uuid;
  inserted_note public.notes;
  inserted_link public.note_links;
begin
  if target_entity_type not in ('request', 'client') then
    raise exception 'A Brief Note can only target the Request or the Client.'
      using errcode = 'check_violation';
  end if;

  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');

  resolved_entity_id := case target_entity_type
    when 'request' then scope.request_id
    else scope.client_id
  end;

  if resolved_entity_id is null then
    raise exception 'This opportunity has no % to attach a note to.', target_entity_type
      using errcode = 'check_violation';
  end if;

  insert into public.notes (organization_id, body, created_by)
  values (scope.organization_id, new_body, (select auth.uid()))
  returning * into inserted_note;

  insert into public.note_links (organization_id, note_id, entity_type, entity_id)
  values (scope.organization_id, inserted_note.id, target_entity_type, resolved_entity_id)
  returning * into inserted_link;

  return query
  select
    inserted_note.id, inserted_note.body, inserted_note.pinned, inserted_note.created_by,
    inserted_note.edited_by, inserted_note.edited_at, inserted_note.created_at, inserted_note.updated_at,
    inserted_link.entity_type, inserted_link.entity_id;
end;
$$;

-- 4. Update ------------------------------------------------------------------------------------------------

create or replace function public.pipeline_update_opportunity_note(
  target_note_id uuid,
  target_opportunity_id uuid,
  new_body text
)
returns table (
  id uuid,
  body text,
  pinned boolean,
  created_by uuid,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  entity_type text,
  entity_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  target_link public.note_links;
  updated_note public.notes;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');

  select link.* into target_link
  from public.note_links as link
  where link.note_id = target_note_id
    and link.organization_id = scope.organization_id
    and (
      (link.entity_type = 'request' and link.entity_id = scope.request_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  limit 1;

  if target_link.id is null then
    raise exception 'That note is not on this opportunity.' using errcode = 'insufficient_privilege';
  end if;

  update public.notes as note
  set body = new_body, edited_by = (select auth.uid()), edited_at = now()
  where note.id = target_note_id
  returning * into updated_note;

  return query
  select
    updated_note.id, updated_note.body, updated_note.pinned, updated_note.created_by,
    updated_note.edited_by, updated_note.edited_at, updated_note.created_at, updated_note.updated_at,
    target_link.entity_type, target_link.entity_id;
end;
$$;

-- 5. Delete ------------------------------------------------------------------------------------------------

create or replace function public.pipeline_delete_opportunity_note(
  target_note_id uuid,
  target_opportunity_id uuid,
  target_entity_type text
)
returns table (unlinked boolean, note_deleted boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  resolved_entity_id uuid;
  remaining integer;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');

  resolved_entity_id := case target_entity_type
    when 'request' then scope.request_id
    when 'client' then scope.client_id
    else null
  end;

  delete from public.note_links as link
  where link.note_id = target_note_id
    and link.organization_id = scope.organization_id
    and link.entity_type = target_entity_type
    and link.entity_id = resolved_entity_id;

  if not found then
    raise exception 'That note is not on this opportunity.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into remaining from public.note_links as link where link.note_id = target_note_id;

  if remaining = 0 then
    delete from public.notes as note where note.id = target_note_id;
    return query select true, true;
  end if;

  return query select true, false;
end;
$$;

-- 6. Grants ------------------------------------------------------------------------------------------------

revoke all on function public.pipeline_opportunity_notes(uuid) from public;
revoke all on function public.pipeline_create_opportunity_note(uuid, text, text) from public;
revoke all on function public.pipeline_update_opportunity_note(uuid, uuid, text) from public;
revoke all on function public.pipeline_delete_opportunity_note(uuid, uuid, text) from public;

revoke execute on function public.pipeline_opportunity_notes(uuid) from anon;
revoke execute on function public.pipeline_create_opportunity_note(uuid, text, text) from anon;
revoke execute on function public.pipeline_update_opportunity_note(uuid, uuid, text) from anon;
revoke execute on function public.pipeline_delete_opportunity_note(uuid, uuid, text) from anon;

grant execute on function public.pipeline_opportunity_notes(uuid) to authenticated;
grant execute on function public.pipeline_create_opportunity_note(uuid, text, text) to authenticated;
grant execute on function public.pipeline_update_opportunity_note(uuid, uuid, text) to authenticated;
grant execute on function public.pipeline_delete_opportunity_note(uuid, uuid, text) to authenticated;
