-- Deferred sweep Part 5: invoice and quote emails now also reach a client's separate billing-contact
-- email, matching Jobber's documented "primary starred email + billing contact" batch-mailer behavior
-- (deferred 2026-09-06 as a known Jobber gap; Jafar approved building it 2026-09-28). The billing contact
-- is a second flagged row on client_contact_methods (kind='email'), one per client, distinct from the
-- primary email. Both single-send functions gain the second recipient; batch deliver calls the same
-- invoice function, so it inherits this for free.

alter table public.client_contact_methods
  add column if not exists is_billing_contact boolean not null default false;

alter table public.client_contact_methods
  add constraint client_contact_methods_billing_kind_check
  check (not is_billing_contact or kind = 'email');

alter table public.client_contact_methods
  add constraint client_contact_methods_billing_not_primary_check
  check (not (is_primary and is_billing_contact));

create unique index client_contact_methods_billing_unique_idx
  on public.client_contact_methods (client_id)
  where is_billing_contact;

-- create_client: an optional billing-contact email alongside the primary one.
CREATE OR REPLACE FUNCTION "public"."create_client"("payload" "jsonb") RETURNS "public"."clients"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  created_client public.clients;
  new_property_id uuid;
  new_note_id uuid;
  email_value text := nullif(trim(payload->>'email'), '');
  billing_email_value text := nullif(trim(payload->>'billing_email'), '');
  phone_value text := nullif(trim(payload->>'phone'), '');
  property_payload jsonb := payload->'property';
  initial_note_value text := nullif(trim(payload->>'initial_note'), '');
  preferences jsonb := payload->'preferences';
  tag_ids jsonb := payload->'tag_ids';
begin
  insert into public.clients (
    organization_id,
    display_name,
    client_type,
    first_name,
    last_name,
    company_name,
    lifecycle_status,
    lead_source,
    lead_temperature,
    next_follow_up_at
  )
  values (
    (payload->>'organization_id')::uuid,
    payload->>'display_name',
    coalesce(nullif(payload->>'client_type', ''), 'person'),
    nullif(trim(payload->>'first_name'), ''),
    nullif(trim(payload->>'last_name'), ''),
    nullif(trim(payload->>'company_name'), ''),
    coalesce(nullif(payload->>'lifecycle_status', ''), 'lead'),
    nullif(trim(payload->>'lead_source'), ''),
    nullif(payload->>'lead_temperature', ''),
    nullif(payload->>'next_follow_up_at', '')::timestamptz
  )
  returning * into created_client;

  if email_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'email', email_value, true);
  end if;

  if billing_email_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_billing_contact)
    values (created_client.organization_id, created_client.id, 'email', billing_email_value, true);
  end if;

  if phone_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'phone', phone_value, true);
  end if;

  if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
    insert into public.properties (
      organization_id,
      client_id,
      label,
      address_line1,
      address_line2,
      city,
      state_region,
      postal_code,
      country,
      access_notes,
      is_billing_address
    )
    values (
      created_client.organization_id,
      created_client.id,
      coalesce(nullif(trim(property_payload->>'label'), ''), 'Primary property'),
      property_payload->>'address_line1',
      nullif(trim(property_payload->>'address_line2'), ''),
      property_payload->>'city',
      nullif(trim(property_payload->>'state_region'), ''),
      nullif(trim(property_payload->>'postal_code'), ''),
      coalesce(nullif(property_payload->>'country', ''), 'US'),
      nullif(trim(property_payload->>'access_notes'), ''),
      coalesce((property_payload->>'is_billing_address')::boolean, false)
    )
    returning id into new_property_id;
  end if;

  if initial_note_value is not null then
    insert into public.notes (organization_id, body, created_by)
    values (created_client.organization_id, initial_note_value, (select auth.uid()))
    returning id into new_note_id;

    insert into public.note_links (organization_id, note_id, entity_type, entity_id)
    values (created_client.organization_id, new_note_id, 'client', created_client.id);
  end if;

  -- The preference row already exists: an after-insert trigger creates it for every client.
  if preferences is not null and jsonb_typeof(preferences) = 'object' then
    update public.client_communication_preferences as saved
    set
      appointment_reminders = coalesce((preferences->>'appointment_reminders')::boolean, saved.appointment_reminders),
      quote_follow_ups = coalesce((preferences->>'quote_follow_ups')::boolean, saved.quote_follow_ups),
      invoice_reminders = coalesce((preferences->>'invoice_reminders')::boolean, saved.invoice_reminders),
      job_follow_ups = coalesce((preferences->>'job_follow_ups')::boolean, saved.job_follow_ups),
      review_requests = coalesce((preferences->>'review_requests')::boolean, saved.review_requests),
      contact_policy = coalesce(nullif(preferences->>'contact_policy', ''), saved.contact_policy)
    where saved.organization_id = created_client.organization_id
      and saved.client_id = created_client.id;
  end if;

  -- The tag has to belong to this organization; the composite foreign key enforces that.
  if tag_ids is not null and jsonb_typeof(tag_ids) = 'array' then
    insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id, created_by)
    select
      created_client.organization_id,
      chosen.value::uuid,
      'client',
      created_client.id,
      (select auth.uid())
    from jsonb_array_elements_text(tag_ids) as chosen(value)
    on conflict (tag_id, entity_type, entity_id) do nothing;
  end if;

  return created_client;
