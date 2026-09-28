-- Merge one client into another, following Jobber's "Merge duplicate clients"
-- (help.getjobber.com/en/articles/merge-duplicate-clients, read 2026-09-28).
--
-- Jobber: the primary client survives and the secondary is deleted. Everything moves -- jobs, visits, quotes,
-- requests, invoices, statements, properties, communications, notes, contact details, tags. On a conflict the
-- primary's value wins; a value only the secondary has is copied over; emails, phones and tags are combined.
-- It cannot be undone, needs full client permission, and stays inside one account.
--
-- Jafar's choices on 2026-09-28: the secondary is deleted but a permanent merge record keeps who it was, and old
-- links to it open the survivor; money history moves too (only the client link changes -- a document the
-- customer already received keeps the name printed on it); any "stop" on either record survives the merge.
--
-- A phone or email belongs to at most one client per organization (client_contact_methods_org_value_unique_idx),
-- so the two clients never share a contact method: every method, and the consent history hanging off it, simply
-- moves.
--
-- Pieces:
--   public.client_merges                      -- the permanent record of each merge
--   marketing_campaign_recipients             -- a merged client may hold two sends of one past campaign
--   four composite keys become deferrable     -- so a method or payment and the rows citing it move together
--   private.client_merge_in_progress()        -- history guards step aside for a client-link-only change
--   private.client_merge_plan / public.client_merge_preview / public.merge_clients
--   public.resolve_merged_client              -- where an old link to a merged client should go

-- ---------------------------------------------------------------------------------------------------------
-- 1. The merge record
-- ---------------------------------------------------------------------------------------------------------

-- No foreign key to clients on either side: the merged client is deleted by the merge, and the survivor may
-- itself be merged later, so its row is followed as a chain rather than cascaded away.
create table public.client_merges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  surviving_client_id uuid not null,
  merged_client_id uuid not null unique,
  -- Who the merged client was: names, phones, emails, addresses. Enough to answer "where did Jon go?".
  merged_client_snapshot jsonb not null,
  -- How many of each kind of record moved.
  moved jsonb not null,
  merged_by uuid,
  merged_at timestamptz not null default now(),
  constraint client_merges_distinct check (surviving_client_id <> merged_client_id)
);

create index client_merges_surviving_idx on public.client_merges (organization_id, surviving_client_id);

alter table public.client_merges enable row level security;

create policy "permitted members can view client merges"
  on public.client_merges
  for select
  to authenticated
  using (organization_id in (select private.permitted_organizations('customers.view')));

-- Only public.merge_clients writes here.
revoke all on table public.client_merges from anon, authenticated;
grant select on table public.client_merges to authenticated;

comment on table public.client_merges is
  'One row per client merge: the survivor, the deleted duplicate''s identity, what moved, who and when. Written only by public.merge_clients.';


-- ---------------------------------------------------------------------------------------------------------
-- 2. A merged client can hold two sends of one past campaign
-- ---------------------------------------------------------------------------------------------------------

-- The recipient row is the send record (provider message id, delivery, unsubscribe link), so when both
-- duplicates received the same campaign both rows are kept. merged_from_client_id tells them apart; a fresh
-- audience row always has it null, so one send per client per campaign still holds for new campaigns.
alter table public.marketing_campaign_recipients add column merged_from_client_id uuid;

alter table public.marketing_campaign_recipients
  drop constraint marketing_campaign_recipients_campaign_client_key;
alter table public.marketing_campaign_recipients
  add constraint marketing_campaign_recipients_campaign_client_key
  unique nulls not distinct (campaign_id, client_id, merged_from_client_id);


-- ---------------------------------------------------------------------------------------------------------
-- 3. Keys that carry the client id on both sides are checked at the end of a merge
-- ---------------------------------------------------------------------------------------------------------

-- Each of these cites (organization, client, row). Moving the cited row and the citing rows is two statements,
-- so the check waits for the end of the transaction -- but only when public.merge_clients asks it to.
-- INITIALLY IMMEDIATE keeps every other write checked exactly as before.
alter table public.client_marketing_consent_events
  alter constraint client_marketing_consent_events_method_fk deferrable initially immediate;
alter table public.client_marketing_unsubscribe_links
  alter constraint client_marketing_unsubscribe_links_method_fk deferrable initially immediate;
alter table public.communication_sms_consent_events
  alter constraint communication_sms_consent_events_method_fk deferrable initially immediate;
alter table public.invoice_payment_allocations
  alter constraint invoice_payment_allocations_payment_fk deferrable initially immediate;


-- ---------------------------------------------------------------------------------------------------------
-- 4. History guards step aside for a client-link-only change during a merge
-- ---------------------------------------------------------------------------------------------------------

