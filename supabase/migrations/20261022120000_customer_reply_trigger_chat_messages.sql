-- Website chat messages could not be saved: the shared "customer replied" trigger read
-- `new.in_reply_to_intent_id`, a column only `communication_inbound_messages` has. PL/pgSQL does not
-- short-circuit `tg_table_name = ... and new.<column>`, so the field lookup ran for chat rows too and
-- every visitor message failed with 42703. The reply-to link is now read from the row as JSON, which
-- simply yields null on a table without that column.
create or replace function private.opportunity_record_customer_reply()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  replied_intent_id uuid;
  replied_quote_id uuid;
begin
  if tg_table_name = 'communication_inbound_messages' then
    replied_intent_id := (to_jsonb(new) ->> 'in_reply_to_intent_id')::uuid;
  end if;

  if replied_intent_id is not null then
    select intent.quote_id into replied_quote_id
    from public.communication_delivery_intents as intent
    where intent.id = replied_intent_id
      and intent.organization_id = new.organization_id;

    if replied_quote_id is not null then
      update public.opportunities
      set progress_at = greatest(progress_at, new.created_at)
      where organization_id = new.organization_id
        and quote_id = replied_quote_id
        and client_id = new.client_id
        and outcome = 'open';

      if found then
        return null;
      end if;
    end if;
  end if;

  update public.opportunities
  set progress_at = greatest(progress_at, new.created_at)
  where organization_id = new.organization_id
    and client_id = new.client_id
    and outcome = 'open'
    and stage <> 'request_closed'
    and progress_at < new.created_at;

  return null;
end;
$$;

revoke all on function private.opportunity_record_customer_reply() from public, anon, authenticated;
