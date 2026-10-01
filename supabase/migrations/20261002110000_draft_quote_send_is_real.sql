-- Pipeline upgrade B3: dropping a Draft quote on Awaiting response really sends it.
--
-- Until now the drop ran `publish_quote` alone: the quote was frozen and marked as sent, the customer
-- received nothing, and the history said "Sent version N to the customer" with no word on how. The board
-- now asks first, and one of two commands does the move:
--
--   send_draft_quote_email      freezes the draft and queues the customer's email in ONE transaction. If the
--                               email cannot be queued (no customer email address, no sender ready), the
--                               freeze rolls back with it and the quote is still a Draft.
--   mark_quote_sent_externally  freezes the draft because a person says they sent it themselves, and
--                               records who, when, by which channel, and their optional note.
--
-- Both add their own history entry beside `quote.published`, so the quote's history says how it went out.
-- `publish_quote` itself is unchanged and still serves the Quote page.

-- The channels a person can name for a quote they sent themselves. One list, read by the command and by
-- its history line.
create or replace function private.quote_external_send_channel_label(send_channel text) returns text
    language sql immutable
    set search_path to 'pg_catalog'
    as $$
  select case send_channel
    when 'in_person' then 'In person'
    when 'phone' then 'Phone call'
    when 'text_message' then 'Text message'
    when 'own_email' then 'My own email'
    when 'printed' then 'Printed or posted copy'
    when 'other' then 'Other'
  end;
$$;

revoke all on function private.quote_external_send_channel_label(text) from public;

create or replace function public.mark_quote_sent_externally(
  target_quote_id uuid,
  expected_revision integer,
  send_channel text,
  send_note text default null
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
  channel_label text := private.quote_external_send_channel_label(send_channel);
  clean_note text := nullif(btrim(coalesce(send_note, '')), '');
  published jsonb;
  quote_organization_id uuid;
begin
  if channel_label is null then
    raise exception 'Choose how the quote was sent.' using errcode = 'check_violation';
  end if;
  if char_length(clean_note) > 500 then
    raise exception 'Keep the note to 500 characters or fewer.' using errcode = 'check_violation';
  end if;

  -- Checks the caller's `quotes.send`, the draft's revision, its lines and its tax, exactly as the Quote
  -- page's own action does. A repeat of a send that already landed comes back `already_published` and
  -- writes nothing more, so a retried request never doubles the history.
  published := public.publish_quote(target_quote_id, expected_revision);
  if (published ->> 'already_published')::boolean then
    return published;
  end if;

  select organization_id into quote_organization_id from public.quotes where id = target_quote_id;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_organization_id, 'quote', target_quote_id, 'quote.sent_externally',
    'Marked version ' || (published ->> 'version_number') || ' as sent outside UCRM: ' || channel_label
      || coalesce(' - ' || left(clean_note, 180), ''),
    (select auth.uid()),
    jsonb_build_object(
      'quote_version_id', published ->> 'quote_version_id',
      'version_number', (published ->> 'version_number')::integer,
      'channel', send_channel,
      'note', clean_note
    )
  );

  return published || jsonb_build_object('send_method', 'external', 'send_channel', send_channel);
end;
$$;

alter function public.mark_quote_sent_externally(uuid, integer, text, text) owner to postgres;
revoke all on function public.mark_quote_sent_externally(uuid, integer, text, text) from public;
grant all on function public.mark_quote_sent_externally(uuid, integer, text, text) to authenticated;
grant all on function public.mark_quote_sent_externally(uuid, integer, text, text) to service_role;

comment on function public.mark_quote_sent_externally(uuid, integer, text, text) is
  'Pipeline B3. Publishes a draft quote because a person sent it to the customer themselves, and records who, when, the channel, and an optional note in the quote history.';

