-- Pipeline B7 follow-up: one send, one history line.
--
-- Sending a Draft quote wrote two history entries: `publish_quote`'s general "Sent version N to the
-- customer", then the send command's own "Emailed version N to ..." or "Marked version N as sent outside
-- UCRM: Phone call". For a quote the contractor phoned through, the first wrongly reads as if UCRM sent
-- it. Each send command now replaces that general entry with its own, in the same transaction. Nothing
-- reads `quote.published` entries except the history list itself.
--
-- `publish_quote` is unchanged: on its own (no caller in the app since B7) it still records its entry.
-- Both functions below are the B3 versions with only the marked delete added; grants and owners carry over.

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

  -- One send, one history line: the general entry `publish_quote` just wrote gives way to this one,
  -- which says how the quote went out.
  delete from public.activity_events
  where organization_id = quote_organization_id and entity_type = 'quote' and entity_id = target_quote_id
    and event_type = 'quote.published'
    and metadata ->> 'quote_version_id' = published ->> 'quote_version_id';

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

  -- One send, one history line: the general entry `publish_quote` just wrote gives way to this one,
  -- which says how the quote went out.
  delete from public.activity_events
  where organization_id = target_organization_id and entity_type = 'quote' and entity_id = target_quote_id
    and event_type = 'quote.published'
    and metadata ->> 'quote_version_id' = published ->> 'quote_version_id';

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

-- Existing quotes sent through either command carry both entries; keep only the one that says how.
delete from public.activity_events published
where published.entity_type = 'quote'
  and published.event_type = 'quote.published'
  and exists (
    select 1 from public.activity_events specific
    where specific.organization_id = published.organization_id
      and specific.entity_type = 'quote'
      and specific.entity_id = published.entity_id
      and specific.event_type in ('quote.emailed', 'quote.sent_externally')
      and specific.metadata ->> 'quote_version_id' = published.metadata ->> 'quote_version_id'
  );
