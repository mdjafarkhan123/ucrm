-- Jobs, Part 15e: the customer's Work Report, and the one safe door they see it through.
--
-- A signature (15d) proves what somebody agreed to at a moment and is frozen forever. A work report is the
-- opposite kind of document: it is the picture a contractor hands the customer of what was done -- the
-- photos, the ticked-off checklist answers, the work list, and optionally the signature that closed it out.
-- Jobber's "send the client a copy of the completed work" is this. Because it is a living view and not a
-- receipt, it is deliberately built with no snapshot: un-checking a photo fixes every link already sent, the
-- moment it is saved. Jafar approved that: the customer link is always current.
--
-- Everything customer-facing here reuses the mechanism Invoices and Quotes already ship, rather than
-- inventing a second one:
--   1. One builder. private.job_report_customer_document is the only place the customer's document is
--      assembled, so the token page (a stranger with a link) and Preview as client (a signed-in member)
--      can never drift.
--   2. The raw token never reaches the database. The server hashes it and passes 32 bytes.
--   3. `anon` gets nothing. The public page runs on our server with the service key and calls exactly one
--      resolver, the only public seam.
--
-- "Always current" is why nothing is copied: the two join tables record only *which* photos and *which*
-- answered questions are chosen, and the document resolves the actual photo and the actual answer live at
-- read time. A cleared answer simply stops appearing; re-answering brings it back. No PDF is produced, the
-- same as everywhere else in this app -- the customer's copy is a hosted page.

-- 1. The selection -----------------------------------------------------------------------------------------

-- One report per job. Not a version, not a history: a single living selection the crew edits. The two
-- toggles are the whole of the money decision -- a report may show the work list, and only a report that
-- shows the work list may show its prices.
create table public.job_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  include_service_details boolean not null default true,
  include_price boolean not null default false,
  -- The one signature the crew chose to show the customer, if any. Cleared rather than cascaded when the
  -- signature goes with the organization: the report is the job's, and a signature is append-only anyway.
  signature_id uuid,
  summary text check (summary is null or char_length(trim(summary)) between 1 and 2000),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint job_reports_job_unique unique (organization_id, job_id),
  constraint job_reports_organization_id_unique unique (organization_id, id),
  constraint job_reports_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_reports_signature_fk foreign key (organization_id, signature_id)
    references public.job_signatures(organization_id, id) on delete set null (signature_id),
  -- Prices are a detail of the work list. There is no report that hides the work and shows its total.
  constraint job_reports_price_requires_details check (not include_price or include_service_details)
);

comment on table public.job_reports is
  'One living work report per job: the two customer-facing toggles, an optional chosen signature and a '
  'summary. Carries no copied content -- the photos and checklist answers it shows are chosen in the two '
  'join tables below and resolved live, so the customer link is always current.';

-- The set null on signature deletion needs the foreign key column indexed.
create index job_reports_signature_idx
  on public.job_reports(organization_id, signature_id) where signature_id is not null;

-- The chosen photos. A row here means "show this attachment on the report"; there is nothing else to store,
-- because the file itself lives in the attachments table and is resolved at read time. Restrict on the
-- attachment, exactly as quote_version_attachments does: a photo that is on a report cannot be deleted out
-- from under it -- un-check it first.
create table public.job_report_photos (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  attachment_id uuid not null,
  created_at timestamptz not null default now(),
  constraint job_report_photos_unique unique (organization_id, job_id, attachment_id),
  constraint job_report_photos_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_report_photos_attachment_fk foreign key (organization_id, attachment_id)
    references public.attachments(organization_id, id) on delete restrict
);

create index job_report_photos_job_idx on public.job_report_photos(organization_id, job_id);
create index job_report_photos_attachment_idx on public.job_report_photos(organization_id, attachment_id);

-- The chosen checklist answers, keyed by which visit answered the question. A row means "show this visit's
-- answer to this question"; the answer itself is read live from visit_checklist_answers, so a cleared answer
-- quietly drops off the report and a re-answer brings it back. Cascades on both the visit and the item: if
-- the question or the visit is gone, the choice to show it is meaningless.
create table public.job_report_checklist_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  visit_id uuid not null,
  item_id uuid not null,
  created_at timestamptz not null default now(),
  constraint job_report_checklist_items_unique unique (organization_id, visit_id, item_id),
  constraint job_report_checklist_items_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_report_checklist_items_visit_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete cascade,
  constraint job_report_checklist_items_item_fk foreign key (organization_id, item_id)
    references public.job_checklist_items(organization_id, id) on delete cascade
);

