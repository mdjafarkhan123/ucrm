-- Files and Media, Part 7D-2a: managing customer file shares after they are made.
--
-- The approved behavior is docs/files-media-behavior-contract.md, "How a selected-file share works" (Jafar,
-- 2026-09-24). This adds the two things 7D-1 left out of the database:
--
--   1. Turning a share off. Staff with files.share stop a link early; it writes one Client activity entry,
--      the same way making the share did. Turning off is final -- more time means a new share.
--   2. A turned-off or expired link is no longer the same answer as an unknown one. The customer who holds a
--      once-real link sees that it is no longer active plus the business's phone and email; a link that never
--      existed stays a plain "not found", so the page still cannot be used to discover businesses or shares.
--
-- Additive: one new function, one replaced reader. Rolling back is restoring the 7D-1 reader and dropping
-- turn_off_file_share.

-- ---------------------------------------------------------------------------------------------------------
-- Turning a share off
-- ---------------------------------------------------------------------------------------------------------

-- Service role only. The route has already checked files.share and that the caller can see the share under
-- their own policies; this is the second lock that the share belongs to the organization and the actor.
-- Turning off one that is already off, or already expired, changes nothing and writes no second entry.
create or replace function public.turn_off_file_share(
  target_organization_id uuid,
  target_actor_id uuid,
  target_share_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  share_row public.file_shares;
  file_count integer;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  select * into share_row
  from public.file_shares
  where organization_id = target_organization_id and id = target_share_id
  for update;
  if share_row.id is null then
    raise exception 'That link was not found.' using errcode = 'no_data_found';
  end if;

  if share_row.revoked_at is null and share_row.expires_at > now() then
    update public.file_shares
    set revoked_at = now(), revoked_by = target_actor_id
    where id = share_row.id
    returning * into share_row;

    select count(*) into file_count from public.file_share_items where share_id = share_row.id;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      target_organization_id, 'client', share_row.client_id, 'client.file_share_turned_off',
      case when file_count = 1 then 'Turned off the link to 1 shared file'
           else format('Turned off the link to %s shared files', file_count) end,
      target_actor_id,
      jsonb_build_object('file_share_id', share_row.id, 'file_count', file_count)
    );
  end if;

  return jsonb_build_object(
    'id', share_row.id,
    'client_id', share_row.client_id,
    'revoked_at', share_row.revoked_at,
    'expires_at', share_row.expires_at
  );
end;
$$;

comment on function public.turn_off_file_share(uuid, uuid, uuid) is
  'Stops one customer file share early and writes one Client activity entry. Idempotent: an already off or expired share is left as it is. Service role only: the calling route checks files.share and the caller''s own view of the share first.';

revoke all on function public.turn_off_file_share(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.turn_off_file_share(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- The customer's reader, now telling "no longer active" apart from "never existed"
-- ---------------------------------------------------------------------------------------------------------

-- Null only for a link that never existed. A real link answers with its state:
--   active   -> the business and the still-shareable Files (frozen names), as before;
--   inactive -> the business with its phone and email, and no Files at all.
-- The email is the business's own sending address -- the one its customer emails come from -- chosen the
-- same way the senders' own readiness query chooses it.
create or replace function public.resolve_file_share(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  share_row public.file_shares;
  business jsonb;
  shared jsonb;
  is_active boolean;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into share_row from public.file_shares where token_hash = supplied_token_hash;
  if share_row.id is null then
    return null;
  end if;

  is_active := share_row.revoked_at is null and share_row.expires_at > now();

  select jsonb_build_object(
           'name', organization.name,
           'logo_object_key', settings.logo_object_key,
           'phone', nullif(btrim(settings.phone), ''),
           'email', (
             select sender.email_address
             from public.communication_email_senders as sender
             where sender.organization_id = organization.id
               and sender.lifecycle_state = 'enabled'
             order by sender.is_organization_default desc, sender.created_at
             limit 1
           )
         )
    into business
  from public.organizations as organization
  left join public.organization_settings as settings on settings.organization_id = organization.id
  where organization.id = share_row.organization_id;

  if not is_active then
    return jsonb_build_object('state', 'inactive', 'business', business);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', file.id,
           'name', item.shared_name,
           'mime_type', file.mime_type,
           'kind', file.kind,
           'size_bytes', file.size_bytes,
           'object_key', file.object_key,
           'thumbnail_object_key', file.thumbnail_object_key
         ) order by item.position), '[]'::jsonb)
    into shared
  from public.file_share_items as item
  join public.files as file
    on file.organization_id = item.organization_id and file.id = item.file_id
  where item.share_id = share_row.id
    and file.trashed_at is null
    and file.processing_state = 'available';

  return jsonb_build_object(
    'state', 'active',
    'business', business,
    'expires_at', share_row.expires_at,
    'files', shared
  );
end;
$$;

comment on function public.resolve_file_share(bytea) is
  'The customer''s reader for a file share. Hashed token in. Null for a link that never existed; {state: inactive, business} for a turned-off or expired one; {state: active, business, expires_at, files} otherwise, with only the live shared Files under their frozen names. Service role only.';

revoke all on function public.resolve_file_share(bytea) from public, anon, authenticated;
grant execute on function public.resolve_file_share(bytea) to service_role;
