-- Files and Media, Part 4B: the manage actions -- rename, move, new folder, Trash and restore.
--
-- Part 2 created the three tables with read policies only and took INSERT/UPDATE/DELETE away from
-- `authenticated` on purpose: "every insert, update and delete goes through a server-side command". Part 3
-- wrote the upload half of that promise (`register_pending_file`, `complete_file_upload`). This migration
-- writes the other half, in the same shape: `security definer`, service role only, every argument re-checked
-- so the function is a second lock rather than a first one. The route has already checked the caller's
-- files.manage or files.trash permission before it gets here.
--
-- Nothing structural changes. No table, column, constraint, policy or table grant is touched, and rolling
-- this back is `drop function`.
--
-- One behavior deserves calling out, because it is destructive and the contract asks for it explicitly.
-- `docs/files-media-behavior-contract.md` says moving a File to Trash "first shows every affected visible
-- record and the consequence", and that "ordinary unprotected links may be removed only through that
-- confirmed action". So trashing a File detaches it from every record using it. The alternative -- keeping
-- the links and hiding the File -- would leave a job or a quote pointing at something the contractor cannot
-- see, which is worse than a clean detach they were warned about. Restoring brings the File and its folder
-- back; it does not put it back on those records, and the confirmation says so.

-- ---------------------------------------------------------------------------------------------------------
-- The shared second lock
-- ---------------------------------------------------------------------------------------------------------

