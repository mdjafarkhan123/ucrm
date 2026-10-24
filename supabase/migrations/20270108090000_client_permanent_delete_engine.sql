-- Data privacy Part 3a: the permanent customer delete engine.
-- Design: docs/data-privacy-deletion-engine.md. Plan: docs/data-privacy-deletion-behavior-contract.md
-- (§ Money records after any delete, § "Don't contact me" survives deletion, § Delete permanently now).
--
-- One customer is deleted for good. What tax law needs stays exactly as it was: issued invoices, payments,
-- refunds, deposits, opening balances and card checkouts. A "don't contact me" survives as a scrambled
-- fingerprint of the phone or email, with no name. Everything else about the person goes. The customer row
-- itself stays as an empty "Deleted client" tombstone so the kept money records still point at something,
-- the way Stripe keeps a deleted customer object for the charges that reference it.
--
-- Pieces:
--   1. clients.purged_at
--   2. private.client_purge_in_progress() -- history guards and schedule alerts step aside for it
--   3. Usage and charge records outlive the message they paid for (ON DELETE SET NULL)
--   4. "Don't contact me" fingerprints: Vault key, table, fingerprint function, re-entry trigger
--   5. client_deletion_receipts
--   6. private.client_deletion_plan  -- the one answer to "what goes, what stays, what stops it?"
--   7. private.apply_client_purge    -- the delete
--   8. public.run_client_purge       -- service-role entry point for the scheduled and Jafar paths


-- ---------------------------------------------------------------------------------------------------------
-- 1. The tombstone marker
-- ---------------------------------------------------------------------------------------------------------

alter table public.clients add column purged_at timestamptz;
alter table public.clients add constraint clients_purged_is_deleted
  check (purged_at is null or deleted_at is not null);

comment on column public.clients.purged_at is
  'When the customer was permanently deleted. The row is then an empty "Deleted client" tombstone, kept only so retained invoices and payments still point at something.';


-- ---------------------------------------------------------------------------------------------------------
-- 2. History guards and schedule alerts step aside while a customer is purged
-- ---------------------------------------------------------------------------------------------------------

-- A transaction-local setting only private.apply_client_purge turns on, and turns off again before it
-- returns. PostgREST cannot set arbitrary settings, so a caller cannot reach it except through that function.
create or replace function private.client_purge_in_progress() returns boolean
  language sql stable
  set search_path to 'pg_catalog', 'public'
  as $$
  select coalesce(current_setting('app.client_purge_in_progress', true), '') = 'true';
$$;

alter function private.client_purge_in_progress() owner to postgres;

-- A purge deletes the customer's quotes and scrubs the name and address off the versions of a quote it keeps
-- for a deposit.
create or replace function private.reject_published_quote_version_change() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if private.client_purge_in_progress() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' and private.property_delete_in_progress() then
    return old;
  end if;
  if old.status = 'published' then
    raise exception 'Published quote versions cannot be changed or deleted.' using errcode = 'P0409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.reject_published_quote_child_change() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  target_version_id uuid;
begin
  if tg_op = 'DELETE' and (private.property_delete_in_progress() or private.client_purge_in_progress()) then
    return old;
  end if;
  target_version_id := case when tg_op = 'DELETE' then old.quote_version_id else new.quote_version_id end;
  if exists (
    select 1 from public.quote_versions
    where id = target_version_id and status = 'published'
  ) then
    raise exception 'Published quote version content cannot be changed or deleted.' using errcode = 'P0409';
  end if;
  if tg_op = 'UPDATE' and old.quote_version_id is distinct from new.quote_version_id and exists (
    select 1 from public.quote_versions
    where id = old.quote_version_id and status = 'published'
  ) then
    raise exception 'Published quote version content cannot be moved.' using errcode = 'P0409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.job_costing_events_are_append_only() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_op = 'DELETE' and (private.property_delete_in_progress() or private.client_purge_in_progress()) then
    return old;
  end if;
  raise exception 'Job costing history cannot be changed or removed.' using errcode = 'insufficient_privilege';
end;
$$;

create or replace function private.job_signatures_are_append_only() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_op = 'DELETE' and (
    current_setting('app.organization_purge_in_progress', true) = 'true'
    or private.property_delete_in_progress()
    or private.client_purge_in_progress()
  ) then
    return old;
  end if;
  raise exception 'A collected signature cannot be changed or removed.'
    using errcode = 'insufficient_privilege';
end;
$$;

create or replace function private.file_links_protect_history() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if old.protected
    and not private.property_delete_in_progress()
    and not private.client_merge_in_progress()
    and not private.client_purge_in_progress() then
    raise exception 'This file is part of a document the customer already received and cannot be removed from it.'
      using errcode = '23503';
  end if;
  return old;
end;
$$;

-- Only the history of a draft invoice is ever removed; an issued invoice's history is kept with the invoice.
create or replace function private.invoice_events_are_append_only() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_op = 'UPDATE' and private.client_merge_in_progress()
     and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  if tg_op = 'DELETE' and private.client_purge_in_progress() then
    return old;
  end if;
  raise exception 'Invoice history is append-only.' using errcode = 'check_violation';
end;
$$;

-- No crew alert or customer schedule notice may name a person who was just deleted.
create or replace function private.alert_visit_cancelled() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public', 'private'
  as $$
declare
  assignee record;
  subject text;
  label text;
begin
  if old.completed_at is not null or private.client_purge_in_progress() then
    return old;
  end if;
  subject := private.alert_job_label(old.organization_id, old.job_id);
  label := private.alert_visit_when(old.visit_date, old.start_time, old.all_day);
  for assignee in
    select a.user_id from public.job_visit_assignments as a
    where a.organization_id = old.organization_id and a.visit_id = old.id
      and a.user_id is distinct from auth.uid()
  loop
    perform private.record_schedule_alert(
      old.organization_id, assignee.user_id, 'schedule.changed', 'job', old.job_id,
      'Your Visit was cancelled: ' || subject || case when label = '' then '' else ', ' || label end,
      '{n} of your Visits for ' || subject || ' changed, starting {first}',
      label
    );
  end loop;
  return old;
end;
$$;

create or replace function private.alert_assessment_cancelled() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public', 'private'
  as $$
declare
  assignee record;
  subject text;
  label text;
begin
  if private.client_purge_in_progress() then
    return old;
  end if;
  subject := private.alert_assessment_label(old.organization_id, old.id);
  label := private.alert_assessment_when(old.organization_id, old.starts_at, old.all_day);
  for assignee in
    select a.user_id from public.assessment_assignees as a
    where a.organization_id = old.organization_id and a.assessment_id = old.id
      and a.user_id is distinct from auth.uid()
  loop
    perform private.record_schedule_alert(
      old.organization_id, assignee.user_id, 'schedule.changed', 'assessment', old.id,
      'Your Assessment was cancelled: ' || subject || case when label = '' then '' else ', ' || label end,
      'Your Assessment was cancelled: ' || subject || case when label = '' then '' else ', ' || label end,
      label
    );
  end loop;
  return old;
end;
$$;

create or replace function private.alert_visit_unassigned() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public', 'private'
  as $$
declare
  visit record;
  subject text;
  label text;
begin
  if old.user_id is not distinct from auth.uid() or private.client_purge_in_progress() then
    return old;
  end if;
  select v.visit_date, v.start_time, v.all_day, v.completed_at into visit
  from public.job_visits as v where v.organization_id = old.organization_id and v.id = old.visit_id;
  -- Gone (a cancelled Visit is announced on its own) or already finished.
  if not found or visit.completed_at is not null then
    return old;
  end if;
  subject := private.alert_job_label(old.organization_id, old.job_id);
  label := private.alert_visit_when(visit.visit_date, visit.start_time, visit.all_day);
  perform private.record_schedule_alert(
    old.organization_id, old.user_id, 'schedule.removed', 'job', old.job_id,
    'You''re off ' || subject || case when label = '' then '' else ', ' || label end,
    'You''re off {n} Visits for ' || subject || ', starting {first}',
    label
  );
  return old;
end;
$$;

create or replace function private.job_visits_log_schedule_change() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'private'
  as $$
declare
  change_kind text;
  row_data public.job_visits;
