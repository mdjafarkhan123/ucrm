-- Files and Media, Part 7B-1: photo captions and labels.
--
-- Decisions (docs/files-media-behavior-contract.md, Part 7B, approved by Jafar 2026-09-24) follow CompanyCam:
--   * One optional caption per photo, stored on the File so it reads the same everywhere the photo appears.
--   * Labels come from one organization-wide list, seeded with Before / During / After / Damage. A photo can
--     carry several. files.manage holders curate the list; everyone else only picks from it.
--   * Who may caption and label is decided by the calling route (files.manage, or the right to add photos to
--     a job or visit the photo is on). These commands are the second lock, exactly like rename_file.
--
-- Captions and labels are photo-only. A document keeps its file name, and the contract scopes 7B to photos.
--
-- Rolling back: drop the four commands, the seed trigger and functions, the two tables, and files.caption.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Caption on the File
-- ---------------------------------------------------------------------------------------------------------

alter table public.files add column if not exists caption text;

-- Null is "no caption"; the command turns an empty box into null, so a blank caption never exists.
alter table public.files
  add constraint files_caption_check
    check (caption is null or char_length(btrim(caption)) between 1 and 500);

comment on column public.files.caption is
  'Optional one-line description of a photo, written once and shown wherever the photo appears. Photos only.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. The organization's label list
-- ---------------------------------------------------------------------------------------------------------

create table if not exists public.file_labels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint file_labels_name_check check (char_length(btrim(name)) between 1 and 40),
  constraint file_labels_organization_id_id_key unique (organization_id, id)
);

comment on table public.file_labels is
  'One organization-wide list of photo labels (Before, After, Damage, Kitchen...). Curated by files.manage holders.';

-- "Before" and "before " are the same label, as with folder names.
create unique index if not exists file_labels_unique_name_idx
  on public.file_labels (organization_id, lower(btrim(name)));

create index if not exists file_labels_created_by_idx
  on public.file_labels (created_by)
  where created_by is not null;

-- ---------------------------------------------------------------------------------------------------------
-- 3. Which labels a photo carries
-- ---------------------------------------------------------------------------------------------------------

create table if not exists public.file_label_assignments (
  organization_id uuid not null,
  file_id uuid not null,
  label_id uuid not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint file_label_assignments_pkey primary key (organization_id, file_id, label_id),
  -- Composite keys keep a label and a photo from ever pairing across organizations.
  constraint file_label_assignments_file_fk foreign key (organization_id, file_id)
    references public.files (organization_id, id) on delete cascade,
  constraint file_label_assignments_label_fk foreign key (organization_id, label_id)
    references public.file_labels (organization_id, id) on delete cascade
);

comment on table public.file_label_assignments is
  'The labels on one photo. Removing a label from the list removes it from every photo.';

-- The primary key serves "labels on this photo". This one serves "photos with this label" and the cascade
-- when a label is deleted.
create index if not exists file_label_assignments_label_idx
  on public.file_label_assignments (organization_id, label_id);

create index if not exists file_label_assignments_created_by_idx
  on public.file_label_assignments (created_by)
  where created_by is not null;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Reading rules
-- ---------------------------------------------------------------------------------------------------------

alter table public.file_labels enable row level security;
alter table public.file_label_assignments enable row level security;

-- Every member may read the list: a field member picking "Before" on a job photo needs it, and a label name
-- reveals nothing about any customer.
create policy "members can view file labels" on public.file_labels
  for select to authenticated
  using (private.is_organization_member(organization_id));

-- A photo's labels are visible exactly when the photo is, by the same two routes the files policy uses.
create policy "members can view labels on files they can see" on public.file_label_assignments
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and (
      private.has_permission(organization_id, 'files.view')
      or private.file_has_visible_link(organization_id, file_id)
    )
  );

-- Writes go through the commands below only, like every other Files table.
revoke all on table public.file_labels, public.file_label_assignments from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.file_labels, public.file_label_assignments from authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 5. Starter labels
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.seed_file_labels(target_organization_id uuid)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into public.file_labels (organization_id, name)
  values
    (target_organization_id, 'Before'),
    (target_organization_id, 'During'),
    (target_organization_id, 'After'),
    (target_organization_id, 'Damage')
  on conflict do nothing;
$$;

create or replace function private.create_file_labels()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform private.seed_file_labels(new.id);
  return new;
end;
$$;

create or replace trigger organizations_create_file_labels
  after insert on public.organizations
  for each row execute function private.create_file_labels();

revoke all on function private.seed_file_labels(uuid) from public, anon, authenticated;
revoke all on function private.create_file_labels() from public, anon, authenticated;

-- Every organization that exists today starts with the same four.
select private.seed_file_labels(organization.id) from public.organizations organization;

