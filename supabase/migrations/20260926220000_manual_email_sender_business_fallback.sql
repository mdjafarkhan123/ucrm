-- Operational email Part 5: a hand-sent message must never fail because nobody assigned the staff member a
-- personal sending address. Approved 2026-09-26 in docs/contractor-email-contract.md, section "Request
-- lifecycle and sender fallback", following Jobber: Jobber sends every message from an address the business
-- always has, and the contractor only chooses where replies return (default "whoever sent it", falling back to
-- a named team member or the company email address). Before this migration the three manual enqueue functions
-- demanded a sender whose assigned_user_id equalled the actor and otherwise raised, so a newly invited team
-- member's first reply refused with no way to self-diagnose.
--
-- The fallback order is the actor's own manual sender, then the business default, then the business's oldest
-- usable shared address. Only an organization with no usable manual sender at all still refuses, because there
-- is genuinely nothing to send from; that refusal now names Settings -> Email, which Part 5 turns into the
-- request-setup screen. Sending from the business address is visible to the customer as the business display
-- name; the per-conversation reply alias is unchanged, so the customer's reply still returns to the same
-- Conversation and the staff member still sees the answer.

-- The address this actor should send a hand-written message from, ready to send right now, or null.
-- A sender assigned to a team member who is no longer active is skipped, because the claim function fails such
-- an intent at submission time; the actor's own sender is exempt since the caller already checked permission.
create or replace function private.resolve_manual_email_sender(
  p_organization_id uuid,
  p_actor_user_id uuid
)
returns public.communication_email_senders
language sql
security definer
set search_path = pg_catalog, public
as $$
  select email_sender.*
  from public.communication_email_senders as email_sender
  join public.communication_email_domains as domain
    on domain.organization_id = email_sender.organization_id and domain.id = email_sender.domain_id
  where email_sender.organization_id = p_organization_id
    and email_sender.lifecycle_state = 'enabled'
    and email_sender.allows_manual
    and (
      email_sender.assigned_user_id is null
      or email_sender.assigned_user_id = p_actor_user_id
      or exists (
        select 1
        from public.organization_members as member
        where member.organization_id = email_sender.organization_id
          and member.user_id = email_sender.assigned_user_id
          and member.status = 'active'
      )
    )
    and domain.purpose = 'sending' and domain.lifecycle_state = 'verified'
    and domain.provider_verified and domain.provider_authenticated
    and domain.ownership_status = 'passing' and domain.dkim_status = 'passing'
  order by
    coalesce(email_sender.assigned_user_id = p_actor_user_id, false) desc,
    email_sender.is_organization_default desc,
    email_sender.assigned_user_id is not null,
    email_sender.created_at,
    email_sender.id
  limit 1
  for share of email_sender, domain;
$$;

revoke all on function private.resolve_manual_email_sender(uuid, uuid) from public, anon, authenticated;

-- Patched in place, as 20260926091000 did for the review-request sender: the surrounding bodies are long and
-- unrelated, and the guard fails loudly if either block has moved since this migration was written.
do $$
declare
  patched_signatures text[] := array[
    'public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text, jsonb, timestamptz)',
    'public.enqueue_inbound_message_forward(uuid, uuid, uuid, text, text[], text, text, text, uuid[])',
    'public.enqueue_manual_communication_email(uuid, uuid, uuid, uuid, text, text, text, text, jsonb)'
  ];
  signature text;
  definition text;
  old_select text := $old$  select email_sender.* into sender
  from public.communication_email_senders email_sender
  where email_sender.organization_id = target_organization_id
    and email_sender.assigned_user_id = target_actor_user_id
    and email_sender.lifecycle_state = 'enabled'
    and email_sender.allows_manual
  order by email_sender.is_organization_default desc, email_sender.created_at, email_sender.id
  limit 1
  for share of email_sender;$old$;
  new_select text := $new$  sender := private.resolve_manual_email_sender(target_organization_id, target_actor_user_id);$new$;
  old_raise text := $old$'Your assigned email sender is not ready. Ask an administrator to review it.'$old$;
  new_raise text := $new$'Your business has no email address ready to send from. Set up business email in Settings -> Email.'$new$;
begin
  foreach signature in array patched_signatures loop
    definition := pg_get_functiondef(signature::regprocedure);

    if position(old_select in definition) = 0 or position(old_raise in definition) = 0 then
      raise exception 'manual sender block not found in %; the function changed since this migration was written',
        signature;
    end if;

    execute replace(replace(definition, old_select, new_select), old_raise, new_raise);
  end loop;
end;
$$;