create index job_report_checklist_items_job_idx
  on public.job_report_checklist_items(organization_id, job_id);
create index job_report_checklist_items_visit_idx
  on public.job_report_checklist_items(organization_id, visit_id);
create index job_report_checklist_items_item_idx
  on public.job_report_checklist_items(organization_id, item_id);

-- The customer link, copied field-for-field from invoice_access_links (its 6a table plus the 6b view
-- columns). The one difference is deliberate: this points at the job, not at a report version, because a
-- report has no versions -- there is one living selection, and the link always shows its current state.
create table public.job_report_access_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  recipient_name text check (recipient_name is null or char_length(trim(recipient_name)) between 1 and 200),
  recipient_email text check (
    recipient_email is null or (
      recipient_email = lower(trim(recipient_email))
      and char_length(recipient_email) between 6 and 320
      and recipient_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    )
  ),
  token_hash bytea not null check (octet_length(token_hash) = 32),
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text check (revoked_reason is null or revoked_reason in ('rotated', 'revoked')),
  first_viewed_at timestamptz,
  last_viewed_at timestamptz,
  view_count integer not null default 0 check (view_count >= 0),
  constraint job_report_access_links_token_hash_unique unique (token_hash),
  constraint job_report_access_links_organization_id_unique unique (organization_id, id),
  constraint job_report_access_links_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_report_access_links_revocation_agrees
    check ((revoked_at is null) = (revoked_reason is null)),
  constraint job_report_access_links_expiry_follows_issue
    check (expires_at is null or expires_at > issued_at)
);

comment on table public.job_report_access_links is
  'One customer link to a job''s work report. Stores only the token hash -- the raw token exists once, in the '
  'URL handed to the staff member who created it, and must never appear in a row, a log line, or an activity '
  'payload.';

comment on column public.job_report_access_links.first_viewed_at is
  'Stamped once, by an explicit call from the customer''s browser after the report is on screen. Never by a '
  'page request, a HEAD, a mail scanner or a link preview.';

create index job_report_access_links_job_idx
  on public.job_report_access_links(organization_id, job_id, issued_at desc);
create index job_report_access_links_issued_by_idx
  on public.job_report_access_links(issued_by) where issued_by is not null;

-- 2. Least privilege ---------------------------------------------------------------------------------------

-- Every one of these tables is read only through the security-definer functions below -- the editor read,
-- the customer document, the link resolver. None is part of the Data API for a member or a stranger, exactly
-- as invoice_access_links is closed. The access-link table additionally holds a token hash that must never
-- be selectable. So: RLS on, no policy, no grant, on all four.
alter table public.job_reports enable row level security;
alter table public.job_report_photos enable row level security;
alter table public.job_report_checklist_items enable row level security;
alter table public.job_report_access_links enable row level security;

revoke all on public.job_reports from anon, authenticated;
revoke all on public.job_report_photos from anon, authenticated;
revoke all on public.job_report_checklist_items from anon, authenticated;
revoke all on public.job_report_access_links from anon, authenticated;

-- 3. Whether there is anything to show ---------------------------------------------------------------------

-- A report exists as a row the moment the editor is opened and saved, but an empty selection is not a
-- document. This is the one definition of "has content", used to gate issuing a link, to decide whether the
-- customer door opens at all, and to log the feed only when the report crosses between empty and not.
create or replace function private.job_report_has_content(
  target_organization_id uuid,
  target_job_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.job_reports as report
    where report.organization_id = target_organization_id
      and report.job_id = target_job_id
      and (
        report.include_service_details
        or report.signature_id is not null
        or nullif(trim(coalesce(report.summary, '')), '') is not null
        or exists (
          select 1 from public.job_report_photos as photo
          where photo.organization_id = target_organization_id and photo.job_id = target_job_id
        )
        or exists (
          select 1 from public.job_report_checklist_items as sel
          where sel.organization_id = target_organization_id and sel.job_id = target_job_id
        )
      )
  );