-- A transaction-local setting only public.merge_clients turns on, and turns off again before it returns.
-- PostgREST cannot set arbitrary settings, so a caller cannot reach it except through that checked function.
create or replace function private.client_merge_in_progress() returns boolean
  language sql stable
  set search_path to 'pg_catalog', 'public'
  as $$
  select coalesce(current_setting('app.client_merge_in_progress', true), '') = 'true';
$$;

alter function private.client_merge_in_progress() owner to postgres;

-- True when the only thing an update changes is which client the row belongs to.
create or replace function private.only_client_link_changed(old_row jsonb, new_row jsonb) returns boolean
  language sql immutable
  set search_path to 'pg_catalog', 'public'
  as $$
  select (old_row - 'client_id' - 'updated_at') = (new_row - 'client_id' - 'updated_at');
$$;

alter function private.only_client_link_changed(jsonb, jsonb) owner to postgres;

create or replace function private.invoice_events_are_append_only() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_op = 'UPDATE' and private.client_merge_in_progress()
     and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  raise exception 'Invoice history is append-only.' using errcode = 'check_violation';
end;
$$;

create or replace function private.payment_history_is_append_only() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if tg_op = 'UPDATE' and private.client_merge_in_progress()
     and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  raise exception 'Payment history is append-only. Correct it by recording a correction.'
    using errcode = 'check_violation';
end;
$$;

create or replace function private.invoice_sources_are_immutable() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if private.client_merge_in_progress() and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  raise exception 'A billing claim cannot be edited. Delete the draft or correct the invoice instead.'
    using errcode = 'check_violation';
end;
$$;

create or replace function private.invoices_guard_identity() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if private.client_merge_in_progress() and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  if new.organization_id is distinct from old.organization_id then
    raise exception 'An invoice cannot be moved to another organization.' using errcode = 'check_violation';
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'An invoice cannot be moved to another client.' using errcode = 'check_violation';
  end if;
  if new.invoice_number is distinct from old.invoice_number then
    raise exception 'An invoice number cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.root_invoice_id is distinct from old.root_invoice_id
     or new.predecessor_invoice_id is distinct from old.predecessor_invoice_id then
    raise exception 'An invoice cannot be moved to another correction chain.'
      using errcode = 'check_violation';
  end if;
  if new.currency_code is distinct from old.currency_code and old.document_frozen_at is not null then
    raise exception 'An issued invoice''s currency cannot be changed.' using errcode = 'check_violation';
  end if;
  if old.issued_at is not null and new.issued_at is distinct from old.issued_at then
    raise exception 'An invoice that has been issued cannot be un-issued.' using errcode = 'check_violation';
  end if;
  if old.recognized_at is not null and new.recognized_at is distinct from old.recognized_at then
    raise exception 'A settled invoice cannot be un-settled.' using errcode = 'check_violation';
  end if;
  if old.voided_at is not null then
    if new.voided_at is distinct from old.voided_at then
      raise exception 'A voided invoice cannot be reopened.' using errcode = 'check_violation';
    end if;
    if to_jsonb(new) - 'replaced_at' - 'replaced_by_invoice_id' - 'frozen_status_label' - 'updated_at'
         - 'is_effective_receivable'
       is distinct from
       to_jsonb(old) - 'replaced_at' - 'replaced_by_invoice_id' - 'frozen_status_label' - 'updated_at'
         - 'is_effective_receivable' then
      raise exception 'A voided invoice cannot be changed.' using errcode = 'check_violation';
    end if;
  end if;
  if old.replaced_at is not null then
    if new.replaced_at is distinct from old.replaced_at
       or new.replaced_by_invoice_id is distinct from old.replaced_by_invoice_id
       or new.frozen_status_label is distinct from old.frozen_status_label then
      raise exception 'A replaced invoice''s history cannot be rewritten.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create or replace function private.jobs_guard_identity_and_transitions() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if private.client_merge_in_progress() and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  if new.organization_id is distinct from old.organization_id then
    raise exception 'A job cannot be moved to another organization.' using errcode = 'check_violation';
  end if;
  if new.job_number is distinct from old.job_number then
    raise exception 'A job number cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.job_type is distinct from old.job_type or new.is_as_needed is distinct from old.is_as_needed then
    raise exception 'A job type cannot be changed after the job is created. Create a new job instead.'
      using errcode = 'check_violation';
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'A job cannot be moved to another client.' using errcode = 'check_violation';
  end if;
  -- Lineage is permanent in both directions: a converted job can never forget its quote, and a direct job can
  -- never claim one it did not come from.
  if new.quote_id is distinct from old.quote_id or new.quote_version_id is distinct from old.quote_version_id then
    raise exception 'Quote lineage cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'A job creation time cannot be changed.' using errcode = 'check_violation';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'active' and new.status = 'closed')
      or (old.status = 'closed' and new.status = 'active')
    ) then
      raise exception 'A job cannot go from % to %.', old.status, new.status
        using errcode = 'check_violation';
    end if;

    if new.status = 'closed' and new.closed_at is null then
      new.closed_at := now();
    end if;
    if new.status = 'active' then
      new.closed_at := null;
      new.closed_by := null;
      new.reopened_at := now();
    end if;
  end if;

  return new;