begin
  if tg_op = 'DELETE' then
    if private.client_purge_in_progress() then
      return null;
    end if;
    row_data := old;
    if old.visit_date is not null and old.completed_at is null then
      change_kind := 'removed';
    end if;
  else
    row_data := new;
    if new.completed_at is not null then
      change_kind := null;
    elsif tg_op = 'INSERT' then
      if new.visit_date is not null then change_kind := 'scheduled'; end if;
    elsif old.visit_date is null and new.visit_date is not null then
      change_kind := 'scheduled';
    elsif old.visit_date is not null and new.visit_date is null then
      change_kind := 'removed';
    elsif (old.visit_date, old.start_time, old.all_day) is distinct from (new.visit_date, new.start_time, new.all_day) then
      change_kind := 'moved';
    end if;
  end if;

  if change_kind is not null then
    insert into private.appointment_schedule_changes
      (organization_id, booking_type, booking_id, visit_id, kind, changed_by)
    values (row_data.organization_id, 'job', row_data.job_id, row_data.id, change_kind, (select auth.uid()));
  end if;
  return null;
end;
$$;

create or replace function private.assessments_log_schedule_change() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'private'
  as $$
declare
  change_kind text;
  row_data public.assessments;
begin
  if tg_op = 'DELETE' then
    if private.client_purge_in_progress() then
      return null;
    end if;
    row_data := old;
    if old.starts_at is not null and old.completed_at is null then
      change_kind := 'removed';
    end if;
  else
    row_data := new;
    if new.completed_at is not null then
      change_kind := null;
    elsif tg_op = 'INSERT' then
      if new.starts_at is not null then change_kind := 'scheduled'; end if;
    elsif old.starts_at is null and new.starts_at is not null then
      change_kind := 'scheduled';
    elsif old.starts_at is not null and new.starts_at is null then
      change_kind := 'removed';
    elsif (old.starts_at, old.all_day) is distinct from (new.starts_at, new.all_day) then
      change_kind := 'moved';
    end if;
  end if;

  if change_kind is not null then
    insert into private.appointment_schedule_changes
      (organization_id, booking_type, booking_id, visit_id, kind, changed_by)
    values (row_data.organization_id, 'assessment', row_data.id, row_data.id, change_kind, (select auth.uid()));
  end if;
  return null;
end;
$$;

-- The scrubbed address of a kept property shell is not a real address, so it never goes to the geocoder.
create or replace function private.mark_property_for_geocoding() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_op = 'INSERT' then
    -- A new property's address has never been verified. Coordinates come only from our geocoder, so they start
    -- empty and the row waits in the pending queue regardless of what was supplied.
    new.geocode_status := 'pending';
    new.latitude := null;
    new.longitude := null;
    return new;
  end if;

  if private.client_purge_in_progress() then
    return new;
  end if;

  -- UPDATE: only a real change to a geocodable component invalidates the stored coordinates. `is distinct from`
  -- treats nulls correctly, so clearing or setting an optional line counts and a no-op rewrite does not. This
  -- also means the worker's own write of coordinates + status (which touches neither address column) never
  -- trips this trigger back to pending.
  if new.address_line1 is distinct from old.address_line1
     or new.address_line2 is distinct from old.address_line2
     or new.city is distinct from old.city
     or new.state_region is distinct from old.state_region
     or new.postal_code is distinct from old.postal_code
     or new.country is distinct from old.country then
    new.geocode_status := 'pending';
    new.latitude := null;
    new.longitude := null;
  end if;

  return new;
end;
$$;

-- A purge removes the customer's note links. The old single statement named old.file_id on a note_links row,
-- which has no such field, so every note link delete failed (deleting a note in the app included). Each
-- table now gets its own statement, as private.link_note_files already does.
create or replace function private.prune_note_file_links() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_table_name = 'note_files' then
    delete from public.file_links as link
    where link.organization_id = old.organization_id
      and link.role = 'note_file'
      and link.file_id = old.file_id
      and not exists (
        select 1
        from public.note_files as held
        join public.note_links as placed on placed.note_id = held.note_id
        where held.file_id = link.file_id
          and placed.entity_type = link.entity_type
          and placed.entity_id = link.entity_id
      );
  else
    delete from public.file_links as link
    where link.organization_id = old.organization_id
      and link.role = 'note_file'
      and link.entity_type = old.entity_type
      and link.entity_id = old.entity_id
      and not exists (
        select 1
        from public.note_files as held
        join public.note_links as placed on placed.note_id = held.note_id
        where held.file_id = link.file_id
          and placed.entity_type = link.entity_type
          and placed.entity_id = link.entity_id
      );
  end if;
  return null;
end;
$$;


-- ---------------------------------------------------------------------------------------------------------
-- 3. Usage and charge records outlive the message they paid for
-- ---------------------------------------------------------------------------------------------------------

-- The business's text-credit charges, email allowance use and capacity bookings are its bill, not the
-- customer's information. Deleting a message now leaves them in place with no message link, so a delete never
-- changes what the business was charged or how much of its allowance it used.
alter table public.communication_sms_credit_reservations
  alter column delivery_intent_id drop not null,
  drop constraint communication_sms_credit_reservations_intent_fk,
  add constraint communication_sms_credit_reservations_intent_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel)
    on delete set null (delivery_intent_id);

alter table public.communication_email_usage_events
  alter column delivery_intent_id drop not null,
  drop constraint communication_email_usage_events_delivery_intent_id_fkey,
  add constraint communication_email_usage_events_delivery_intent_id_fkey
    foreign key (delivery_intent_id) references public.communication_delivery_intents (id) on delete set null;

alter table public.communication_email_capacity_reservations
  alter column delivery_intent_id drop not null,
  drop constraint communication_email_capacity_reservatio_delivery_intent_id_fkey,
  add constraint communication_email_capacity_reservatio_delivery_intent_id_fkey
    foreign key (delivery_intent_id) references public.communication_delivery_intents (id) on delete set null;


-- ---------------------------------------------------------------------------------------------------------
-- 4. "Don't contact me" fingerprints
-- ---------------------------------------------------------------------------------------------------------

-- The key lives in Vault, so a copy of the table alone cannot be reversed by trying every phone number.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'contact_fingerprint_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'contact_fingerprint_key',
      'HMAC key for the scrambled opt-out fingerprints a permanently deleted customer leaves behind.'
    );
  end if;
end;
$$;

create table public.contact_opt_out_fingerprints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  channel text not null check (channel in ('phone', 'email')),
  fingerprint bytea not null check (octet_length(fingerprint) = 32),
  kind text not null,
  opted_out_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint contact_opt_out_fingerprints_one_kind unique (organization_id, channel, fingerprint, kind),
  constraint contact_opt_out_fingerprints_kind_check check (
    (channel = 'phone' and kind in ('sms_opt_out', 'no_marketing', 'do_not_disturb'))
    or (channel = 'email' and kind in (
      'email_marketing_opt_out', 'email_hard_bounce', 'email_complaint', 'email_unsubscribe',
      'no_marketing', 'do_not_disturb'
    ))
  )
);

alter table public.contact_opt_out_fingerprints enable row level security;
revoke all on table public.contact_opt_out_fingerprints from anon, authenticated;

comment on table public.contact_opt_out_fingerprints is
  'A deleted customer''s "don''t contact me", kept as an HMAC of the phone or email with no name. When the same phone or email is added to a customer again, the matching opt-out is written onto the new record (private.carry_contact_opt_outs), so every existing send check honours it until the person opts back in.';

-- Phones keep their last ten digits, so "+1 555 123 4567" and "555-123-4567" are one person; over-matching
-- here only ever blocks a message, never sends one.
create or replace function private.contact_fingerprint(
  target_organization_id uuid, contact_kind text, normalized_value text
) returns bytea
  language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  digits text;
  canonical text;
  fingerprint_key text;
begin
  if normalized_value is null or btrim(normalized_value) = '' then
    return null;
  end if;

  if contact_kind = 'phone' then
    digits := regexp_replace(normalized_value, '[^0-9]', '', 'g');
    if digits = '' then
      return null;
    end if;
    canonical := case when char_length(digits) >= 10 then right(digits, 10) else digits end;
  elsif contact_kind = 'email' then
    canonical := lower(btrim(normalized_value));
  else
    raise exception 'Only a phone or an email can be fingerprinted.' using errcode = 'check_violation';
  end if;

  select decrypted_secret into fingerprint_key
  from vault.decrypted_secrets where name = 'contact_fingerprint_key';
  if fingerprint_key is null then
    raise exception 'The contact fingerprint key is missing from Vault.' using errcode = 'P0001';
  end if;

  -- The organisation is part of the input, so the same person has unrelated fingerprints in two businesses.
  return extensions.hmac(
    convert_to(target_organization_id::text || ':' || contact_kind || ':' || canonical, 'UTF8'),
    convert_to(fingerprint_key, 'UTF8'),
    'sha256'
  );
