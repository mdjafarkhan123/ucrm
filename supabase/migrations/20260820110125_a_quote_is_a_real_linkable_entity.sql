-- The previous migration widened the four entity_type lists and taught the view/manage dispatchers about
-- quotes, but not the trigger that checks the target actually exists. Every insert of a quote note, tag,
-- attachment, or activity event was refused with "The linked quote was not found in this organization."
--
-- Widening a polymorphic seam means three edits, not two: the list, the visibility pair, and this. Caught
-- by the Part 3A database test attaching a file to a quote.
create or replace function private.linked_entity_exists(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then exists (
      select 1 from public.clients
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'property' then exists (
      select 1 from public.properties
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'request' then exists (
      select 1 from public.requests
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'quote' then exists (
      select 1 from public.quotes
      where id = target_entity_id and organization_id = target_organization_id
    )
    else false
  end;
$$;
