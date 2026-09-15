-- Communications A2 / Stage 9D: automatic trigger for Stage 9C's syncTrustHubRegistrationStatus.
--
-- Gap found while closing out 9C (tracked in Memory's NOW.md): syncTrustHubRegistrationStatus re-fetches a
-- submitted registration's live Twilio Brand/Campaign status and reflects it onto
-- communication_sms_registrations, but nothing ever called it -- it only ran if invoked directly.
--
-- Twilio's own documentation, for this exact ISV Brand/Campaign status-tracking scenario, recommends a push
-- notification over repeatedly polling the Brand endpoint: "the advantage of an Event Streams subscription is
-- that it creates a 'push' notification of status change, rather than you having to repeatedly poll the Brand
-- endpoint itself with GET calls" (troubleshooting-sole-proprietor-brand-registration-failures, researched
-- 2026-09-15, not memory). Jafar approved building both: Twilio Event Streams (a webhook Sink) as the primary,
-- near-real-time path, plus this migration's daily poll as a safety net -- mirroring the "reconcile daily"
-- pattern this app already uses for SMS message delivery status (docs/research/ghl-jobber-sms-onboarding-plan.md).
-- Because every contractor's Brand/Campaign lives under UCRM's own single Twilio account (not a subaccount per
-- contractor), only one Event Streams Sink/Subscription is ever needed for the whole platform -- creating it
-- is a real action on the live Twilio account and stays Jafar's to do, not automated here.
--
-- This migration covers: (1) an index so the webhook can look up a registration by an inbound Brand/Campaign
-- SID without a table scan, and (2) the poll's daily schedule + secret bridge, mirroring
-- organization_closure_cron_extensions_and_vault.sql / organization-closure-daily-cron-schedule.sql exactly
-- (pg_cron has no HTTP/Node context, so it calls pg_net -> the internal
-- /api/jafar/internal/trust-hub-status-cron route, authorized by a Vault-held shared secret since a scheduled
-- job has no owner session). pg_cron/pg_net are already installed by the closure-cron migration.

create index communication_sms_trust_hub_resources_role_sid_idx
  on public.communication_sms_trust_hub_resources (resource_role, provider_sid)
  where provider_sid is not null;

do $$
declare
  target_url_secret_id uuid;
  cron_secret_secret_id uuid;
begin
  select id into target_url_secret_id from vault.secrets where name = 'trust_hub_status_cron_target_url';
  if target_url_secret_id is null then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
      'trust_hub_status_cron_target_url',
      'Internal URL the daily Trust Hub status-sync safety-net cron job calls (net.http_post target). Update this value directly when the deployment target changes -- no migration or code change needed.'
    );
  end if;

  select id into cron_secret_secret_id from vault.secrets where name = 'trust_hub_status_cron_secret';
  if cron_secret_secret_id is null then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
      'trust_hub_status_cron_secret',
      'Bearer secret sent as the Authorization header to the internal trust-hub-status-cron route. Must match the app''s TRUST_HUB_STATUS_CRON_SECRET environment variable.'
    );
  end if;
end;
$$;

select cron.schedule(
  'trust-hub-status-sync-daily',
  '30 6 * * *',
  $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'trust_hub_status_cron_target_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'trust_hub_status_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);
