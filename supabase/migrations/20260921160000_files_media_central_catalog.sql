-- Files and Media, Part 2: the central File catalog, its links, and its folders.
--
-- Today an `attachments` row is both the file and its one use: the same picture attached to a job and to a
-- quote is two rows and two R2 objects. The approved contract (docs/files-media-behavior-contract.md) and
-- docs/adr/0002-one-file-many-links.md replace that with one File that owns one immutable private R2 object,
-- plus a separate link for every record that uses it. "Used in 5 places" is then a fact about link rows
-- rather than a guess.
--
-- This migration is additive on purpose. It creates three new tables, backfills them from `attachments`
-- without moving or rewriting a single R2 object, and leaves every existing read and write path working
-- exactly as before. Nothing in the app reads these tables yet; the upload pipeline is Part 3 and the File
-- Manager is Part 4. Rolling back means dropping what is created here -- `attachments` keeps its rows, its
-- object keys and its behavior, so no customer-facing document or stored object depends on this change.
--
-- Four guarantees are built into the schema rather than left to application code:
--
--   * Tenant isolation. Every table carries organization_id, and every cross-table reference is a composite
--     foreign key through (organization_id, id) -- the pattern job_report_photos and quote_version_attachments
--     already use. A link to another organization's File is not "prevented", it is unrepresentable.
--   * Link truth. One row per (File, record, role), an entity-exists trigger, and cascade on the owning
--     organization mean the link table cannot drift from reality. A reader may only see a link row for a
--     record they are already allowed to view, so any later count is truthful without extra filtering, and a
--     hidden record can never be inferred from a total.
--   * Protected history. A link the customer has already received (an issued quote's file, a work report's
--     photo) is marked protected. Protected links cannot be deleted and a File carrying one cannot be moved
--     to Trash until its owning domain retires the use first.
--   * No direct writes. `authenticated` gets read policies only. Every insert, update and delete goes through
--     a server-side command, matching how quotes, invoices and SMS already work in this codebase.

-- ---------------------------------------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------------------------------------

insert into public.permissions (description, key, scope_model)
values
  ('See the business file library', 'files.view', 'none'),
  ('Upload to the file library, and rename, move and organize files', 'files.manage', 'none'),
  ('Move a file to Trash and restore it', 'files.trash', 'none')
on conflict (key) do nothing;

-- Owners, admins and office run the library. Sales and finance browse it so they can find a document to put
-- on a quote or an invoice, but do not reorganize or trash it. Field members get nothing here: they reach a
-- file through the job they are assigned to, which their record permissions already decide.
insert into public.role_permissions (access_scope, permission_key, role)
values
  ('all', 'files.view', 'owner'),
  ('all', 'files.manage', 'owner'),
  ('all', 'files.trash', 'owner'),
  ('all', 'files.view', 'admin'),
  ('all', 'files.manage', 'admin'),
  ('all', 'files.trash', 'admin'),
  ('all', 'files.view', 'office'),
  ('all', 'files.manage', 'office'),
  ('all', 'files.trash', 'office'),
  ('all', 'files.view', 'sales'),
  ('all', 'files.view', 'finance')
on conflict (role, permission_key) do nothing;

-- ---------------------------------------------------------------------------------------------------------
-- Folders
-- ---------------------------------------------------------------------------------------------------------

-- A folder is a display convenience only: moving a File between folders never touches a link, and a File
-- belongs to at most one folder. Folders are flat in this release -- the approved contract asks for "optional
-- user folders", not a tree, and a parent column can be added later without moving any file.
create table if not exists public.file_folders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint file_folders_name_check
    check (char_length(btrim(name)) between 1 and 120),
  constraint file_folders_organization_id_id_key unique (organization_id, id)
);

comment on table public.file_folders is
  'Optional per-organization folders for the File Manager. Purely a display grouping: a File sits in at most one folder and moving it changes no attachment.';

create unique index if not exists file_folders_unique_name_idx
  on public.file_folders (organization_id, lower(btrim(name)));

create index if not exists file_folders_created_by_idx
  on public.file_folders (created_by)
  where created_by is not null;

-- ---------------------------------------------------------------------------------------------------------
-- Files
-- ---------------------------------------------------------------------------------------------------------

