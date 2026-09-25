-- Google review campaign Part 3 fix: a manual review request is a hand-sent message, so its email goes from
-- the business's default sender when that sender allows manual sending (as enqueue_manual_communication_email
-- requires allows_manual). The automation (Part 4) will ask for allows_automated instead. The previous
-- migration demanded allows_automated, which refused a business whose default address is manual-only.

-- The business's default sending address for a request of this origin, ready to send right now, or null.
create or replace function private.review_request_email_sender(p_organization_id uuid, p_origin text)
returns public.communication_email_senders
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select email_sender.*
  from public.communication_email_senders as email_sender
  join public.communication_email_domains as domain
    on domain.organization_id = email_sender.organization_id and domain.id = email_sender.domain_id
  where email_sender.organization_id = p_organization_id
    and email_sender.lifecycle_state = 'enabled'
    and email_sender.is_organization_default
    and case when p_origin = 'automation' then email_sender.allows_automated else email_sender.allows_manual end
    and domain.purpose = 'sending' and domain.lifecycle_state = 'verified'
    and domain.provider_verified and domain.provider_authenticated
    and domain.ownership_status = 'passing' and domain.dkim_status = 'passing'
  order by email_sender.created_at, email_sender.id
  limit 1;
$$;

revoke all on function private.review_request_email_sender(uuid, text) from public, anon, authenticated;

do $$
declare
  context_def text := pg_get_functiondef('public.get_review_request_context(uuid, uuid, uuid, uuid)'::regprocedure);
  create_def text := pg_get_functiondef('public.create_review_request(uuid, uuid, uuid, uuid, text, uuid, text, text, text, text, bytea, timestamptz, text)'::regprocedure);
  old_context text := $old$  select exists (
    select 1
    from public.communication_email_senders as sender
    join public.communication_email_domains as domain
      on domain.organization_id = sender.organization_id and domain.id = sender.domain_id
    where sender.organization_id = p_organization_id
      and sender.lifecycle_state = 'enabled' and sender.allows_automated and sender.is_organization_default
      and domain.purpose = 'sending' and domain.lifecycle_state = 'verified'
      and domain.provider_verified and domain.provider_authenticated
      and domain.ownership_status = 'passing' and domain.dkim_status = 'passing'
  ) into email_ready;$old$;
  new_context text := $new$  email_ready := (private.review_request_email_sender(p_organization_id, 'manual')).id is not null;$new$;
  old_create text := $old$    select email_sender.* into sender
    from public.communication_email_senders as email_sender
    join public.communication_email_domains as domain
      on domain.organization_id = email_sender.organization_id and domain.id = email_sender.domain_id
    where email_sender.organization_id = p_organization_id
      and email_sender.lifecycle_state = 'enabled' and email_sender.allows_automated
      and email_sender.is_organization_default
      and domain.purpose = 'sending' and domain.lifecycle_state = 'verified'
      and domain.provider_verified and domain.provider_authenticated
      and domain.ownership_status = 'passing' and domain.dkim_status = 'passing'
    order by email_sender.created_at, email_sender.id
    limit 1
    for share of email_sender, domain;$old$;
  new_create text := $new$    sender := private.review_request_email_sender(p_organization_id, 'manual');$new$;
begin
  if position(old_context in context_def) = 0 or position(old_create in create_def) = 0 then
    raise exception 'review request sender block not found; the functions changed since this migration was written';
  end if;
  execute replace(context_def, old_context, new_context);
  execute replace(create_def, old_create, new_create);
end;
$$;
