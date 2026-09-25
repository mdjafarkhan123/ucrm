-- Files and Media, Part 7D-1: a customer file share -- a link to a handful of chosen Files.
--
-- The approved behavior is docs/files-media-behavior-contract.md, "How a selected-file share works" (Jafar,
-- 2026-09-24): staff pick up to 50 available Files and one Client, choose 7, 30 or 90 days, and get a link.
-- The customer's page shows exactly those Files under the names they had when shared, and nothing else from
-- the library.
--
-- The link itself is the shape job_report_access_links already proved: only a SHA-256 hash of the token is
-- stored, the raw token exists once in the response to the person who made it, and the customer's reader is
-- a service-role-only function that answers null for every kind of failure alike.
--
-- A share is fixed once made. It never gains Files and its expiry never moves, so there is no update path
-- here except the view stamp. Turning a share off, the staff list and the expired/off contact page are 7D-2.
--
-- Additive only: two new tables, one permission, three functions. Rolling back is dropping them.

-- ---------------------------------------------------------------------------------------------------------
-- Permission
-- ---------------------------------------------------------------------------------------------------------

insert into public.permissions (description, key, scope_model)
values ('Share chosen files with a customer by link', 'files.share', 'none')
on conflict (key) do nothing;

-- The same three roles that run the library. Sales, finance and field members do not hand library files to
-- customers; a quote, an invoice or a work report is how their work reaches a customer.
insert into public.role_permissions (access_scope, permission_key, role)
values
  ('all', 'files.share', 'owner'),
  ('all', 'files.share', 'admin'),
  ('all', 'files.share', 'office')
on conflict (role, permission_key) do nothing;

-- ---------------------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------------------

create table if not exists public.file_shares (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  client_id uuid not null,
  token_hash bytea not null,
  issued_by uuid references auth.users (id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by uuid references auth.users (id) on delete set null,
  first_viewed_at timestamptz,
  last_viewed_at timestamptz,
  view_count integer not null default 0,
  constraint file_shares_token_hash_check check (octet_length(token_hash) = 32),
  constraint file_shares_token_hash_key unique (token_hash),
  constraint file_shares_expiry_follows_issue check (expires_at > issued_at),
  constraint file_shares_revoked_by_needs_revoked_at check (revoked_by is null or revoked_at is not null),
  constraint file_shares_view_count_check check (view_count >= 0),
  constraint file_shares_organization_id_id_key unique (organization_id, id),
  constraint file_shares_client_fkey
    foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete cascade
);

comment on table public.file_shares is
  'One customer link to a fixed set of chosen Files for one Client. Stores only the token hash; the raw token exists once, in the response to the staff member who made it. Never gains Files and never changes expiry.';

-- The 7D-2 staff list (newest first) and the Client's own "shared with" view read these.
create index if not exists file_shares_organization_issued_idx
  on public.file_shares (organization_id, issued_at desc);
create index if not exists file_shares_client_idx
  on public.file_shares (organization_id, client_id);
create index if not exists file_shares_issued_by_idx
  on public.file_shares (issued_by) where issued_by is not null;
create index if not exists file_shares_revoked_by_idx
  on public.file_shares (revoked_by) where revoked_by is not null;

create table if not exists public.file_share_items (
  organization_id uuid not null,
  share_id uuid not null,
  file_id uuid not null,
  -- What the customer sees. Frozen at share time so a later rename in the library never changes a page
  -- already in front of the customer.
  shared_name text not null,
  position smallint not null,
  primary key (share_id, file_id),
  constraint file_share_items_shared_name_check
    check (char_length(btrim(shared_name)) between 1 and 255),
  constraint file_share_items_position_check check (position between 0 and 49),
  constraint file_share_items_share_position_key unique (share_id, position),
  constraint file_share_items_share_fkey
    foreign key (organization_id, share_id)
    references public.file_shares (organization_id, id) on delete cascade,
  -- A permanently purged File leaves the share; a trashed one stays but is hidden by the reader.
  constraint file_share_items_file_fkey
    foreign key (organization_id, file_id)
    references public.files (organization_id, id) on delete cascade
);

comment on table public.file_share_items is
  'The Files one customer share names, in the order chosen, under the name each had when shared.';

-- A File's details panel ("shared with") and the Trash warning look shares up by File.
create index if not exists file_share_items_file_idx
  on public.file_share_items (organization_id, file_id);

alter table public.file_shares enable row level security;
alter table public.file_share_items enable row level security;

-- Staff who may share may also see the organization's shares. Writes go only through the functions below.
create policy "sharers can view file shares" on public.file_shares
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and private.has_permission(organization_id, 'files.share')
  );

create policy "sharers can view file share items" on public.file_share_items
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and private.has_permission(organization_id, 'files.share')
  );

revoke all on table public.file_shares, public.file_share_items from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.file_shares, public.file_share_items from authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Making a share
-- ---------------------------------------------------------------------------------------------------------

