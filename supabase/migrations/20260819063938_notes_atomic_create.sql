create or replace function public.create_note(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  new_body text,
  new_pinned boolean default false
)
returns table (
  id uuid,
  organization_id uuid,
  body text,
  pinned boolean,
  created_by uuid,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  link_id uuid,
  entity_type text,
  entity_id uuid,
  link_created_at timestamptz
)
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  inserted_note public.notes;
  inserted_link public.note_links;
begin
  insert into public.notes (organization_id, body, pinned, created_by)
  values (target_organization_id, new_body, coalesce(new_pinned, false), (select auth.uid()))
  returning * into inserted_note;

  insert into public.note_links (organization_id, note_id, entity_type, entity_id)
  values (target_organization_id, inserted_note.id, target_entity_type, target_entity_id)
  returning * into inserted_link;

  return query
  select
    inserted_note.id, inserted_note.organization_id, inserted_note.body, inserted_note.pinned,
    inserted_note.created_by, inserted_note.edited_by, inserted_note.edited_at, inserted_note.created_at,
    inserted_note.updated_at, inserted_link.id, inserted_link.entity_type, inserted_link.entity_id,
    inserted_link.created_at;
end;
$$;

revoke all on function public.create_note(uuid, text, uuid, text, boolean) from public;
grant execute on function public.create_note(uuid, text, uuid, text, boolean) to authenticated;
