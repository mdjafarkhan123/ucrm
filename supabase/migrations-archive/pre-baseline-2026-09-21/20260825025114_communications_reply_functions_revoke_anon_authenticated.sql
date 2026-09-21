-- Security-advisor fix: the newly created claim_communication_outbox_event() and
-- ensure_communication_reply_alias() were only revoked "from public", not also "from anon,
-- authenticated" -- Supabase's default privileges grant EXECUTE on new public-schema functions to those
-- roles directly, not only via the PUBLIC pseudo-role, so a plain "revoke ... from public" leaves them
-- callable over PostgREST. Every existing communications SECURITY DEFINER function in this schema
-- revokes from all three (see 20260823080419_communications_email_delivery_foundation.sql); these two
-- were missed when they were created/replaced today.

revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;

revoke all on function public.ensure_communication_reply_alias(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.ensure_communication_reply_alias(uuid, uuid, uuid, uuid) to service_role;