end;
$$;

alter function private.contact_fingerprint(uuid, text, text) owner to postgres;
revoke all on function private.contact_fingerprint(uuid, text, text) from public, anon, authenticated;

-- When a phone or email comes back to the business, its old "don't contact me" is written onto the new record
-- as the ordinary consent, unsubscribe, suppression or contact-policy row the send checks already read. The
-- carried event keeps the original date, so a later START or opt-in is newer and wins.
create or replace function private.carry_contact_opt_outs() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  fingerprint_value bytea;
  carried record;
begin
  -- Almost every business has none, so most inserts stop at this index probe.
  if not exists (
    select 1 from public.contact_opt_out_fingerprints where organization_id = new.organization_id
  ) then
    return null;
  end if;

  fingerprint_value := private.contact_fingerprint(new.organization_id, new.kind, new.normalized_value);
  if fingerprint_value is null then
    return null;
  end if;

  for carried in
    select id, kind, opted_out_at
    from public.contact_opt_out_fingerprints
    where organization_id = new.organization_id and channel = new.kind and fingerprint = fingerprint_value
  loop
    if carried.kind = 'sms_opt_out' then
      insert into public.communication_sms_consent_events (
        organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
        evidence, occurred_at
      ) values (
        new.organization_id, new.client_id, new.id, 'opt_out', 'system',
        'deleted_customer_opt_out:' || new.id || ':' || carried.id,
        jsonb_build_object('reason', 'carried_from_deleted_customer'), carried.opted_out_at
      )
      on conflict (organization_id, source, source_event_key) do nothing;
    elsif carried.kind = 'email_marketing_opt_out' then
      insert into public.client_marketing_consent_events (
        organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
        evidence, occurred_at
      ) values (
        new.organization_id, new.client_id, new.id, 'opt_out', 'unsubscribe',
        'deleted_customer_opt_out:' || new.id || ':' || carried.id,
        jsonb_build_object('reason', 'carried_from_deleted_customer'), carried.opted_out_at
      )
      on conflict (organization_id, source, source_event_key) do nothing;
    elsif carried.kind in ('email_hard_bounce', 'email_complaint', 'email_unsubscribe') then
      insert into public.communication_email_suppressions (organization_id, recipient_email, reason, source, evidence)
      values (
        new.organization_id, new.normalized_value, substr(carried.kind, 7), 'manual',
        jsonb_build_object('reason', 'carried_from_deleted_customer', 'first_recorded_at', carried.opted_out_at)
      )
      on conflict (organization_id, recipient_email, reason) where released_at is null do nothing;
    else
      -- A stricter contact policy wins over a looser one, as merge already does.
      insert into public.client_communication_preferences (organization_id, client_id, contact_policy)
      values (new.organization_id, new.client_id, carried.kind)
      on conflict (organization_id, client_id) do update
      set contact_policy = case
        when array_position(array['allow', 'no_marketing', 'do_not_disturb'], excluded.contact_policy)
           > array_position(array['allow', 'no_marketing', 'do_not_disturb'], client_communication_preferences.contact_policy)
        then excluded.contact_policy
        else client_communication_preferences.contact_policy
      end;
    end if;
  end loop;

  return null;
end;
$$;

alter function private.carry_contact_opt_outs() owner to postgres;
revoke all on function private.carry_contact_opt_outs() from public, anon, authenticated;

create trigger client_contact_methods_carry_opt_outs_insert
  after insert on public.client_contact_methods
  for each row execute function private.carry_contact_opt_outs();

create trigger client_contact_methods_carry_opt_outs_update
  after update of value on public.client_contact_methods
  for each row when (old.normalized_value is distinct from new.normalized_value)
  execute function private.carry_contact_opt_outs();

-- Writes or clears the fingerprints for every phone and email the customer has, from their latest choices.
-- Their latest choice wins: a phone whose last word was START clears an older SMS fingerprint.
create or replace function private.record_client_opt_out_fingerprints(
  target_organization_id uuid, target_client_id uuid
) returns void
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  org uuid := target_organization_id;
  preferences public.client_communication_preferences;
  method record;
  blocked_subjects integer;
  allowed_subjects integer;
  last_opt_out_at timestamptz;
  marketing record;
  suppression record;
  fingerprint_value bytea;
begin
  select * into preferences
  from public.client_communication_preferences
  where organization_id = org and client_id = target_client_id;

  for method in
    select id, kind, normalized_value
    from public.client_contact_methods
    where organization_id = org and client_id = target_client_id
  loop
    fingerprint_value := private.contact_fingerprint(org, method.kind, method.normalized_value);
    continue when fingerprint_value is null;

    if method.kind = 'phone' then
      -- An opt-in names the kinds of text it allows, so a STOP still in force for any one kind is kept, and it
      -- is cleared only once every kind was opted back into. The carried opt-out blocks every kind until then.
      select count(*) filter (where status = 'opted_out'), count(*) filter (where status = 'opted_in')
      into blocked_subjects, allowed_subjects
      from unnest(array['service', 'work_updates', 'billing_updates']) as subject,
        lateral public.communication_sms_consent_status(org, method.id, subject) as status;

      if blocked_subjects > 0 then
        select max(occurred_at) into last_opt_out_at
        from public.communication_sms_consent_events
        where organization_id = org and client_contact_method_id = method.id and event_kind = 'opt_out';

        insert into public.contact_opt_out_fingerprints (organization_id, channel, fingerprint, kind, opted_out_at)
        values (org, 'phone', fingerprint_value, 'sms_opt_out', last_opt_out_at)
        on conflict (organization_id, channel, fingerprint, kind) do update
        set opted_out_at = greatest(contact_opt_out_fingerprints.opted_out_at, excluded.opted_out_at);
      elsif allowed_subjects = 3 then
        delete from public.contact_opt_out_fingerprints
        where organization_id = org and channel = 'phone' and fingerprint = fingerprint_value and kind = 'sms_opt_out';
      elsif allowed_subjects = 0 and preferences.sms_opt_out_at is not null
        and (preferences.sms_opt_in_at is null or preferences.sms_opt_in_at < preferences.sms_opt_out_at) then
        insert into public.contact_opt_out_fingerprints (organization_id, channel, fingerprint, kind, opted_out_at)
        values (org, 'phone', fingerprint_value, 'sms_opt_out', preferences.sms_opt_out_at)
        on conflict (organization_id, channel, fingerprint, kind) do update
        set opted_out_at = greatest(contact_opt_out_fingerprints.opted_out_at, excluded.opted_out_at);
      end if;
    else
      select state, effective_at into marketing
      from public.client_marketing_consent_state
      where organization_id = org and client_contact_method_id = method.id;

      if marketing.state = 'opted_out' then
        insert into public.contact_opt_out_fingerprints (organization_id, channel, fingerprint, kind, opted_out_at)
        values (org, 'email', fingerprint_value, 'email_marketing_opt_out', marketing.effective_at)
        on conflict (organization_id, channel, fingerprint, kind) do update
        set opted_out_at = greatest(contact_opt_out_fingerprints.opted_out_at, excluded.opted_out_at);
      elsif marketing.state = 'opted_in' then
        delete from public.contact_opt_out_fingerprints
        where organization_id = org and channel = 'email' and fingerprint = fingerprint_value
          and kind = 'email_marketing_opt_out';
      end if;

      -- A blocked address becomes a fingerprint, and its plain row goes with the customer (an email belongs to
      -- one customer per business, so no one else still needs it).
      for suppression in
        select reason, created_at
        from public.communication_email_suppressions
        where organization_id = org and recipient_email = method.normalized_value and released_at is null
      loop
        insert into public.contact_opt_out_fingerprints (organization_id, channel, fingerprint, kind, opted_out_at)
        values (org, 'email', fingerprint_value, 'email_' || suppression.reason, suppression.created_at)
        on conflict (organization_id, channel, fingerprint, kind) do update
        set opted_out_at = greatest(contact_opt_out_fingerprints.opted_out_at, excluded.opted_out_at);
      end loop;

      delete from public.communication_email_suppressions
      where organization_id = org and recipient_email = method.normalized_value;
    end if;

    if preferences.contact_policy in ('no_marketing', 'do_not_disturb') then
      insert into public.contact_opt_out_fingerprints (organization_id, channel, fingerprint, kind, opted_out_at)
      values (org, method.kind, fingerprint_value, preferences.contact_policy, preferences.updated_at)
      on conflict (organization_id, channel, fingerprint, kind) do update
      set opted_out_at = greatest(contact_opt_out_fingerprints.opted_out_at, excluded.opted_out_at);
    elsif preferences.contact_policy = 'allow' then
      delete from public.contact_opt_out_fingerprints
      where organization_id = org and channel = method.kind and fingerprint = fingerprint_value
        and kind in ('no_marketing', 'do_not_disturb');
    end if;
  end loop;
