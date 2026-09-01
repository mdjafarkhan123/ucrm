-- Automation Part 6D bug fix: stop_automation_enrollment(), when the caller left the reason box empty,
-- backfilled stop_reason with the literal internal code 'stopped_manually' instead of leaving it null. The
-- Quote-level Automation card then showed that code back to the contractor in italics as if it were a note
-- they had written. The UI already hides the "reason" line when stop_reason is null/empty, so the fix is to
-- stop synthesizing a fake reason: store whatever the caller typed (trimmed, 200-char cap), or null if
-- nothing was typed.
--
-- CREATE OR REPLACE forward-fix (the original 20260831055152 is already applied on remote).

create or replace function public.stop_automation_enrollment(p_organization_id uuid, p_actor_user_id uuid, p_enrollment_id uuid, p_reason text, p_idempotency_key uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  existing_receipt public.automation_enrollment_command_receipts%rowtype;
  enrollment private.automation_enrollments%rowtype;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_receipt
  from public.automation_enrollment_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = p_enrollment_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That enrollment does not exist.' using errcode = 'no_data_found';
  end if;
  if enrollment.state not in ('active', 'paused') then
    raise exception 'This enrollment is already finished.' using errcode = 'restrict_violation';
  end if;

  update private.automation_work_items
  set state = 'cancelled', claim_token = null, claimed_at = null
  where enrollment_id = p_enrollment_id and state = 'pending';

  update private.automation_enrollments
  set state = 'stopped',
      stop_reason = nullif(left(btrim(p_reason), 200), ''),
      stopped_at = now(),
      paused_work_due_at = null
  where id = p_enrollment_id;

  command_result := jsonb_build_object('enrollment_id', p_enrollment_id, 'state', 'stopped');

  insert into public.automation_enrollment_command_receipts (
    organization_id, idempotency_key, command, subject_type, subject_id, enrollment_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'stop', enrollment.subject_type, enrollment.subject_id,
    p_enrollment_id, command_result
  );

  return command_result;
end;
$function$;