end;
$$;

-- A merge only removes a client file link when the survivor already holds the same file in the same role.
create or replace function private.file_links_protect_history() returns trigger
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if old.protected and not private.property_delete_in_progress() and not private.client_merge_in_progress() then
    raise exception 'This file is part of a document the customer already received and cannot be removed from it.'
      using errcode = '23503';
  end if;
  return old;
end;
$$;

create or replace function private.client_opening_balances_guard_identity() returns trigger
  language plpgsql
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  if private.client_merge_in_progress() and private.only_client_link_changed(to_jsonb(old), to_jsonb(new)) then
    return new;
  end if;
  if new.organization_id is distinct from old.organization_id
     or new.client_id is distinct from old.client_id
     or new.balance_type is distinct from old.balance_type
     or new.amount_minor is distinct from old.amount_minor
     or new.currency_code is distinct from old.currency_code
     or new.as_of_date is distinct from old.as_of_date
     or new.import_batch_id is distinct from old.import_batch_id
     or new.import_row_id is distinct from old.import_row_id
     or new.root_opening_balance_id is distinct from old.root_opening_balance_id
     or new.predecessor_opening_balance_id is distinct from old.predecessor_opening_balance_id then
    raise exception 'An opening balance fact cannot be changed, only corrected by a new linked fact.'
      using errcode = 'check_violation';
  end if;
  if old.replaced_at is not null
     and (new.replaced_at is distinct from old.replaced_at
          or new.replaced_by_opening_balance_id is distinct from old.replaced_by_opening_balance_id) then
    raise exception 'A replaced opening balance fact cannot be changed.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;


-- ---------------------------------------------------------------------------------------------------------
-- 5. The plan: what would move, what it changes, and what refuses it
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.client_merge_plan(
  primary_row public.clients,
  secondary_row public.clients
) returns jsonb
  language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  org uuid := primary_row.organization_id;
  secondary_id uuid := secondary_row.id;
  moves jsonb;
  warnings jsonb := '[]'::jsonb;
  blockers jsonb := '[]'::jsonb;
  primary_prefs public.client_communication_preferences;
  secondary_prefs public.client_communication_preferences;
  primary_opted_out boolean;
  secondary_opted_out boolean;