-- `register_pending_file` already refuses an uploader who is not a member of the organization it was handed.
-- Five more commands need the same sentence, so it lives in one place. It is not the permission check --
-- files.manage and files.trash are the route's job, resolved from the caller's own session -- it is the
-- check that the organization and the person named in the arguments actually belong together.
create or replace function private.assert_file_actor(
  target_organization_id uuid,
  target_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1 from public.organization_members member
    where member.organization_id = target_organization_id
      and member.user_id = target_actor_id
  ) then
    raise exception 'That person is not a member of this organization.'
      using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function private.assert_file_actor(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Rename
-- ---------------------------------------------------------------------------------------------------------

-- The file name is what a download saves as and what search matches, so it is trimmed and length-checked
-- here as well as by files_display_name_check. Keeping the extension is the caller's job: the route does it
-- in one place so "Boiler before" cannot silently turn a .jpg into a file the contractor's computer will
-- not open.
create or replace function public.rename_file(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid,
  target_display_name text
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  renamed public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  update public.files
  set display_name = btrim(target_display_name)
  where id = target_file_id
    and organization_id = target_organization_id
    and trashed_at is null
  returning * into renamed;

  if renamed.id is null then
    raise exception 'That file was not found.' using errcode = 'no_data_found';
  end if;

  return renamed;
end;
$$;

comment on function public.rename_file(uuid, uuid, uuid, text) is
  'Renames one live File. Service role only: the calling route checks files.manage and preserves the file extension first.';

-- ---------------------------------------------------------------------------------------------------------
-- Move between folders
-- ---------------------------------------------------------------------------------------------------------

-- A folder is a display grouping, so this changes no link and no attachment. Passing null is "no folder",
-- which is why the target folder is checked for existence rather than leaned on the foreign key: the
-- composite FK would accept null silently and the contractor would watch a file leave a folder they meant
-- to move it into.
create or replace function public.move_file_to_folder(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid,
  target_folder_id uuid default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  moved public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  if target_folder_id is not null and not exists (
    select 1 from public.file_folders folder
    where folder.organization_id = target_organization_id
      and folder.id = target_folder_id
  ) then
    raise exception 'That folder was not found.' using errcode = 'no_data_found';
  end if;

  update public.files
  set folder_id = target_folder_id
  where id = target_file_id
    and organization_id = target_organization_id
    and trashed_at is null
  returning * into moved;

  if moved.id is null then
    raise exception 'That file was not found.' using errcode = 'no_data_found';
  end if;

  return moved;
end;
$$;

comment on function public.move_file_to_folder(uuid, uuid, uuid, uuid) is
  'Puts one live File in a folder, or in no folder when the target is null. Changes no link. Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- New folder
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.create_file_folder(
  target_organization_id uuid,
  target_created_by uuid,
  target_name text
)
returns public.file_folders
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created public.file_folders;
begin
  perform private.assert_file_actor(target_organization_id, target_created_by);

  insert into public.file_folders (organization_id, name, created_by)
  values (target_organization_id, btrim(target_name), target_created_by)
  returning * into created;

  return created;
exception
  -- file_folders_unique_name_idx is case- and space-insensitive, so "Boiler jobs" and "boiler jobs " are the
  -- same folder. Saying so beats a duplicate the contractor then has to tell apart.
  when unique_violation then
    raise exception 'You already have a folder with that name.' using errcode = 'unique_violation';
end;
$$;

comment on function public.create_file_folder(uuid, uuid, text) is
  'Creates one flat File Manager folder. Service role only: the calling route checks files.manage first.';

-- ---------------------------------------------------------------------------------------------------------
-- Trash and restore
-- ---------------------------------------------------------------------------------------------------------

-- Moving a File to Trash detaches it from every record using it, which is what the behavior contract calls
-- the confirmed action. A File carrying a use the customer already received cannot go at all, and it is
-- refused here with the same words the contractor saw next to the padlock rather than by a raw trigger
-- error, so the message does not depend on which of the two guards fires first.
create or replace function public.trash_file(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  trashed public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  if not exists (
    select 1 from public.files file
    where file.id = target_file_id
      and file.organization_id = target_organization_id
      and file.trashed_at is null
  ) then
    raise exception 'That file was not found.' using errcode = 'no_data_found';
  end if;

  if exists (
    select 1 from public.file_links link
    where link.organization_id = target_organization_id
      and link.file_id = target_file_id
      and link.protected
  ) then
    raise exception 'This file is part of a document the customer already received, so it cannot be moved to Trash yet.'
      using errcode = 'check_violation';
  end if;

  -- Every remaining use is unprotected, so this is the detach the contractor confirmed. file_links_file_idx
  -- serves it, and the protect-history trigger is still underneath as the structural guarantee.
  delete from public.file_links
  where organization_id = target_organization_id
    and file_id = target_file_id;

  update public.files
  set trashed_at = now(),
      trashed_by = target_actor_id
  where id = target_file_id
    and organization_id = target_organization_id
    and trashed_at is null
  returning * into trashed;

  return trashed;
end;
$$;

comment on function public.trash_file(uuid, uuid, uuid) is
  'Moves one File to Trash and detaches it from every record using it, per the behavior contract''s confirmed action. Refuses a File carrying a use the customer already received. Service role only.';

-- The File comes back where it was, including its folder -- trashing never cleared folder_id, and if the
-- folder itself was deleted meanwhile the foreign key already emptied the box. Links do not come back; the
-- confirmation that removed them said so.
create or replace function public.restore_file(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  restored public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  update public.files
  set trashed_at = null,
      trashed_by = null
  where id = target_file_id
    and organization_id = target_organization_id
    and trashed_at is not null
  returning * into restored;

  if restored.id is null then
    raise exception 'That file is not in Trash.' using errcode = 'no_data_found';
  end if;

  return restored;
end;
$$;

comment on function public.restore_file(uuid, uuid, uuid) is
  'Takes one File back out of Trash, into the folder it was in. Does not re-attach it to records. Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------------------------------------

-- Same posture as the Part 3 pipeline functions: the service role calls them from a route that has already
-- checked the permission, and a signed-in user cannot reach them directly.
revoke all on function public.rename_file(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.move_file_to_folder(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.create_file_folder(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.trash_file(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.restore_file(uuid, uuid, uuid) from public, anon, authenticated;