-- Service role only. The route has already checked the caller's files.share permission and that the caller
-- can see the Client and every File under their own policies; this is the second lock that the organization,
-- the person, the Client and the Files all belong together and that every File is shareable right now.
create or replace function public.create_file_share(
  target_organization_id uuid,
  target_actor_id uuid,
  target_client_id uuid,
  target_file_ids uuid[],
  target_days integer,
  supplied_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  file_count integer := coalesce(array_length(target_file_ids, 1), 0);
  distinct_count integer;
  shareable_count integer;
  client_name text;
  share_row public.file_shares;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'A customer link needs a full-length token.' using errcode = 'check_violation';
  end if;

  if target_days is null or target_days not in (7, 30, 90) then
    raise exception 'A share lasts 7, 30 or 90 days.' using errcode = 'check_violation';
  end if;

  select count(distinct file_id) into distinct_count from unnest(target_file_ids) as file_id;
  if file_count = 0 or file_count > 50 or distinct_count <> file_count then
    raise exception 'Choose between 1 and 50 different files to share.' using errcode = 'check_violation';
  end if;

  select client.display_name into client_name
  from public.clients as client
  where client.organization_id = target_organization_id and client.id = target_client_id;
  if client_name is null then
    raise exception 'That client was not found.' using errcode = 'no_data_found';
  end if;

  select count(*) into shareable_count
  from public.files as file
  where file.organization_id = target_organization_id
    and file.id = any (target_file_ids)
    and file.processing_state = 'available'
    and file.trashed_at is null;
  if shareable_count <> file_count then
    -- Checked again at the moment of sharing: a File can be trashed, or still be checking, after the
    -- dialog was opened.
    raise exception 'One of those files is still being checked or is in Trash. Choose again.'
      using errcode = 'P0409';
  end if;

  insert into public.file_shares (
    organization_id, client_id, token_hash, issued_by, expires_at
  ) values (
    target_organization_id, target_client_id, supplied_token_hash, target_actor_id,
    now() + make_interval(days => target_days)
  )
  returning * into share_row;

  insert into public.file_share_items (organization_id, share_id, file_id, shared_name, position)
  select target_organization_id, share_row.id, file.id, file.display_name, (chosen.ordinality - 1)::smallint
  from unnest(target_file_ids) with ordinality as chosen (file_id, ordinality)
  join public.files as file
    on file.organization_id = target_organization_id and file.id = chosen.file_id;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    target_organization_id, 'client', target_client_id, 'client.files_shared',
    case when file_count = 1 then 'Shared 1 file with the customer'
         else format('Shared %s files with the customer', file_count) end,
    target_actor_id,
    jsonb_build_object('file_share_id', share_row.id, 'file_count', file_count,
                       'expires_at', share_row.expires_at)
  );

  return jsonb_build_object(
    'id', share_row.id,
    'client_id', target_client_id,
    'client_name', client_name,
    'file_count', file_count,
    'issued_at', share_row.issued_at,
    'expires_at', share_row.expires_at
  );
end;
$$;

comment on function public.create_file_share(uuid, uuid, uuid, uuid[], integer, bytea) is
  'Makes one customer file share: 1-50 available Files, one Client, 7/30/90 days, names frozen now. Writes one Client activity entry. Returns everything but the token. Service role only: the calling route checks files.share and the caller''s own view of the Client and Files first.';

-- ---------------------------------------------------------------------------------------------------------
-- The customer's reader
-- ---------------------------------------------------------------------------------------------------------

-- Hashed token in; the business and the still-shareable Files out, or null for every failure alike. A File
-- moved to Trash since sharing simply stops appearing. `object_key` is included for the server route that
-- streams the bytes; the page never forwards it to the browser.
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
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into share_row from public.file_shares where token_hash = supplied_token_hash;
  if share_row.id is null or share_row.revoked_at is not null or share_row.expires_at <= now() then
    return null;
  end if;

  select jsonb_build_object(
           'name', organization.name,
           'logo_object_key', settings.logo_object_key
         )
    into business
  from public.organizations as organization
  left join public.organization_settings as settings on settings.organization_id = organization.id
  where organization.id = share_row.organization_id;

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
    'business', business,
    'expires_at', share_row.expires_at,
    'files', shared
  );
end;
$$;

comment on function public.resolve_file_share(bytea) is
  'The customer''s reader for a file share. Hashed token in, business plus the live shared Files (frozen names) out, or null for unknown, turned off or expired alike. Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- "The customer opened it"
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.record_file_share_view(supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  share_id uuid;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  update public.file_shares
  set first_viewed_at = coalesce(first_viewed_at, now()),
      last_viewed_at = now(),
      view_count = view_count + 1
  where token_hash = supplied_token_hash
    and revoked_at is null
    and expires_at > now()
  returning id into share_id;

  if share_id is null then
    return null;
  end if;
  return jsonb_build_object('recorded', true);
end;
$$;

comment on function public.record_file_share_view(bytea) is
  'The customer''s browser saying the shared files were on screen. Stamps the share''s view facts. Service role only.';

revoke all on function public.create_file_share(uuid, uuid, uuid, uuid[], integer, bytea) from public, anon, authenticated;
revoke all on function public.resolve_file_share(bytea) from public, anon, authenticated;
revoke all on function public.record_file_share_view(bytea) from public, anon, authenticated;
grant execute on function public.create_file_share(uuid, uuid, uuid, uuid[], integer, bytea) to service_role;
grant execute on function public.resolve_file_share(bytea) to service_role;
grant execute on function public.record_file_share_view(bytea) to service_role;
