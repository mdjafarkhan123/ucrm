-- Communications Part 3: Quotes are the first system-owned operational-email source.
alter table public.communication_delivery_intents add column quote_id uuid;
alter table public.communication_delivery_intents add constraint communication_delivery_intents_quote_fk
  foreign key (organization_id, quote_id) references public.quotes(organization_id, id) on delete restrict;
create index communication_delivery_intents_quote_created_idx
  on public.communication_delivery_intents (organization_id, quote_id, created_at desc, id desc)
  where quote_id is not null;

create or replace function public.enqueue_quote_communication_email(
  target_organization_id uuid, target_actor_user_id uuid, target_quote_id uuid,
  target_logical_send_key text, target_quote_url text, target_quote_token_hash bytea
) returns public.communication_delivery_intents
language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare
  quote_row public.quotes; version_row public.quote_versions; client_row public.clients;
  recipient public.client_contact_methods; quote_recipient public.quote_recipients;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'quotes.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send this quote by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_quote_url !~ '^https?://[^[:space:]]+$' or target_quote_token_hash is null
    or octet_length(target_quote_token_hash) <> 32 then
    raise exception 'The quote delivery link is not available.' using errcode = 'check_violation';
  end if;
  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = target_logical_send_key for share;
  if intent.id is not null then
    if intent.quote_id is distinct from target_quote_id then
      raise exception 'This email retry does not match the original quote.' using errcode = 'unique_violation';
    end if;
    return intent;
  end if;
  select * into quote_row from public.quotes
    where organization_id = target_organization_id and id = target_quote_id
      and status in ('awaiting_response', 'changes_requested', 'approved') and archived_at is null for share;
  if quote_row.id is null then raise exception 'This quote is not available to send.' using errcode = 'foreign_key_violation'; end if;
  select * into version_row from public.quote_versions
    where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
      and quote_id = quote_row.id and status = 'published' for share;
  select * into client_row from public.clients
    where organization_id = quote_row.organization_id and id = quote_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = quote_row.organization_id and client_id = quote_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if version_row.id is null or client_row.id is null or recipient.id is null then
    raise exception 'This quote needs an active customer email address before it can be sent.' using errcode = 'object_not_in_prerequisite_state';
  end if;
  select * into sender from public.communication_email_senders
    where organization_id = quote_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and (assigned_user_id = client_row.owner_user_id or is_organization_default)
    order by (assigned_user_id = client_row.owner_user_id) desc, is_organization_default desc, created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    raise exception 'No automated email sender is ready for this business.' using errcode = 'object_not_in_prerequisite_state';
  end if;
  insert into public.quote_recipients (organization_id, quote_id, display_name, email, created_by)
    values (quote_row.organization_id, quote_row.id, coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value, target_actor_user_id)
    on conflict (organization_id, quote_id, email) do update set display_name = excluded.display_name returning * into quote_recipient;
  update public.quote_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = quote_row.organization_id and quote_id = quote_row.id and recipient_id = quote_recipient.id and revoked_at is null;
  insert into public.quote_access_links (organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by)
    values (quote_row.organization_id, quote_row.id, version_row.id, quote_recipient.id, target_quote_token_hash, target_actor_user_id);
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, quote_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
    values (quote_row.organization_id, quote_row.client_id, recipient.id, quote_row.id, target_logical_send_key, recipient.normalized_value,
      'Your quote from ' || version_row.organization_name,
      '<p>Your quote is ready to review.</p><p><a href="' || replace(target_quote_url, '&', '&amp;') || '">View your quote</a></p>',
      'Your quote is ready to review. View it here: ' || target_quote_url, 'automated', 'essential', sender.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);
  return intent;
end;
$$;
revoke all on function public.enqueue_quote_communication_email(uuid, uuid, uuid, text, text, bytea) from public, anon, authenticated;
grant execute on function public.enqueue_quote_communication_email(uuid, uuid, uuid, text, text, bytea) to service_role;
