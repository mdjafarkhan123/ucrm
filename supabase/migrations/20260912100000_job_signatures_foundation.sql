-- Jobs, Part 15d-1: a customer's signature on a job, and the frozen document it was given against.
--
-- The act this stores is the one a crew performs at a kitchen table: "sign here to say the work is done",
-- or "sign here to authorise this before we start". Jobber does it with Job -> More -> Collect Signature
-- and keeps the result as a signed PDF in the job's internal notes. Housecall Pro does it with typed
-- signature kinds -- before work, after work, custom -- and records the signer, the date, and the amount
-- that was approved, then marks the signature stale when the job's price moves afterwards.
--
-- This file follows the structured model, and follows it because of what "signed" has to mean. A note can
-- be deleted; a record that proves what somebody agreed to cannot. So:
--
--   * The signed document is COPIED onto the row -- identity, the priced work list, and the total -- with a
--     SHA-256 of exactly those bytes. Editing the job afterwards can never make the signed evidence lie,
--     because the evidence never reads the job again.
--   * The row is APPEND-ONLY at the table, not merely ungranted: update and delete both raise. There is no
--     void and no edit, matching Jobber and Housecall Pro, neither of which offers one.
--   * A job's document moving after a signature is not an error to correct, it is a fact to show. The read
--     model recomputes the hash and reports `is_stale`, which is Housecall Pro's grey-turns-red prompt, and
--     the crew collects a new signature beside the old one.
--
-- No PDF is produced. This app runs no server PDF engine by the decision taken in Invoices Part 6;
-- customer-facing documents here are hosted pages, and the customer's copy of this one is Part 15e's job.

-- 1. The record ---------------------------------------------------------------------------------------------

create table public.job_signatures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  -- Context only: "the crew was on Tuesday's visit when this was signed". A signature belongs to the job --
  -- it is the job's scope and total that were agreed to -- so losing the visit must not lose the signature.
  visit_id uuid,
  -- Housecall Pro's three kinds, fixed rather than a configurable library. A Settings page for editing the
  -- names of three things is a surface to maintain, not a capability anyone asked for.
  signature_type text not null check (
    signature_type in ('work_authorization', 'work_completion', 'other')
  ),
  signer_name text not null check (char_length(trim(signer_name)) between 1 and 120),
  -- Free text, because "Homeowner" and "Site manager" and "Tenant" are all real answers and none of them is
  -- a role this system knows about.
  signer_role text check (signer_role is null or char_length(trim(signer_role)) between 1 and 60),
  -- The exact sentence that was on the screen above the signature line. Preset from the type and editable,
  -- because what somebody signed is the words they read, not the enum we filed it under.
  statement text not null check (char_length(trim(statement)) between 1 and 500),
  method text not null check (method in ('typed', 'drawn')),
  -- The frozen job document, prices and total included. Housecall Pro freezes "the amount that was
  -- approved" and shows the signature on the invoice; a completion signature over a work list with no
  -- money on it proves nothing about what was being charged for.
  document_snapshot jsonb not null,
  -- SHA-256 of the canonical snapshot, computed in the command and copied in, so the row proves itself
  -- without trusting a jsonb column somebody could argue about.
  document_hash text not null check (document_hash ~ '^[0-9a-f]{64}$'),
  -- Null for a typed name. A drawn one is a small private PNG in object storage; the bytes never enter
  -- Postgres, because these rows are read on every job page and an image column would be dragged through
  -- every read that never shows it.
  image_object_key text check (image_object_key is null or char_length(image_object_key) between 1 and 500),
  image_byte_size integer check (image_byte_size is null or image_byte_size between 1 and 262144),
  -- Truncated IP and user agent of the collecting device, cut to size before they arrive.
  evidence jsonb not null default '{}'::jsonb,
  collected_by uuid references auth.users(id) on delete set null,
  collected_at timestamptz not null default now(),
  constraint job_signatures_organization_id_unique unique (organization_id, id),
  constraint job_signatures_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_signatures_visit_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete set null (visit_id),
  -- A typed signature is a name in a box; a drawn one is a picture. The two never half-swap.
  constraint job_signatures_image_matches_method check (
    (method = 'drawn') = (image_object_key is not null)
    and (image_object_key is null) = (image_byte_size is null)
  )
);

