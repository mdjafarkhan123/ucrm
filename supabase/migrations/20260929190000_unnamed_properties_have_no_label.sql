-- An address saved without a name has no name. It used to be stamped "Primary property", which then showed
-- under every unnamed address -- even ones that are not the main one -- while the "Main" badge is the only
-- honest marker of that. Jobber names an address by its street, so an unnamed one now shows the street alone.

alter table public.properties alter column label drop default;
alter table public.properties alter column label drop not null;

-- The stock name, and a street copied into the name box, were never names the office chose.
update public.properties
set label = null
where label = 'Primary property'
   or label = address_line1;

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
      nullif(trim(property_payload->>'label'), ''),
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
        nullif(trim(property_payload->>'label'), ''),
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

CREATE OR REPLACE FUNCTION "public"."process_next_import_row"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  row_rec public.import_rows;
  batch_rec public.import_batches;
  final_batch public.import_batches;
  client_payload jsonb;
  property_payload jsonb;
  email_value text;
  phone_value text;
  note_value text;
  new_client_id uuid;
  new_note_id uuid;
  ob_predecessor_id uuid;
  ob_predecessor public.client_opening_balances;
  ob_root_id uuid;
begin
  -- 1. Claim the oldest ready row across all committed batches, any entity type. The partial
  -- import_rows_ready_idx leads on exactly this ORDER BY, so the claim is a plain index walk with no sort
  -- (competing-consumer queue).
  select * into row_rec
  from public.import_rows
  where status = 'ready'
  order by created_at, source_row_number
  for update skip locked
  limit 1;

  if found then
    select * into batch_rec from public.import_batches where id = row_rec.batch_id;
    client_payload := row_rec.resolved_payload -> 'client';
    property_payload := row_rec.resolved_payload -> 'property';
    email_value := nullif(trim(row_rec.resolved_payload ->> 'email'), '');
    phone_value := nullif(trim(row_rec.resolved_payload ->> 'phone'), '');
    note_value := nullif(trim(client_payload ->> 'initial_note'), '');

    begin
      if batch_rec.entity_type = 'client' then
        if row_rec.planned_action = 'create' then
          -- 1a. The client itself. Every field is already validated and defaulted by the Review step; the
          -- column set mirrors public.create_client.
          insert into public.clients (
            organization_id, display_name, client_type, first_name, last_name, company_name,
            lifecycle_status, lead_source
          )
          values (
            row_rec.organization_id,
            client_payload ->> 'display_name',
            coalesce(nullif(client_payload ->> 'client_type', ''), 'person'),
            nullif(trim(client_payload ->> 'first_name'), ''),
            nullif(trim(client_payload ->> 'last_name'), ''),
            nullif(trim(client_payload ->> 'company_name'), ''),
            coalesce(nullif(client_payload ->> 'lifecycle_status', ''), 'lead'),
            nullif(trim(client_payload ->> 'lead_source'), '')
          )
          returning id into new_client_id;

          -- 1b. Contact methods. A brand-new client has neither yet, so each is the primary of its kind. A
          -- value that collides org-wide (including with a still-restorable soft-deleted client -- which the
          -- Review dry-run cannot see) raises unique_violation and is handled below as a friendly per-row
          -- failure.
          if email_value is not null then
            insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
            values (row_rec.organization_id, new_client_id, 'email', email_value, true);
          end if;
          if phone_value is not null then
            insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
            values (row_rec.organization_id, new_client_id, 'phone', phone_value, true);
          end if;

          -- 1c. First property (the before-insert trigger makes the first non-deleted property primary).
          if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
            insert into public.properties (
              organization_id, client_id, label, address_line1, address_line2, city, state_region,
              postal_code, country
            )
            values (
              row_rec.organization_id, new_client_id,
              nullif(trim(property_payload ->> 'label'), ''),
              property_payload ->> 'address_line1',
              nullif(trim(property_payload ->> 'address_line2'), ''),
              property_payload ->> 'city',
              nullif(trim(property_payload ->> 'state_region'), ''),
              nullif(trim(property_payload ->> 'postal_code'), ''),
              coalesce(nullif(property_payload ->> 'country', ''), 'US')
            );
          end if;

        elsif row_rec.planned_action = 'update' then
          new_client_id := row_rec.match_client_id;

          -- 1a. Only the fields Review decided to change are present in client_payload (it never writes a
          -- null to clear a field), so coalesce keeps the existing value for every absent key.
          update public.clients set
            first_name = coalesce(client_payload ->> 'first_name', first_name),
            last_name = coalesce(client_payload ->> 'last_name', last_name),
            company_name = coalesce(client_payload ->> 'company_name', company_name),
            lead_source = coalesce(client_payload ->> 'lead_source', lead_source),
            display_name = coalesce(client_payload ->> 'display_name', display_name)
          where id = new_client_id and organization_id = row_rec.organization_id;

          -- 1b. Contact methods are added only when Review put them here (the client lacked that kind or a
          -- toggle allowed it, and the value is new org-wide). Primary only if the client has none of that
          -- kind yet, so we never create a second primary. A collision is caught below.
          if email_value is not null then
            insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
            values (
              row_rec.organization_id, new_client_id, 'email', email_value,
              not exists (
                select 1 from public.client_contact_methods
                where client_id = new_client_id and kind = 'email'
              )
            );
          end if;
          if phone_value is not null then
            insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
            values (
              row_rec.organization_id, new_client_id, 'phone', phone_value,
              not exists (
                select 1 from public.client_contact_methods
                where client_id = new_client_id and kind = 'phone'
              )
            );
          end if;

          -- 1c. A property is added only when Review put one here (client had none, or the toggle allowed
          -- it).
          if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
            insert into public.properties (
              organization_id, client_id, label, address_line1, address_line2, city, state_region,
              postal_code, country
            )
            values (
              row_rec.organization_id, new_client_id,
              nullif(trim(property_payload ->> 'label'), ''),
              property_payload ->> 'address_line1',
              nullif(trim(property_payload ->> 'address_line2'), ''),
              property_payload ->> 'city',
              nullif(trim(property_payload ->> 'state_region'), ''),
              nullif(trim(property_payload ->> 'postal_code'), ''),
              coalesce(nullif(property_payload ->> 'country', ''), 'US')
            );
          end if;
        else
          -- Only create/update rows are ever 'ready'; anything else is a contract breach, not a data error.
          raise exception 'A ready import row had an unexpected action: %', row_rec.planned_action
            using errcode = 'check_violation';
        end if;

        -- 1d. The note is additive on both client paths, attributed to the office member who ran the import.
        -- Opening-balance rows never carry a client payload, so note_value is null for them and this never
        -- fires.
        if note_value is not null then
          insert into public.notes (organization_id, body, created_by)
          values (row_rec.organization_id, note_value, batch_rec.created_by)
          returning id into new_note_id;

          insert into public.note_links (organization_id, note_id, entity_type, entity_id)
          values (row_rec.organization_id, new_note_id, 'client', new_client_id);
        end if;

      elsif batch_rec.entity_type = 'opening_balance' then
        if row_rec.planned_action = 'create' then
          -- A fresh fact. The set-root trigger points root_opening_balance_id at the new row's own id.
          insert into public.client_opening_balances (
            organization_id, client_id, balance_type, amount_minor, currency_code, as_of_date, source_note,
            import_batch_id, import_row_id, created_by
          )
          values (
            row_rec.organization_id,
            (row_rec.resolved_payload ->> 'client_id')::uuid,
            row_rec.resolved_payload ->> 'balance_type',
            (row_rec.resolved_payload ->> 'amount_minor')::bigint,
            row_rec.resolved_payload ->> 'currency_code',
            (row_rec.resolved_payload ->> 'as_of_date')::date,
            nullif(trim(row_rec.resolved_payload ->> 'source_note'), ''),
            row_rec.batch_id, row_rec.id, batch_rec.created_by
          )
          returning id into new_client_id;

        elsif row_rec.planned_action = 'update' then
          -- A correction: lock the fact it replaces, insert the new fact carrying that fact's root, then mark
          -- the old one replaced. Never edits or deletes the old fact's own data (contract).
          ob_predecessor_id := (row_rec.resolved_payload ->> 'predecessor_opening_balance_id')::uuid;

          select * into ob_predecessor
          from public.client_opening_balances
          where id = ob_predecessor_id and organization_id = row_rec.organization_id
          for update;

          if not found then
            raise exception 'The opening balance fact this row corrects no longer exists.'
              using errcode = 'foreign_key_violation';
          end if;
          if ob_predecessor.replaced_at is not null then
            raise exception 'The opening balance fact this row corrects has already been replaced.'
              using errcode = 'check_violation';
          end if;
          ob_root_id := ob_predecessor.root_opening_balance_id;

          insert into public.client_opening_balances (
            organization_id, client_id, balance_type, amount_minor, currency_code, as_of_date, source_note,
            predecessor_opening_balance_id, root_opening_balance_id, import_batch_id, import_row_id, created_by
          )
          values (
            row_rec.organization_id,
            (row_rec.resolved_payload ->> 'client_id')::uuid,
            row_rec.resolved_payload ->> 'balance_type',
            (row_rec.resolved_payload ->> 'amount_minor')::bigint,
            row_rec.resolved_payload ->> 'currency_code',
            (row_rec.resolved_payload ->> 'as_of_date')::date,
            nullif(trim(row_rec.resolved_payload ->> 'source_note'), ''),
            ob_predecessor_id, ob_root_id,
            row_rec.batch_id, row_rec.id, batch_rec.created_by
          )
          returning id into new_client_id;

          update public.client_opening_balances
          set replaced_at = now(), replaced_by_opening_balance_id = new_client_id
          where id = ob_predecessor_id;
        else
          raise exception 'A ready import row had an unexpected action: %', row_rec.planned_action
            using errcode = 'check_violation';
        end if;

      else
        -- A contract breach (a batch entity_type the worker was never taught), not a data error.
        raise exception 'process_next_import_row does not know entity_type %', batch_rec.entity_type
          using errcode = 'check_violation';
      end if;

      -- 1e. Record the success: bump the batch's running count and mark the row imported. Names are generic
      -- across entity types: 'create' produced a brand-new row, 'update' corrected/changed an existing one.
      if row_rec.planned_action = 'create' then
        update public.import_batches set created_count = created_count + 1 where id = row_rec.batch_id;
      else
        update public.import_batches set updated_count = updated_count + 1 where id = row_rec.batch_id;
      end if;

      update public.import_rows
      set status = 'imported', result_client_id = new_client_id, processed_at = now()
      where id = row_rec.id;

      return jsonb_build_object(
        'status', 'processed', 'row_id', row_rec.id, 'batch_id', row_rec.batch_id,
        'action', row_rec.planned_action, 'client_id', new_client_id
      );
    exception
      when unique_violation then
        -- The one genuinely expected Client-import failure: the row's email/phone collides org-wide, usually
        -- with a client sitting in Recently Deleted that the Review dry-run could not see. Opening-balance
        -- rows have no unique constraint that can fire here; they fall through to "when others" instead.
        update public.import_rows
        set status = 'failed', processed_at = now(),
          error_message = 'This contact''s email or phone already belongs to another client in your account '
            || '(possibly one you deleted), so it was not imported.'
        where id = row_rec.id;
        update public.import_batches set error_count = error_count + 1 where id = row_rec.batch_id;
        return jsonb_build_object(
          'status', 'failed', 'row_id', row_rec.id, 'batch_id', row_rec.batch_id, 'error', 'duplicate_contact'
        );
      when others then
        update public.import_rows
        set status = 'failed', processed_at = now(), error_message = left(sqlerrm, 500)
        where id = row_rec.id;
        update public.import_batches set error_count = error_count + 1 where id = row_rec.batch_id;
        return jsonb_build_object(
          'status', 'failed', 'row_id', row_rec.id, 'batch_id', row_rec.batch_id, 'error', sqlerrm
        );
    end;
  end if;

  -- 2. No claimable ready row. Finalize one 'importing' batch whose queue is fully drained (no ready rows
  -- left, committed). SKIP LOCKED so two wakes cannot both finalize the same batch; the NOT EXISTS check reads
  -- committed state, so a row still being written by another wake (locked, status still 'ready') correctly
  -- keeps its batch out of this until it commits.
  select * into final_batch
  from public.import_batches
  where status = 'importing'
    and not exists (
      select 1 from public.import_rows r
      where r.batch_id = public.import_batches.id and r.status = 'ready'
    )
  order by created_at
  for update skip locked
  limit 1;

  if found then
    update public.import_batches set status = 'completed' where id = final_batch.id
    returning * into final_batch;
    return jsonb_build_object(
      'status', 'batch_completed', 'batch_id', final_batch.id,
      'organization_id', final_batch.organization_id,
      'error_count', final_batch.error_count, 'held_count', final_batch.held_count
    );
  end if;

  return jsonb_build_object('status', 'idle');
end;
$$;