create table if not exists public.files (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  folder_id uuid,
  display_name text not null,
  mime_type text not null,
  size_bytes bigint not null,
  -- Derived rather than stored by the caller so the Photos / Videos / Documents views can never disagree
  -- with the file's own type. `like` on text is immutable, which is what a stored generated column needs.
  kind text generated always as (
    case
      when mime_type like 'image/%' then 'image'
      when mime_type like 'video/%' then 'video'
      else 'document'
    end
  ) stored,
  object_key text not null,
  thumbnail_object_key text,
  -- Where the File first entered UCRM. It never changes, even when every link is later removed, so "Not
  -- attached" can still say where a stray file came from.
  origin_type text not null,
  origin_id uuid,
  processing_state text not null default 'pending',
  uploaded_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  trashed_at timestamptz,
  trashed_by uuid references auth.users (id) on delete set null,
  constraint files_display_name_check
    check (char_length(btrim(display_name)) between 1 and 255),
  constraint files_mime_type_check
    check (char_length(btrim(mime_type)) between 1 and 127),
  -- The same 25 MB ceiling `attachments` enforces today. Video raises it in Part 3, from measured mobile
  -- upload and playback evidence rather than a copied competitor number.
  constraint files_size_bytes_check
    check (size_bytes > 0 and size_bytes <= 26214400),
  constraint files_origin_type_check
    check (origin_type = any (array['file_manager', 'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit'])),
  -- A direct library upload has no originating record; every other origin must name one.
  constraint files_origin_id_matches_type_check
    check ((origin_id is null) = (origin_type = 'file_manager')),
  constraint files_processing_state_check
    check (processing_state = any (array['pending', 'available', 'failed', 'quarantined'])),
  constraint files_trashed_by_needs_trashed_at_check
    check (trashed_by is null or trashed_at is not null),
  constraint files_object_key_key unique (object_key),
  constraint files_organization_id_id_key unique (organization_id, id),
  -- Naming the column keeps organization_id, which is NOT NULL, out of the SET NULL: deleting a folder
  -- empties the folder box and leaves the File exactly where it is.
  constraint files_folder_fk
    foreign key (organization_id, folder_id)
    references public.file_folders (organization_id, id) on delete set null (folder_id)
);

comment on table public.files is
  'One manageable business file. Owns exactly one immutable private R2 object; every use of it is a row in public.file_links, never a second copy. Replacing the content creates a new File so issued documents keep what the customer received.';

comment on column public.files.processing_state is
  'pending until the Part 3 pipeline has verified size, type and signature and scanned the object. Only "available" files may be previewed, downloaded, attached or shared with a customer.';

comment on column public.files.thumbnail_object_key is
  'R2 key of the safe preview derivative. Null until the pipeline makes one, and for types that have none. A derivative is never a separate File.';

-- The catalog and its smart views: newest first, cursor paginated on (created_at, id), excluding Trash.
create index if not exists files_catalog_idx
  on public.files (organization_id, created_at desc, id desc)
  where trashed_at is null;

create index if not exists files_kind_idx
  on public.files (organization_id, kind, created_at desc, id desc)
  where trashed_at is null;

create index if not exists files_folder_idx
  on public.files (organization_id, folder_id, created_at desc, id desc)
  where folder_id is not null and trashed_at is null;

-- Trash view, and the 30-day purge sweep that reads it.
create index if not exists files_trashed_idx
  on public.files (organization_id, trashed_at)
  where trashed_at is not null;

create index if not exists files_uploaded_by_idx
  on public.files (uploaded_by)
  where uploaded_by is not null;

create index if not exists files_trashed_by_idx
  on public.files (trashed_by)
  where trashed_by is not null;

create unique index if not exists files_thumbnail_object_key_key
  on public.files (thumbnail_object_key)
  where thumbnail_object_key is not null;

-- ---------------------------------------------------------------------------------------------------------
-- Links
-- ---------------------------------------------------------------------------------------------------------

-- One row per use of a File on one CRM record. Reusing a File adds a row here; it never copies the object.
create table if not exists public.file_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  file_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  role text not null default 'attachment',
  -- True once the customer has already received this use: an issued quote's file, a sent message's
  -- attachment, a shared work report's photo. Its owning domain retires the use before the link can go.
  protected boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint file_links_entity_type_check
    check (entity_type = any (array['client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit'])),
  constraint file_links_role_check
    check (role = any (array['attachment', 'work_photo', 'report_photo'])),
  -- "Repeated appearances inside one record count as one place": the same File cannot be linked to the same
  -- record twice in the same role.
  constraint file_links_unique_use_key unique (file_id, entity_type, entity_id, role),
  constraint file_links_file_fk
    foreign key (organization_id, file_id)
    references public.files (organization_id, id) on delete cascade
);