end;
$$;

-- update_client: the billing-contact email is kept in step with primary email/phone -- present in the
-- payload means create-or-update the one billing row, absent means clear it.
CREATE OR REPLACE FUNCTION "public"."update_client"("payload" "jsonb") RETURNS "public"."clients"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  target_organization_id uuid := (payload->>'organization_id')::uuid;
  target_client_id uuid := (payload->>'id')::uuid;
  updated_client public.clients;
  email_value text := nullif(trim(payload->>'email'), '');
  billing_email_value text := nullif(trim(payload->>'billing_email'), '');
  phone_value text := nullif(trim(payload->>'phone'), '');
  property_payload jsonb := payload->'property';
  preferences jsonb := payload->'preferences';
  tag_ids jsonb := payload->'tag_ids';
  existing_email_id uuid;
  existing_billing_id uuid;
  existing_phone_id uuid;
  existing_property_id uuid;
begin
  update public.clients as target
  set
    display_name = payload->>'display_name',
    client_type = coalesce(nullif(payload->>'client_type', ''), target.client_type),
    first_name = nullif(trim(payload->>'first_name'), ''),
    last_name = nullif(trim(payload->>'last_name'), ''),
    company_name = nullif(trim(payload->>'company_name'), ''),
    lifecycle_status = coalesce(nullif(payload->>'lifecycle_status', ''), target.lifecycle_status),
    lead_source = nullif(trim(payload->>'lead_source'), ''),
    lead_temperature = nullif(payload->>'lead_temperature', ''),
    next_follow_up_at = nullif(payload->>'next_follow_up_at', '')::timestamptz
  where target.id = target_client_id
    and target.organization_id = target_organization_id
    and target.deleted_at is null
  returning target.* into updated_client;

  if updated_client.id is null then
    raise exception 'That client could not be found.' using errcode = 'P0002';
  end if;

  select id into existing_email_id
  from public.client_contact_methods
  where organization_id = target_organization_id
    and client_id = target_client_id
    and kind = 'email'
    and is_primary;

  if email_value is null then
    delete from public.client_contact_methods where id = existing_email_id;
  elsif existing_email_id is null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (target_organization_id, target_client_id, 'email', email_value, true);
  else
    update public.client_contact_methods set value = email_value where id = existing_email_id;
  end if;

  select id into existing_billing_id
  from public.client_contact_methods
  where organization_id = target_organization_id
    and client_id = target_client_id
    and kind = 'email'
    and is_billing_contact;

  if billing_email_value is null then
    delete from public.client_contact_methods where id = existing_billing_id;
  elsif existing_billing_id is null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_billing_contact)
    values (target_organization_id, target_client_id, 'email', billing_email_value, true);
  else
    update public.client_contact_methods set value = billing_email_value where id = existing_billing_id;
  end if;

  select id into existing_phone_id
  from public.client_contact_methods
  where organization_id = target_organization_id
    and client_id = target_client_id
    and kind = 'phone'
    and is_primary;

  if phone_value is null then
    delete from public.client_contact_methods where id = existing_phone_id;
  elsif existing_phone_id is null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (target_organization_id, target_client_id, 'phone', phone_value, true);
  else
    update public.client_contact_methods set value = phone_value where id = existing_phone_id;
  end if;

  if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
    select id into existing_property_id
    from public.properties
    where organization_id = target_organization_id
      and client_id = target_client_id
      and deleted_at is null
      and is_primary;

    if existing_property_id is null then
      insert into public.properties (
        organization_id,
        client_id,
        label,
        address_line1,
        address_line2,
        city,
        state_region,
        postal_code,
        country,
        access_notes,
        is_billing_address
      )
      values (
        target_organization_id,
        target_client_id,
        coalesce(nullif(trim(property_payload->>'label'), ''), 'Primary property'),
        property_payload->>'address_line1',
        nullif(trim(property_payload->>'address_line2'), ''),
        property_payload->>'city',
        nullif(trim(property_payload->>'state_region'), ''),
        nullif(trim(property_payload->>'postal_code'), ''),
        coalesce(nullif(property_payload->>'country', ''), 'US'),
        nullif(trim(property_payload->>'access_notes'), ''),
        coalesce((property_payload->>'is_billing_address')::boolean, false)
      );
    else
      update public.properties as existing
      set
        label = coalesce(nullif(trim(property_payload->>'label'), ''), existing.label),
        address_line1 = property_payload->>'address_line1',
        address_line2 = nullif(trim(property_payload->>'address_line2'), ''),
        city = property_payload->>'city',
        state_region = nullif(trim(property_payload->>'state_region'), ''),
        postal_code = nullif(trim(property_payload->>'postal_code'), ''),
        country = coalesce(nullif(property_payload->>'country', ''), existing.country),
        access_notes = nullif(trim(property_payload->>'access_notes'), ''),
        is_billing_address = coalesce(
          (property_payload->>'is_billing_address')::boolean,
          existing.is_billing_address
        )
      where existing.id = existing_property_id;
    end if;
  end if;

  if preferences is not null and jsonb_typeof(preferences) = 'object' then
    update public.client_communication_preferences as saved
    set
      appointment_reminders = coalesce((preferences->>'appointment_reminders')::boolean, saved.appointment_reminders),
      quote_follow_ups = coalesce((preferences->>'quote_follow_ups')::boolean, saved.quote_follow_ups),
      invoice_reminders = coalesce((preferences->>'invoice_reminders')::boolean, saved.invoice_reminders),
      job_follow_ups = coalesce((preferences->>'job_follow_ups')::boolean, saved.job_follow_ups),
      review_requests = coalesce((preferences->>'review_requests')::boolean, saved.review_requests),
      contact_policy = coalesce(nullif(preferences->>'contact_policy', ''), saved.contact_policy)
    where saved.organization_id = target_organization_id
      and saved.client_id = target_client_id;
  end if;

  if tag_ids is not null and jsonb_typeof(tag_ids) = 'array' then
    delete from public.tag_assignments as assigned
    where assigned.organization_id = target_organization_id
      and assigned.entity_type = 'client'
      and assigned.entity_id = target_client_id
      and assigned.tag_id not in (
        select chosen.value::uuid from jsonb_array_elements_text(tag_ids) as chosen(value)
      );

    insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id, created_by)
    select
      target_organization_id,
      chosen.value::uuid,
      'client',
      target_client_id,
      (select auth.uid())
    from jsonb_array_elements_text(tag_ids) as chosen(value)
    on conflict (tag_id, entity_type, entity_id) do nothing;
  end if;

  return updated_client;
