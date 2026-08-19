-- Client creation and editing foundation.
-- Adds the saved contact policy, database-enforced duplicate blocking on email and phone, tag and
-- preference writes inside the existing atomic create, and one matching atomic update interface.
-- No policy or grant changes: every table touched here already has permission-aware policies and both
-- functions run as the caller, so row level security still decides what may be written.

-- 1. Contact policy ----------------------------------------------------------------------------------

-- A saved layer on top of the six detailed preferences, never a replacement for them. Switching to
-- "Do not disturb" and back leaves every checkbox exactly as the office left it.
alter table public.client_communication_preferences
  add column contact_policy text not null default 'allow'
    constraint client_communication_preferences_contact_policy_check
    check (contact_policy in ('allow', 'no_marketing', 'do_not_disturb'));

-- 2. Duplicate blocking ------------------------------------------------------------------------------

-- normalized_value is already generated (email lowercased and trimmed, phone digits only), so this index
-- is exactly the approved exact-match rule enforced by the database. A concurrent second request loses on
-- the index rather than on an application check it could race past.
-- Scope note: this blocks against every client that still exists, including one sitting in Recently
-- Deleted, because that client is still restorable.
create unique index client_contact_methods_org_value_unique_idx
  on public.client_contact_methods(organization_id, kind, normalized_value);

-- The old lookup index had identical leading columns, so the unique index already serves those reads.
drop index if exists public.client_contact_methods_lookup_idx;

-- 3. Atomic client creation --------------------------------------------------------------------------

-- Extends the existing function with tags and communication preferences so the client, its contact
-- methods, first property, initial note, tags, and preferences all commit or all roll back together.
create or replace function public.create_client(payload jsonb)
returns public.clients
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  created_client public.clients;
  new_property_id uuid;
  new_note_id uuid;
  email_value text := nullif(trim(payload->>'email'), '');
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
    owner_user_id,
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
    nullif(payload->>'owner_user_id', '')::uuid,
    nullif(payload->>'next_follow_up_at', '')::timestamptz
  )
  returning * into created_client;

  if email_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'email', email_value, true);
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
      marketing = coalesce((preferences->>'marketing')::boolean, saved.marketing),
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

revoke all on function public.create_client(jsonb) from public;
grant execute on function public.create_client(jsonb) to authenticated;

-- 4. Atomic client update ------------------------------------------------------------------------------

-- The edit-side twin of create_client. Identity, primary email and phone, the primary property,
-- preferences, and tags move together. It never deletes a property; property removal belongs to property
-- management. Notes are managed through the collaboration interfaces, not here.
create or replace function public.update_client(payload jsonb)
returns public.clients
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid := (payload->>'organization_id')::uuid;
  target_client_id uuid := (payload->>'id')::uuid;
  updated_client public.clients;
  email_value text := nullif(trim(payload->>'email'), '');
  phone_value text := nullif(trim(payload->>'phone'), '');
  property_payload jsonb := payload->'property';
  preferences jsonb := payload->'preferences';
  tag_ids jsonb := payload->'tag_ids';
  existing_email_id uuid;
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

  -- An address supplied on the edit form updates the primary property in place, or creates one when the
  -- client has none yet. Leaving the address blank changes nothing.
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
      marketing = coalesce((preferences->>'marketing')::boolean, saved.marketing),
      contact_policy = coalesce(nullif(preferences->>'contact_policy', ''), saved.contact_policy)
    where saved.organization_id = target_organization_id
      and saved.client_id = target_client_id;
  end if;

  -- Tags are reconciled only when the caller sends the list, so a payload without tags leaves them alone.
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

revoke all on function public.update_client(jsonb) from public;
grant execute on function public.update_client(jsonb) to authenticated;