end;
$$;

alter function private.record_client_opt_out_fingerprints(uuid, uuid) owner to postgres;
revoke all on function private.record_client_opt_out_fingerprints(uuid, uuid) from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------------------
-- 5. The receipt
-- ---------------------------------------------------------------------------------------------------------

-- What a permanent delete removed and kept, as counts only. The pending array holds the stored file copies
-- still to remove; the cleanup worker clears it when they are gone, and only then is the receipt completed.
-- Twilio's message log is not deleted (HighLevel deletes a contact's conversations only in its own app).
create table public.client_deletion_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  client_id uuid not null,
  trigger_kind text not null check (trigger_kind in ('delete_now', 'scheduled', 'platform_owner')),
  requested_by uuid references auth.users (id) on delete set null,
  requested_by_owner_email text check (
    requested_by_owner_email is null or char_length(btrim(requested_by_owner_email)) between 3 and 320
  ),
  reason text check (reason is null or char_length(btrim(reason)) between 3 and 1000),
  deleted_counts jsonb not null check (jsonb_typeof(deleted_counts) = 'object'),
  kept_counts jsonb not null check (jsonb_typeof(kept_counts) = 'object'),
  status text not null check (status in ('in_progress', 'completed', 'failed_partial')),
  component_results jsonb not null default '{}'::jsonb check (jsonb_typeof(component_results) = 'object'),
  pending_storage_object_keys text[],
  retry_count integer not null default 0 check (retry_count >= 0),
  last_error text check (last_error is null or char_length(last_error) <= 2000),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint client_deletion_receipts_client_fk foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete cascade,
  constraint client_deletion_receipts_completion check ((status = 'completed') = (completed_at is not null)),
  constraint client_deletion_receipts_platform_owner check (
    trigger_kind <> 'platform_owner' or (requested_by_owner_email is not null and reason is not null)
  )
);

create index client_deletion_receipts_client_idx
  on public.client_deletion_receipts (organization_id, client_id, created_at desc);
create index client_deletion_receipts_unfinished_idx
  on public.client_deletion_receipts (created_at) where status <> 'completed';

alter table public.client_deletion_receipts enable row level security;
revoke all on table public.client_deletion_receipts from anon, authenticated;

comment on table public.client_deletion_receipts is
  'One row per permanent customer delete: who, when, why, and counts of what went and what was kept. Never names, addresses or message content.';


-- ---------------------------------------------------------------------------------------------------------
-- 6. The plan
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.client_deletion_plan(target_organization_id uuid, target_client_id uuid)
  returns jsonb
  language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  org uuid := target_organization_id;
  c uuid := target_client_id;
  request_ids uuid[];
  quote_ids uuid[];
  shell_quote_ids uuid[];
  job_ids uuid[];
  visit_ids uuid[];
  assessment_ids uuid[];
  expense_ids uuid[];
  property_ids uuid[];
  shell_property_ids uuid[];
  draft_invoice_ids uuid[];
  kept_invoice_ids uuid[];
  opportunity_ids uuid[];
  review_request_ids uuid[];
  review_feedback_ids uuid[];
  inbound_message_ids uuid[];
  chat_session_ids uuid[];
  form_submission_ids uuid[];
  currency text;
  opening_receivable bigint := 0;
  opening_credit bigint := 0;
  payment_credit bigint;
  deposit_credit bigint;
  leftover bigint;
  blockers jsonb;
  counts jsonb;
  kept jsonb;
