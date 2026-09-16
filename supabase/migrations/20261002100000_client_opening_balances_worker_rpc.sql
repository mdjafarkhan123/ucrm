-- Financial reconciliation, Part 6, step 2: the opening-balance import worker.
--
-- 20261001100000 locked the shape: public.client_opening_balances, written only by the assisted-import
-- pipeline (public.import_batches/import_rows, entity_type = 'opening_balance'), never a form, never SQL run
-- by hand. That queue is the exact same one public.process_next_import_row already drains for Client imports
-- (one shared partial index, one shared claim) -- so this migration teaches that one worker a second entity
-- type rather than adding a competing worker, the same "one queue, several entity types" shape the original
-- foundation migration's comment anticipated.
--
-- Contract this migration fixes for entity_type = 'opening_balance' rows (mirrors the client contract already
-- documented on import_rows.resolved_payload):
--   planned_action = 'create' -- a fresh fact:
--     { "client_id": uuid, "balance_type": "receivable"|"credit", "amount_minor": integer > 0,
--       "currency_code": "USD", "as_of_date": "YYYY-MM-DD", "source_note": text|null }
--   planned_action = 'update' -- a correction (contract: "correcting an opening fact appends a linked
--   correction rather than editing or deleting history"): the same fields plus
--     "predecessor_opening_balance_id": uuid -- the existing, not-yet-replaced fact this one corrects.
--   'skip'/'hold'/'error' never reach 'ready' (same rule as Client rows); Review (onboarding-and-data-
--   portability Part 4) decides which bucket a row falls into. This worker only executes 'ready' rows.
--
-- A correction is two writes in the fact's one transaction: insert the new fact carrying the predecessor's
-- root, then mark the predecessor replaced. The guard trigger (client_opening_balances_guard_identity) allows
-- that one replaced_at/replaced_by_opening_balance_id transition and forbids any further change, so a fact can
-- be replaced exactly once.
--
-- import_rows.result_client_id is reused (not renamed) to hold whichever id this row produced -- a Client for
-- entity_type='client', an opening-balance fact for entity_type='opening_balance'. No screen reads this column
-- yet for either entity type, so widening its meaning now costs nothing and avoids an unrelated rename.

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

comment on function public.process_next_import_row() is
  'The shared assisted-import worker''s one entry point, for every entity_type the pipeline carries. Claims '
  'the oldest ready import_rows row across all batches (for update skip locked on import_rows_ready_idx), then '
  'branches on the row''s batch entity_type: ''client'' writes/updates public.clients (create_client is '
  'security-invoker/auth.uid; this worker runs as service_role); ''opening_balance'' inserts a '
  'public.client_opening_balances fact, or -- for a correction (planned_action=''update'') -- inserts the '
  'corrected fact and marks the predecessor replaced, in one transaction. Maintains the batch''s '
  'created/updated/error counts and records the row imported or failed -- never raising, so one bad row cannot '
  'wedge the queue. When no ready row is claimable it finalizes one fully-drained importing batch to '
  'completed. Returns {status: idle} when there is nothing to claim or finalize. (SECURITY DEFINER; '
  'service_role only.)';

comment on column public.import_rows.result_client_id is
  'The id this row produced once the worker has run: a Client for entity_type=''client'' (create or update), '
  'an opening-balance fact for entity_type=''opening_balance'' (the fresh fact, or the correcting fact for a '
  'planned_action=''update'' row). Column name predates the second entity type; not renamed because nothing '
  'reads it yet for either type.';

notify pgrst, 'reload schema';
