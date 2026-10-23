-- Stage 10 Part 7 follow-up (docs/global-sms-behavior-contract.md § Part 7): release a number here before Twilio.
--
-- The worker used to read the due list, ask Twilio to let a number go and only then record it. A top-up confirmed
-- in between would pay a month for a number Twilio had already taken back. Now the worker records the release
-- first (communication_sms_record_number_released locks the number, so a later top-up finds nothing unpaid to pay),
-- then asks Twilio, then marks Twilio's side done. A Twilio failure leaves the number on the due list until Twilio
-- confirms, so Uplift is never billed for a number nobody owns.

alter table public.communication_sms_sender_identities
  add column provider_released_at timestamptz;

-- Released here, still held at Twilio: the worker's retry list. Tiny, so a partial index keeps it free.
create index communication_sms_sender_identities_twilio_release_idx
  on public.communication_sms_sender_identities (released_at)
  where renewal_state = 'released' and released_at is not null and provider_released_at is null;

-- Numbers past their grace, then numbers released here that Twilio has not confirmed yet.
create or replace function public.communication_sms_due_number_releases(p_limit integer default 10)
returns table (
  sender_id uuid,
  organization_id uuid,
  phone_number text,
  provider_phone_number_sid text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select due.id, due.organization_id, due.phone_number, due.provider_phone_number_sid
  from (
    select s.id, s.organization_id, s.phone_number, s.provider_phone_number_sid, s.grace_ends_at as due_at
    from public.communication_sms_sender_identities s
    where s.renewal_state = 'unpaid' and s.lifecycle_state <> 'released' and s.grace_ends_at <= now()
    union all
    select s.id, s.organization_id, s.phone_number, s.provider_phone_number_sid, s.released_at
    from public.communication_sms_sender_identities s
    where s.renewal_state = 'released' and s.released_at is not null and s.provider_released_at is null
  ) due
  order by due.due_at, due.id
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

-- Twilio let the number go (or no longer has it).
create or replace function public.communication_sms_record_number_provider_released(p_sender_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog, public
as $$
  update public.communication_sms_sender_identities
  set provider_released_at = now(), updated_at = now()
  where id = p_sender_id and renewal_state = 'released' and provider_released_at is null
  returning true;
$$;

revoke all on function public.communication_sms_due_number_releases(integer) from public, anon, authenticated;
revoke all on function public.communication_sms_record_number_provider_released(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_due_number_releases(integer) to service_role;
grant execute on function public.communication_sms_record_number_provider_released(uuid) to service_role;
