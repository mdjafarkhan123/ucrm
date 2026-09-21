-- Baseline, part 2 of 4: things that live outside the app's own schemas but the app depends on.
--
-- 1. The sign-up hook: every new auth user gets a profile row.
-- 2. Two Realtime channel rules for Website Chat (staff see their own channels; a visitor may listen only
--    on the short-lived channel they were granted). Realtime creates `realtime.messages` itself, so the
--    Realtime service must already have started on the target database when this runs.
-- 3. Vault placeholders. Names and descriptions only, never values: every environment sets its own real
--    URL and secret directly in Vault. Until it does, the scheduled jobs (part 4) stay off. A placeholder is
--    not a URL, and pg_net raises on one, so the wake calls made on the send path (for example, queuing an
--    email) fail with "invalid URL" until the real values are set. Set them before using those paths.

drop trigger if exists on_auth_user_created_create_profile on auth.users;
create trigger on_auth_user_created_create_profile
  after insert on auth.users
  for each row execute function private.handle_new_user_profile();

drop policy if exists website_chat_staff_channel_read on realtime.messages;
create policy website_chat_staff_channel_read
  on realtime.messages
  for select
  to authenticated
  using (extension = 'broadcast' and private.website_chat_staff_topic_permitted(topic));

drop policy if exists website_chat_visitor_channel_read on realtime.messages;
create policy website_chat_visitor_channel_read
  on realtime.messages
  for select
  to anon
  using (extension = 'broadcast' and private.website_chat_realtime_topic_granted(topic));

do $$
declare
  placeholder record;
begin
  for placeholder in
    select * from (values
    ('automation_worker_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret shared with AUTOMATION_WORKER_SECRET in the app environment.'),
    ('automation_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal automation worker URL ending in /api/internal/automation/worker.'),
    ('client_import_worker_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret shared with CLIENT_IMPORT_WORKER_SECRET in the app environment.'),
    ('client_import_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal client-import worker URL ending in /api/internal/imports/clients/worker.'),
    ('closure_cron_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret sent as the Authorization header to the internal closure-cron route. Must match the app''s CLOSURE_CRON_SECRET environment variable.'),
    ('closure_cron_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Internal URL the daily organization-closure cron job calls (net.http_post target). Update this value directly when the deployment target changes -- no migration or code change needed.'),
    ('communications_email_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Live email-outbox worker route for the communications wake cron.'),
    ('communications_inbound_attachment_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal inbound attachment worker URL ending in /api/internal/communications/inbound-attachment-worker.'),
    ('communications_sms_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal sms outbox worker URL ending in /api/internal/communications/sms-worker.'),
    ('communications_worker_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Shared bearer for internal communications workers; must match app env COMMUNICATIONS_WORKER_SECRET.'),
    ('form_submission_worker_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret shared with FORM_SUBMISSION_WORKER_SECRET in the app environment.'),
    ('form_submission_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal form-submission worker URL ending in /api/internal/forms/worker.'),
    ('sms_price_reconciliation_cron_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret sent as the Authorization header to the internal sms-price-reconciliation-cron route. Must match the app''s SMS_PRICE_RECONCILIATION_CRON_SECRET environment variable.'),
    ('sms_price_reconciliation_cron_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Internal URL the SMS price-reconciliation cron job calls (net.http_post target). Update this value directly when the deployment target changes -- no migration or code change needed.'),
    ('sms_usage_reconciliation_cron_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret sent as the Authorization header to the internal sms-usage-reconciliation-cron route. Must match the app''s SMS_USAGE_RECONCILIATION_CRON_SECRET environment variable.'),
    ('sms_usage_reconciliation_cron_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Internal URL the SMS usage-window reconciliation cron job calls (net.http_post target). Update this value directly when the deployment target changes -- no migration or code change needed.'),
    ('team_invitation_worker_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret for the invitation worker route. Must match TEAM_INVITATION_WORKER_SECRET.'),
    ('team_invitation_worker_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal invitation worker URL ending in /api/internal/team-invitations/worker.'),
    ('trust_hub_status_cron_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret sent as the Authorization header to the internal trust-hub-status-cron route. Must match the app''s TRUST_HUB_STATUS_CRON_SECRET environment variable.'),
    ('trust_hub_status_cron_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Internal URL the daily Trust Hub status-sync safety-net cron job calls (net.http_post target). Update this value directly when the deployment target changes -- no migration or code change needed.')
    ) as p(secret_name, secret_value, secret_description)
  loop
    if not exists (select 1 from vault.secrets where name = placeholder.secret_name) then
      perform vault.create_secret(placeholder.secret_value, placeholder.secret_name, placeholder.secret_description);
    end if;
  end loop;
end;
$$;
