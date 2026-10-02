-- Pipeline E3b: a card that came from a Quote takes Brief Notes too.
--
-- The plan says a Brief Note belongs to the card's backing Request or Quote, or its Client. Until now the Note
-- functions only knew a card's Request, so on a Quote card the default target was refused and a Note's photo
-- had no record to upload against. Now:
--   * A Quote card writes Notes onto its Quote (or the Client); a Request card onto its Request (or the Client).
--   * A Quote converted from a Request keeps showing that Request's Notes in the Brief, labelled "Request", as
--     Jobber lists a linked Request's notes beside the Quote's own. They stay where they were written.
--   * A Note's photo on a Quote card is uploaded against the Quote.
--
-- pipeline_note_scope gains the card's quote_id, and its request_id now falls back to the Quote's source
-- Request, so the read, edit, delete and file functions see the same three records.

-- 1. The card's records ---------------------------------------------------------------------------------------

drop function private.pipeline_note_scope(uuid, text);

create function private.pipeline_note_scope(target_opportunity_id uuid, required_permission text)
returns table (organization_id uuid, request_id uuid, client_id uuid, quote_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  found record;
begin
  select
    opportunity.organization_id,
    coalesce(opportunity.request_id, quote.request_id) as request_id,
    opportunity.client_id,
    opportunity.quote_id
  into found
  from public.opportunities as opportunity
  left join public.quotes as quote
    on quote.organization_id = opportunity.organization_id and quote.id = opportunity.quote_id
  where opportunity.id = target_opportunity_id;

  -- One answer for "no such card" and "not your card": a stranger learns nothing either way.
  if found.organization_id is null
     or not private.member_has_permission(found.organization_id, (select auth.uid()), required_permission)
  then
    raise exception 'You do not have access to notes on this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  return query select found.organization_id, found.request_id, found.client_id, found.quote_id;
end;
$$;

revoke all on function private.pipeline_note_scope(uuid, text) from public, anon, authenticated;

-- 2. Saving a Note's Files and mentions: a File may also come from the card's Quote ---------------------------
--
-- Unchanged from 20261004090000 except for the extra p_scope_quote_id and the 'quote' origin.

drop function private.pipeline_note_save_extras(uuid, uuid, uuid, uuid, uuid, uuid[], uuid[]);

create function private.pipeline_note_save_extras(
  p_scope_organization_id uuid,
  p_scope_request_id uuid,
  p_scope_client_id uuid,
  p_scope_quote_id uuid,
  p_opportunity_id uuid,
  p_note_id uuid,
  p_file_ids uuid[],
  p_mention_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  wanted_files uuid[];
  wanted_mentions uuid[];
  added_mentions uuid[];
begin
  if p_file_ids is not null then
    select coalesce(array_agg(listed.file_id order by listed.first_at), '{}')
    into wanted_files
    from (
      select entry.file_id, min(entry.at) as first_at
      from unnest(p_file_ids) with ordinality as entry(file_id, at)
      where entry.file_id is not null
      group by entry.file_id
    ) as listed;

    if cardinality(wanted_files) > 10 then
      raise exception 'A note can hold up to 10 photos and files.' using errcode = 'check_violation';
    end if;

    if exists (
      select 1 from unnest(wanted_files) as wanted(file_id)
      where not exists (
          select 1 from public.note_files as held
          where held.note_id = p_note_id and held.file_id = wanted.file_id
        )
        and not exists (
          select 1 from public.files as file
          where file.organization_id = p_scope_organization_id
            and file.id = wanted.file_id
            and file.trashed_at is null
            and file.processing_state in ('pending', 'available')
            and file.origin_role = 'note_file'
            and file.uploaded_by = actor
            and (
              (file.origin_type = 'request' and file.origin_id = p_scope_request_id)
              or (file.origin_type = 'quote' and file.origin_id = p_scope_quote_id)
              or (file.origin_type = 'client' and file.origin_id = p_scope_client_id)
            )
        )
    ) then
      raise exception 'One of the files could not be added. Try uploading it again.'
        using errcode = 'check_violation';
    end if;

    delete from public.note_files as held
    where held.note_id = p_note_id and not (held.file_id = any (wanted_files));

    insert into public.note_files as held (organization_id, note_id, file_id, position, created_by)
    select p_scope_organization_id, p_note_id, wanted.file_id, (wanted.at - 1)::smallint, actor
    from unnest(wanted_files) with ordinality as wanted(file_id, at)
    on conflict (note_id, file_id) do update set position = excluded.position
      where held.position is distinct from excluded.position;
  end if;

  if p_mention_user_ids is not null then
    select coalesce(array_agg(distinct listed.user_id), '{}')
    into wanted_mentions
    from unnest(p_mention_user_ids) as listed(user_id)
    where listed.user_id is not null;

    if cardinality(wanted_mentions) > 10 then
      raise exception 'A note can mention up to 10 teammates.' using errcode = 'check_violation';
    end if;

    if exists (
      select 1 from unnest(wanted_mentions) as wanted(user_id)
      where not private.member_receives_task_alerts(p_scope_organization_id, wanted.user_id)
    ) then
      raise exception 'Someone you mentioned cannot see the Pipeline, so they would not be able to open this card.'
        using errcode = 'check_violation';
    end if;

    select coalesce(array_agg(wanted.user_id), '{}')
    into added_mentions
    from unnest(wanted_mentions) as wanted(user_id)
    where not exists (
      select 1 from public.note_mentions as mention
      where mention.note_id = p_note_id and mention.user_id = wanted.user_id
    );

    delete from public.note_mentions as mention
    where mention.note_id = p_note_id and not (mention.user_id = any (wanted_mentions));

    insert into public.note_mentions (organization_id, note_id, user_id)
    select p_scope_organization_id, p_note_id, added.user_id
    from unnest(added_mentions) as added(user_id);

    perform private.alert_note_mentions(p_note_id, p_opportunity_id, added_mentions);
  end if;
end;
$$;

revoke all on function private.pipeline_note_save_extras(uuid, uuid, uuid, uuid, uuid, uuid, uuid[], uuid[])
  from public, anon, authenticated;

-- 3. The Brief's Note functions read and write the card's Quote ---------------------------------------------
--
-- Same signatures and answers as 20261004090000 (and the baseline's delete); only the records they match change.

create or replace function public.pipeline_opportunity_notes(target_opportunity_id uuid)
returns table (
  id uuid, body text, pinned boolean, created_by uuid, edited_by uuid, edited_at timestamptz,
  created_at timestamptz, updated_at timestamptz, entity_type text, entity_id uuid, files jsonb,
  mention_user_ids uuid[]
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
    note.created_at, note.updated_at, link.entity_type, link.entity_id,
    private.pipeline_note_files_json(note.id), private.note_mention_ids(note.id)
  from public.note_links as link
  join public.notes as note on note.id = link.note_id
  where link.organization_id = scope.organization_id
    and (
      (link.entity_type = 'request' and link.entity_id = scope.request_id)
      or (link.entity_type = 'quote' and link.entity_id = scope.quote_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  order by note.pinned desc, note.created_at desc;
end;
$$;

-- A new Note goes on the card's own record or its Client. A Quote card does not write onto the Request it came
-- from: that Request's Notes show here, but new ones belong to the Quote.
create or replace function public.pipeline_create_opportunity_note(
  target_opportunity_id uuid,
  target_entity_type text,
  new_body text,
  new_file_ids uuid[] default '{}',
  new_mention_user_ids uuid[] default '{}'
)
returns table (
  id uuid, body text, pinned boolean, created_by uuid, edited_by uuid, edited_at timestamptz,
  created_at timestamptz, updated_at timestamptz, entity_type text, entity_id uuid, files jsonb,
  mention_user_ids uuid[]
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
  if target_entity_type not in ('request', 'quote', 'client') then
    raise exception 'A Brief Note can only target the Request, the Quote or the Client.'
      using errcode = 'check_violation';
  end if;

  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');

  resolved_entity_id := case target_entity_type
    when 'request' then case when scope.quote_id is null then scope.request_id end
    when 'quote' then scope.quote_id
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

  perform private.pipeline_note_save_extras(
    scope.organization_id, scope.request_id, scope.client_id, scope.quote_id, target_opportunity_id,
    inserted_note.id, coalesce(new_file_ids, '{}'), coalesce(new_mention_user_ids, '{}')
  );

  return query
  select
    inserted_note.id, inserted_note.body, inserted_note.pinned, inserted_note.created_by,
    inserted_note.edited_by, inserted_note.edited_at, inserted_note.created_at, inserted_note.updated_at,
    inserted_link.entity_type, inserted_link.entity_id,
    private.pipeline_note_files_json(inserted_note.id), private.note_mention_ids(inserted_note.id);
end;
$$;

create or replace function public.pipeline_update_opportunity_note(
  target_note_id uuid,
  target_opportunity_id uuid,
  new_body text,
  new_file_ids uuid[] default null,
  new_mention_user_ids uuid[] default null
)
returns table (
  id uuid, body text, pinned boolean, created_by uuid, edited_by uuid, edited_at timestamptz,
  created_at timestamptz, updated_at timestamptz, entity_type text, entity_id uuid, files jsonb,
  mention_user_ids uuid[]
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
      or (link.entity_type = 'quote' and link.entity_id = scope.quote_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  limit 1;

  if target_link.id is null then
    raise exception 'That note is not on this opportunity.' using errcode = 'insufficient_privilege';
  end if;

  -- Only a real change of text marks the Note edited; changing its Files or mentions alone does not.
  update public.notes as note
  set body = new_body,
      edited_by = case when note.body is distinct from new_body then (select auth.uid()) else note.edited_by end,
      edited_at = case when note.body is distinct from new_body then now() else note.edited_at end
  where note.id = target_note_id
  returning * into updated_note;

  perform private.pipeline_note_save_extras(
    scope.organization_id, scope.request_id, scope.client_id, scope.quote_id, target_opportunity_id,
    target_note_id, new_file_ids, new_mention_user_ids
  );

  return query
  select
    updated_note.id, updated_note.body, updated_note.pinned, updated_note.created_by,
    updated_note.edited_by, updated_note.edited_at, updated_note.created_at, updated_note.updated_at,
    target_link.entity_type, target_link.entity_id,
    private.pipeline_note_files_json(updated_note.id), private.note_mention_ids(updated_note.id);
end;
$$;

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
    when 'quote' then scope.quote_id
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

create or replace function public.pipeline_opportunity_note_file(target_opportunity_id uuid, target_file_id uuid)
returns table (
  display_name text, mime_type text, object_key text, thumbnail_object_key text, processing_state text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.view');

  return query
  select file.display_name, file.mime_type, file.object_key, file.thumbnail_object_key, file.processing_state
  from public.files as file
  where file.organization_id = scope.organization_id
    and file.id = target_file_id
    and file.trashed_at is null
    and exists (
      select 1
      from public.note_files as held
      join public.note_links as link on link.note_id = held.note_id
      where held.organization_id = scope.organization_id
        and held.file_id = file.id
        and (
          (link.entity_type = 'request' and link.entity_id = scope.request_id)
          or (link.entity_type = 'quote' and link.entity_id = scope.quote_id)
          or (link.entity_type = 'client' and link.entity_id = scope.client_id)
        )
    );
end;
$$;
