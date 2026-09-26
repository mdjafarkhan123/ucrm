-- Google review campaign Part 3 fix: create_review_request's "was this send already made?" lookup named its
-- table alias `intent`, the same name as the function's own `intent` variable, so every call failed with
-- 42702 "column reference intent.id is ambiguous" before creating anything. The alias is renamed.

do $$
declare
  create_def text := pg_get_functiondef('public.create_review_request(uuid, uuid, uuid, uuid, text, uuid, text, text, text, text, bytea, timestamptz, text)'::regprocedure);
  old_lookup text := $old$  join public.communication_delivery_intents as intent on intent.id = request.delivery_intent_id
  where intent.organization_id = p_organization_id and intent.logical_send_key = send_key;$old$;
  new_lookup text := $new$  join public.communication_delivery_intents as sent_intent on sent_intent.id = request.delivery_intent_id
  where sent_intent.organization_id = p_organization_id and sent_intent.logical_send_key = send_key;$new$;
begin
  if position(old_lookup in create_def) = 0 then
    raise exception 'review request retry lookup not found; the function changed since this migration was written';
  end if;
  execute replace(create_def, old_lookup, new_lookup);
end;
$$;
