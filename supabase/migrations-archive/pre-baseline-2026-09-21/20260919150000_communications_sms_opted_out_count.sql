-- Fix: two live Settings routes (sms/usage, sms/holds) still query public.communication_sms_consent_state,
-- which 20260919100000 (Stage 4A part 1) dropped in favor of a subject-scoped, compute-on-read model. This
-- was masked because the checked-in database.types.ts had not been regenerated since that drop. Discovered
-- while regenerating types for Stage 4C; fixed here because it sits on the same consent surface and both
-- affected routes are simple, bounded, read-only counts.
--
-- Adds the one thing those routes actually need: how many of an organization's customer numbers are
-- currently opted out (globally, subject-independent), optionally only those opted out since a given time.
-- Uses the exact same "governing event" ordering as communication_sms_consent_status() (occurred_at desc,
-- received_at desc, id desc) and the same projection index, so it stays consistent with the accepted 4A
-- eligibility model. help_requested rows are excluded from the candidate set -- per 4A, a HELP request never
-- changes eligibility and must not be mistaken for the governing event.

create or replace function public.communication_sms_opted_out_count(
  p_organization_id uuid,
  p_since timestamptz default null
) returns integer
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select count(*)::integer
  from (
    select distinct on (governing.client_contact_method_id)
      governing.client_contact_method_id, governing.event_kind, governing.occurred_at
    from public.communication_sms_consent_events governing
    where governing.organization_id = p_organization_id
      and governing.event_kind in ('opt_in', 'opt_out')
    order by governing.client_contact_method_id, governing.occurred_at desc, governing.received_at desc,
      governing.id desc
  ) current_state
  where current_state.event_kind = 'opt_out'
    and (p_since is null or current_state.occurred_at >= p_since);
$$;

comment on function public.communication_sms_opted_out_count(uuid, timestamptz) is
  'Count of an organization''s customer numbers currently opted out of SMS (global, subject-independent), '
  'optionally scoped to those whose opt-out occurred at or after p_since. Derived on read from '
  'communication_sms_consent_events using the same governing-event rule as communication_sms_consent_status().';

revoke all on function public.communication_sms_opted_out_count(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.communication_sms_opted_out_count(uuid, timestamptz) to service_role;
