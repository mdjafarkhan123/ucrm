-- Stage 10 Part 2: only one request may make the Twilio purchase call for an order. The mark-purchasing step becomes a
-- claim that says whether this caller won it; a concurrent double press that loses the claim waits and checks
-- instead of buying again.

drop function public.communication_sms_mark_number_order_purchasing(uuid);

create or replace function public.communication_sms_claim_number_order_purchase(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  update public.communication_sms_number_orders
  set state = 'purchasing', updated_at = now()
  where id = p_order_id and state = 'reserved';
  return found;
end;
$$;

-- A resumed order that is still "purchasing" may be retried only after the first attempt has certainly ended. This
-- refreshes updated_at as the retry's own claim, and only one caller wins it.
create or replace function public.communication_sms_reclaim_number_order_purchase(
  p_order_id uuid,
  p_stale_before timestamptz
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  update public.communication_sms_number_orders
  set updated_at = now()
  where id = p_order_id and state = 'purchasing' and updated_at < p_stale_before;
  return found;
end;
$$;

revoke all on function public.communication_sms_claim_number_order_purchase(uuid) from public, anon, authenticated;
revoke all on function public.communication_sms_reclaim_number_order_purchase(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.communication_sms_claim_number_order_purchase(uuid) to service_role;
grant execute on function public.communication_sms_reclaim_number_order_purchase(uuid, timestamptz) to service_role;
