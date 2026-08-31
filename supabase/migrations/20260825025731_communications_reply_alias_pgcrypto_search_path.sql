-- gen_random_bytes() lives in the 'extensions' schema in this project (pgcrypto is installed there,
-- not in public), so the function's search_path must include it -- the create-or-replace at
-- 20260825120000_communications_reply_alias_foundation.sql was missing it and would fail on first call.
create or replace function public.ensure_communication_reply_alias(
  target_organization_id uuid,
  target_sender_id uuid,
  target_client_id uuid,
  target_contact_method_id uuid
) returns public.communication_reply_aliases
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  alias public.communication_reply_aliases;
  receiving_domain public.communication_email_domains;
begin
  update public.communication_reply_aliases
    set last_activity_at = now(), expires_at = now() + interval '90 days', updated_at = now()
    where organization_id = target_organization_id and sender_id = target_sender_id
      and client_id = target_client_id and client_contact_method_id = target_contact_method_id
    returning * into alias;
  if alias.id is not null then
    return alias;
  end if;

  select * into receiving_domain from public.communication_email_domains
  where organization_id = target_organization_id and purpose = 'receiving' and lifecycle_state = 'verified'
  order by created_at
  limit 1;
  if receiving_domain.id is null then
    return null;
  end if;

  loop
    begin
      insert into public.communication_reply_aliases (
        organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id, alias_local_part
      ) values (
        target_organization_id, receiving_domain.id, target_sender_id, target_client_id, target_contact_method_id,
        encode(gen_random_bytes(16), 'hex')
      ) returning * into alias;
      exit;
    exception when unique_violation then
      select * into alias from public.communication_reply_aliases
        where organization_id = target_organization_id and sender_id = target_sender_id
          and client_id = target_client_id and client_contact_method_id = target_contact_method_id;
      if alias.id is not null then exit; end if;
    end;
  end loop;

  return alias;
end;
$$;

revoke all on function public.ensure_communication_reply_alias(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.ensure_communication_reply_alias(uuid, uuid, uuid, uuid) to service_role;