begin
  select jsonb_build_object(
    'properties', (select count(*) from public.properties where organization_id = org and client_id = secondary_id and deleted_at is null),
    'contacts', (select count(*) from public.client_contacts where organization_id = org and client_id = secondary_id),
    'phones', (select count(*) from public.client_contact_methods where organization_id = org and client_id = secondary_id and kind = 'phone'),
    'emails', (select count(*) from public.client_contact_methods where organization_id = org and client_id = secondary_id and kind = 'email'),
    'requests', (select count(*) from public.requests where organization_id = org and client_id = secondary_id),
    'quotes', (select count(*) from public.quotes where organization_id = org and client_id = secondary_id),
    'jobs', (select count(*) from public.jobs where organization_id = org and client_id = secondary_id),
    'invoices', (select count(*) from public.invoices where organization_id = org and client_id = secondary_id),
    'payments', (select count(*) from public.client_payment_events where organization_id = org and client_id = secondary_id),
    'messages',
      (select count(*) from public.communication_delivery_intents where organization_id = org and client_id = secondary_id)
      + (select count(*) from public.communication_inbound_messages where organization_id = org and client_id = secondary_id)
      + (select count(*) from public.website_chat_messages where organization_id = org and client_id = secondary_id),
    'notes', (select count(*) from public.note_links where organization_id = org and entity_type = 'client' and entity_id = secondary_id),
    'files',
      (select count(*) from public.file_links where organization_id = org and entity_type = 'client' and entity_id = secondary_id)
      + (select count(*) from public.attachments where organization_id = org and entity_type = 'client' and entity_id = secondary_id),
    'tags', (select count(*) from public.tag_assignments where organization_id = org and entity_type = 'client' and entity_id = secondary_id)
  ) into moves;

  -- Jobber refuses while a card payment is still being settled for either client.
  if exists (
    select 1 from public.payment_stripe_checkouts
    where organization_id = org and client_id in (primary_row.id, secondary_id) and status in ('open', 'processing')
  ) then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'kind', 'card_payment_in_progress',
      'label', 'A card payment is still being processed. Try again once it has finished.'));
  end if;

  select * into primary_prefs from public.client_communication_preferences
  where organization_id = org and client_id = primary_row.id;
  select * into secondary_prefs from public.client_communication_preferences
  where organization_id = org and client_id = secondary_id;

  primary_opted_out := primary_prefs.sms_opt_out_at is not null
    and (primary_prefs.sms_opt_in_at is null or primary_prefs.sms_opt_in_at < primary_prefs.sms_opt_out_at);
  secondary_opted_out := secondary_prefs.sms_opt_out_at is not null
    and (secondary_prefs.sms_opt_in_at is null or secondary_prefs.sms_opt_in_at < secondary_prefs.sms_opt_out_at);

  if secondary_opted_out and not primary_opted_out then
    warnings := warnings || jsonb_build_array(jsonb_build_object('kind', 'sms_opt_out',
      'label', secondary_row.display_name || ' asked not to be texted, so ' || primary_row.display_name
        || ' will not be texted either.'));
  end if;

  if secondary_prefs.contact_policy is not null
     and array_position(array['allow', 'no_marketing', 'do_not_disturb'], secondary_prefs.contact_policy)
       > array_position(array['allow', 'no_marketing', 'do_not_disturb'], coalesce(primary_prefs.contact_policy, 'allow')) then
    warnings := warnings || jsonb_build_array(jsonb_build_object('kind', 'contact_policy',
      'label', case secondary_prefs.contact_policy
        when 'do_not_disturb' then secondary_row.display_name || ' is marked Do not disturb, and the merged client will be too.'
        else secondary_row.display_name || ' is marked No marketing, and the merged client will be too.'
      end));
  end if;

  if (secondary_prefs.appointment_reminders is false and primary_prefs.appointment_reminders is not false)
     or (secondary_prefs.quote_follow_ups is false and primary_prefs.quote_follow_ups is not false)
     or (secondary_prefs.invoice_reminders is false and primary_prefs.invoice_reminders is not false)
     or (secondary_prefs.job_follow_ups is false and primary_prefs.job_follow_ups is not false)
     or (secondary_prefs.review_requests is false and primary_prefs.review_requests is not false) then
    warnings := warnings || jsonb_build_array(jsonb_build_object('kind', 'notifications_off',
      'label', 'Automatic messages ' || secondary_row.display_name
        || ' had turned off stay off for the merged client.'));
  end if;

  if primary_row.lifecycle_status = 'lead' and secondary_row.lifecycle_status = 'customer' then
    warnings := warnings || jsonb_build_array(jsonb_build_object('kind', 'becomes_customer',
      'label', primary_row.display_name || ' becomes a customer, because ' || secondary_row.display_name
        || ' already is one.'));
  end if;

  if primary_row.archived_at is not null and secondary_row.archived_at is null then
    warnings := warnings || jsonb_build_array(jsonb_build_object('kind', 'restores_archived',
      'label', primary_row.display_name || ' is archived and will be restored, because '
        || secondary_row.display_name || ' is active.'));
  end if;

  return jsonb_build_object('moves', moves, 'warnings', warnings, 'blockers', blockers);
end;
$$;

alter function private.client_merge_plan(public.clients, public.clients) owner to postgres;
revoke all on function private.client_merge_plan(public.clients, public.clients) from public, anon, authenticated;

comment on function private.client_merge_plan(public.clients, public.clients) is
  'What merging the secondary client into the primary would move, the preference changes it brings, and what refuses it. The one rule behind the preview and the merge.';


-- The same access check for the preview and the merge. Both clients must be live, in one organization the
-- caller can merge in, and visible to the caller. A client the caller cannot see reads as not found.
create or replace function private.load_clients_for_merge(
  p_primary_client_id uuid,
  p_secondary_client_id uuid,
  lock_rows boolean,
  out primary_row public.clients,
  out secondary_row public.clients
)
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  caller uuid := (select auth.uid());
begin
  if p_primary_client_id is null or p_secondary_client_id is null
     or p_primary_client_id = p_secondary_client_id then
    raise exception 'Choose two different clients to merge.' using errcode = '22023';
  end if;

  -- Lock in id order so two merges touching the same pair cannot deadlock.
  if lock_rows then
    perform 1 from public.clients
    where id in (p_primary_client_id, p_secondary_client_id)
    order by id
    for update;
  end if;

  select * into primary_row from public.clients where id = p_primary_client_id and deleted_at is null;
  select * into secondary_row from public.clients where id = p_secondary_client_id and deleted_at is null;

  if primary_row.id is null or secondary_row.id is null
     or primary_row.organization_id <> secondary_row.organization_id
     or caller is null
     or not private.can_view_client(primary_row.organization_id, primary_row.id)
     or not private.can_view_client(secondary_row.organization_id, secondary_row.id) then
    raise exception 'That client could not be found.' using errcode = 'P0002';
  end if;

  if not private.member_has_permission(primary_row.organization_id, caller, 'customers.merge') then
    raise exception 'You do not have access to merge clients.' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

