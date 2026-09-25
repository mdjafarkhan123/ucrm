-- Cron-only worker wake dispatchers must not be callable through the public API.
--
-- These three SECURITY DEFINER functions revoke EXECUTE from PUBLIC, but Supabase's default privileges also
-- grant it to anon and authenticated directly, so anyone holding the public anon key could fire worker wakes
-- on demand. Only pg_cron (running as postgres) and service_role need them.

revoke all on function "public"."dispatch_communication_ses_inbound_worker_wake"() from public, anon, authenticated;
revoke all on function "public"."dispatch_communication_marketing_events_worker_wake"() from public, anon, authenticated;
revoke all on function "public"."dispatch_communication_marketing_worker_wake"() from public, anon, authenticated;
grant execute on function "public"."dispatch_communication_ses_inbound_worker_wake"() to service_role;
grant execute on function "public"."dispatch_communication_marketing_events_worker_wake"() to service_role;
grant execute on function "public"."dispatch_communication_marketing_worker_wake"() to service_role;
