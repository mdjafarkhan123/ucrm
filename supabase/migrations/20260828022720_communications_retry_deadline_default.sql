alter table public.communication_delivery_intents
  alter column expires_at set default (now() + interval '24 hours');