end;
$$;

-- enqueue_invoice_communication_email: a distinct billing-contact email gets its own access link and its
-- own queued send, under a namespaced logical send key so a retry of the same idempotency key never
-- double-sends either recipient. The two trailing parameters default to null so any other caller of the
-- previous six-argument signature keeps working unchanged and simply never reaches a billing contact.
CREATE OR REPLACE FUNCTION "public"."enqueue_invoice_communication_email"("target_organization_id" "uuid", "target_actor_user_id" "uuid", "target_invoice_id" "uuid", "target_logical_send_key" "text", "target_invoice_url" "text", "target_invoice_token_hash" "bytea", "target_billing_invoice_url" "text" DEFAULT NULL::"text", "target_billing_invoice_token_hash" "bytea" DEFAULT NULL::"bytea") RETURNS "public"."communication_delivery_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'private'
    AS $_$
declare
  invoice_row public.invoices; client_row public.clients;
  recipient public.client_contact_methods; billing_recipient public.client_contact_methods;
  business_name text;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents; billing_intent public.communication_delivery_intents;
  primary_send_key text; billing_send_key text;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'invoices.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send this invoice by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_invoice_url !~ '^https?://[^[:space:]]+$' or target_invoice_token_hash is null
    or octet_length(target_invoice_token_hash) <> 32 then
    raise exception 'The invoice delivery link is not available.' using errcode = 'check_violation';
  end if;
  primary_send_key := target_logical_send_key || ':primary';
  billing_send_key := target_logical_send_key || ':billing';
  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = primary_send_key for share;
  if intent.id is not null then
    if intent.invoice_id is distinct from target_invoice_id then
      raise exception 'This email retry does not match the original invoice.' using errcode = 'unique_violation';
    end if;
    return intent;
  end if;
  select * into invoice_row from public.invoices
    where organization_id = target_organization_id and id = target_invoice_id for share;
  if invoice_row.id is null or invoice_row.issued_at is null
    or invoice_row.voided_at is not null or invoice_row.replaced_at is not null then
    raise exception 'This invoice is not available to send.' using errcode = 'foreign_key_violation';
  end if;
  select * into client_row from public.clients
    where organization_id = invoice_row.organization_id and id = invoice_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = invoice_row.organization_id and client_id = invoice_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    raise exception 'This invoice needs an active customer email address before it can be sent.' using errcode = 'object_not_in_prerequisite_state';
  end if;
  select * into billing_recipient from public.client_contact_methods
    where organization_id = invoice_row.organization_id and client_id = invoice_row.client_id and kind = 'email'
      and is_billing_contact for share;
  select organization.name into business_name from public.organizations as organization
    where organization.id = invoice_row.organization_id;
  -- The organization's default automated sender, exactly as enqueue_quote_communication_email chooses it.
  -- (An earlier draft preferred a sender assigned to the client's owner, but clients carry no owner column,
  -- so that reference raised undefined_column on every real send.)
  select * into sender from public.communication_email_senders
    where organization_id = invoice_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    raise exception 'No automated email sender is ready for this business.' using errcode = 'object_not_in_prerequisite_state';
  end if;
  update public.invoice_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = invoice_row.organization_id and invoice_id = invoice_row.id and revoked_at is null;
  insert into public.invoice_access_links (organization_id, invoice_id, recipient_name, recipient_email, token_hash, issued_by)
    values (invoice_row.organization_id, invoice_row.id,
      coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value,
      target_invoice_token_hash, target_actor_user_id);
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, invoice_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
    values (invoice_row.organization_id, invoice_row.client_id, recipient.id, invoice_row.id, primary_send_key, recipient.normalized_value,
      'Your invoice from ' || coalesce(nullif(trim(business_name), ''), 'your contractor'),
      '<p>Your invoice is ready to view.</p><p><a href="' || replace(target_invoice_url, '&', '&amp;') || '">View your invoice</a></p>',
      'Your invoice is ready to view. View it here: ' || target_invoice_url, 'automated', 'essential', sender.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);

  -- The billing contact is always a different email than the primary (the table's own check constraint
  -- guarantees it), so this can never double-send to the same address. It uses its own link and token,
  -- passed in by the caller, so the two recipients never share a secret.
  if billing_recipient.id is not null and target_billing_invoice_url is not null
    and target_billing_invoice_token_hash is not null then
    insert into public.invoice_access_links (organization_id, invoice_id, recipient_name, recipient_email, token_hash, issued_by)
      values (invoice_row.organization_id, invoice_row.id,
        coalesce(nullif(trim(client_row.display_name), ''), billing_recipient.normalized_value), billing_recipient.normalized_value,
        target_billing_invoice_token_hash, target_actor_user_id);
    insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, invoice_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
      values (invoice_row.organization_id, invoice_row.client_id, billing_recipient.id, invoice_row.id, billing_send_key, billing_recipient.normalized_value,
        'Your invoice from ' || coalesce(nullif(trim(business_name), ''), 'your contractor'),
        '<p>Your invoice is ready to view.</p><p><a href="' || replace(target_billing_invoice_url, '&', '&amp;') || '">View your invoice</a></p>',
        'Your invoice is ready to view. View it here: ' || target_billing_invoice_url, 'automated', 'essential', sender.id, target_actor_user_id)
      returning * into billing_intent;
    insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (billing_intent.organization_id, billing_intent.id);
  end if;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.sent', target_actor_user_id, invoice_row.revision, null,
    case when billing_intent.id is not null then
      jsonb_build_object('delivery_intent_id', intent.id, 'recipient_email', recipient.normalized_value,
        'billing_delivery_intent_id', billing_intent.id, 'billing_recipient_email', billing_recipient.normalized_value)
    else
      jsonb_build_object('delivery_intent_id', intent.id, 'recipient_email', recipient.normalized_value)
    end
  );
  return intent;
