-- Part 5's refund confirmation (apply_stripe_refund_event, see 20261010090000) journals each refund
-- notification under a compound key -- "<source event id>:<stripe refund id>" -- so the same webhook
-- redelivered for two different refunds on one charge still dedupes correctly, and the synchronous call
-- right after refunds.create() (source id "sync:<refund id>") never collides with the webhook's own entry
-- for the same refund. The original 20261008090000 constraint only ever saw plain checkout/dispute event
-- ids ("evt_..."), so every refund confirmation -- synchronous or webhook -- was rejected by this check and
-- silently left the refund stuck on 'pending'. Found live-verifying Part 5 (2026-09-19): a $5.00 test refund
-- sent successfully in Stripe but never settled in UCRM.
alter table public.payment_stripe_webhook_events
  drop constraint payment_stripe_webhook_events_stripe_event_id_check;

alter table public.payment_stripe_webhook_events
  add constraint payment_stripe_webhook_events_stripe_event_id_check check (
    stripe_event_id ~ '^evt_[A-Za-z0-9_]{1,255}$'
    or stripe_event_id ~ '^evt_[A-Za-z0-9_]{1,255}:re_[A-Za-z0-9_]{1,255}$'
    or stripe_event_id ~ '^sync:re_[A-Za-z0-9_]{1,255}:re_[A-Za-z0-9_]{1,255}$'
  );
