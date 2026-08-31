-- The first capacity migration ran before this constraint was named explicitly.
-- Normalize its generated name, then make the claim's upsert target that stable constraint.
do $$
declare
  function_definition text;
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.communication_email_capacity_reservations'::regclass
      and conname = 'communication_email_capacity_reservation_delivery_intent_id_key'
  ) then
    alter table public.communication_email_capacity_reservations
      rename constraint communication_email_capacity_reservation_delivery_intent_id_key
      to communication_email_capacity_reservations_delivery_intent_key;
  end if;

  select pg_get_functiondef('public.claim_communication_outbox_event()'::regprocedure)
  into function_definition;
  if position('on conflict (delivery_intent_id) do update' in function_definition) > 0 then
    function_definition := replace(
      function_definition,
      'on conflict (delivery_intent_id) do update',
      'on conflict on constraint communication_email_capacity_reservations_delivery_intent_key do update'
    );
    execute function_definition;
  end if;
end;
$$;
