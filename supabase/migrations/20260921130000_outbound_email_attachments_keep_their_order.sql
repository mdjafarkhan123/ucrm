-- Outbound email attachments keep the order they were attached in.
--
-- Files attached in one call all get the same created_at, so the worker's listing (order by created_at, id)
-- broke the tie with a random row id and a message's files could go out in any order. The order is now stored
-- explicitly: sort_order is the file's zero-based place in the array the caller sent, and the listing reads it.
--
-- Existing rows are backfilled with the order the old listing returned them in (created_at, then id), so no
-- message already queued changes order.

alter table public.communication_outbound_attachments
  add column sort_order integer not null default 0;

update public.communication_outbound_attachments as attachment
set sort_order = ranked.place - 1
from (
  select
    id,
    row_number() over (partition by delivery_intent_id order by created_at, id) as place
  from public.communication_outbound_attachments
) as ranked
where ranked.id = attachment.id;

alter table public.communication_outbound_attachments
  add constraint communication_outbound_attachments_sort_order_check check (sort_order >= 0);

create or replace function private.attach_communication_outbound_files(
  target_organization_id uuid,
  target_delivery_intent_id uuid,
  target_attachments jsonb
) returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  total_bytes bigint;
  file_count integer;
begin
  if target_attachments is null or jsonb_array_length(target_attachments) = 0 then
    return;
  end if;

  select count(*), coalesce(sum((item ->> 'byte_size')::bigint), 0)
  into file_count, total_bytes
  from jsonb_array_elements(target_attachments) as item;

  if file_count > 10 then
    raise exception 'Attach at most 10 files to one email.' using errcode = 'check_violation';
  end if;
  if total_bytes > 20 * 1024 * 1024 then
    raise exception 'Attachments must total 20 MB or less.' using errcode = 'check_violation';
  end if;

  -- Defense in depth behind the API's own prefix check: a key issued for one organization can never be
  -- committed against another, matching how set_organization_logo guards its own prefix.
  if exists (
    select 1 from jsonb_array_elements(target_attachments) as item
    where item ->> 'object_key' not like target_organization_id::text || '/outbound-email-attachments/%'
  ) then
    raise exception 'That file does not belong to this business.' using errcode = 'check_violation';
  end if;

  insert into public.communication_outbound_attachments (
    organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key, sort_order
  )
  select
    target_organization_id,
    target_delivery_intent_id,
    item.value ->> 'file_name',
    item.value ->> 'mime_type',
    (item.value ->> 'byte_size')::bigint,
    item.value ->> 'object_key',
    (item.ordinality - 1)::integer
  from jsonb_array_elements(target_attachments) with ordinality as item(value, ordinality)
  on conflict (delivery_intent_id, object_key) do nothing;
end;
$$;

create or replace function public.list_communication_outbound_attachments(target_delivery_intent_id uuid)
returns table (file_name text, mime_type text, byte_size bigint, object_key text)
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select
    attachment.file_name,
    attachment.mime_type,
    attachment.byte_size,
    attachment.object_key
  from public.communication_outbound_attachments attachment
  where attachment.delivery_intent_id = target_delivery_intent_id
    and attachment.delivery_mode = 'inline_media'
  order by attachment.sort_order, attachment.id;
$$;
