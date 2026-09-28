-- The previous migration (20260928200000) added two trailing parameters to
-- enqueue_invoice_communication_email and enqueue_quote_communication_email so the billing contact could get
-- its own link. `CREATE OR REPLACE FUNCTION` only replaces a function whose argument list is unchanged in
-- count and type; adding parameters instead creates a second, overloaded function and leaves the original
-- six-argument one in place untouched (confirmed against pg_proc: both the six- and eight-argument versions
-- existed after that migration ran). The six-argument one never learned about the billing contact, so any
-- caller that still resolves to it would silently skip the second recipient. Every caller in this codebase
-- already passes all eight arguments, so the old overload is dead weight; dropping it also removes the
-- ambiguity of two functions sharing one name.
drop function if exists "public"."enqueue_invoice_communication_email"(
  "target_organization_id" "uuid", "target_actor_user_id" "uuid", "target_invoice_id" "uuid",
  "target_logical_send_key" "text", "target_invoice_url" "text", "target_invoice_token_hash" "bytea"
);

drop function if exists "public"."enqueue_quote_communication_email"(
  "target_organization_id" "uuid", "target_actor_user_id" "uuid", "target_quote_id" "uuid",
  "target_logical_send_key" "text", "target_quote_url" "text", "target_quote_token_hash" "bytea"
);