$$;

comment on function private.job_report_has_content(uuid, uuid) is
  'Whether a job''s report is a document or an empty shell. The one definition, used to gate issuing a link, '
  'to decide whether the customer door opens, and to log the feed only on the empty/not crossing.';

revoke all on function private.job_report_has_content(uuid, uuid) from public, anon, authenticated, service_role;

-- 4. The one builder ---------------------------------------------------------------------------------------

-- Invoker, not definer, and private: it is only ever reached from inside a security-definer function that
-- has already decided the caller may be here, the same shape as private.invoice_customer_document. It makes
-- no access decision; it is handed the job row, the business name, and whether prices are included, and it
-- resolves the current selection live. Money is left out whole when include_price is false -- a hidden price
-- is one that never enters the payload, not one drawn and covered in the browser.
create or replace function private.job_report_customer_document(
  job_row public.jobs,
  business_name text,
  include_price boolean
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  report_row public.job_reports;
  client_row public.clients;
  property_row public.properties;
begin
  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = job_row.id;
  if not found then
    return null;
  end if;

  select * into client_row
  from public.clients
  where organization_id = job_row.organization_id and id = job_row.client_id;

  select * into property_row
  from public.properties
  where organization_id = job_row.organization_id and id = job_row.property_id;

  return jsonb_build_object(
    'business', jsonb_build_object('name', business_name),
    'job', jsonb_build_object(
      'job_number', job_row.job_number,
      'title', job_row.title,
      'job_type', job_row.job_type,
      'currency_code', job_row.currency_code
    ),
    'client', jsonb_build_object(
      'display_name', client_row.display_name,
      'company_name', client_row.company_name,
      'first_name', client_row.first_name,
      'last_name', client_row.last_name
    ),
    'property', jsonb_build_object(
      'label', property_row.label,
      'address_line1', property_row.address_line1,
      'address_line2', property_row.address_line2,
      'city', property_row.city,
      'state_region', property_row.state_region,
      'postal_code', property_row.postal_code,
      'country', property_row.country
    ),
    'summary', nullif(trim(coalesce(report_row.summary, '')), ''),
    -- Photos, resolved live. A row in the join table names an attachment; the file name and object key come
    -- from the attachment now, so a renamed file shows its new name. The object key is what the public file
    -- route allow-lists and streams.
    'photos', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'attachment_id', photo.attachment_id,
          'file_name', att.file_name,
          'object_key', att.object_key
        ) order by att.created_at, photo.attachment_id
      ), '[]'::jsonb)
      from public.job_report_photos as photo
      join public.attachments as att
        on att.organization_id = photo.organization_id and att.id = photo.attachment_id
      where photo.organization_id = job_row.organization_id and photo.job_id = job_row.id
    ),
    -- Checklist answers, grouped by visit and resolved live. The inner join to visit_checklist_answers is
    -- what makes "always current" true: a cleared answer produces no row, so it drops off the report until
    -- it is answered again.
    'checklist', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'visit_id', grp.visit_id,
          'visit_date', grp.visit_date,
          'items', grp.items
        ) order by grp.visit_date, grp.visit_id
      ), '[]'::jsonb)
      from (
        select sel.visit_id,
               visit.visit_date,
               jsonb_agg(
                 jsonb_build_object(
                   'item_id', item.id,
                   'label', item.label,
                   'item_type', item.item_type,
                   'value', answer.value
                 ) order by item.position, item.id
               ) as items
        from public.job_report_checklist_items as sel
        join public.job_visits as visit
          on visit.organization_id = sel.organization_id and visit.id = sel.visit_id
        join public.job_checklist_items as item
          on item.organization_id = sel.organization_id and item.id = sel.item_id
        join public.visit_checklist_answers as answer
          on answer.organization_id = sel.organization_id
         and answer.visit_id = sel.visit_id
         and answer.item_id = sel.item_id
        where sel.organization_id = job_row.organization_id and sel.job_id = job_row.id
        group by sel.visit_id, visit.visit_date
      ) as grp
    ),
    -- The work list, only when the report shows it, and its prices only when it shows those. The check
    -- constraint means include_price already implies include_service_details.
    'service_details', case when report_row.include_service_details then jsonb_build_object(
      'lines', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'line_id', line.id,
            'position', line.position,
            'line_kind', line.line_kind,
            'category', line.category,
            'name', line.name,
            'description', line.description,
            'unit_label', line.unit_label,
            'quantity', line.quantity
          )
          || case when include_price
               then jsonb_build_object(
                 'unit_price_minor', line.unit_price_minor,
                 'line_total_minor', line.line_total_minor)
               else '{}'::jsonb end
          order by line.position, line.id
        ), '[]'::jsonb)
        from public.job_line_items as line
        where line.organization_id = job_row.organization_id and line.job_id = job_row.id
      ),
      'totals', case when include_price then jsonb_build_object(
        'subtotal_minor', job_row.subtotal_minor,
        'discount_minor', job_row.discount_minor,
        'tax_minor', job_row.tax_minor,
        'total_minor', job_row.total_minor
      ) else null end
    ) else null end,
    -- The chosen signature, as facts the customer may read. The drawn image is not streamed on the public
    -- page in this part -- the customer sees who signed, what they agreed to and when.
    'signature', (
      select case when sig.id is null then null else jsonb_build_object(
        'signer_name', sig.signer_name,
        'signer_role', sig.signer_role,
        'signature_type', sig.signature_type,
        'statement', sig.statement,
        'method', sig.method,
        'has_image', sig.image_object_key is not null,
        'collected_at', sig.collected_at
      ) end
      from public.job_signatures as sig
      where sig.organization_id = job_row.organization_id and sig.id = report_row.signature_id
    )
  );