alter function private.load_clients_for_merge(uuid, uuid, boolean) owner to postgres;
revoke all on function private.load_clients_for_merge(uuid, uuid, boolean) from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------------------
-- 6. The preview the confirmation screen reads
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.client_merge_preview(p_primary_client_id uuid, p_secondary_client_id uuid)
  returns jsonb
  language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  loaded record;
  plan jsonb;
begin
  select * into loaded from private.load_clients_for_merge(p_primary_client_id, p_secondary_client_id, false);
  plan := private.client_merge_plan(loaded.primary_row, loaded.secondary_row);

  return jsonb_build_object(
    'moves', plan -> 'moves',
    'warnings', (select coalesce(jsonb_agg(item ->> 'label'), '[]'::jsonb) from jsonb_array_elements(plan -> 'warnings') as item),
    'blockers', (select coalesce(jsonb_agg(item ->> 'label'), '[]'::jsonb) from jsonb_array_elements(plan -> 'blockers') as item)
  );
end;
$$;

alter function public.client_merge_preview(uuid, uuid) owner to postgres;
revoke all on function public.client_merge_preview(uuid, uuid) from public, anon;
grant execute on function public.client_merge_preview(uuid, uuid) to authenticated, service_role;


-- ---------------------------------------------------------------------------------------------------------
-- 7. The merge
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.merge_clients(p_primary_client_id uuid, p_secondary_client_id uuid)
  returns jsonb
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  loaded record;
  primary_row public.clients;
  secondary_row public.clients;
  org uuid;
  p uuid;
  s uuid;
  plan jsonb;
  snapshot jsonb;
  primary_prefs public.client_communication_preferences;
  secondary_prefs public.client_communication_preferences;
  primary_opted_out boolean;
  secondary_opted_out boolean;
  merge_id uuid;