begin
  select coalesce(array_agg(id order by id), '{}') into request_ids
  from public.requests where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into quote_ids
  from public.quotes where organization_id = org and client_id = c;

  -- A quote that took a deposit or has a card checkout anchors money records (the deposit report and the
  -- invoice's payment list read the deposit through it), so it stays as an anonymous shell.
  select coalesce(array_agg(quote.id order by quote.id), '{}') into shell_quote_ids
  from public.quotes as quote
  where quote.organization_id = org and quote.client_id = c
    and (
      exists (
        select 1 from public.quote_deposit_events as deposit
        where deposit.organization_id = org and deposit.quote_id = quote.id
      )
      or exists (
        select 1 from public.payment_stripe_checkouts as checkout
        where checkout.organization_id = org and checkout.quote_id = quote.id
      )
    );

  select coalesce(array_agg(id order by id), '{}') into job_ids
  from public.jobs where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into visit_ids
  from public.job_visits where organization_id = org and job_id = any(job_ids);

  select coalesce(array_agg(id order by id), '{}') into assessment_ids
  from public.assessments where organization_id = org and request_id = any(request_ids);

  select coalesce(array_agg(id order by id), '{}') into expense_ids
  from public.job_expenses where organization_id = org and job_id = any(job_ids);

  select coalesce(array_agg(id order by id), '{}') into property_ids
  from public.properties where organization_id = org and client_id = c;

  select coalesce(array_agg(distinct property_id), '{}') into shell_property_ids
  from public.quotes where organization_id = org and id = any(shell_quote_ids);

  -- A settled bill is kept even if it was never issued, as delete_invoice_draft refuses it too.
  select coalesce(array_agg(id order by id) filter (where issued_at is null and recognized_at is null), '{}'),
         coalesce(array_agg(id order by id) filter (where issued_at is not null or recognized_at is not null), '{}')
  into draft_invoice_ids, kept_invoice_ids
  from public.invoices where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into opportunity_ids
  from public.opportunities where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into review_request_ids
  from public.review_requests where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into review_feedback_ids
  from public.review_feedback where organization_id = org and request_id = any(review_request_ids);

  select coalesce(array_agg(id order by id), '{}') into inbound_message_ids
  from public.communication_inbound_messages where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into chat_session_ids
  from public.website_chat_sessions where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into form_submission_ids
  from private.form_submissions where organization_id = org and result ->> 'client_id' = c::text;

  -- Money still open refuses the delete. An opening balance and unused credit settle against each other, so
  -- only what is left over between them counts.
  select coalesce(settings.currency_code, 'USD') into currency
  from public.organization_settings as settings where settings.organization_id = org;

  select coalesce(totals.receivable_minor, 0), coalesce(totals.credit_minor, 0)
  into opening_receivable, opening_credit
  from private.client_opening_balance_totals(org, array[c]) as totals;
  opening_receivable := coalesce(opening_receivable, 0);
  opening_credit := coalesce(opening_credit, 0);

  select coalesce(sum(private.payment_event_available_minor(org, receipt.id)), 0)::bigint into payment_credit
  from public.client_payment_events as receipt
  where receipt.organization_id = org and receipt.client_id = c and receipt.event_type = 'received';

  select coalesce(sum(private.deposit_event_available_minor(org, deposit.id)), 0)::bigint into deposit_credit
  from public.quote_deposit_events as deposit
  where deposit.organization_id = org and deposit.quote_id = any(quote_ids) and deposit.event_type = 'received';

  leftover := opening_receivable - opening_credit - payment_credit - deposit_credit;

  select coalesce(jsonb_agg(blocker - 'sort' order by blocker ->> 'sort'), '[]'::jsonb) into blockers
  from (
    select jsonb_build_object(
      'sort', 'a' || lpad(invoice.invoice_number::text, 12, '0'),
      'kind', 'invoice_unpaid',
      'label', 'Invoice #' || invoice.invoice_number
        || ' has an unpaid balance. Record the payment, void the invoice or write it off.',
      'invoice_id', invoice.id,
      'amount_minor', invoice.total_minor - coalesce(applied.amount_minor, 0),
      'currency_code', invoice.currency_code
    ) as blocker
    from public.invoices as invoice
    left join lateral (
      select sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end)
        as amount_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = org and entry.invoice_id = invoice.id
    ) as applied on true
    where invoice.organization_id = org and invoice.client_id = c and invoice.is_effective_receivable
      and invoice.total_minor - coalesce(applied.amount_minor, 0) > 0

    -- A payment or deposit applied to a draft is the customer's money on a bill that was never issued, so the
    -- draft cannot go with them; delete_invoice_draft refuses it the same way.
    union all
    select jsonb_build_object(
      'sort', 'a' || lpad(invoice.invoice_number::text, 12, '0'),
      'kind', 'draft_invoice_holds_money',
      'label', 'Draft invoice #' || invoice.invoice_number
        || ' has money on it. Return it to client credit, then apply it to an invoice or refund it.',
      'invoice_id', invoice.id,
      'amount_minor', private.invoice_allocated_minor(org, invoice.id),
      'currency_code', invoice.currency_code
    )
    from public.invoices as invoice
    where invoice.organization_id = org and invoice.client_id = c
      and invoice.id = any(draft_invoice_ids)
      and private.invoice_allocated_minor(org, invoice.id) <> 0

    union all
    select jsonb_build_object(
      'sort', 'b', 'kind', 'opening_balance_owed',
      'label', 'They still owe an opening balance. Record the payment first.',
      'amount_minor', leftover, 'currency_code', currency)
    where leftover > 0

    union all
    select jsonb_build_object(
      'sort', 'c', 'kind', 'credit_unused',
      'label', 'They have unused credit or a deposit. Apply it to an invoice or refund it first.',
      'amount_minor', -leftover, 'currency_code', currency)
    where leftover < 0

    union all
    select jsonb_build_object(
      'sort', 'd', 'kind', 'card_payment_in_progress',
      'label', 'A card payment is still being processed. Try again once it has finished.')
    where exists (
      select 1 from public.payment_stripe_checkouts
      where organization_id = org and client_id = c and status in ('open', 'processing')
    )

    union all
    select jsonb_build_object(
      'sort', 'e', 'kind', 'refund_in_progress',
      'label', 'A card refund is still being processed. Try again once it has finished.')
    where exists (
      select 1 from public.payment_stripe_refunds as refund
      join public.payment_stripe_checkouts as checkout
        on checkout.organization_id = refund.organization_id and checkout.id = refund.checkout_id
      where refund.organization_id = org and checkout.client_id = c and refund.status = 'pending'
    )

    union all
    select jsonb_build_object(
      'sort', 'f', 'kind', 'message_sending',
      'label', 'A message to this customer is being sent right now. Try again in a minute.')
    where exists (
      select 1 from public.communication_delivery_intents as intent
      where intent.organization_id = org and intent.client_id = c
        and (
          intent.status in ('claimed', 'submission_unknown')
          or exists (
            select 1 from public.communication_outbox_events as outbox
            where outbox.delivery_intent_id = intent.id and outbox.status = 'processing'
          )
        )
    )
  ) as found;

  with gone(entity_type, entity_id) as (
    select 'client', c
    union all select 'property', unnest(property_ids)
    union all select 'request', unnest(request_ids)
    union all select 'quote', unnest(quote_ids)
    union all select 'job', unnest(job_ids)
    union all select 'visit', unnest(visit_ids)
    union all select 'job_expense', unnest(expense_ids)
    union all select 'assessment', unnest(assessment_ids)
    union all select 'invoice', unnest(draft_invoice_ids)
    union all select 'opportunity', unnest(opportunity_ids)
  )
  select jsonb_build_object(
    'requests', cardinality(request_ids),
    'quotes', cardinality(quote_ids),
    'jobs', cardinality(job_ids),
    'visits', cardinality(visit_ids),
    'properties', cardinality(property_ids),
    'contact_methods', (
      select count(*) from public.client_contact_methods where organization_id = org and client_id = c
    ),
    'messages',
      (select count(*) from public.communication_delivery_intents where organization_id = org and client_id = c)
      + cardinality(inbound_message_ids)
      + (select count(*) from public.website_chat_messages where organization_id = org and client_id = c),
    'notes', (
      select count(distinct link.note_id) from public.note_links as link
      join gone on gone.entity_type = link.entity_type and gone.entity_id = link.entity_id
      where link.organization_id = org
    ),
    'files', (
      select count(distinct file_id) from (
        select link.file_id from public.file_links as link
        join gone on gone.entity_type = link.entity_type and gone.entity_id = link.entity_id
        where link.organization_id = org
        union all
        select attachment.file_id from public.attachments as attachment
        join gone on gone.entity_type = attachment.entity_type and gone.entity_id = attachment.entity_id
        where attachment.organization_id = org and attachment.file_id is not null
      ) as linked
    ),
    'review_requests', cardinality(review_request_ids),
    'opportunities', cardinality(opportunity_ids),
    'draft_invoices', cardinality(draft_invoice_ids)
  ) into counts;

  select jsonb_build_object(
    'invoices', cardinality(kept_invoice_ids),
    'payments', (
      select count(*) from public.client_payment_events where organization_id = org and client_id = c
    ),
    'deposits', (
      select count(*) from public.quote_deposit_events
      where organization_id = org and quote_id = any(shell_quote_ids)
    ),
    'opening_balances', (
      select count(*) from public.client_opening_balances where organization_id = org and client_id = c
    )
  ) into kept;

  return jsonb_build_object(
    'request_ids', to_jsonb(request_ids),
    'quote_ids', to_jsonb(quote_ids),
    'shell_quote_ids', to_jsonb(shell_quote_ids),
    'job_ids', to_jsonb(job_ids),
    'visit_ids', to_jsonb(visit_ids),
    'assessment_ids', to_jsonb(assessment_ids),
    'expense_ids', to_jsonb(expense_ids),
    'property_ids', to_jsonb(property_ids),
    'shell_property_ids', to_jsonb(shell_property_ids),
    'draft_invoice_ids', to_jsonb(draft_invoice_ids),
    'kept_invoice_ids', to_jsonb(kept_invoice_ids),
    'opportunity_ids', to_jsonb(opportunity_ids),
    'review_request_ids', to_jsonb(review_request_ids),
    'review_feedback_ids', to_jsonb(review_feedback_ids),
    'inbound_message_ids', to_jsonb(inbound_message_ids),
    'chat_session_ids', to_jsonb(chat_session_ids),
    'form_submission_ids', to_jsonb(form_submission_ids),
    'counts', counts,
    'kept', kept,
    'blockers', blockers
  );
end;
$$;

alter function private.client_deletion_plan(uuid, uuid) owner to postgres;
revoke all on function private.client_deletion_plan(uuid, uuid) from public, anon, authenticated;

comment on function private.client_deletion_plan(uuid, uuid) is
  'What a permanent delete of one customer removes, what it keeps for the money records, and what refuses it. The one rule behind both the confirmation and the delete, so they can never disagree.';


-- ---------------------------------------------------------------------------------------------------------
-- 7. The delete
-- ---------------------------------------------------------------------------------------------------------

-- Postgres checks every deleted row's references one by one. A customer with thousands of messages or hundreds
-- of jobs needs these lookups indexed, or each check reads the whole table (measured: the callback link read
-- every inbound message on the platform once per deleted callback).
create index communication_inbound_messages_callback_event_idx
  on public.communication_inbound_messages (provider_callback_event_id)
  where provider_callback_event_id is not null;

create index communication_sms_reconciliation_items_intent_idx
  on public.communication_sms_reconciliation_items (delivery_intent_id)
  where delivery_intent_id is not null;

create index job_checklist_items_job_idx
  on public.job_checklist_items (organization_id, job_id);

create index marketing_campaign_recipients_contact_method_idx
  on public.marketing_campaign_recipients (client_contact_method_id)
  where client_contact_method_id is not null;

-- The raw marketing email events are found only by the provider's message id.
create index marketing_campaign_recipient_events_message_idx
  on public.marketing_campaign_recipient_events (provider_message_id)
  where provider_message_id is not null;

create or replace function private.plan_uuids(plan jsonb, plan_key text) returns uuid[]
  language sql immutable
  set search_path to 'pg_catalog', 'public'
  as $$
  select coalesce(array(select jsonb_array_elements_text(plan -> plan_key)::uuid), '{}');
$$;

alter function private.plan_uuids(jsonb, text) owner to postgres;

create or replace function private.apply_client_purge(
  target_organization_id uuid,
  target_client_id uuid,
  purge_trigger_kind text,
  requested_by_user uuid default null,
  requested_by_owner_email text default null,
  purge_reason text default null
) returns jsonb
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  client_row public.clients;
  org uuid;
  c uuid;
  plan jsonb;
  request_ids uuid[];
  quote_ids uuid[];
  shell_quote_ids uuid[];
  job_ids uuid[];
  visit_ids uuid[];
  assessment_ids uuid[];
  expense_ids uuid[];
  property_ids uuid[];
  shell_property_ids uuid[];
  draft_invoice_ids uuid[];
  kept_invoice_ids uuid[];
  opportunity_ids uuid[];
  review_feedback_ids uuid[];
  inbound_message_ids uuid[];
  chat_session_ids uuid[];
  form_submission_ids uuid[];
  intent_ids uuid[];
  removed_note_ids uuid[];
  touched_file_ids uuid[];
  storage_keys text[];
  receipt public.client_deletion_receipts;
  storage_pending boolean;
