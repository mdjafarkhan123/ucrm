-- Part 6D found this the hard way: 20260923130000 widened can_view_linked_entity/can_manage_linked_record
-- with an 'organization' branch, but file_links' own insert trigger (private.validate_linked_entity) checks
-- a different function -- private.linked_entity_exists -- which still fell through to `else false` for
-- 'organization' and refused every file_links row finalize_file_processing tried to insert for a logo.
-- There is no table row to look up: the "record" is the organization itself, so this only confirms the id
-- the caller already passed is the organization the file was uploaded for.
create or replace function private.linked_entity_exists(target_organization_id uuid, target_entity_type text, target_entity_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
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
    when 'job_expense' then exists (
      select 1 from public.job_expenses
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'job' then exists (
      select 1 from public.jobs
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'visit' then exists (
      select 1 from public.job_visits
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'invoice' then exists (
      select 1 from public.invoices
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'organization' then target_entity_id = target_organization_id
    else false
  end;
$function$;