end;
$_$;

-- enqueue_quote_communication_email: same billing-contact addition, mirroring the invoice function. The
-- billing contact gets its own quote_recipients snapshot row and its own quote_access_links row (its own
-- token), exactly as the primary recipient does.
CREATE OR REPLACE FUNCTION "public"."enqueue_quote_communication_email"("target_organization_id" "uuid", "target_actor_user_id" "uuid", "target_quote_id" "uuid", "target_logical_send_key" "text", "target_quote_url" "text", "target_quote_token_hash" "bytea", "target_billing_quote_url" "text" DEFAULT NULL::"text", "target_billing_quote_token_hash" "bytea" DEFAULT NULL::"bytea") RETURNS "public"."communication_delivery_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'private'
    AS $_$
declare
  quote_row public.quotes; version_row public.quote_versions; client_row public.clients;
  recipient public.client_contact_methods; quote_recipient public.quote_recipients;
  billing_recipient public.client_contact_methods; billing_quote_recipient public.quote_recipients;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents; billing_intent public.communication_delivery_intents;
  alias public.communication_reply_aliases; billing_alias public.communication_reply_aliases;
  access_link_id uuid; billing_access_link_id uuid;
  primary_send_key text; billing_send_key text;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'quotes.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send this quote by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_quote_url !~ '^https?://[^[:space:]]+$' or target_quote_token_hash is null
    or octet_length(target_quote_token_hash) <> 32 then
    raise exception 'The quote delivery link is not available.' using errcode = 'check_violation';
  end if;
  primary_send_key := target_logical_send_key || ':primary';
  billing_send_key := target_logical_send_key || ':billing';
  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = primary_send_key for share;
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
  select * into billing_recipient from public.client_contact_methods
    where organization_id = quote_row.organization_id and client_id = quote_row.client_id and kind = 'email'
      and is_billing_contact for share;
  select * into sender from public.communication_email_senders
    where organization_id = quote_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    raise exception 'No automated email sender is ready for this business.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  alias := public.ensure_communication_reply_alias(quote_row.organization_id, sender.id, quote_row.client_id, recipient.id);

  insert into public.quote_recipients (organization_id, quote_id, display_name, email, created_by)
    values (quote_row.organization_id, quote_row.id, coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value, target_actor_user_id)
    on conflict (organization_id, quote_id, email) do update set display_name = excluded.display_name returning * into quote_recipient;
  update public.quote_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = quote_row.organization_id and quote_id = quote_row.id and recipient_id = quote_recipient.id and revoked_at is null;
  insert into public.quote_access_links (organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by)
    values (quote_row.organization_id, quote_row.id, version_row.id, quote_recipient.id, target_quote_token_hash, target_actor_user_id)
    returning id into access_link_id;
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, quote_id, quote_version_id, quote_recipient_id, quote_access_link_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by)
    values (quote_row.organization_id, quote_row.client_id, recipient.id, quote_row.id, version_row.id, quote_recipient.id, access_link_id, primary_send_key, recipient.normalized_value,
      'Your quote from ' || version_row.organization_name,
      '<p>Your quote is ready to review.</p><p><a href="' || replace(target_quote_url, '&', '&amp;') || '">View your quote</a></p>',
      'Your quote is ready to review. View it here: ' || target_quote_url, 'automated', 'essential', sender.id, alias.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);

  if billing_recipient.id is not null and target_billing_quote_url is not null
    and target_billing_quote_token_hash is not null then
    billing_alias := public.ensure_communication_reply_alias(quote_row.organization_id, sender.id, quote_row.client_id, billing_recipient.id);

    insert into public.quote_recipients (organization_id, quote_id, display_name, email, created_by)
      values (quote_row.organization_id, quote_row.id, coalesce(nullif(trim(client_row.display_name), ''), billing_recipient.normalized_value), billing_recipient.normalized_value, target_actor_user_id)
      on conflict (organization_id, quote_id, email) do update set display_name = excluded.display_name returning * into billing_quote_recipient;
    update public.quote_access_links set revoked_at = now(), revoked_reason = 'rotated'
      where organization_id = quote_row.organization_id and quote_id = quote_row.id and recipient_id = billing_quote_recipient.id and revoked_at is null;
    insert into public.quote_access_links (organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by)
      values (quote_row.organization_id, quote_row.id, version_row.id, billing_quote_recipient.id, target_billing_quote_token_hash, target_actor_user_id)
      returning id into billing_access_link_id;
    insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, quote_id, quote_version_id, quote_recipient_id, quote_access_link_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by)
      values (quote_row.organization_id, quote_row.client_id, billing_recipient.id, quote_row.id, version_row.id, billing_quote_recipient.id, billing_access_link_id, billing_send_key, billing_recipient.normalized_value,
        'Your quote from ' || version_row.organization_name,
        '<p>Your quote is ready to review.</p><p><a href="' || replace(target_billing_quote_url, '&', '&amp;') || '">View your quote</a></p>',
        'Your quote is ready to review. View it here: ' || target_billing_quote_url, 'automated', 'essential', sender.id, billing_alias.id, target_actor_user_id)
      returning * into billing_intent;
    insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (billing_intent.organization_id, billing_intent.id);
  end if;

  return intent;
end;
$_$;