end;
$$;

comment on function private.job_report_customer_document(public.jobs, text, boolean) is
  'The only definition of what a customer may see on a work report. Called by '
  'public.resolve_job_report_access_link for the customer and public.job_report_customer_preview for staff. '
  'Resolves photos and checklist answers live, so it is always current. Prices leave only when include_price '
  'is true, and no cost, margin or internal note is ever added here.';

revoke all on function private.job_report_customer_document(public.jobs, text, boolean)
  from public, anon, authenticated, service_role;

-- 5. The editor: read the selection and its candidates -----------------------------------------------------

-- What the crew sees when they open "Edit report": the current selection, and everything they could add --
-- the job's and its visits' photos, the answered checklist questions grouped by visit, and the job's
-- signatures. Bounded by one job. jobs.edit, with the same assigned narrowing every job read carries.
create or replace function public.job_report_state(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  report_row public.job_reports;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.organization_id into org from public.jobs as job where job.id = target_job_id;
  if org is null then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if not private.member_has_permission(org, caller, 'jobs.edit')
     or not private.can_view_job(org, target_job_id) then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = org and job_id = target_job_id;

  return jsonb_build_object(
    'report', jsonb_build_object(
      'include_service_details', coalesce(report_row.include_service_details, true),
      'include_price', coalesce(report_row.include_price, false),
      'signature_id', report_row.signature_id,
      'summary', report_row.summary,
      'photo_ids', (
        select coalesce(jsonb_agg(photo.attachment_id order by photo.created_at, photo.attachment_id),
          '[]'::jsonb)
        from public.job_report_photos as photo
        where photo.organization_id = org and photo.job_id = target_job_id
      ),
      'checklist', (
        select coalesce(jsonb_agg(jsonb_build_object('visit_id', sel.visit_id, 'item_id', sel.item_id)),
          '[]'::jsonb)
        from public.job_report_checklist_items as sel
        where sel.organization_id = org and sel.job_id = target_job_id
      )
    ),
    'has_content', private.job_report_has_content(org, target_job_id),
    'can_view_price', private.member_has_permission(org, caller, 'jobs.view_price'),
    'candidates', jsonb_build_object(
      -- Every image attached to the job itself or to any of its visits.
      'photos', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'attachment_id', att.id,
            'file_name', att.file_name,
            'mime_type', att.mime_type,
            'entity_type', att.entity_type,
            'entity_id', att.entity_id,
            'created_at', att.created_at
          ) order by att.created_at, att.id
        ), '[]'::jsonb)
        from public.attachments as att
        where att.organization_id = org
          and att.mime_type like 'image/%'
          and (
            (att.entity_type = 'job' and att.entity_id = target_job_id)
            or (att.entity_type = 'visit' and att.entity_id in (
              select visit.id from public.job_visits as visit
              where visit.organization_id = org and visit.job_id = target_job_id
            ))
          )
      ),
      -- Answered checklist questions, grouped by the visit that answered them. Only answered ones are
      -- pickable: there is nothing to show a customer for a blank question.
      'visits', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'visit_id', grp.visit_id,
            'visit_date', grp.visit_date,
            'items', grp.items
          ) order by grp.visit_date, grp.visit_id
        ), '[]'::jsonb)
        from (
          select visit.id as visit_id,
                 visit.visit_date,
                 jsonb_agg(
                   jsonb_build_object(
                     'item_id', item.id,
                     'label', item.label,
                     'item_type', item.item_type,
                     'value', answer.value
                   ) order by item.position, item.id
                 ) as items
          from public.visit_checklist_answers as answer
          join public.job_visits as visit
            on visit.organization_id = answer.organization_id and visit.id = answer.visit_id
          join public.job_checklist_items as item
            on item.organization_id = answer.organization_id and item.id = answer.item_id
          where answer.organization_id = org and answer.job_id = target_job_id
          group by visit.id, visit.visit_date
        ) as grp
      ),
      -- The job's signatures, so one can be shown on the report.
      'signatures', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', sig.id,
            'signer_name', sig.signer_name,
            'signature_type', sig.signature_type,
            'collected_at', sig.collected_at
          ) order by sig.collected_at desc, sig.id desc
        ), '[]'::jsonb)
        from public.job_signatures as sig
        where sig.organization_id = org and sig.job_id = target_job_id
      )
    )
  );