comment on table public.job_signatures is
  'A signature collected against a job, bound to a frozen copy of the job document as it stood at that '
  'moment and a hash of it. Append-only: there is no edit, no delete and no void. A later job edit does not '
  'rewrite the evidence -- it makes the signature stale, and the crew collects a new one beside it.';

comment on column public.job_signatures.document_snapshot is
  'What was signed: identity, client, property, the priced work list and the total. Never read back through '
  'a plain grant -- job_signature_document serves it and strips the money without jobs.view_price.';

comment on column public.job_signatures.document_hash is
  'SHA-256 of the canonical snapshot, copied at signing. Recomputing it against the job''s current document '
  'is what tells a screen the job has changed since this was signed.';

comment on column public.job_signatures.visit_id is
  'Which visit the crew were on, for context. Cleared rather than cascaded when the visit goes: the '
  'signature is against the job, and a deleted visit must not take signed evidence with it.';

-- The job's own list, newest first -- the card's only read. The id tiebreaks so two signatures collected in
-- the same instant have a stable order.
create index job_signatures_job_idx
  on public.job_signatures(organization_id, job_id, collected_at desc, id desc);

-- The visit foreign key's own index, needed for the `set null` on visit deletion.
create index job_signatures_visit_idx
  on public.job_signatures(organization_id, visit_id) where visit_id is not null;

-- 2. Append-only, at the table ------------------------------------------------------------------------------

-- The same shape as job_costing_events and invoice_events: refused by the database, not merely left
-- ungranted. The org-purge bypass is the one exception, and it is DELETE only -- an organization being
-- erased must not be blocked by its own evidence, but no path anywhere may ever rewrite a signature.
create or replace function private.job_signatures_are_append_only()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
    return old;
  end if;
  raise exception 'A collected signature cannot be changed or removed.'
    using errcode = 'insufficient_privilege';
end;
$$;

revoke all on function private.job_signatures_are_append_only() from public;
revoke execute on function private.job_signatures_are_append_only() from anon, authenticated;

create trigger job_signatures_are_append_only
before update or delete on public.job_signatures
for each row execute function private.job_signatures_are_append_only();

-- Truncate skips the row trigger entirely, so it gets its own statement-level guard. It has no purge
-- bypass: the purge deletes, it does not truncate.
create or replace function private.job_signatures_reject_truncate()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Collected signatures cannot be emptied.' using errcode = 'insufficient_privilege';
end;
$$;

revoke all on function private.job_signatures_reject_truncate() from public;
revoke execute on function private.job_signatures_reject_truncate() from anon, authenticated;

create trigger job_signatures_reject_truncate
before truncate on public.job_signatures
for each statement execute function private.job_signatures_reject_truncate();

-- 3. Who sees what ------------------------------------------------------------------------------------------

alter table public.job_signatures enable row level security;

-- A signature is part of the job, so it is visible exactly when the job is, including the assigned narrowing
-- a Field member carries. The scope half is spelled out inline rather than calling can_view_job, so it
-- hoists to one evaluation per statement instead of one per row (the 15a-4 lesson).
create policy "permitted members can view job signatures"
on public.job_signatures for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

-- No write policy at all: every write goes through collect_job_signature below.
revoke all on public.job_signatures from anon, authenticated;

-- document_snapshot is deliberately absent from this grant. It carries the job's prices and total, and the
-- house rule is that money never travels on a plain grant -- job_signature_document serves it and shapes it
-- by jobs.view_price. image_object_key IS granted, because the authenticated streaming route reads it
-- through the member's own client precisely so that row level security decides whether it exists.
grant select (
  id, organization_id, job_id, visit_id, signature_type, signer_name, signer_role, statement,
  method, document_hash, image_object_key, image_byte_size, collected_by, collected_at
) on public.job_signatures to authenticated;

-- 4. The frozen document -------------------------------------------------------------------------------------

