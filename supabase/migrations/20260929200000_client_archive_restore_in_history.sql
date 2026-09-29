-- Archiving and restoring a client now leaves a line in the client's history, as the client contract asks
-- ("archive, unarchive, and merge are audited"). Each path that changes archived_at writes its own line, the
-- way merge_clients already does: the office archiving, the office restoring, and new work bringing an
-- archived client back on its own.

CREATE OR REPLACE FUNCTION public.archive_client(target_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  client_row public.clients;
  open_work jsonb;
begin
  select * into client_row
  from public.clients
  where id = target_client_id and deleted_at is null
  for update;

  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'customers.archive'
     ) then
    raise exception 'You do not have access to archive this client.' using errcode = 'insufficient_privilege';
  end if;

  if client_row.archived_at is not null then
    return jsonb_build_object('applied', false, 'archived', true, 'open_work', null);
  end if;

  open_work := private.client_open_work(client_row.organization_id, client_row.id);

  if (open_work->>'requests')::bigint > 0
     or (open_work->>'quotes')::bigint > 0
     or (open_work->>'jobs')::bigint > 0
     or (open_work->>'invoices')::bigint > 0 then
    return jsonb_build_object('applied', false, 'archived', false, 'open_work', open_work);
  end if;

  update public.clients set archived_at = now() where id = client_row.id;

  insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id)
  values (client_row.organization_id, 'client', client_row.id, 'client.archived', 'Archived this client.',
    (select auth.uid()));

  return jsonb_build_object('applied', true, 'archived', true, 'open_work', null);
end;
$function$;

CREATE OR REPLACE FUNCTION public.restore_client(target_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  client_row public.clients;
begin
  select * into client_row
  from public.clients
  where id = target_client_id and deleted_at is null
  for update;

  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'customers.archive'
     ) then
    raise exception 'You do not have access to restore this client.' using errcode = 'insufficient_privilege';
  end if;

  if client_row.archived_at is null then
    return jsonb_build_object('applied', false, 'archived', false);
  end if;

  update public.clients set archived_at = null where id = client_row.id;

  insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id)
  values (client_row.organization_id, 'client', client_row.id, 'client.restored', 'Restored this client.',
    (select auth.uid()));

  return jsonb_build_object('applied', true, 'archived', false);
end;
$function$;

-- Fires on a new request, quote, job or invoice. The person who added the work is the actor; a website
-- booking or an automation has none, and the history says it happened on its own.
CREATE OR REPLACE FUNCTION private.unarchive_client_for_new_work()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  restored_org uuid;
begin
  update public.clients
  set archived_at = null
  where id = new.client_id and archived_at is not null
  returning organization_id into restored_org;

  if restored_org is not null then
    insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id,
      metadata)
    values (restored_org, 'client', new.client_id, 'client.restored_by_new_work',
      'Restored when a new ' || rtrim(tg_table_name, 's') || ' was added.',
      (select auth.uid()),
      jsonb_build_object('record_type', rtrim(tg_table_name, 's'), 'record_id', new.id));
  end if;

  return new;
end;
$function$;
