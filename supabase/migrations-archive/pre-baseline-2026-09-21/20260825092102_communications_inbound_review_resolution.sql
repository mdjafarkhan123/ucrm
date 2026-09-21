-- Communications Part 5C-i: resolve a guarded ("Needs review") inbound conversation.
--
-- Part 4 parks an inbound email that could not be trusted onto a conversation at review_status
-- 'pending_review' (unknown_sender / ambiguous_sender / expired_alias). Until now that state was
-- display-only: nobody could act on it. This adds the two actions GHL exposes -- link the sender to an
-- existing contact, or dismiss it -- as one atomic command per sender address.
--
-- Scope is deliberately the whole guarded conversation, not one message: /communications groups guarded
-- messages by sender_email (one row per unknown sender, see src/lib/communications/inbox.ts), so the row
-- the operator acts on IS the set of that sender's pending messages. Resolving one and silently leaving
-- its siblings behind would contradict what the screen shows.
--
-- Dismissal is not deletion. The row survives with its original review_reason plus who resolved it and
-- when; permanent deletion stays its own permission with its own audit record
-- (docs/unified-inbox-behavior-contract.md § Inbox handling).

alter table public.communication_inbound_messages
  add column review_resolved_at timestamptz,
  add column review_resolved_by uuid references auth.users (id) on delete set null;

alter table public.communication_inbound_messages
  drop constraint communication_inbound_messages_review_status_check,
  add constraint communication_inbound_messages_review_status_check
    check (review_status in ('accepted', 'pending_review', 'dismissed'));

-- Replaces the original reason/status pairing so a resolved row can keep the reason it was flagged for.
-- An untouched accepted row carries neither; a linked one carries both (why it was held, who released it);
-- a pending one carries only the reason; a dismissed one always carries both.
alter table public.communication_inbound_messages
  drop constraint communication_inbound_messages_review_reason_matches_status,
  add constraint communication_inbound_messages_review_reason_matches_status check (
    (review_status = 'accepted' and review_reason is null and review_resolved_at is null)
    or (review_status = 'accepted' and review_reason is not null and review_resolved_at is not null)
    or (review_status = 'pending_review' and review_reason is not null and review_resolved_at is null)
    or (review_status = 'dismissed' and review_reason is not null and review_resolved_at is not null)
  );

create or replace function public.resolve_inbound_message_review(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_sender_email text,
  target_resolution text,
  target_client_id uuid default null
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  pending_ids uuid[];
  linked_client_id uuid;
  contact_method public.client_contact_methods;
  fallback_sender_id uuid;
  needs_fallback_sender boolean;
  resolved_count integer;
begin
  if target_resolution not in ('link', 'dismiss') then
    raise exception 'Unknown review resolution.' using errcode = 'invalid_parameter_value';
  end if;

  -- "Assign and manage conversations" is the contract's manage-conversations capability; linking also
  -- reads and writes contact data, so it additionally requires customer access.
  if not private.member_has_permission(
    target_organization_id, target_actor_user_id, 'conversations.manage_assignment'
  ) then
    raise exception 'You do not have permission to manage conversations.' using errcode = 'insufficient_privilege';
  end if;

  if target_resolution = 'link'
    and not private.member_has_permission(target_organization_id, target_actor_user_id, 'customers.view') then
    raise exception 'You do not have permission to manage conversations.' using errcode = 'insufficient_privilege';
  end if;

  -- Locked up front so two operators resolving the same guarded row cannot each apply a different outcome.
  -- The lock lives in the subquery because Postgres rejects FOR UPDATE alongside an aggregate.
  select array_agg(locked.id) into pending_ids
  from (
    select message.id
    from public.communication_inbound_messages message
    where message.organization_id = target_organization_id
      and lower(message.sender_email) = lower(btrim(target_sender_email))
      and message.review_status = 'pending_review'
    for update
  ) locked;

  if pending_ids is null then
    raise exception 'This conversation no longer needs review.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if target_resolution = 'dismiss' then
    update public.communication_inbound_messages
    set review_status = 'dismissed',
        review_resolved_at = now(),
        review_resolved_by = target_actor_user_id,
        updated_at = now()
    where id = any(pending_ids);

    get diagnostics resolved_count = row_count;
    return resolved_count;
  end if;

  if target_client_id is null then
    raise exception 'Choose a client to link this conversation to.' using errcode = 'invalid_parameter_value';
  end if;

  select client.id into linked_client_id
  from public.clients client
  where client.organization_id = target_organization_id
    and client.id = target_client_id
    and client.deleted_at is null
  for share of client;

  if linked_client_id is null then
    raise exception 'That client is not available.' using errcode = 'foreign_key_violation';
  end if;

  -- An unknown sender is unknown precisely because its address is on no client yet, so linking records
  -- the address on the chosen client as an additional (never primary) email. Approved by Jafar 2026-08-25.
  select method.* into contact_method
  from public.client_contact_methods method
  where method.organization_id = target_organization_id
    and method.client_id = target_client_id
    and method.kind = 'email'
    and method.normalized_value = lower(btrim(target_sender_email));

  if contact_method.id is null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, label, is_primary)
    values (
      target_organization_id, target_client_id, 'email', lower(btrim(target_sender_email)),
      'From Conversations', false
    )
    returning * into contact_method;
  end if;

  -- Every resolved row needs a sender identity (the resolution-complete constraint). A message held for an
  -- expired or ambiguous alias already knows which sending address the thread belongs to; a truly unknown
  -- sender does not, and falls back to the organization's default sending address.
  select exists (
    select 1
    from public.communication_inbound_messages message
    left join public.communication_reply_aliases alias on alias.id = message.reply_alias_id
    where message.id = any(pending_ids) and alias.sender_id is null
  ) into needs_fallback_sender;

  if needs_fallback_sender then
    select email_sender.id into fallback_sender_id
    from public.communication_email_senders email_sender
    where email_sender.organization_id = target_organization_id
      and email_sender.lifecycle_state = 'enabled'
    order by email_sender.is_organization_default desc, email_sender.created_at, email_sender.id
    limit 1;

    if fallback_sender_id is null then
      raise exception 'This organization has no active sending address to link the conversation to.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  end if;

  update public.communication_inbound_messages message
  set client_id = target_client_id,
      client_contact_method_id = contact_method.id,
      sender_id = coalesce(
        (
          select alias.sender_id from public.communication_reply_aliases alias
          where alias.id = message.reply_alias_id
        ),
        fallback_sender_id
      ),
      review_status = 'accepted',
      review_resolved_at = now(),
      review_resolved_by = target_actor_user_id,
      updated_at = now()
  where message.id = any(pending_ids);

  get diagnostics resolved_count = row_count;
  return resolved_count;
end;
$$;

revoke all on function public.resolve_inbound_message_review(uuid, uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_inbound_message_review(uuid, uuid, text, text, uuid)
  to service_role;
