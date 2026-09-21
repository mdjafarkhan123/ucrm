-- Onboarding & Data Portability, Part 1, step 5b: the client-import worker.
--
-- Step 5a (Commit) settled skip/hold/error rows and queued the create/update rows as 'ready' -- but nothing
-- has touched the real client list yet. This is the worker that drains that queue: one RPC that claims the
-- oldest ready row, turns it into (or onto) a real client, records the outcome, and -- once the queue is dry --
-- flips the batch to 'completed'. It is the exact shape process_next_form_submission (Part 4D) already uses:
-- claim + resolve + write + record, all in one transaction, so a crash mid-row simply leaves the row 'ready'
-- for the next wake and one bad row never wedges the queue.
--
-- Why the create/update sequence is inlined here rather than calling public.create_client: create_client is
-- security invoker, granted only to `authenticated`, and leans on auth.uid() (for the note's created_by) and
-- RLS. This worker runs as service_role with no logged-in user -- the same reason the forms worker inlines its
-- own writes. The note's created_by is taken from the batch's created_by (the office member who ran the
-- import) instead of auth.uid().
--
-- No customer-facing side effects: creating a client fires only the one after-insert trigger that seeds its
-- communication-preferences row (harmless). None of the automation/communications/review/dunning engines listen
-- to client creation -- those fire on quotes and invoices -- so an import stays silent, as promised.
--
-- Completion is decided by a drained-queue check, never by "whichever row committed last": two wakes finishing
-- the last two rows concurrently could each still see the other's row as 'ready' and neither would flip the
-- batch. Instead, a wake that finds no claimable ready row looks for an 'importing' batch with zero ready rows
-- left and finalizes THAT. In the common single-wake drain the TS loop calls again after the last row, sees the
-- queue empty, and finalizes immediately; if every wake is lost, the once-a-minute cron sweep (step 5b wake
-- migration) still calls in and finalizes. The SKIP LOCKED claim remains the exactly-once boundary throughout.

-- ---------------------------------------------------------------------------------------------------------
-- 1. process_next_import_row -- claim one ready row, write it, or finalize a drained batch
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.process_next_import_row()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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
begin
  -- 1. Claim the oldest ready row across all committed batches. The partial import_rows_ready_idx leads on
  -- exactly this ORDER BY, so the claim is a plain index walk with no sort (competing-consumer queue).
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

        -- 1b. Contact methods. A brand-new client has neither yet, so each is the primary of its kind. A value
        -- that collides org-wide (including with a still-restorable soft-deleted client -- which the Review
        -- dry-run cannot see) raises unique_violation and is handled below as a friendly per-row failure.
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
            coalesce(nullif(trim(property_payload ->> 'label'), ''), 'Primary property'),
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

        -- 1a. Only the fields Review decided to change are present in client_payload (it never writes a null
        -- to clear a field), so coalesce keeps the existing value for every absent key.
        update public.clients set
          first_name = coalesce(client_payload ->> 'first_name', first_name),
          last_name = coalesce(client_payload ->> 'last_name', last_name),
          company_name = coalesce(client_payload ->> 'company_name', company_name),
          lead_source = coalesce(client_payload ->> 'lead_source', lead_source),
          display_name = coalesce(client_payload ->> 'display_name', display_name)
        where id = new_client_id and organization_id = row_rec.organization_id;

        -- 1b. Contact methods are added only when Review put them here (the client lacked that kind or a
        -- toggle allowed it, and the value is new org-wide). Primary only if the client has none of that kind
        -- yet, so we never create a second primary. A collision is caught below.
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

        -- 1c. A property is added only when Review put one here (client had none, or the toggle allowed it).
        if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
          insert into public.properties (
            organization_id, client_id, label, address_line1, address_line2, city, state_region,
            postal_code, country
          )
          values (
            row_rec.organization_id, new_client_id,
            coalesce(nullif(trim(property_payload ->> 'label'), ''), 'Primary property'),
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

      -- 1d. The note is additive on both paths, attributed to the office member who ran the import.
      if note_value is not null then
        insert into public.notes (organization_id, body, created_by)
        values (row_rec.organization_id, note_value, batch_rec.created_by)
        returning id into new_note_id;

        insert into public.note_links (organization_id, note_id, entity_type, entity_id)
        values (row_rec.organization_id, new_note_id, 'client', new_client_id);
      end if;

      -- 1e. Record the success: bump the batch's running count and mark the row imported.
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
        -- The one genuinely expected failure: the row's email/phone collides org-wide, usually with a client
        -- sitting in Recently Deleted that the Review dry-run could not see. Recorded in plain words for the
        -- error file; the inner writes for this row rolled back, the claim and this update do not.
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

  -- 2. No claimable ready row. Finalize one 'importing' batch whose queue is fully drained (no ready rows left,
  -- committed). SKIP LOCKED so two wakes cannot both finalize the same batch; the NOT EXISTS check reads
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

comment on function public.process_next_import_row() is
  'The client-import worker''s one entry point. Claims the oldest ready import_rows row (for update skip '
  'locked on import_rows_ready_idx), executes its resolved_payload as an inlined create/update client sequence '
  '(create_client is security-invoker/auth.uid; the worker runs as service_role), maintains the batch''s '
  'created/updated/error counts, and records the row imported or failed -- never raising, so one bad row cannot '
  'wedge the queue. When no ready row is claimable it finalizes one fully-drained importing batch to completed. '
  'Returns {status: idle} when there is nothing to claim or finalize. (SECURITY DEFINER; service_role only.)';

revoke all on function public.process_next_import_row() from public, anon, authenticated;
grant execute on function public.process_next_import_row() to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 2. set_import_batch_error_file -- stamp the generated error file's R2 key
-- ---------------------------------------------------------------------------------------------------------
-- The per-row error file is built and uploaded by the worker's TS layer (R2 is a network op, not something the
-- database does), then its object key is recorded here. Kept as a definer RPC for the same reason every import
-- write is: import_batches has no update policy (rule 12). service_role only; the app never calls it.

create or replace function public.set_import_batch_error_file(target_batch_id uuid, object_key text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if target_batch_id is null then
    raise exception 'batch_id is required.' using errcode = 'invalid_parameter_value';
  end if;
  update public.import_batches
  set error_file_object_key = nullif(trim(object_key), '')
  where id = target_batch_id;
end;
$$;

comment on function public.set_import_batch_error_file(uuid, text) is
  'Records the R2 object key of the per-row error file the import worker generated for a batch. Service-role '
  'only; the app never calls it (rule 12: import_batches has no update policy). SECURITY DEFINER.';

revoke all on function public.set_import_batch_error_file(uuid, text) from public, anon, authenticated;
grant execute on function public.set_import_batch_error_file(uuid, text) to service_role;

notify pgrst, 'reload schema';