-- Built with explicit jsonb_build_object rather than to_jsonb(row), because the hash is only meaningful if
-- the key order is fixed: a column added to public.jobs next month must not silently change what every
-- existing signature hashes to.
create or replace function private.job_document_snapshot(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  job_row public.jobs;
  client_row public.clients;
  property_row public.properties;
begin
  select * into job_row
  from public.jobs
  where organization_id = target_organization_id and id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  select * into client_row
  from public.clients
  where organization_id = target_organization_id and id = job_row.client_id;

  select * into property_row
  from public.properties
  where organization_id = target_organization_id and id = job_row.property_id;

  return jsonb_build_object(
    'job_id', job_row.id,
    'job_number', job_row.job_number,
    'title', job_row.title,
    'job_type', job_row.job_type,
    'instructions', job_row.instructions,
    'currency_code', job_row.currency_code,
    'client', jsonb_build_object(
      'client_id', client_row.id,
      'display_name', client_row.display_name,
      'company_name', client_row.company_name,
      'first_name', client_row.first_name,
      'last_name', client_row.last_name
    ),
    'property', jsonb_build_object(
      'property_id', property_row.id,
      'label', property_row.label,
      'address_line1', property_row.address_line1,
      'address_line2', property_row.address_line2,
      'city', property_row.city,
      'state_region', property_row.state_region,
      'postal_code', property_row.postal_code,
      'country', property_row.country
    ),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'line_id', line.id,
        'position', line.position,
        'line_kind', line.line_kind,
        'category', line.category,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'unit_price_minor', line.unit_price_minor,
        'is_taxable', line.is_taxable,
        'line_total_minor', line.line_total_minor
      ) order by line.position, line.id), '[]'::jsonb)
      from public.job_line_items as line
      where line.organization_id = target_organization_id and line.job_id = target_job_id
    ),
    'totals', jsonb_build_object(
      'subtotal_minor', job_row.subtotal_minor,
      'discount_minor', job_row.discount_minor,
      'tax_minor', job_row.tax_minor,
      'total_minor', job_row.total_minor
    )
  );
end;
$$;

comment on function private.job_document_snapshot(uuid, uuid) is
  'The job as a document: identity, client, property, the priced work list and the totals. Frozen onto a '
  'signature at collection, and recomputed later only to answer "has this job changed since it was signed".';

revoke all on function private.job_document_snapshot(uuid, uuid) from public;
revoke execute on function private.job_document_snapshot(uuid, uuid) from anon, authenticated;

-- 5. Collecting one ------------------------------------------------------------------------------------------