begin
  select * into loaded from private.load_clients_for_merge(p_primary_client_id, p_secondary_client_id, true);
  primary_row := loaded.primary_row;
  secondary_row := loaded.secondary_row;
  org := primary_row.organization_id;
  p := primary_row.id;
  s := secondary_row.id;

  -- Hold any card checkout still settling for either client, then ask the plan under that lock, so a payment
  -- cannot start landing between the check and the move.
  perform 1 from public.payment_stripe_checkouts
  where organization_id = org and client_id in (p, s)
  for update;

  plan := private.client_merge_plan(primary_row, secondary_row);
  if jsonb_array_length(plan -> 'blockers') > 0 then
    raise exception 'These clients cannot be merged: %',
      (select string_agg(item ->> 'label', ' ') from jsonb_array_elements(plan -> 'blockers') as item)
      using errcode = 'check_violation';
  end if;

  -- Who the duplicate was, kept forever on the merge record.
  select jsonb_build_object(
    'display_name', secondary_row.display_name,
    'first_name', secondary_row.first_name,
    'last_name', secondary_row.last_name,
    'company_name', secondary_row.company_name,
    'client_type', secondary_row.client_type,
    'lifecycle_status', secondary_row.lifecycle_status,
    'lead_source', secondary_row.lead_source,
    'created_at', secondary_row.created_at,
    'contact_methods', coalesce((
      select jsonb_agg(jsonb_build_object('kind', kind, 'value', value, 'label', label) order by kind, created_at)
      from public.client_contact_methods where organization_id = org and client_id = s
    ), '[]'::jsonb),
    'properties', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'address_line1', address_line1, 'city', city, 'postal_code', postal_code) order by created_at)
      from public.properties where organization_id = org and client_id = s
    ), '[]'::jsonb)
  ) into snapshot;

  perform set_config('app.client_merge_in_progress', 'true', true);
  set constraints
    public.client_marketing_consent_events_method_fk,
    public.client_marketing_unsubscribe_links_method_fk,
    public.communication_sms_consent_events_method_fk,
    public.invoice_payment_allocations_payment_fk
    deferred;

  -- The client row: the primary's values win; a blank on the primary is filled from the secondary.
  update public.clients as c set
    first_name = coalesce(c.first_name, secondary_row.first_name),
    last_name = coalesce(c.last_name, secondary_row.last_name),
    company_name = coalesce(c.company_name, secondary_row.company_name),
    lead_source = coalesce(c.lead_source, secondary_row.lead_source),
    lead_temperature = coalesce(c.lead_temperature, secondary_row.lead_temperature),
    next_follow_up_at = coalesce(c.next_follow_up_at, secondary_row.next_follow_up_at),
    billing_payment_term_id = coalesce(c.billing_payment_term_id, secondary_row.billing_payment_term_id),
    -- Once either was a customer, the merged client is one, dated from the earlier conversion.
    lifecycle_status = case when secondary_row.lifecycle_status = 'customer' then 'customer' else c.lifecycle_status end,
    converted_to_customer_at = case
      when c.converted_to_customer_at is null then secondary_row.converted_to_customer_at
      when secondary_row.converted_to_customer_at is null then c.converted_to_customer_at
      else least(c.converted_to_customer_at, secondary_row.converted_to_customer_at)
    end,
    -- Stays archived only if both were: live work from the secondary brings the survivor back, as new work does.
    archived_at = case when secondary_row.archived_at is null then null else c.archived_at end,
    -- The billing address is one whole address, so it is taken whole or not at all.
    billing_address_line1 = case when c.billing_address_line1 is null then secondary_row.billing_address_line1 else c.billing_address_line1 end,
    billing_address_line2 = case when c.billing_address_line1 is null then secondary_row.billing_address_line2 else c.billing_address_line2 end,
    billing_city = case when c.billing_address_line1 is null then secondary_row.billing_city else c.billing_city end,
    billing_state_region = case when c.billing_address_line1 is null then secondary_row.billing_state_region else c.billing_state_region end,
    billing_postal_code = case when c.billing_address_line1 is null then secondary_row.billing_postal_code else c.billing_postal_code end,
    billing_country = case when c.billing_address_line1 is null then secondary_row.billing_country else c.billing_country end
  where c.id = p;

  -- Preferences: any "stop" on either record survives (Jafar, 2026-09-28).
  select * into primary_prefs from public.client_communication_preferences where organization_id = org and client_id = p;
  select * into secondary_prefs from public.client_communication_preferences where organization_id = org and client_id = s;
  primary_opted_out := primary_prefs.sms_opt_out_at is not null
    and (primary_prefs.sms_opt_in_at is null or primary_prefs.sms_opt_in_at < primary_prefs.sms_opt_out_at);
  secondary_opted_out := secondary_prefs.sms_opt_out_at is not null
    and (secondary_prefs.sms_opt_in_at is null or secondary_prefs.sms_opt_in_at < secondary_prefs.sms_opt_out_at);

  if secondary_prefs.client_id is not null then
    update public.client_communication_preferences as pref set
      appointment_reminders = pref.appointment_reminders and secondary_prefs.appointment_reminders,
      quote_follow_ups = pref.quote_follow_ups and secondary_prefs.quote_follow_ups,
      invoice_reminders = pref.invoice_reminders and secondary_prefs.invoice_reminders,
      job_follow_ups = pref.job_follow_ups and secondary_prefs.job_follow_ups,
      review_requests = pref.review_requests and secondary_prefs.review_requests,
      contact_policy = case
        when array_position(array['allow', 'no_marketing', 'do_not_disturb'], secondary_prefs.contact_policy)
           > array_position(array['allow', 'no_marketing', 'do_not_disturb'], pref.contact_policy)
        then secondary_prefs.contact_policy else pref.contact_policy end,
      sms_opt_out_at = case when secondary_opted_out and not primary_opted_out then secondary_prefs.sms_opt_out_at else pref.sms_opt_out_at end,
      sms_opt_in_at = case when secondary_opted_out and not primary_opted_out then secondary_prefs.sms_opt_in_at else pref.sms_opt_in_at end,
      opt_out_source = case when secondary_opted_out and not primary_opted_out then secondary_prefs.opt_out_source else pref.opt_out_source end
    where pref.organization_id = org and pref.client_id = p;
  end if;

  -- Contact people and their phones and emails. The survivor keeps its own primary and billing choices.
  update public.client_contacts set
    client_id = p,
    is_primary = is_primary and not exists (
      select 1 from public.client_contacts where organization_id = org and client_id = p and is_primary)
  where organization_id = org and client_id = s;

  update public.client_contact_methods as method set
    client_id = p,
    is_primary = method.is_primary and not exists (
      select 1 from public.client_contact_methods as mine
      where mine.organization_id = org and mine.client_id = p and mine.kind = method.kind and mine.is_primary),
    is_billing_contact = method.is_billing_contact and not exists (
      select 1 from public.client_contact_methods as mine
      where mine.organization_id = org and mine.client_id = p and mine.is_billing_contact)
  where method.organization_id = org and method.client_id = s;

  update public.client_marketing_consent_events set client_id = p where organization_id = org and client_id = s;
  update public.client_marketing_consent_state set client_id = p where organization_id = org and client_id = s;
  update public.client_marketing_unsubscribe_links set client_id = p where organization_id = org and client_id = s;
  update public.communication_sms_consent_events set client_id = p where organization_id = org and client_id = s;

  -- Properties. The primary-property row moves on its own first: a non-primary row arriving at a client with no
  -- properties would otherwise be promoted by properties_set_first_primary and collide with it.
  update public.properties set
    client_id = p,
    is_primary = not exists (
      select 1 from public.properties where organization_id = org and client_id = p and deleted_at is null),
    is_billing_address = is_billing_address and not exists (
      select 1 from public.properties where organization_id = org and client_id = p and is_billing_address)
  where organization_id = org and client_id = s and is_primary;

  update public.properties set
    client_id = p,
    is_primary = false,
    is_billing_address = is_billing_address and not exists (
      select 1 from public.properties where organization_id = org and client_id = p and is_billing_address)
  where organization_id = org and client_id = s;

  -- Work and money. Only the client link changes; numbers, statuses and frozen documents stay as they were.
  update public.requests set client_id = p where organization_id = org and client_id = s;
  update public.opportunities set client_id = p where organization_id = org and client_id = s;
  update public.quotes set client_id = p where organization_id = org and client_id = s;
  update public.jobs set client_id = p where organization_id = org and client_id = s;
  update public.invoices set client_id = p where organization_id = org and client_id = s;
  update public.invoice_sources set client_id = p where organization_id = org and client_id = s;
  update public.invoice_events set client_id = p where organization_id = org and client_id = s;
  update public.client_payment_events set client_id = p where organization_id = org and client_id = s;
  update public.invoice_payment_allocations set client_id = p where organization_id = org and client_id = s;
  update public.client_opening_balances set client_id = p where organization_id = org and client_id = s;
  update public.payment_stripe_checkouts set client_id = p where organization_id = org and client_id = s;

  -- Conversations: the two threads become one.
  update public.communication_delivery_intents set client_id = p where organization_id = org and client_id = s;
  update public.communication_inbound_messages set client_id = p where organization_id = org and client_id = s;
  update public.communication_reply_aliases set client_id = p where organization_id = org and client_id = s;
  update public.communication_forward_events set client_id = p where organization_id = org and client_id = s;
  update public.website_chat_sessions set client_id = p where organization_id = org and client_id = s;
  update public.website_chat_sessions set candidate_client_id_by_phone = p
    where organization_id = org and candidate_client_id_by_phone = s;
  update public.website_chat_sessions set candidate_client_id_by_email = p
    where organization_id = org and candidate_client_id_by_email = s;
  update public.website_chat_messages set client_id = p where organization_id = org and client_id = s;

  -- One assignee per conversation: the survivor's stands; the secondary's is used only if it had none.
  update public.communication_conversation_assignments set client_id = p
  where organization_id = org and client_id = s
    and not exists (select 1 from public.communication_conversation_assignments where organization_id = org and client_id = p);
  -- Followers combine.
  insert into public.communication_conversation_followers (organization_id, client_id, user_id, followed_at)
  select organization_id, p, user_id, followed_at
  from public.communication_conversation_followers where organization_id = org and client_id = s
  on conflict do nothing;
  -- Read position: the earlier one, so a teammate still sees the other thread's messages they had not read.
  insert into public.communication_conversation_read_marks (organization_id, user_id, client_id, last_read_at, created_at, updated_at)
  select organization_id, user_id, p, last_read_at, created_at, now()
  from public.communication_conversation_read_marks where organization_id = org and client_id = s
  on conflict (organization_id, user_id, client_id)
  do update set last_read_at = least(communication_conversation_read_marks.last_read_at, excluded.last_read_at),
    updated_at = now();
  -- The secondary's leftover rows in these three go with it (they cascade).

  -- Marketing sends: both duplicates may have received one campaign; both send records are kept.
  update public.marketing_campaign_recipients set
    client_id = p,
    merged_from_client_id = coalesce(merged_from_client_id, s)
  where organization_id = org and client_id = s;
  update public.marketing_campaign_result_credits set client_id = p where organization_id = org and client_id = s;

  update public.file_shares set client_id = p where organization_id = org and client_id = s;
  update public.review_requests set client_id = p where organization_id = org and client_id = s;
  update public.import_rows set match_client_id = p where organization_id = org and match_client_id = s;
  update public.import_rows set result_client_id = p where organization_id = org and result_client_id = s;

  -- Notes, files, tags and history point at the client by type and id. Tags and note links combine without
  -- repeating one the survivor already has.
  update public.note_links as link set entity_id = p
  where link.organization_id = org and link.entity_type = 'client' and link.entity_id = s
    and not exists (
      select 1 from public.note_links as mine
      where mine.note_id = link.note_id and mine.entity_type = 'client' and mine.entity_id = p);
  delete from public.note_links where organization_id = org and entity_type = 'client' and entity_id = s;

  update public.tag_assignments as tag set entity_id = p
  where tag.organization_id = org and tag.entity_type = 'client' and tag.entity_id = s
    and not exists (
      select 1 from public.tag_assignments as mine
      where mine.tag_id = tag.tag_id and mine.entity_type = 'client' and mine.entity_id = p);
  delete from public.tag_assignments where organization_id = org and entity_type = 'client' and entity_id = s;

  update public.file_links as link set entity_id = p
  where link.organization_id = org and link.entity_type = 'client' and link.entity_id = s
    and not exists (
      select 1 from public.file_links as mine
      where mine.file_id = link.file_id and mine.entity_type = 'client' and mine.entity_id = p and mine.role = link.role);
  -- A leftover is the same file already on the survivor in the same role, so removing it loses nothing.
  delete from public.file_links where organization_id = org and entity_type = 'client' and entity_id = s;

  update public.attachments set entity_id = p where organization_id = org and entity_type = 'client' and entity_id = s;
  update public.files set origin_id = p where organization_id = org and origin_type = 'client' and origin_id = s;
  update public.activity_events set entity_id = p where organization_id = org and entity_type = 'client' and entity_id = s;

  -- An earlier merge into the secondary now leads to the survivor too.
  update public.client_merges set surviving_client_id = p where organization_id = org and surviving_client_id = s;

  insert into public.client_merges (organization_id, surviving_client_id, merged_client_id, merged_client_snapshot, moved, merged_by)
  values (org, p, s, snapshot, plan -> 'moves', (select auth.uid()))
  returning id into merge_id;

  insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata)
  values (org, 'client', p, 'client_merged',
    left('Merged in "' || secondary_row.display_name || '".', 280),
    (select auth.uid()),
    jsonb_build_object('merge_id', merge_id, 'merged_client_id', s, 'merged_display_name', secondary_row.display_name,
      'moved', plan -> 'moves'));

  -- Everything that matters has moved. Whatever still points at the secondary is its own duplicate bookkeeping
  -- (preferences, a second assignee, follower and read rows) and cascades away; a RESTRICT key still pointing
  -- here would mean a table this merge does not know about, and fails the whole merge rather than lose it.
  delete from public.clients where id = s;

  perform set_config('app.client_merge_in_progress', 'false', true);

  return jsonb_build_object('merge_id', merge_id, 'surviving_client_id', p);
