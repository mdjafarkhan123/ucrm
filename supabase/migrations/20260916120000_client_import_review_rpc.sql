-- Onboarding & Data Portability, Part 1, step 4: the "Review" dry-run.
--
-- After the office maps their columns (step 3), Review works out -- row by row -- what WOULD happen, so they
-- can see it before anything is written. Nothing lands in `clients` here; that is step 5's worker. This
-- migration adds the two functions the Review /api route calls:
--
--   * public.match_import_clients  -- a read: given the file's normalized emails and phones (as arrays, so a
--     5,000-row file is one round trip with no URL-length ceiling), return every existing client those values
--     match, with the handful of fields the "update existing" branch needs. Uses the same
--     client_contact_methods_org_value_unique_idx that enforces our per-org email/phone uniqueness.
--   * public.review_import_batch   -- the write: replace the batch's previous dry-run with the freshly
--     computed rows and move the batch mapped -> reviewed, all in one transaction (rule 12 -- import_rows has
--     no insert policy, so the write lands in a SECURITY DEFINER RPC).
--
-- Matching is scoped to clients the office can still see (deleted_at is null), matching what their list shows.
-- A collision against a *restorable* (soft-deleted) client -- which the unique index still blocks -- is the
-- rare case the step-5 worker catches on the unique index and reports in the error file, rather than something
-- Review predicts here.

-- ---------------------------------------------------------------------------------------------------------
-- 1. match_import_clients -- batched dedupe lookup (read; respects RLS)
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.match_import_clients(
  target_org uuid,
  emails text[],
  phones text[]
)
returns table (
  client_id uuid,
  matched_kind text,
  matched_value text,
  client_type text,
  first_name text,
  last_name text,
  company_name text,
  lead_source text,
  has_email boolean,
  has_phone boolean,
  has_property boolean
)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select
    m.client_id,
    m.kind as matched_kind,
    m.normalized_value as matched_value,
    c.client_type,
    c.first_name,
    c.last_name,
    c.company_name,
    c.lead_source,
    exists (
      select 1 from public.client_contact_methods e
      where e.client_id = c.id and e.kind = 'email'
    ) as has_email,
    exists (
      select 1 from public.client_contact_methods p
      where p.client_id = c.id and p.kind = 'phone'
    ) as has_phone,
    exists (
      select 1 from public.properties pr
      where pr.client_id = c.id and pr.deleted_at is null
    ) as has_property
  from public.client_contact_methods m
  join public.clients c
    on c.id = m.client_id
   and c.organization_id = target_org
   and c.deleted_at is null
  where m.organization_id = target_org
    and (
      (m.kind = 'email' and m.normalized_value = any(emails))
      or (m.kind = 'phone' and m.normalized_value = any(phones))
    );
$$;

revoke all on function public.match_import_clients(uuid, text[], text[]) from public;
-- Anon has no import screen; drop the default anon EXECUTE grant like every other import function. The body is
-- security invoker, so it already reads only what the caller's RLS on client_contact_methods/clients allows.
revoke execute on function public.match_import_clients(uuid, text[], text[]) from anon;
grant execute on function public.match_import_clients(uuid, text[], text[]) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 2. review_import_batch -- persist the dry-run (write; SECURITY DEFINER, rule 12)
-- ---------------------------------------------------------------------------------------------------------

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

  -- Lock the batch so a second Review of the same batch cannot interleave its delete/insert with ours.
  select * into target_batch from public.import_batches where id = target_batch_id for update;
  if not found then
    raise exception 'That import was not found.' using errcode = 'no_data_found';
  end if;

  -- Backstop the route's permission check against the batch's own organization, never the payload.
  if not private.has_permission(target_batch.organization_id, 'customers.create') then
    raise exception 'You do not have permission to change this import.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Only a mapped batch, or one already reviewed (the office stepped back and changed something), can be
  -- (re)reviewed. Once the worker has started or the batch is finished, its rows are frozen.
  if target_batch.status not in ('mapped', 'reviewed') then
    raise exception 'This import can no longer be reviewed.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Re-review replaces the previous dry-run entirely, so the screen never mixes old and new decisions.
  delete from public.import_rows where batch_id = target_batch_id;

  -- Every row lands as pending_review: Review only records the decision. The commit step (step 5) is what
  -- moves create/update rows to 'ready' for the worker and settles skip/hold/error rows -- the worker must
  -- never drain a batch the office has not yet confirmed.
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

revoke all on function public.review_import_batch(jsonb) from public;
revoke execute on function public.review_import_batch(jsonb) from anon;
grant execute on function public.review_import_batch(jsonb) to authenticated;

-- Refresh the resolved_payload contract to include initial_note -- a real client field the office can map
-- (IMPORT_CLIENT_TARGETS) and one create_client already accepts. Notes are additive, so on update it is always
-- carried (never dropped by a "don't overwrite" toggle) and the worker appends it as a new note.
comment on column public.import_rows.resolved_payload is
  'Fixed worker contract. planned_action=create: '
  '{ "client": { client_type, first_name, last_name, company_name, display_name, lifecycle_status, '
  'lead_source, initial_note }, "email": text|null, "phone": text|null, "property": { label, address_line1, '
  'address_line2, city, state_region, postal_code, country }|null }. planned_action=update: the same shape but '
  'carrying ONLY the fields to change (the Review step drops any scalar field whose "don''t overwrite" toggle '
  'is on and whose target already has a value; email/phone/property are added only when the client lacks that '
  'kind and no earlier file row claimed the value; initial_note, being additive, is always carried); '
  'match_client_id names the client to update. Null for skip/hold/error rows.';
