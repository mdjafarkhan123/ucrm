-- Operational email SES Part 4: restore the inbound resolver's original service-role-only access.
--
-- The baseline revoked record_communication_inbound_message from PUBLIC and granted it only to service_role.
-- 20260925150000 created the 13-argument version as a new function, which picked up Supabase's default
-- EXECUTE grants to anon and authenticated. It is SECURITY DEFINER and inserts inbound messages for any
-- organization, so a browser holding the public anon key could have forged customer replies. Only the
-- server-side Brevo webhook and SES worker (service role) may call it.

revoke all on function "public"."record_communication_inbound_message"(
    text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb, text
) from public, anon, authenticated;
grant execute on function "public"."record_communication_inbound_message"(
    text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb, text
) to service_role;