comment on table public.file_links is
  'Every use of a File on a CRM record. The "Used in" list and its count are the distinct records here that the reader is already allowed to view, so a hidden record can never be inferred from a total.';

-- "Used in": every link for one File. Also the index the composite foreign key needs.
create index if not exists file_links_file_idx
  on public.file_links (organization_id, file_id, created_at desc);

-- A record's own files.
create index if not exists file_links_entity_idx
  on public.file_links (organization_id, entity_type, entity_id, created_at desc);

create index if not exists file_links_created_by_idx
  on public.file_links (created_by)
  where created_by is not null;

-- ---------------------------------------------------------------------------------------------------------
-- Triggers: keep the tables honest
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.files_touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace trigger files_set_updated_at
  before update on public.files
  for each row execute function private.files_touch_updated_at();

create or replace trigger file_folders_set_updated_at
  before update on public.file_folders
  for each row execute function private.files_touch_updated_at();

-- A link must point at a record that really exists inside the same organization. `validate_linked_entity`
-- already does exactly this for attachments, notes and tags, and reads the same three column names.
create or replace trigger file_links_validate_entity
  before insert or update of entity_type, entity_id, organization_id on public.file_links
  for each row execute function private.validate_linked_entity();

-- Protected history, half one: the link itself cannot be removed while it is protected. The owning domain
-- clears `protected` as part of retiring the use (voiding the invoice, replacing the issued quote version),
-- and only then may the link go. This also fires through the cascade from `files`, so a File with a
-- protected use cannot be hard-deleted either.
create or replace function private.file_links_protect_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.protected then
    raise exception 'This file is part of a document the customer already received and cannot be removed from it.'
      using errcode = '23503';
  end if;
  return old;
end;
$$;

create or replace trigger file_links_protect_history
  before delete on public.file_links
  for each row execute function private.file_links_protect_history();

-- Protected history, half two: a File carrying a protected use cannot be moved to Trash. Restoring it, and
-- every other update, stays allowed.
create or replace function private.files_protected_use_blocks_trash()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.trashed_at is not null and old.trashed_at is null then
    if exists (
      select 1
      from public.file_links link
      where link.organization_id = new.organization_id
        and link.file_id = new.id
        and link.protected
    ) then
      raise exception 'This file is part of a document the customer already received, so it cannot be moved to Trash yet.'
        using errcode = '23503';
    end if;
  end if;
  return new;
end;
$$;

create or replace trigger files_protected_use_blocks_trash
  before update of trashed_at on public.files
  for each row execute function private.files_protected_use_blocks_trash();

-- Trigger functions are never called directly, and `authenticated` and `anon` have no USAGE on `private`
-- anyway. Matches 20260921150000.
revoke all on function private.files_touch_updated_at() from public, anon, authenticated;
revoke all on function private.file_links_protect_history() from public, anon, authenticated;
revoke all on function private.files_protected_use_blocks_trash() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Reading rules
-- ---------------------------------------------------------------------------------------------------------

-- Does this reader reach the File through a record they may already view? Kept in `private` and wrapped in a
-- security definer so the policy is one indexed lookup rather than a per-row join the planner has to unpick.
create or replace function private.file_has_visible_link(target_organization_id uuid, target_file_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.file_links link
    where link.organization_id = target_organization_id
      and link.file_id = target_file_id
      and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
  );
$$;

revoke all on function private.file_has_visible_link(uuid, uuid) from public, anon;
grant execute on function private.file_has_visible_link(uuid, uuid) to authenticated;

alter table public.files enable row level security;
alter table public.file_links enable row level security;
alter table public.file_folders enable row level security;

-- Two ways to see a File, and one convenience. Library browsers (files.view) see the whole organization's
-- catalog including Trash and files still being processed. Everyone else sees a File only through a record
-- they may already view, and only once it is available and not in Trash -- File Manager never widens client,
-- job, financial or communication access. The third branch lets an uploader watch their own upload finish
-- before the pipeline has marked it available.
create policy "members can view permitted files" on public.files
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and (
      private.has_permission(organization_id, 'files.view')
      or (
        trashed_at is null
        and processing_state = 'available'
        and private.file_has_visible_link(organization_id, id)
      )
      or (uploaded_by = (select auth.uid()) and trashed_at is null)
    )
  );

-- Deliberately not gated on files.view. A link row is only visible when the reader may view the record it
-- points at, so the "Used in" list and its count are filtered by the database itself: a library browser with
-- no access to a hidden job sees neither the row nor the number. Owners and admins see the complete count
-- because they can already view every record.
create policy "members can view links to records they can see" on public.file_links
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and private.can_view_linked_entity(organization_id, entity_type, entity_id)
  );