-- ---------------------------------------------------------------------------------------------------------
-- 6. Commands (service role only; the route checks the permission first)
-- ---------------------------------------------------------------------------------------------------------

-- Caption and labels together, because the details panel saves them as one decision. Either may be left
-- untouched: a null label list means "keep the labels", an empty one means "no labels".
create or replace function public.describe_file(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid,
  set_caption boolean,
  target_caption text,
  target_label_ids uuid[]
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  described public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  select * into described
  from public.files file
  where file.id = target_file_id
    and file.organization_id = target_organization_id
    and file.trashed_at is null
  for update;

  if described.id is null then
    raise exception 'That file was not found.' using errcode = 'no_data_found';
  end if;
  if described.kind <> 'image' then
    raise exception 'Only photos take a caption or labels.' using errcode = 'check_violation';
  end if;

  if set_caption then
    update public.files
    set caption = nullif(btrim(coalesce(target_caption, '')), '')
    where id = described.id
      and organization_id = target_organization_id
    returning * into described;
  end if;

  if target_label_ids is not null then
    if exists (
      select 1 from unnest(target_label_ids) as wanted(label_id)
      where not exists (
        select 1 from public.file_labels label
        where label.organization_id = target_organization_id
          and label.id = wanted.label_id
      )
    ) then
      -- A label a colleague deleted while this panel was open. Saying so beats silently dropping it.
      raise exception 'One of those labels no longer exists.' using errcode = 'P0404';
    end if;

    delete from public.file_label_assignments assignment
    where assignment.organization_id = target_organization_id
      and assignment.file_id = described.id
      and assignment.label_id <> all (target_label_ids);

    insert into public.file_label_assignments (organization_id, file_id, label_id, created_by)
    select target_organization_id, described.id, wanted.label_id, target_actor_id
    from (select distinct unnest(target_label_ids) as label_id) as wanted
    on conflict do nothing;
  end if;

  return described;
end;
$$;

comment on function public.describe_file(uuid, uuid, uuid, boolean, text, uuid[]) is
  'Sets one live photo''s caption and/or its labels. Service role only: the route checks files.manage or the right to add photos to a job or visit the photo is on.';

-- The list is short by nature (CompanyCam users keep a few dozen); 100 stops a runaway script, not a person.
create or replace function public.create_file_label(
  target_organization_id uuid,
  target_actor_id uuid,
  target_name text
)
returns public.file_labels
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created public.file_labels;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  -- Serialize creates per organization so two people cannot both slip under the ceiling.
  perform pg_advisory_xact_lock(hashtextextended('file_labels:' || target_organization_id::text, 0));
  if (select count(*) from public.file_labels where organization_id = target_organization_id) >= 100 then
    raise exception 'You can have up to 100 labels.' using errcode = 'check_violation';
  end if;

  insert into public.file_labels (organization_id, name, created_by)
  values (target_organization_id, btrim(target_name), target_actor_id)
  returning * into created;

  return created;
exception
  when unique_violation then
    raise exception 'You already have a label with that name.' using errcode = 'unique_violation';
end;
$$;

comment on function public.create_file_label(uuid, uuid, text) is
  'Adds one label to the organization''s photo label list. Service role only: the route checks files.manage.';

create or replace function public.rename_file_label(
  target_organization_id uuid,
  target_label_id uuid,
  target_actor_id uuid,
  target_name text
)
returns public.file_labels
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  renamed public.file_labels;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  update public.file_labels
  set name = btrim(target_name)
  where id = target_label_id
    and organization_id = target_organization_id
  returning * into renamed;

  if renamed.id is null then
    raise exception 'That label was not found.' using errcode = 'no_data_found';
  end if;

  return renamed;
exception
  when unique_violation then
    raise exception 'You already have a label with that name.' using errcode = 'unique_violation';
end;
$$;

comment on function public.rename_file_label(uuid, uuid, uuid, text) is
  'Renames one photo label; every photo carrying it shows the new name. Service role only: the route checks files.manage.';

-- Deleting a label takes it off every photo (the assignment foreign key cascades). Photos are untouched.
create or replace function public.delete_file_label(
  target_organization_id uuid,
  target_label_id uuid,
  target_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  delete from public.file_labels
  where id = target_label_id
    and organization_id = target_organization_id;

  if not found then
    raise exception 'That label was not found.' using errcode = 'no_data_found';
  end if;
end;
$$;

comment on function public.delete_file_label(uuid, uuid, uuid) is
  'Removes one label from the list and from every photo carrying it. Service role only: the route checks files.manage.';

revoke all on function public.describe_file(uuid, uuid, uuid, boolean, text, uuid[]) from public, anon, authenticated;
revoke all on function public.create_file_label(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.rename_file_label(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.delete_file_label(uuid, uuid, uuid) from public, anon, authenticated;