end;
$$;

comment on function public.job_report_state(uuid) is
  'The work-report editor read: one job''s current selection plus the photos, answered checklist questions '
  'and signatures it could include. Needs jobs.edit and respects the assigned narrowing.';

revoke all on function public.job_report_state(uuid) from public;
revoke execute on function public.job_report_state(uuid) from anon;
grant execute on function public.job_report_state(uuid) to authenticated;

-- 6. The editor: save the selection ------------------------------------------------------------------------

-- Replaces the whole selection in one call: the two toggles, the chosen signature, the summary, and the two
-- join tables by delete-then-insert (the shape replace_checklist_template_items uses). jobs.edit gates it;
-- include_price additionally needs jobs.view_price, the same rule the signature document applies to reads.
-- Everything referenced is checked to belong to this job -- the composite foreign keys prove the tenant, not
-- the job. One feed line is written only when the report crosses between empty and not, so re-saving a photo
-- swap does not spam the history.
create or replace function public.save_job_report(
  target_job_id uuid,
  new_include_service_details boolean,
  new_include_price boolean,
  new_signature_id uuid default null,
  new_summary text default null,
  photo_attachment_ids uuid[] default '{}',
  checklist_selections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  clean_summary text;
  had_content boolean;
  has_content_now boolean;
  photo_count integer;
  selection_count integer;
begin
  if caller is null then
    raise exception 'You must be signed in to save a report.' using errcode = 'insufficient_privilege';
  end if;

  select * into job_row from public.jobs where id = target_job_id for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if not private.member_has_permission(job_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  if new_include_service_details is null or new_include_price is null then
    raise exception 'A report needs its options set.' using errcode = 'P0400';
  end if;
  if new_include_price and not new_include_service_details then
    raise exception 'Show the work list before showing its prices.' using errcode = 'P0400';
  end if;
  if new_include_price
     and not private.member_has_permission(job_row.organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to show prices on this report.'
      using errcode = 'insufficient_privilege';
  end if;

  clean_summary := nullif(trim(coalesce(new_summary, '')), '');
  if clean_summary is not null and char_length(clean_summary) > 2000 then
    raise exception 'That summary is too long.' using errcode = 'P0400';
  end if;

  -- The signature, if one is chosen, must be this job's.
  if new_signature_id is not null then
    if not exists (
      select 1 from public.job_signatures as sig
      where sig.organization_id = job_row.organization_id
        and sig.id = new_signature_id
        and sig.job_id = target_job_id
    ) then
      raise exception 'That signature is not on this job.' using errcode = 'P0404';
    end if;
  end if;

  -- Every chosen photo must be an image attached to this job or one of its visits.
  if photo_attachment_ids is not null and array_length(photo_attachment_ids, 1) is not null then
    select count(*) into photo_count
    from public.attachments as att
    where att.organization_id = job_row.organization_id
      and att.id = any(photo_attachment_ids)
      and att.mime_type like 'image/%'
      and (
        (att.entity_type = 'job' and att.entity_id = target_job_id)
        or (att.entity_type = 'visit' and att.entity_id in (
          select visit.id from public.job_visits as visit
          where visit.organization_id = job_row.organization_id and visit.job_id = target_job_id
        ))
      );
    if photo_count <> cardinality(array(select distinct unnest(photo_attachment_ids))) then
      raise exception 'One of those photos does not belong to this job.' using errcode = 'P0400';
    end if;
  end if;

  -- Every chosen checklist answer must name a question and a visit that are both this job's.
  if checklist_selections is not null and jsonb_array_length(checklist_selections) > 0 then
    select count(*) into selection_count
    from jsonb_array_elements(checklist_selections) as choice
    where exists (
      select 1 from public.job_checklist_items as item
      where item.organization_id = job_row.organization_id
        and item.id = (choice ->> 'item_id')::uuid
        and item.job_id = target_job_id
    )
    and exists (
      select 1 from public.job_visits as visit
      where visit.organization_id = job_row.organization_id
        and visit.id = (choice ->> 'visit_id')::uuid
        and visit.job_id = target_job_id
    );
    if selection_count <> jsonb_array_length(checklist_selections) then
      raise exception 'One of those checklist answers does not belong to this job.'
        using errcode = 'P0400';
    end if;
  end if;

  had_content := private.job_report_has_content(job_row.organization_id, target_job_id);

  insert into public.job_reports (
    organization_id, job_id, include_service_details, include_price, signature_id, summary, updated_by
  ) values (
    job_row.organization_id, target_job_id, new_include_service_details, new_include_price,
    new_signature_id, clean_summary, caller
  )
  on conflict (organization_id, job_id) do update
    set include_service_details = excluded.include_service_details,
        include_price = excluded.include_price,
        signature_id = excluded.signature_id,
        summary = excluded.summary,
        updated_by = excluded.updated_by,
        updated_at = now();

  delete from public.job_report_photos
  where organization_id = job_row.organization_id and job_id = target_job_id;
  if photo_attachment_ids is not null and array_length(photo_attachment_ids, 1) is not null then
    insert into public.job_report_photos (organization_id, job_id, attachment_id)
    select job_row.organization_id, target_job_id, chosen
    from (select distinct unnest(photo_attachment_ids) as chosen) as distinct_photos;
  end if;

  delete from public.job_report_checklist_items
  where organization_id = job_row.organization_id and job_id = target_job_id;
  if checklist_selections is not null and jsonb_array_length(checklist_selections) > 0 then
    insert into public.job_report_checklist_items (organization_id, job_id, visit_id, item_id)
    select distinct job_row.organization_id, target_job_id,
      (choice ->> 'visit_id')::uuid, (choice ->> 'item_id')::uuid
    from jsonb_array_elements(checklist_selections) as choice;
  end if;

  has_content_now := private.job_report_has_content(job_row.organization_id, target_job_id);

  -- Only a crossing is worth a feed line. A photo swap inside an already-live report changes every sent
  -- link silently, which is the whole point of "always current".
  if had_content <> has_content_now then
    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      job_row.organization_id, 'job', target_job_id,
      case when has_content_now then 'job.work_report_prepared' else 'job.work_report_cleared' end,
      case when has_content_now then 'Prepared a work report for the customer'
           else 'Cleared the work report' end,
      caller,
      jsonb_build_object('job_id', target_job_id)
    );
  end if;

  return jsonb_build_object('job_id', target_job_id, 'has_content', has_content_now);
end;
$$;

comment on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb) is
  'Replaces a job''s whole work-report selection in one call. Needs jobs.edit; include_price additionally '
  'needs jobs.view_price. Writes one feed line only when the report crosses between empty and not.';

revoke all on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb) from public;
revoke execute on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb) from anon;
grant execute on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb)
  to authenticated;

