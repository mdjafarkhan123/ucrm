-- Onboarding & Data Portability, Part 4: the opening-balances assisted-import screens.
--
-- 20261001100000 locked the schema, 20261002100000 taught the shared worker the opening_balance branch. This
-- migration adds the write path the 4-screen wizard (Upload -> Map -> Review -> Done) needs on top of the same
-- import_batches/import_rows pipeline Part 1 built, following that exact pattern:
--
--   * create_opening_balance_import_batch -- Upload's write (mirrors create_import_batch).
--   * commit_opening_balance_import_batch -- Commit's write (mirrors commit_import_batch), minus the consent
--     gate: an opening balance never contacts a customer, so HubSpot's consent affirmation does not apply here.
--   * match_active_opening_balances -- Review's dedupe read: for a set of clients, their current (unreplaced)
--     receivable/credit facts, so a second file row for a client already carrying that balance type becomes a
--     correction (planned_action='update', carrying the existing fact's id as the predecessor) instead of a
--     silent duplicate. Mirrors match_import_clients' shape (batched array params, one round trip).
--
-- set_import_batch_mapping and review_import_batch are already entity-agnostic (they work purely off the
-- batch row), except one thing: both hardcode the Client-import permission key ('customers.create'). Reused
-- as-is for an opening_balance batch, that would let anyone who may import clients also write financial
-- opening-balance facts, which is the wrong gate (the contract requires Invoice financial-write access). Both
-- are widened here to ask a new one-line helper which permission a batch's entity_type requires, instead of
-- duplicating their ~150 lines for one string.

create or replace function private.import_batch_entity_permission(target_entity_type text)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then 'customers.create'
    when 'opening_balance' then 'invoices.create'
    else null
  end;
$$;

comment on function private.import_batch_entity_permission(text) is
  'The one permission key that may write an import_batches/import_rows batch of this entity_type. Central so '
  'set_import_batch_mapping and review_import_batch (shared across every entity_type) cannot drift from each '
  'other or from create_*_import_batch.';

revoke all on function private.import_batch_entity_permission(text) from public;
revoke execute on function private.import_batch_entity_permission(text) from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 1. set_import_batch_mapping / review_import_batch -- widen the permission check, nothing else changes.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.set_import_batch_mapping(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid := (payload->>'batch_id')::uuid;
  target_batch public.import_batches;
begin
  if target_batch_id is null then
    raise exception 'batch_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  select * into target_batch from public.import_batches where id = target_batch_id;
  if not found then
    raise exception 'That import was not found.' using errcode = 'no_data_found';
  end if;

  if not private.has_permission(
    target_batch.organization_id, private.import_batch_entity_permission(target_batch.entity_type)
  ) then
    raise exception 'You do not have permission to change this import.'
      using errcode = 'insufficient_privilege';
  end if;

  if target_batch.status not in ('uploaded', 'mapped') then
    raise exception 'This import can no longer be changed.'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.import_batches
  set column_mapping = coalesce(payload->'column_mapping', '{}'::jsonb),
      match_action = coalesce(payload->>'match_action', match_action),
      status = 'mapped'
  where id = target_batch_id
  returning * into target_batch;

  return target_batch;
end;
$$;

create or replace function public.review_import_batch(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid := (payload->>'batch_id')::uuid;
  target_batch public.import_batches;
begin
  if target_batch_id is null then
    raise exception 'batch_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  select * into target_batch from public.import_batches where id = target_batch_id for update;
  if not found then
    raise exception 'That import was not found.' using errcode = 'no_data_found';
  end if;

  if not private.has_permission(
    target_batch.organization_id, private.import_batch_entity_permission(target_batch.entity_type)
  ) then
    raise exception 'You do not have permission to change this import.'
      using errcode = 'insufficient_privilege';
  end if;

  if target_batch.status not in ('mapped', 'reviewed') then
    raise exception 'This import can no longer be reviewed.'
      using errcode = 'invalid_parameter_value';
  end if;

  delete from public.import_rows where batch_id = target_batch_id;

  insert into public.import_rows (
    organization_id,
    batch_id,
    source_row_number,
    raw,
    planned_action,
    resolved_payload,
    match_client_id,
    match_reason,
    flags,
    error_message
  )
  select
    target_batch.organization_id,
    target_batch_id,
    row_in.source_row_number,
    row_in.raw,
    row_in.planned_action,
    row_in.resolved_payload,
    row_in.match_client_id,
    row_in.match_reason,
    coalesce(row_in.flags, '{}'),
    row_in.error_message
  from jsonb_to_recordset(coalesce(payload->'rows', '[]'::jsonb)) as row_in(
    source_row_number integer,
    raw jsonb,
    planned_action text,
    resolved_payload jsonb,
    match_client_id uuid,
    match_reason text,
    flags text[],
    error_message text
  );

  update public.import_batches
  set status = 'reviewed'
  where id = target_batch_id
  returning * into target_batch;

  return target_batch;
end;
$$;

comment on function public.set_import_batch_mapping(jsonb) is
  'Saves a batch''s column mapping (+ match_action, for entity types that use it) and moves it uploaded/mapped '
  '-> mapped. Entity-agnostic: the write permission it backstops against comes from '
  'private.import_batch_entity_permission(batch.entity_type), not a hardcoded key.';

comment on function public.review_import_batch(jsonb) is
  'Replaces a batch''s dry-run rows with the freshly computed set and moves it mapped/reviewed -> reviewed. '
  'Entity-agnostic: the write permission it backstops against comes from '
  'private.import_batch_entity_permission(batch.entity_type), not a hardcoded key.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. create_opening_balance_import_batch -- Upload's write (mirrors create_import_batch).
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.create_opening_balance_import_batch(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid := (payload->>'organization_id')::uuid;
  created_batch public.import_batches;
begin
  if target_organization_id is null then
    raise exception 'organization_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  if not private.has_permission(target_organization_id, 'invoices.create') then
    raise exception 'You do not have permission to import opening balances here.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.import_batches (
    organization_id,
    created_by,
    entity_type,
    source_filename,
    storage_object_key,
    file_row_count,
    -- Opening balances have no skip/update choice (a match is always a correction, never a duplicate or a
    -- silent overwrite) -- 'update' is stored only because the column is not null; Review never reads it for
    -- this entity_type.
    match_action
  )
  values (
    target_organization_id,
    (select auth.uid()),
    'opening_balance',
    payload->>'source_filename',
    payload->>'storage_object_key',
    (payload->>'file_row_count')::integer,
    'update'
  )
  returning * into created_batch;

  return created_batch;
end;
$$;

comment on function public.create_opening_balance_import_batch(jsonb) is
  'Records one uploaded, already-parsed opening-balances CSV as a draft import_batches row (entity_type = '
  '''opening_balance''). SECURITY DEFINER; self-checks invoices.create.';

revoke all on function public.create_opening_balance_import_batch(jsonb) from public;
revoke execute on function public.create_opening_balance_import_batch(jsonb) from anon;
grant execute on function public.create_opening_balance_import_batch(jsonb) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 3. commit_opening_balance_import_batch -- Commit's write (mirrors commit_import_batch, no consent gate).
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.commit_opening_balance_import_batch(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid := (payload->>'batch_id')::uuid;
  target_batch public.import_batches;
  held integer;
  errored integer;
  to_import integer;
begin
  if target_batch_id is null then
    raise exception 'batch_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  select * into target_batch from public.import_batches where id = target_batch_id for update;
  if not found then
    raise exception 'That import was not found.' using errcode = 'no_data_found';
  end if;

  if target_batch.entity_type <> 'opening_balance' then
    raise exception 'This import is not an opening-balances import.' using errcode = 'invalid_parameter_value';
  end if;

  if not private.has_permission(target_batch.organization_id, 'invoices.create') then
    raise exception 'You do not have permission to change this import.'
      using errcode = 'insufficient_privilege';
  end if;

  if target_batch.status <> 'reviewed' then
    raise exception 'This import can no longer be committed.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- No skip outcome for this entity_type (Review never plans one), so unlike commit_import_batch there is
  -- nothing to settle to 'skipped'. hold/error settle exactly like the client importer; create/update queue.
  update public.import_rows
  set status = case planned_action
    when 'create' then 'ready'
    when 'update' then 'ready'
    when 'hold' then 'held'
    when 'error' then 'failed'
    else status
  end
  where batch_id = target_batch_id
    and status = 'pending_review';

  select
    count(*) filter (where planned_action = 'hold'),
    count(*) filter (where planned_action = 'error'),
    count(*) filter (where planned_action in ('create', 'update'))
  into held, errored, to_import
  from public.import_rows
  where batch_id = target_batch_id;

  update public.import_batches
  set held_count = held,
      error_count = errored,
      status = case when to_import = 0 then 'completed' else 'importing' end
  where id = target_batch_id
  returning * into target_batch;

  return target_batch;
end;
$$;

comment on function public.commit_opening_balance_import_batch(jsonb) is
  'Commits a reviewed opening-balances import: settles hold/error rows to their final status, queues '
  'create/update rows as ''ready'' for the shared step-5b worker, and seeds the batch''s held/error counts. No '
  'consent gate -- an opening balance never contacts a customer. SECURITY DEFINER; self-checks invoices.create.';

revoke all on function public.commit_opening_balance_import_batch(jsonb) from public;
revoke execute on function public.commit_opening_balance_import_batch(jsonb) from anon;
grant execute on function public.commit_opening_balance_import_batch(jsonb) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 4. match_active_opening_balances -- Review's dedupe read (mirrors match_import_clients).
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.match_active_opening_balances(
  target_org uuid,
  client_ids uuid[]
)
returns table (
  client_id uuid,
  balance_type text,
  opening_balance_id uuid,
  amount_minor bigint,
  as_of_date date
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select fact.client_id, fact.balance_type, fact.id, fact.amount_minor, fact.as_of_date
  from public.client_opening_balances fact
  where fact.organization_id = target_org
    and fact.replaced_at is null
    and fact.client_id = any(client_ids)
    and private.has_permission(target_org, 'invoices.create');
$$;

comment on function public.match_active_opening_balances(uuid, uuid[]) is
  'Every current (unreplaced) opening-balance fact for the named clients, one row per {client, balance_type}. '
  'Review uses this to turn a second file row for a client''s already-recorded balance type into a correction '
  '(predecessor_opening_balance_id) instead of a silent duplicate. SECURITY DEFINER so the read is guaranteed '
  'even when invoices.view is not separately granted alongside the invoices.create this whole flow requires; '
  'self-checked in the WHERE clause rather than trusting the caller, same backstop every import RPC uses.';

revoke all on function public.match_active_opening_balances(uuid, uuid[]) from public;
revoke execute on function public.match_active_opening_balances(uuid, uuid[]) from anon;
grant execute on function public.match_active_opening_balances(uuid, uuid[]) to authenticated;

notify pgrst, 'reload schema';
