-- Part 4 item 4: attachment import queue. status='pending_import' is reused as the queue state itself
-- (no new enum value) -- claimed_at/claim_token null means unclaimed; a claim older than 10 minutes is
-- reclaimable. An import retry is naturally idempotent (re-fetching the same provider download token and
-- overwriting the same object key), so unlike outbound email this needs no separate quarantine RPC.

alter table public.communication_inbound_attachments
  add column claimed_at timestamptz,
  add column claim_token uuid,
  add column provider_download_token text,
  add constraint communication_inbound_attachments_claim_check check (
    (claimed_at is null) = (claim_token is null)
  );

create index communication_inbound_attachments_import_queue_idx
  on public.communication_inbound_attachments (claimed_at, created_at)
  where status = 'pending_import';

create or replace function public.claim_communication_inbound_attachment_imports(
  batch_size integer default 20
)
returns setof public.communication_inbound_attachments
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_claim_token uuid;
begin
  if batch_size not between 1 and 100 then
    raise exception 'The inbound attachment import batch is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  new_claim_token := gen_random_uuid();

  return query
  update public.communication_inbound_attachments attachment
  set claimed_at = now(), claim_token = new_claim_token
  from (
    select id
    from public.communication_inbound_attachments
    where status = 'pending_import'
      and (claimed_at is null or claimed_at <= now() - interval '10 minutes')
    order by created_at, id
    limit batch_size
    for update skip locked
  ) due
  where attachment.id = due.id
  returning attachment.*;
end;
$$;

revoke all on function public.claim_communication_inbound_attachment_imports(integer)
  from public, anon, authenticated;
grant execute on function public.claim_communication_inbound_attachment_imports(integer) to service_role;

-- A stale/foreign claim_token is a no-op returning the current row, not an error -- nothing about an
-- attachment import is irreversible, so there is nothing to protect by raising here.
create or replace function public.finalize_communication_inbound_attachment_import(
  target_attachment_id uuid,
  target_claim_token uuid,
  target_status text,
  target_object_key text default null,
  target_failure_reason text default null
) returns public.communication_inbound_attachments
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  updated_row public.communication_inbound_attachments;
begin
  if target_status not in ('pending_scan', 'blocked_type', 'blocked_size', 'import_failed') then
    raise exception 'The inbound attachment import outcome is not a valid target status.'
      using errcode = 'check_violation';
  end if;

  update public.communication_inbound_attachments
  set status = target_status,
    object_key = case when target_status = 'pending_scan' then target_object_key else object_key end,
    failure_reason = target_failure_reason,
    provider_download_token = null, claimed_at = null, claim_token = null
  where id = target_attachment_id and claim_token = target_claim_token
  returning * into updated_row;

  if updated_row.id is null then
    select * into updated_row from public.communication_inbound_attachments
    where id = target_attachment_id;
  end if;

  return updated_row;
end;
$$;

revoke all on function public.finalize_communication_inbound_attachment_import(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.finalize_communication_inbound_attachment_import(
  uuid, uuid, text, text, text
) to service_role;
