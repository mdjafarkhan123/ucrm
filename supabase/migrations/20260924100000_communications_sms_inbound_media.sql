-- Communications Stage 6D-1: inbound MMS picture receiving.
--
-- communication_inbound_attachments (built for email) is reused as-is for SMS media, not forked -- the same
-- reasoning record_communication_sms_inbound_message already applied to communication_inbound_messages.
-- `provider` is denormalized from the parent message so the import worker never needs a per-row join -- a
-- join-based bug is exactly what caused the Stage 8-3 critical SMS claim fix, avoided deliberately here.

alter table public.communication_inbound_attachments
  add column provider text not null default 'brevo' check (provider in ('brevo', 'twilio'));

comment on column public.communication_inbound_attachments.provider is
  'Denormalized from the parent inbound message -- brevo for email, twilio for SMS/MMS.';

-- Twilio never reports size upfront the way Brevo's ContentLength does; the worker only learns the real byte
-- size after downloading the media. The argument list is genuinely changing (a new trailing param), not just
-- a default on an existing one, so this needs drop + recreate rather than create or replace.
drop function public.finalize_communication_inbound_attachment_import(uuid, uuid, text, text, text);

create or replace function public.finalize_communication_inbound_attachment_import(
  target_attachment_id uuid,
  target_claim_token uuid,
  target_status text,
  target_object_key text default null,
  target_failure_reason text default null,
  target_byte_size bigint default null
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
    byte_size = coalesce(target_byte_size, byte_size),
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
  uuid, uuid, text, text, text, bigint
) from public, anon, authenticated;
grant execute on function public.finalize_communication_inbound_attachment_import(
  uuid, uuid, text, text, text, bigint
) to service_role;