create policy "library members can view folders" on public.file_folders
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and private.has_permission(organization_id, 'files.view')
  );

-- No insert, update or delete policy is created on purpose. Uploading, attaching, renaming, moving, sharing,
-- trashing, restoring and purging are each separately authorized inside server-side commands, the way every
-- other write in this codebase works. `authenticated` reaching these tables directly would bypass the
-- verification the contract requires before a file becomes usable.
--
-- A missing policy already denies those writes, but Supabase grants every new public table to anon and
-- authenticated by default, so the privilege is taken away as well rather than left resting on the absence
-- of a policy. Nothing customer-facing reads these tables: a customer reaches a file through the access link
-- its owning document issues, which Part 7 builds.
revoke all on table public.files, public.file_links, public.file_folders from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.files, public.file_links, public.file_folders from authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Backfill from `attachments`
-- ---------------------------------------------------------------------------------------------------------

-- Every existing attachment becomes one File plus one link, reusing the object keys it already has. No R2
-- object is copied, moved, renamed or deleted, and `attachments` itself is not rewritten apart from learning
-- which File it became.
alter table public.attachments
  add column if not exists file_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'attachments_file_fk'
  ) then
    alter table public.attachments
      add constraint attachments_file_fk
      foreign key (organization_id, file_id)
      references public.files (organization_id, id) on delete set null (file_id);
  end if;
end
$$;

comment on column public.attachments.file_id is
  'The File this attachment became when the central catalog was introduced. Nullable while the old and new paths run side by side; Part 5 onward reads the File.';

create index if not exists attachments_file_idx
  on public.attachments (organization_id, file_id)
  where file_id is not null;

-- The backfill lives in a function rather than inline so it can be proven re-runnable and so Part 5 can
-- re-sync anything created between this migration and each domain's adoption. object_key is unique on both
-- tables, so running it twice adds nothing. Rolling the whole thing back is `delete from public.files` plus
-- dropping the column -- the attachment rows and their R2 objects are never touched either way.
create or replace function private.backfill_files_from_attachments()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created integer;
begin

insert into public.files (
  organization_id, display_name, mime_type, size_bytes, object_key, thumbnail_object_key,
  origin_type, origin_id, processing_state, uploaded_by, created_at, updated_at
)
select
  attachment.organization_id,
  attachment.file_name,
  attachment.mime_type,
  attachment.size_bytes,
  attachment.object_key,
  attachment.thumbnail_object_key,
  attachment.entity_type,
  attachment.entity_id,
  -- These files are already live in the app and have been readable for months. Marking them available
  -- states the truth; forcing them through the Part 3 pipeline would hide files contractors use today.
  'available',
  attachment.uploaded_by,
  attachment.created_at,
  attachment.created_at
from public.attachments as attachment
on conflict (object_key) do nothing;

get diagnostics created = row_count;

update public.attachments as attachment
set file_id = file.id
from public.files as file
where file.object_key = attachment.object_key
  and file.organization_id = attachment.organization_id
  and attachment.file_id is distinct from file.id;

-- One link per attachment, in its original place. A use is marked protected when the existing schema already
-- refuses to delete it -- the two ON DELETE RESTRICT references, an issued quote version's file list and a
-- work report's photos. That is a fact already in the database rather than a guess about which quote was
-- sent; Parts 6 and 7 set `protected` precisely as each domain adopts the catalog.
insert into public.file_links (
  organization_id, file_id, entity_type, entity_id, role, protected, created_by, created_at
)
select
  attachment.organization_id,
  attachment.file_id,
  attachment.entity_type,
  attachment.entity_id,
  'attachment',
  (
    exists (
      select 1 from public.quote_version_attachments as quote_file
      where quote_file.organization_id = attachment.organization_id
        and quote_file.attachment_id = attachment.id
    )
    or exists (
      select 1 from public.job_report_photos as report_photo
      where report_photo.organization_id = attachment.organization_id
        and report_photo.attachment_id = attachment.id
    )
  ),
  attachment.uploaded_by,
  attachment.created_at
from public.attachments as attachment
where attachment.file_id is not null
on conflict (file_id, entity_type, entity_id, role) do nothing;

  return created;
end;
$$;

revoke all on function private.backfill_files_from_attachments() from public, anon, authenticated;

select private.backfill_files_from_attachments();
