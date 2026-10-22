-- Stage 10 Part 4: a bought number goes live once the approval its route needs has passed
-- (docs/global-sms-behavior-contract.md § Part 4). Owning a number, its paperwork and its texting approval are
-- separate facts; this command is the one place that turns them into a live sender.
--
--   US local numbers texting US customers: the business's approved US registration (A2P 10DLC). The number
--     joins that registration.
--   Local numbers of any other country texting their own country: no registration, only any paperwork the
--     number was bought with, still approved and in date.
--   Toll-free numbers: their own toll-free check, added with that flow; never switched on here.
--
-- Only `pending_setup` senders move, and only forwards to `ready`; pausing, restricting and releasing stay with
-- their own commands. Safe to run again at any time: a second run finds nothing left to do.

create or replace function public.communication_sms_reconcile_sender_readiness(
  p_organization_id uuid,
  p_us_use_case text
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  us_registration_id uuid;
  changed integer := 0;
  moved integer;
begin
  select r.id into us_registration_id
  from public.communication_sms_registrations r
  where r.organization_id = p_organization_id
    and r.country_code = 'US'
    and r.sender_type = 'long_code'
    and r.use_case = p_us_use_case
    and r.status = 'approved';

  with candidates as (
    select s.id
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id
      and s.lifecycle_state = 'pending_setup'
      and s.capable_sms
      and s.sender_type = 'long_code'
      and s.country_code is not null
      and (s.country_code <> 'US' or us_registration_id is not null)
      -- Paperwork the number was bought with must still be approved and in date.
      and not exists (
        select 1
        from public.communication_sms_number_orders o
        where o.organization_id = s.organization_id
          and o.sender_identity_id = s.id
          and (o.bundle_sid is not null or o.address_sid is not null)
          and not exists (
            select 1
            from public.communication_sms_number_paperwork p
            where p.organization_id = o.organization_id
              and p.country_code = o.country_code
              and p.number_type = o.number_type
              and p.status = 'approved'
              and (p.valid_until is null or p.valid_until > now())
          )
      )
    for update of s
  )
  update public.communication_sms_sender_identities s
  set lifecycle_state = 'ready',
      registration_id = case when s.country_code = 'US' then us_registration_id else s.registration_id end,
      updated_at = now()
  from candidates c
  where s.id = c.id;
  get diagnostics moved = row_count;
  changed := changed + moved;

  return changed;
end;
$$;

comment on function public.communication_sms_reconcile_sender_readiness(uuid, text) is
  'Stage 10 Part 4: switches pending_setup long-code senders to ready once their route''s approval has passed (US: the approved US registration; elsewhere: approved, in-date paperwork). Idempotent; toll-free is never switched on here.';

revoke all on function public.communication_sms_reconcile_sender_readiness(uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_reconcile_sender_readiness(uuid, text) to service_role;