-- field_records.record, the crew key from 15a-1. Holding a customer's tablet while they sign off the work
-- they watched happen is exactly what that key is for, and Jobber's base Field preset collects signatures
-- while holding no jobs.edit right at all.
create or replace function public.collect_job_signature(
  target_organization_id uuid,
  target_job_id uuid,
  new_signature_type text,
  new_signer_name text,
  new_statement text,
  new_method text,
  new_signer_role text default null,
  target_visit_id uuid default null,
  new_image_object_key text default null,
  new_image_byte_size integer default null,
  supplied_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  visit_row public.job_visits;
  clean_signer text;
  clean_role text;
  clean_statement text;
  snapshot jsonb;
  snapshot_hash text;
  new_signature public.job_signatures;
begin
  if caller is null then
    raise exception 'You must be signed in to collect a signature.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'field_records.record')
    and not private.member_has_permission(target_organization_id, caller, 'field_records.manage_team') then
    raise exception 'You do not have access to collect a signature.'
      using errcode = 'insufficient_privilege';
  end if;
  -- The assigned narrowing lives here: a Field member may only collect against a job they are on.
  if not private.can_view_job(target_organization_id, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  if new_signature_type is null
    or new_signature_type not in ('work_authorization', 'work_completion', 'other') then
    raise exception 'That is not a kind of signature.' using errcode = 'P0400';
  end if;

  clean_signer := nullif(trim(coalesce(new_signer_name, '')), '');
  if clean_signer is null or char_length(clean_signer) > 120 then
    raise exception 'A signature needs the name of the person signing.' using errcode = 'P0400';
  end if;

  clean_role := nullif(trim(coalesce(new_signer_role, '')), '');
  if clean_role is not null and char_length(clean_role) > 60 then
    raise exception 'That description of the signer is too long.' using errcode = 'P0400';
  end if;

  clean_statement := nullif(trim(coalesce(new_statement, '')), '');
  if clean_statement is null or char_length(clean_statement) > 500 then
    raise exception 'A signature needs the sentence the signer is agreeing to.' using errcode = 'P0400';
  end if;

  if new_method is null or new_method not in ('typed', 'drawn') then
    raise exception 'That is not a way to sign.' using errcode = 'P0400';
  end if;
  if (new_method = 'drawn') <> (new_image_object_key is not null)
    or (new_image_object_key is null) <> (new_image_byte_size is null) then
    raise exception 'That signature is incomplete.' using errcode = 'P0400';
  end if;

  -- The visit is context, but the wrong job's visit is not context, it is a mistake. Checked here because
  -- the composite foreign key only proves the tenant, not the job.
  if target_visit_id is not null then
    select * into visit_row
    from public.job_visits
    where organization_id = target_organization_id
      and id = target_visit_id
      and job_id = target_job_id;
    if not found then
      raise exception 'That visit is not on this job.' using errcode = 'P0404';
    end if;
  end if;

  -- The lock, taken after the PNG is already stored: the behaviour contract forbids a network call while a
  -- row is held, so the upload happens in the route before this command is ever called.
  select * into job_row
  from public.jobs
  where organization_id = target_organization_id and id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  snapshot := private.job_document_snapshot(target_organization_id, target_job_id);
  snapshot_hash := encode(extensions.digest(snapshot::text, 'sha256'), 'hex');

  insert into public.job_signatures (
    organization_id, job_id, visit_id, signature_type, signer_name, signer_role, statement, method,
    document_snapshot, document_hash, image_object_key, image_byte_size, evidence, collected_by
  ) values (
    target_organization_id, target_job_id, target_visit_id, new_signature_type, clean_signer, clean_role,
    clean_statement, new_method, snapshot, snapshot_hash, new_image_object_key, new_image_byte_size,
    coalesce(supplied_evidence, '{}'::jsonb), caller
  )
  returning * into new_signature;

  -- What puts it in the job's history. job_combined_history already unions activity_events for both job and
  -- visit, so a signature collected on a visit shows on that visit's records as well as the job's feed.
  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    target_organization_id,
    case when target_visit_id is null then 'job' else 'visit' end,
    coalesce(target_visit_id, target_job_id),
    'job.signature_collected',
    'Collected ' || clean_signer || '''s signature ('
      || case new_signature_type
           when 'work_authorization' then 'work authorization'
           when 'work_completion' then 'work completion'
           else 'other'
         end
      || ')',
    caller,
    jsonb_build_object(
      'job_id', target_job_id,
      'signature_type', new_signature_type,
      'method', new_method,
      'visit_id', target_visit_id,
      'has_image', new_image_object_key is not null
    )
  );

  return jsonb_build_object(
    'id', new_signature.id,
    'collected_at', new_signature.collected_at,
    'has_image', new_signature.image_object_key is not null
  );
end;
$$;

comment on function public.collect_job_signature(uuid, uuid, text, text, text, text, text, uuid, text, integer, jsonb) is
  'Records a signature against a job, freezing the job document and its hash onto the row. Needs '
  'field_records.record. Staff-collected only -- there is no customer-facing path to this, and no way to '
  'undo it afterwards.';

revoke all on function public.collect_job_signature(uuid, uuid, text, text, text, text, text, uuid, text, integer, jsonb)
  from public;
revoke execute on function public.collect_job_signature(uuid, uuid, text, text, text, text, text, uuid, text, integer, jsonb)
  from anon;
grant execute on function public.collect_job_signature(uuid, uuid, text, text, text, text, text, uuid, text, integer, jsonb)
  to authenticated;

-- 6. The reads -------------------------------------------------------------------------------------------------

-- The job's signature list. No money and no raw snapshot here -- just enough to draw a row, plus the one
-- derived fact a list cannot compute for itself: whether the job has moved since this was signed. Bounded by
-- one job's signatures, and the hash is recomputed once for the job rather than once per signature.
create or replace function public.job_signatures_for_job(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  current_hash text;
  signatures jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.organization_id into org from public.jobs as job where job.id = target_job_id;
  if org is null then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if not private.can_view_job(org, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  current_hash := encode(
    extensions.digest(private.job_document_snapshot(org, target_job_id)::text, 'sha256'), 'hex'
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', signature.id,
        'signature_type', signature.signature_type,
        'statement', signature.statement,
        'signer_name', signature.signer_name,
        'signer_role', signature.signer_role,
        'method', signature.method,
        'has_image', signature.image_object_key is not null,
        'visit_id', signature.visit_id,
        'visit_date', visit.visit_date,
        'collected_at', signature.collected_at,
        'collected_by', signature.collected_by,
        -- Housecall Pro's grey-turns-red, computed rather than stored: a stored flag would need every job
        -- edit to remember to clear it, and the one that forgot would be the one that mattered.
        'is_stale', signature.document_hash is distinct from current_hash
      )
      order by signature.collected_at desc, signature.id desc
    ),
    '[]'::jsonb
  )
  into signatures
  from public.job_signatures as signature
  left join public.job_visits as visit
    on visit.organization_id = signature.organization_id and visit.id = signature.visit_id
  where signature.organization_id = org and signature.job_id = target_job_id;

  return jsonb_build_object(
    'signatures', signatures,
    'can_collect', private.member_has_permission(org, caller, 'field_records.record')
      or private.member_has_permission(org, caller, 'field_records.manage_team')
  );
end;
$$;

comment on function public.job_signatures_for_job(uuid) is
  'One job''s collected signatures, newest first, each flagged is_stale when the job document no longer '
  'hashes to what was signed. Carries no money and no snapshot -- the signed document is its own read.';

revoke all on function public.job_signatures_for_job(uuid) from public;
revoke execute on function public.job_signatures_for_job(uuid) from anon;
grant execute on function public.job_signatures_for_job(uuid) to authenticated;

-- What was actually signed. This is the only way the frozen snapshot is ever read back, and the only place
-- money leaves this table -- stripped for a reader without jobs.view_price, the same rule job_money follows.
create or replace function public.job_signature_document(target_signature_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  signature public.job_signatures;
  document jsonb;
  current_hash text;
begin
  if caller is null then
    raise exception 'You must be signed in to view this signature.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into signature from public.job_signatures where id = target_signature_id;
  if not found then
    raise exception 'That signature could not be found.' using errcode = 'P0404';
  end if;
  if not private.can_view_job(signature.organization_id, signature.job_id) then
    raise exception 'You do not have access to this signature.' using errcode = 'insufficient_privilege';
  end if;

  document := signature.document_snapshot;

  if not private.member_has_permission(signature.organization_id, caller, 'jobs.view_price') then
    -- The work list survives, the numbers do not. A crew member without the price right sees what was
    -- agreed to be done and not what it costs, exactly as they see the job itself. Quantity stays: "two
    -- gutters" is the work, not the money, and job_line_money already draws the line in the same place.
    document := (document - 'totals')
      || jsonb_build_object(
        'lines', (
          select coalesce(jsonb_agg(
            line - 'unit_price_minor' - 'line_total_minor'
            order by (line ->> 'position')::integer, line ->> 'line_id'
          ), '[]'::jsonb)
          from jsonb_array_elements(coalesce(document -> 'lines', '[]'::jsonb)) as line
        )
      );
  end if;

  current_hash := encode(
    extensions.digest(
      private.job_document_snapshot(signature.organization_id, signature.job_id)::text, 'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'id', signature.id,
    'job_id', signature.job_id,
    'signature_type', signature.signature_type,
    'statement', signature.statement,
    'signer_name', signature.signer_name,
    'signer_role', signature.signer_role,
    'method', signature.method,
    'has_image', signature.image_object_key is not null,
    'visit_id', signature.visit_id,
    'collected_at', signature.collected_at,
    'collected_by', signature.collected_by,
    'document_hash', signature.document_hash,
    'is_stale', signature.document_hash is distinct from current_hash,
    'document', document
  );
end;
$$;

comment on function public.job_signature_document(uuid) is
  'The frozen document one signature was given against, exactly as it stood then. Prices and totals are '
  'stripped for a reader without jobs.view_price; the work list is not.';

revoke all on function public.job_signature_document(uuid) from public;
revoke execute on function public.job_signature_document(uuid) from anon;
grant execute on function public.job_signature_document(uuid) to authenticated;