begin
  if purge_trigger_kind not in ('delete_now', 'scheduled', 'platform_owner') then
    raise exception 'An invalid purge trigger kind was supplied.' using errcode = 'check_violation';
  end if;

  select * into client_row
  from public.clients
  where organization_id = target_organization_id and id = target_client_id
  for update;
  if client_row.id is null then
    raise exception 'That client could not be found.' using errcode = 'P0002';
  end if;
  org := client_row.organization_id;
  c := client_row.id;

  -- Running it twice is harmless: the second call finds the tombstone and hands back the first receipt.
  if client_row.purged_at is not null then
    return jsonb_build_object(
      'applied', false,
      'reason', 'already_purged',
      'receipt_id', (
        select id from public.client_deletion_receipts
        where organization_id = org and client_id = c order by created_at desc limit 1
      )
    );
  end if;

  plan := private.client_deletion_plan(org, c);
  if jsonb_array_length(plan -> 'blockers') > 0 then
    raise exception 'This client cannot be deleted yet: %',
      (select string_agg(blocker ->> 'label', ' ') from jsonb_array_elements(plan -> 'blockers') as blocker)
      using errcode = 'check_violation';
  end if;

  request_ids := private.plan_uuids(plan, 'request_ids');
  quote_ids := private.plan_uuids(plan, 'quote_ids');
  job_ids := private.plan_uuids(plan, 'job_ids');

  -- Lock the work, money and sends so nothing converts, invoices, pays or claims a message between the plan and
  -- the delete; then re-read the plan under those locks in case something did in the moment before.
  perform 1 from public.requests where organization_id = org and id = any(request_ids) for update;
  perform 1 from public.quotes where organization_id = org and id = any(quote_ids) for update;
  perform 1 from public.jobs where organization_id = org and id = any(job_ids) for update;
  perform 1 from public.invoices where organization_id = org and client_id = c for update;
  perform 1 from public.payment_stripe_checkouts where organization_id = org and client_id = c for update;
  perform 1 from public.communication_outbox_events as outbox
  where outbox.organization_id = org
    and outbox.delivery_intent_id in (
      select id from public.communication_delivery_intents where organization_id = org and client_id = c
    )
  for update;

  plan := private.client_deletion_plan(org, c);
  if jsonb_array_length(plan -> 'blockers') > 0
    or (plan -> 'request_ids') <> to_jsonb(request_ids)
    or (plan -> 'quote_ids') <> to_jsonb(quote_ids)
    or (plan -> 'job_ids') <> to_jsonb(job_ids) then
    raise exception 'This client''s records just changed. Reload and try again.' using errcode = 'P0409';
  end if;

  shell_quote_ids := private.plan_uuids(plan, 'shell_quote_ids');
  visit_ids := private.plan_uuids(plan, 'visit_ids');
  assessment_ids := private.plan_uuids(plan, 'assessment_ids');
  expense_ids := private.plan_uuids(plan, 'expense_ids');
  property_ids := private.plan_uuids(plan, 'property_ids');
  shell_property_ids := private.plan_uuids(plan, 'shell_property_ids');
  draft_invoice_ids := private.plan_uuids(plan, 'draft_invoice_ids');
  kept_invoice_ids := private.plan_uuids(plan, 'kept_invoice_ids');
  opportunity_ids := private.plan_uuids(plan, 'opportunity_ids');
  review_feedback_ids := private.plan_uuids(plan, 'review_feedback_ids');
  inbound_message_ids := private.plan_uuids(plan, 'inbound_message_ids');
  chat_session_ids := private.plan_uuids(plan, 'chat_session_ids');
  form_submission_ids := private.plan_uuids(plan, 'form_submission_ids');

  select coalesce(array_agg(id), '{}') into intent_ids
  from public.communication_delivery_intents where organization_id = org and client_id = c;

  perform set_config('app.client_purge_in_progress', 'true', true);

  -- 1. "Don't contact me" outlives the delete, before the consent rows it is read from go.
  perform private.record_client_opt_out_fingerprints(org, c);

  -- Every record that goes, by the type-and-id key that notes, files, tags, history, bell notifications and
  -- automations use. Kept invoices are listed too: their notes, tags, notifications and automations go, but the
  -- files on them stay with the invoice as issued.
  create temporary table if not exists client_purge_subjects (
    entity_type text not null,
    entity_id uuid not null,
    record_kept boolean not null
  ) on commit drop;
  truncate client_purge_subjects;

  insert into client_purge_subjects (entity_type, entity_id, record_kept)
  select 'client', c, false
  union all select 'property', unnest(property_ids), false
  union all select 'request', unnest(request_ids), false
  union all select 'quote', unnest(quote_ids), false
  union all select 'job', unnest(job_ids), false
  union all select 'visit', unnest(visit_ids), false
  union all select 'job_visit', unnest(visit_ids), false
  union all select 'job_expense', unnest(expense_ids), false
  union all select 'assessment', unnest(assessment_ids), false
  union all select 'invoice', unnest(draft_invoice_ids), false
  union all select 'invoice', unnest(kept_invoice_ids), true
  union all select 'opportunity', unnest(opportunity_ids), false
  union all select 'review_feedback', unnest(review_feedback_ids), false
  union all select 'inbound_message', unnest(inbound_message_ids), false
  -- A library file sent with a message is linked to the send record (the delivery intent).
  union all select 'message', unnest(intent_ids), false
  union all select 'website_chat_session', unnest(chat_session_ids), false
  union all select 'form_submission', unnest(form_submission_ids), false;

  -- 2. Automations, bell notifications and schedule notices about these records.
  delete from private.automation_enrollments as enrollment
  using client_purge_subjects as subject
  where enrollment.organization_id = org
    and enrollment.subject_type = subject.entity_type and enrollment.subject_id = subject.entity_id;

  delete from private.automation_events as event
  using client_purge_subjects as subject
  where event.organization_id = org
    and event.subject_type = subject.entity_type and event.subject_id = subject.entity_id;

  delete from public.automation_enrollment_command_receipts as command
  using client_purge_subjects as subject
  where command.organization_id = org
    and command.subject_type = subject.entity_type and command.subject_id = subject.entity_id;

  delete from public.team_notifications as notification
  using client_purge_subjects as subject
  where notification.organization_id = org
    and notification.subject_type = subject.entity_type and notification.subject_id = subject.entity_id;

  delete from private.appointment_schedule_changes
  where organization_id = org
    and ((booking_type = 'job' and booking_id = any(job_ids))
      or (booking_type = 'assessment' and booking_id = any(assessment_ids)));

  -- 3. Messages on every channel. A text Twilio already accepted is charged at its send-time price, because its
  -- final price can no longer reach a deleted message; a send still waiting gives its credit and allowance back.
  perform public.communication_sms_settle_reservation_price(reservation.delivery_intent_id, null, null, null)
  from public.communication_sms_credit_reservations as reservation
  join public.communication_delivery_intents as intent
    on intent.organization_id = reservation.organization_id and intent.id = reservation.delivery_intent_id
  where reservation.organization_id = org
    and reservation.delivery_intent_id = any(intent_ids)
    and reservation.state = 'reserved'
    and intent.status = 'submitted';

  perform private.communication_sms_release_reservation(reservation.delivery_intent_id)
  from public.communication_sms_credit_reservations as reservation
  where reservation.organization_id = org
    and reservation.delivery_intent_id = any(intent_ids)
    and reservation.state = 'reserved';

  update public.communication_email_capacity_reservations
  set reservation_state = 'released', settled_at = now()
  where delivery_intent_id = any(intent_ids) and reservation_state in ('reserved', 'submission_unknown');

  select coalesce(array_agg(distinct object_key) filter (where object_key is not null), '{}') into storage_keys
  from (
    select attachment.object_key
    from public.communication_outbound_attachments as attachment
    where attachment.organization_id = org and attachment.delivery_intent_id = any(intent_ids)
    union all
    select attachment.object_key
    from public.communication_inbound_attachments as attachment
    where attachment.organization_id = org and attachment.inbound_message_id = any(inbound_message_ids)
  ) as message_objects;

  -- The raw provider callbacks behind these messages hold the same phone numbers and text. Two deletes, so each
  -- uses its index; the platform-wide table is never read whole.
  delete from public.communication_provider_callback_events
  where delivery_intent_id = any(intent_ids);
  delete from public.communication_provider_callback_events
  where id in (
    select provider_callback_event_id from public.communication_inbound_messages
    where organization_id = org and id = any(inbound_message_ids) and provider_callback_event_id is not null
  );

  delete from public.communication_forward_events
  where organization_id = org
    and (client_id = c or source_inbound_message_id = any(inbound_message_ids));
  delete from public.communication_delivery_intents where organization_id = org and id = any(intent_ids);
  delete from public.communication_inbound_messages where organization_id = org and id = any(inbound_message_ids);
  delete from public.communication_reply_aliases where organization_id = org and client_id = c;
  delete from public.website_chat_messages
  where organization_id = org and (client_id = c or session_id = any(chat_session_ids));
  delete from public.website_chat_sessions where organization_id = org and id = any(chat_session_ids);
  update public.website_chat_sessions set candidate_client_id_by_phone = null
  where organization_id = org and candidate_client_id_by_phone = c;
  update public.website_chat_sessions set candidate_client_id_by_email = null
  where organization_id = org and candidate_client_id_by_email = c;
  delete from public.communication_messenger_identities where organization_id = org and client_id = c;
  delete from public.communication_conversation_assignments where organization_id = org and client_id = c;
  delete from public.communication_conversation_followers where organization_id = org and client_id = c;
  delete from public.communication_conversation_read_marks where organization_id = org and client_id = c;

  -- 4. Notes, tags and history. A note shared with a record that stays keeps living there; only notes left with
  -- no link at all go. The main statement still sees the links the CTE removed, so those are excluded by id.
  with removed_links as (
    delete from public.note_links as link
    using client_purge_subjects as subject
    where link.organization_id = org
      and link.entity_type = subject.entity_type and link.entity_id = subject.entity_id
    returning link.id, link.note_id
  ),
  removed_notes as (
    delete from public.notes as note
    where note.organization_id = org
      and note.id in (select note_id from removed_links)
      and not exists (
        select 1 from public.note_links as other
        where other.organization_id = org and other.note_id = note.id
          and other.id not in (select id from removed_links)
      )
    returning note.id
  )
  select coalesce(array_agg(id), '{}') into removed_note_ids from removed_notes;

  delete from public.tag_assignments as assignment
  using client_purge_subjects as subject
  where assignment.organization_id = org
    and assignment.entity_type = subject.entity_type and assignment.entity_id = subject.entity_id;

  delete from public.activity_events as event
  using client_purge_subjects as subject
  where event.organization_id = org
    and event.entity_type = subject.entity_type and event.entity_id = subject.entity_id;

  -- 5. Files: every file a removed record used is a candidate; step 9 deletes the ones left with no use.
  with removed_file_links as (
    delete from public.file_links as link
    using client_purge_subjects as subject
    where link.organization_id = org and not subject.record_kept
      and link.entity_type = subject.entity_type and link.entity_id = subject.entity_id
    returning link.file_id
  ),
  removed_attachments as (
    delete from public.attachments as attachment
    using client_purge_subjects as subject
    where attachment.organization_id = org and not subject.record_kept
      and attachment.entity_type = subject.entity_type and attachment.entity_id = subject.entity_id
    returning attachment.file_id, attachment.object_key, attachment.thumbnail_object_key
  ),
  legacy_objects as (
    -- An attachment from before the file catalog owns its own storage object.
    select unnest(array[object_key, thumbnail_object_key]) as object_key
    from removed_attachments where file_id is null
  ),
  collected as (
    select array(select object_key from legacy_objects where object_key is not null) as legacy_keys,
      array(
        select file_id from removed_file_links
        union select file_id from removed_attachments where file_id is not null
      ) as file_ids
  )
  select storage_keys || collected.legacy_keys, collected.file_ids
  into storage_keys, touched_file_ids
  from collected;

  select array(
    select distinct file_id from (
      select unnest(touched_file_ids) as file_id
      union all
      select file.id from public.files as file
      join client_purge_subjects as subject
        on subject.entity_type = file.origin_type and subject.entity_id = file.origin_id
      where file.organization_id = org and not subject.record_kept
      union all
      select line.image_file_id from public.request_pricing_lines as line
      where line.organization_id = org and line.request_id = any(request_ids)
      union all
      select line.image_file_id from public.quote_version_lines as line
      where line.organization_id = org and line.quote_id = any(quote_ids)
      union all
      select attachment.file_id from public.quote_version_attachments as attachment
      where attachment.organization_id = org and attachment.quote_id = any(quote_ids)
      union all
      select line.image_file_id from public.job_line_items as line
      where line.organization_id = org and line.job_id = any(job_ids)
      union all
      select line.image_file_id from public.job_visit_line_items as line
      where line.organization_id = org and line.job_id = any(job_ids)
      union all
      select photo.file_id from public.job_report_photos as photo
      where photo.organization_id = org and photo.job_id = any(job_ids)
      union all
      select item.file_id from public.file_share_items as item
      join public.file_shares as share on share.organization_id = item.organization_id and share.id = item.share_id
      where share.organization_id = org and share.client_id = c
    ) as candidates
    where file_id is not null
  ) into touched_file_ids;

  -- Signatures the customer drew.
  select storage_keys || coalesce(array_agg(image_object_key) filter (where image_object_key is not null), '{}')
  into storage_keys
  from (
    select image_object_key from public.quote_signatures
    where organization_id = org and quote_id = any(quote_ids)
    union all
    select image_object_key from public.job_signatures
    where organization_id = org and job_id = any(job_ids)
  ) as signatures;

  -- 6. Work. Jobs first: their invoice links go (the invoice keeps its own frozen lines, totals, customer and
  -- address), and report photos go before the cascade could reach the sections they are kept by.
  delete from public.invoice_sources where organization_id = org and client_id = c;
  delete from public.job_report_photos where organization_id = org and job_id = any(job_ids);
  delete from public.jobs where organization_id = org and id = any(job_ids);

  -- A quote kept for its deposit keeps only what the money reads: its number, status, currency and amounts.
  update public.quotes
  set title = 'Deleted client',
      request_id = null,
      conversion_idempotency_key = null,
      conversion_request_hash = null,
      decision_note = null,
      archive_reason = null
  where organization_id = org and id = any(shell_quote_ids);
  delete from public.quote_recipients where organization_id = org and quote_id = any(shell_quote_ids);
  delete from public.quote_decisions where organization_id = org and quote_id = any(shell_quote_ids);
  delete from public.quote_version_lines where organization_id = org and quote_id = any(shell_quote_ids);
  delete from public.quote_version_attachments where organization_id = org and quote_id = any(shell_quote_ids);
  delete from public.quote_version_schedule_items where organization_id = org and quote_id = any(shell_quote_ids);
  update public.quote_versions
  set client_display_name = 'Deleted client',
      service_address_line1 = null,
      service_address_line2 = null,
      service_city = null,
      service_state_region = null,
      service_postal_code = null,
      service_country = null,
      introduction = null,
      client_message = null
  where organization_id = org and quote_id = any(shell_quote_ids);

  delete from public.quotes
  where organization_id = org and id = any(quote_ids) and not id = any(shell_quote_ids);
  delete from public.requests where organization_id = org and id = any(request_ids);
  delete from public.opportunities where organization_id = org and id = any(opportunity_ids);
  delete from public.review_requests where organization_id = org and client_id = c;
  delete from public.file_shares where organization_id = org and client_id = c;

  -- Campaign send records are reached through the business's campaigns, which the campaign-and-customer index
  -- serves; the recipients table is shared by every business.
  delete from public.marketing_campaign_recipient_events as event
  where event.organization_id = org
    and event.provider_message_id in (
      select recipient.provider_message_id
      from public.marketing_campaigns as campaign
      join public.marketing_campaign_recipients as recipient
        on recipient.organization_id = campaign.organization_id and recipient.campaign_id = campaign.id
      where campaign.organization_id = org and recipient.client_id = c and recipient.provider_message_id is not null
    );
  delete from public.marketing_campaign_result_credits where organization_id = org and client_id = c;
  delete from public.marketing_campaign_recipients as recipient
  using public.marketing_campaigns as campaign
  where campaign.organization_id = org
    and recipient.organization_id = org and recipient.campaign_id = campaign.id and recipient.client_id = c;

  -- Draft invoices were never issued, so nothing requires keeping them.
  delete from public.invoice_events where organization_id = org and invoice_id = any(draft_invoice_ids);
  delete from public.invoices where organization_id = org and id = any(draft_invoice_ids);

  -- 7. Properties. One a kept quote still needs stays as a "Deleted" shell with no notes, people or map pin.
  delete from public.property_contacts where organization_id = org and property_id = any(shell_property_ids);
  update public.properties
  set label = null,
      address_line1 = 'Deleted',
      address_line2 = null,
      city = 'Deleted',
      state_region = null,
      postal_code = null,
      access_notes = null,
      latitude = null,
      longitude = null,
      geocode_status = 'failed',
      is_billing_address = false,
      deleted_at = coalesce(deleted_at, now())
  where organization_id = org and id = any(shell_property_ids);
  delete from public.properties
  where organization_id = org and client_id = c and not id = any(shell_property_ids);

  -- 8. The person: contacts, phones, emails, preferences and consent history.
  delete from public.client_marketing_consent_state where organization_id = org and client_id = c;
  delete from public.client_marketing_unsubscribe_links where organization_id = org and client_id = c;
  delete from public.client_marketing_consent_events where organization_id = org and client_id = c;
  delete from public.communication_sms_consent_events where organization_id = org and client_id = c;
  delete from public.client_communication_preferences where organization_id = org and client_id = c;
  delete from public.client_contact_methods where organization_id = org and client_id = c;
  delete from public.client_contacts where organization_id = org and client_id = c;

  -- 9. Files left with no use anywhere are deleted with their storage objects. A file uploaded somewhere else
  -- that was only linked to the customer (a File Manager document, a file filed into a folder) stays.
  with deletable as (
    select file.id, file.object_key, file.thumbnail_object_key
    from public.files as file
    where file.organization_id = org
      and file.id = any(touched_file_ids)
      and (
        exists (
          select 1 from client_purge_subjects as subject
          where not subject.record_kept
            and subject.entity_type = file.origin_type and subject.entity_id = file.origin_id
        )
        or (file.folder_id is null and file.origin_type <> 'file_manager')
      )
      and not exists (select 1 from public.file_links where organization_id = org and file_id = file.id)
      and not exists (select 1 from public.attachments where organization_id = org and file_id = file.id)
      and not exists (select 1 from public.note_files where organization_id = org and file_id = file.id)
      and not exists (select 1 from public.file_share_items where organization_id = org and file_id = file.id)
      and not exists (select 1 from public.catalog_items where organization_id = org and image_file_id = file.id)
      and not exists (select 1 from public.request_pricing_lines where organization_id = org and image_file_id = file.id)
      and not exists (select 1 from public.quote_version_lines where organization_id = org and image_file_id = file.id)
      and not exists (select 1 from public.quote_version_attachments where organization_id = org and file_id = file.id)
      and not exists (select 1 from public.job_line_items where organization_id = org and image_file_id = file.id)
      and not exists (select 1 from public.job_visit_line_items where organization_id = org and image_file_id = file.id)
      and not exists (select 1 from public.job_report_photos where organization_id = org and file_id = file.id)
  ),
  removed_files as (
    delete from public.files as file
    using deletable
    where file.id = deletable.id
    returning deletable.object_key, deletable.thumbnail_object_key
  )
  select storage_keys || coalesce(
    array_agg(key) filter (where key is not null), '{}'
  )
  into storage_keys
  from removed_files, unnest(array[removed_files.object_key, removed_files.thumbnail_object_key]) as key;

  -- 10. Other traces: merge snapshots of this same person, the rows their import came from, form submissions
  -- (and their photos), and the names and emails stored on the kept invoice and receipt links.
  delete from public.client_merges where organization_id = org and surviving_client_id = c;

  update public.import_rows as import_row
  set raw = '{}'::jsonb, resolved_payload = null, error_message = null
  from public.import_batches as batch
  where batch.organization_id = org
    and import_row.organization_id = org and import_row.batch_id = batch.id
    and (import_row.match_client_id = c or import_row.result_client_id = c);

  select storage_keys || coalesce(array_agg(photo_key) filter (where photo_key is not null), '{}')
  into storage_keys
  from private.form_submissions as submission, unnest(coalesce(submission.photo_object_keys, '{}')) as photo_key
  where submission.organization_id = org and submission.id = any(form_submission_ids);
  delete from private.form_submissions where organization_id = org and id = any(form_submission_ids);

  update public.invoice_access_links
  set recipient_name = null, recipient_email = null
  where organization_id = org and invoice_id = any(kept_invoice_ids)
    and (recipient_name is not null or recipient_email is not null);
  update public.payment_receipt_access_links
  set recipient_name = null, recipient_email = null
  where organization_id = org
    and client_payment_event_id in (
      select id from public.client_payment_events where organization_id = org and client_id = c
    )
    and (recipient_name is not null or recipient_email is not null);

  -- 11. The tombstone.
  update public.clients
  set display_name = 'Deleted client',
      first_name = null,
      last_name = null,
      company_name = null,
      lead_source = null,
      lead_temperature = null,
      next_follow_up_at = null,
      billing_payment_term_id = null,
      billing_address_line1 = null,
      billing_address_line2 = null,
      billing_city = null,
      billing_state_region = null,
      billing_postal_code = null,
      billing_country = null,
      deleted_at = coalesce(deleted_at, now()),
      purged_at = now()
  where id = c;

  -- 12. The receipt.
  select coalesce(array_agg(distinct key), '{}') into storage_keys from unnest(storage_keys) as key;
  storage_pending := cardinality(storage_keys) > 0;

  insert into public.client_deletion_receipts (
    organization_id, client_id, trigger_kind, requested_by, requested_by_owner_email, reason,
    deleted_counts, kept_counts, status, completed_at, component_results,
    pending_storage_object_keys
  ) values (
    org, c, purge_trigger_kind, requested_by_user, nullif(btrim(requested_by_owner_email), ''),
    nullif(btrim(purge_reason), ''),
    plan -> 'counts', plan -> 'kept',
    case when storage_pending then 'in_progress' else 'completed' end,
    case when storage_pending then null else now() end,
    jsonb_build_object(
      'database', 'succeeded',
      'storage_objects', case when storage_pending then 'pending' else 'not_applicable' end
    ),
    case when storage_pending then storage_keys end
  ) returning * into receipt;

  perform set_config('app.client_purge_in_progress', 'false', true);

  return jsonb_build_object(
    'applied', true,
    'receipt_id', receipt.id,
    'status', receipt.status,
    'deleted_counts', receipt.deleted_counts,
    'kept_counts', receipt.kept_counts
  );
