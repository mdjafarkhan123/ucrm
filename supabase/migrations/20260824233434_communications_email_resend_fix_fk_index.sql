drop index if exists public.communication_delivery_intents_resent_from_idx;
create index communication_delivery_intents_resent_from_idx
  on public.communication_delivery_intents (resent_from_intent_id)
  where resent_from_intent_id is not null;