-- 7. Preview as client -------------------------------------------------------------------------------------

-- The same document a customer would see, for a signed-in member holding no token. It mints nothing. Prices
-- follow both the report's own toggle and the member's own right: a member without jobs.view_price never
-- sees amounts, even on a report built to include them.
create or replace function public.job_report_customer_preview(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  report_row public.job_reports;
  effective_include_price boolean;
  business_name text;
  document jsonb;
begin
  select * into job_row from public.jobs where id = target_job_id;
  if not found or not private.member_has_permission(job_row.organization_id, caller, 'jobs.view')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = target_job_id;

  effective_include_price := coalesce(report_row.include_price, false)
    and private.member_has_permission(job_row.organization_id, caller, 'jobs.view_price');

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = job_row.organization_id;

  document := private.job_report_customer_document(job_row, business_name, effective_include_price);

  return jsonb_build_object(
    'document', document,
    'preview', jsonb_build_object(
      'has_content', private.job_report_has_content(job_row.organization_id, target_job_id),
      'prices_withheld', coalesce(report_row.include_price, false) and not effective_include_price
    )
  );
end;
$$;

comment on function public.job_report_customer_preview(uuid) is
  'Preview as client. Returns the same customer document the token page renders, for a signed-in member with '
  'jobs.view, without creating a link. Amounts are withheld from the payload unless the report includes them '
  'and the member holds jobs.view_price.';

revoke all on function public.job_report_customer_preview(uuid) from public;
revoke execute on function public.job_report_customer_preview(uuid) from anon;
grant execute on function public.job_report_customer_preview(uuid) to authenticated;

-- 8. The customer door: issue, revoke, resolve, record -----------------------------------------------------

-- Copy customer link. The member's own press. The token is generated in Node and only its SHA-256 arrives
-- here, so the raw link exists once, in the response. Asking twice does not leave two open doors: this
-- rotates the job's live links in the same transaction. jobs.edit, because there is no jobs.send.
create or replace function public.issue_job_report_access_link(
  target_job_id uuid,
  supplied_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  client_name text;
  client_email text;
  link_row public.job_report_access_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'A customer link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into job_row from public.jobs where id = target_job_id for update;
  if job_row.id is null
     or not private.member_has_permission(job_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to share this job.' using errcode = 'insufficient_privilege';
  end if;

  if not private.job_report_has_content(job_row.organization_id, target_job_id) then
    raise exception 'Add something to the work report before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = job_row.organization_id
             and method.client_id = job_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = job_row.organization_id and client.id = job_row.client_id;

  if client_email is null then
    raise exception 'Add an email address to this client before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  update public.job_report_access_links
  set revoked_at = now(), revoked_reason = 'rotated'
  where organization_id = job_row.organization_id
    and job_id = target_job_id
    and revoked_at is null;

  insert into public.job_report_access_links (
    organization_id, job_id, recipient_name, recipient_email, token_hash, issued_by
  ) values (
    job_row.organization_id, target_job_id,
    coalesce(nullif(trim(client_name), ''), client_email), client_email,
    supplied_token_hash, caller
  )
  returning * into link_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    job_row.organization_id, 'job', target_job_id, 'job.work_report_link_issued',
    'Shared the work report with the customer', caller,
    jsonb_build_object('job_report_access_link_id', link_row.id, 'recipient_email', client_email)
  );

  return jsonb_build_object(
    'job_id', target_job_id,
    'job_report_access_link_id', link_row.id,
    'recipient_name', link_row.recipient_name,
    'recipient_email', link_row.recipient_email,
    'issued_at', link_row.issued_at,
    'expires_at', link_row.expires_at
  );
end;
$$;

comment on function public.issue_job_report_access_link(uuid, bytea) is
  'Creates the customer''s door to a job''s work report and returns everything but the token, which only ever '
  'exists in the caller''s response. Rotates the job''s live links so asking twice never leaves two open. '
  'Needs jobs.edit and a report with content.';

revoke all on function public.issue_job_report_access_link(uuid, bytea) from public;
revoke execute on function public.issue_job_report_access_link(uuid, bytea) from anon;
grant execute on function public.issue_job_report_access_link(uuid, bytea) to authenticated;

-- Turn the link off. jobs.edit, idempotent, one feed line.
create or replace function public.revoke_job_report_access_link(target_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  link_row public.job_report_access_links;
begin
  select * into link_row from public.job_report_access_links where id = target_link_id for update;

  if link_row.id is null
     or not private.member_has_permission(link_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(link_row.organization_id, link_row.job_id) then
    raise exception 'You do not have access to change this link.' using errcode = 'insufficient_privilege';
  end if;

  if link_row.revoked_at is not null then
    return jsonb_build_object(
      'job_report_access_link_id', link_row.id, 'revoked_at', link_row.revoked_at,
      'already_revoked', true
    );
  end if;

  update public.job_report_access_links
  set revoked_at = now(), revoked_reason = 'revoked'
  where id = link_row.id
  returning * into link_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    link_row.organization_id, 'job', link_row.job_id, 'job.work_report_link_revoked',
    'Turned off the work report link', caller,
    jsonb_build_object('job_report_access_link_id', link_row.id)
  );

  return jsonb_build_object(
    'job_report_access_link_id', link_row.id, 'revoked_at', link_row.revoked_at,
    'already_revoked', false
  );
end;
$$;

comment on function public.revoke_job_report_access_link(uuid) is
  'Turns off a work report''s customer link. Needs jobs.edit. Idempotent -- a link already off is reported, '
  'not re-revoked.';

revoke all on function public.revoke_job_report_access_link(uuid) from public;
revoke execute on function public.revoke_job_report_access_link(uuid) from anon;
grant execute on function public.revoke_job_report_access_link(uuid) to authenticated;

-- The customer's reader. Our server hashes the token from the URL and calls this as the service role. Every
-- way of failing returns the same null -- unknown token, revoked, expired, or a report that no longer has
-- content -- so the page cannot be used to find out whether a job exists. Prices follow the report's own
-- toggle: unlike a bill, a work report may be built to show no money at all.
create or replace function public.resolve_job_report_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.job_report_access_links;
  job_row public.jobs;
  report_row public.job_reports;
  business_name text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.job_report_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into job_row from public.jobs where id = link_row.job_id;
  if job_row.id is null then
    return null;
  end if;

  if not private.job_report_has_content(job_row.organization_id, job_row.id) then
    return null;
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = job_row.id;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = job_row.organization_id;

  return private.job_report_customer_document(job_row, business_name, report_row.include_price);
end;
$$;

comment on function public.resolve_job_report_access_link(bytea) is
  'The customer''s reader. Hashed token in, one customer document out, or null for every failure alike. '
  'Service role only: not part of the Data API for anybody else.';

revoke all on function public.resolve_job_report_access_link(bytea) from public;
revoke execute on function public.resolve_job_report_access_link(bytea) from anon, authenticated;
grant execute on function public.resolve_job_report_access_link(bytea) to service_role;

-- The customer opened it. Called by the customer's own browser once the report is drawn -- the only moment
-- that means what staff think "viewed" means. Answers the same whether it recorded anything or not.
create or replace function public.record_job_report_link_view(supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.job_report_access_links;
  job_row public.jobs;
  was_first boolean;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.job_report_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into job_row from public.jobs where id = link_row.job_id;
  if job_row.id is null
     or not private.job_report_has_content(job_row.organization_id, job_row.id) then
    return null;
  end if;

  was_first := link_row.first_viewed_at is null;

  update public.job_report_access_links
  set first_viewed_at = coalesce(first_viewed_at, now()),
      last_viewed_at = now(),
      view_count = view_count + 1
  where id = link_row.id;

  if was_first then
    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      job_row.organization_id, 'job', job_row.id, 'job.work_report_viewed_by_client',
      'The customer opened the work report', null,
      jsonb_build_object('job_report_access_link_id', link_row.id)
    );
  end if;

  return jsonb_build_object('recorded', true, 'first_view', was_first);
end;
$$;

comment on function public.record_job_report_link_view(bytea) is
  'The customer''s browser telling us the report was on screen. Stamps the link''s view facts and writes one '
  'feed line the first time. Service role only.';

revoke all on function public.record_job_report_link_view(bytea) from public;
revoke execute on function public.record_job_report_link_view(bytea) from anon, authenticated;
grant execute on function public.record_job_report_link_view(bytea) to service_role;

notify pgrst, 'reload schema';