end;
$$;

alter function private.apply_client_purge(uuid, uuid, text, uuid, text, text) owner to postgres;
revoke all on function private.apply_client_purge(uuid, uuid, text, uuid, text, text) from public, anon, authenticated;

comment on function private.apply_client_purge(uuid, uuid, text, uuid, text, text) is
  'Permanently deletes one customer: keeps issued invoices, payments, refunds, deposits, opening balances and card checkouts unchanged; leaves opt-out fingerprints; tombstones the client row; records a counts-only receipt with the provider copies still to remove. Refuses while money is open or a message is mid-send. Callers check permission first.';


-- ---------------------------------------------------------------------------------------------------------
-- 8. Entry point for the scheduled delete and Jafar's "Delete for them"
-- ---------------------------------------------------------------------------------------------------------

-- Server-only. The member-facing "Delete permanently now" gets its own permission-checked function in Part 7.
create or replace function public.run_client_purge(
  p_organization_id uuid,
  p_client_id uuid,
  p_trigger_kind text,
  p_requested_by uuid default null,
  p_requested_by_owner_email text default null,
  p_reason text default null
) returns jsonb
  language sql security definer
  set search_path to 'pg_catalog', 'public'
  -- Server calls otherwise inherit the API's 8-second limit; a customer with years of messages and jobs took
  -- 6-10 s on the dev database, and a cut-off delete rolls back and never finishes.
  set statement_timeout to '60s'
  as $$
  select private.apply_client_purge(
    p_organization_id, p_client_id, p_trigger_kind, p_requested_by, p_requested_by_owner_email, p_reason
  );
$$;

alter function public.run_client_purge(uuid, uuid, text, uuid, text, text) owner to postgres;
revoke all on function public.run_client_purge(uuid, uuid, text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.run_client_purge(uuid, uuid, text, uuid, text, text) to service_role;
