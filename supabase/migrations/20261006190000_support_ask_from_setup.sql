-- Client onboarding D6: Ask Uplift from a setup section.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §4 and §7 ("screen/section context").
-- Industry reference: Intercom and Zendesk messengers record the page a conversation was started from and show
-- it to the support agent beside the conversation. Here the "page" is a setup section: a chat started from Ask
-- Uplift keeps that section's key, and Uplift's inbox shows which section the question came from.
--
-- 1. support_threads gains `context_section`: the setup section the chat was asked from, or null. The list of
--    sections lives in the app (src/lib/setup/catalogue.ts) and grows without database changes, so the
--    database checks only its shape; the route checks it is a real section.
-- 2. public.start_support_thread takes the section as a new last argument, defaulting to none. Everything
--    else is unchanged from 20261006170000.

-- 1. Where the chat was asked from -------------------------------------------------------------------------

alter table public.support_threads
  add column context_section text,
  add constraint support_threads_context_section_check check (
    context_section ~ '^[a-z][a-z0-9_]{0,39}$'
  );

comment on column public.support_threads.context_section is
  'The setup section the chat was started from with Ask Uplift (a key from src/lib/setup/catalogue.ts), or null. Set once, when the chat starts.';

-- 2. Starting a chat, with or without a section ------------------------------------------------------------

drop function public.start_support_thread(uuid, text, text, uuid, jsonb);

create function public.start_support_thread(
  target_organization_id uuid,
  thread_topic text,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb,
  thread_context_section text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  clean_body text := btrim(coalesce(message_body, ''));
  clean_topic text := coalesce(nullif(btrim(thread_topic), ''), 'other');
  clean_context text := nullif(btrim(coalesce(thread_context_section, '')), '');
  file_count smallint;
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if actor_id is null or not private.is_support_member(target_organization_id) then
    raise exception 'Only an active team member can message Uplift.'
      using errcode = 'insufficient_privilege';
  end if;

  file_count := private.check_support_attachments(target_organization_id, message_attachments);

  if char_length(clean_body) > 4000 then
    raise exception 'A message can have up to 4000 characters.' using errcode = 'check_violation';
  end if;

  if clean_body = '' and file_count = 0 then
    raise exception 'Write a message or attach a file first.' using errcode = 'check_violation';
  end if;

  if message_client_id is null then
    raise exception 'The message is missing its identifier.' using errcode = 'check_violation';
  end if;

  if clean_topic not in ('setup', 'website', 'google_profile', 'crm', 'billing', 'other') then
    raise exception 'Choose one of the listed topics.' using errcode = 'check_violation';
  end if;

  if clean_context is not null and clean_context !~ '^[a-z][a-z0-9_]{0,39}$' then
    raise exception 'That setup section is not recognised.' using errcode = 'check_violation';
  end if;

  -- Two attempts of the same first message, arriving together, take turns here; the second then finds the
  -- chat the first one made.
  perform pg_advisory_xact_lock(hashtextextended('support-start:' || actor_id::text, 0));

  select * into message_row
  from public.support_messages
  where sender_user_id = actor_id
    and client_message_id = message_client_id
    and organization_id = target_organization_id;

  if message_row.id is not null then
    return private.support_message_json(message_row);
  end if;

  insert into public.support_threads (organization_id, started_by_user_id, topic, context_section)
  values (target_organization_id, actor_id, clean_topic, clean_context)
  returning id into thread_id_value;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_user_id, sender_name, body, client_message_id,
    attachment_count
  )
  values (
    thread_id_value, target_organization_id, 'member', actor_id, private.support_member_name(actor_id),
    clean_body, message_client_id, file_count
  )
  returning * into message_row;

  perform private.add_support_attachments(message_row, message_attachments);

  return private.support_message_json(message_row);
end;
$$;

revoke all on function public.start_support_thread(uuid, text, text, uuid, jsonb, text) from public, anon;
grant execute on function public.start_support_thread(uuid, text, text, uuid, jsonb, text)
  to authenticated, service_role;