-- The customer link in a quote email is made by the application server, so the email command is callable
-- by the service role only and is told who is acting. `publish_quote`, and the pipeline triggers that
-- record who moved the card, all read the acting member from the request identity. For the length of this
-- one transaction that identity is set to the acting member — whose `quotes.send` and
-- `conversations.send` are then checked by the two commands themselves — so the freeze and the email
-- share a single transaction and a single actor, and neither can land without the other.
create or replace function public.send_draft_quote_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_quote_id uuid,
  expected_revision integer,
  target_logical_send_key text,
  target_quote_url text,
  target_quote_token_hash bytea,
  target_billing_quote_url text default null,
  target_billing_quote_token_hash bytea default null
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
  intent public.communication_delivery_intents;
  published jsonb;
  prior_claims text := current_setting('request.jwt.claims', true);
  prior_subject text := current_setting('request.jwt.claim.sub', true);
begin
  if target_actor_user_id is null or target_logical_send_key is null then
    raise exception 'You do not have access to send this quote.' using errcode = 'insufficient_privilege';
  end if;

  -- A retry of a send that already landed: hand back the same email rather than freeze or send again.
  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id
      and logical_send_key = target_logical_send_key || ':primary';
  if intent.id is not null then
    if intent.quote_id is distinct from target_quote_id then
      raise exception 'This email retry does not match the original quote.' using errcode = 'unique_violation';
    end if;
    return jsonb_build_object(
      'quote_id', target_quote_id, 'intent_id', intent.id, 'intent_status', intent.status,
      'recipient_email', intent.recipient_email, 'already_sent', true
    );
  end if;

  -- The same answer for a missing quote and another organization's quote: a stranger learns nothing.
  if not exists (
    select 1 from public.quotes where id = target_quote_id and organization_id = target_organization_id
  ) then
    raise exception 'You do not have access to send this quote.' using errcode = 'insufficient_privilege';
  end if;

  perform set_config('request.jwt.claim.sub', target_actor_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    (coalesce(nullif(prior_claims, '')::jsonb, '{}'::jsonb)
      || jsonb_build_object('sub', target_actor_user_id))::text,
    true
  );

  published := public.publish_quote(target_quote_id, expected_revision);

  -- Raises when the customer has no email address or the business has no sender ready. Nothing above is
  -- kept in that case: the quote is still a Draft.
  intent := public.enqueue_quote_communication_email(
    target_organization_id, target_actor_user_id, target_quote_id, target_logical_send_key,
    target_quote_url, target_quote_token_hash, target_billing_quote_url, target_billing_quote_token_hash
  );

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    target_organization_id, 'quote', target_quote_id, 'quote.emailed',
    'Emailed version ' || (published ->> 'version_number') || ' to ' || intent.recipient_email,
    target_actor_user_id,
    jsonb_build_object(
      'quote_version_id', published ->> 'quote_version_id',
      'version_number', (published ->> 'version_number')::integer,
      'delivery_intent_id', intent.id,
      'recipient_email', intent.recipient_email
    )
  );

  perform set_config('request.jwt.claim.sub', coalesce(prior_subject, ''), true);
  perform set_config('request.jwt.claims', coalesce(prior_claims, ''), true);

  return published || jsonb_build_object(
    'send_method', 'email', 'intent_id', intent.id, 'intent_status', intent.status,
    'recipient_email', intent.recipient_email, 'already_sent', false
  );
end;
$$;

alter function public.send_draft_quote_email(uuid, uuid, uuid, integer, text, text, bytea, text, bytea) owner to postgres;
revoke all on function public.send_draft_quote_email(uuid, uuid, uuid, integer, text, text, bytea, text, bytea) from public;
revoke all on function public.send_draft_quote_email(uuid, uuid, uuid, integer, text, text, bytea, text, bytea) from anon, authenticated;
grant all on function public.send_draft_quote_email(uuid, uuid, uuid, integer, text, text, bytea, text, bytea) to service_role;

comment on function public.send_draft_quote_email(uuid, uuid, uuid, integer, text, text, bytea, text, bytea) is
  'Pipeline B3. Publishes a draft quote and queues its customer email in one transaction, as the named acting member. Service role only, because the customer link is made by the application server. A send that cannot be queued leaves the quote a Draft.';