end;
$$;

alter function public.merge_clients(uuid, uuid) owner to postgres;
revoke all on function public.merge_clients(uuid, uuid) from public, anon;
grant execute on function public.merge_clients(uuid, uuid) to authenticated, service_role;

comment on function public.merge_clients(uuid, uuid) is
  'Merges the secondary client into the primary, as Jobber does: everything moves, the primary''s values win, blanks fill from the secondary, any opt-out survives, and the secondary is deleted with a permanent client_merges record. Cannot be undone. Self-checks customers.merge.';


-- ---------------------------------------------------------------------------------------------------------
-- 8. Where an old link to a merged client should go
-- ---------------------------------------------------------------------------------------------------------

-- Null when the id was never merged, or when the caller cannot see the survivor.
create or replace function public.resolve_merged_client(p_client_id uuid) returns uuid
  language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  merge_row public.client_merges;
begin
  -- surviving_client_id is kept pointing at the latest survivor by merge_clients, so one hop is enough.
  select * into merge_row from public.client_merges where merged_client_id = p_client_id;
  if merge_row.id is null
     or not exists (select 1 from public.clients where id = merge_row.surviving_client_id and deleted_at is null)
     or not private.can_view_client(merge_row.organization_id, merge_row.surviving_client_id) then
    return null;
  end if;
  return merge_row.surviving_client_id;
end;
$$;

alter function public.resolve_merged_client(uuid) owner to postgres;
revoke all on function public.resolve_merged_client(uuid) from public, anon;
grant execute on function public.resolve_merged_client(uuid) to authenticated, service_role;
