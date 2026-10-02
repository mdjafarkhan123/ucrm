-- Pipeline E3: a Brief Note can carry photos and files, and can mention a teammate, who is alerted.
--
-- Files. Jobber keeps a note's attachments inside the note, so a File added to a Note lives on the Note
-- (public.note_files), wherever that Note shows -- the Brief, the Request's Notes, the Client's Notes. The File
-- Manager still has to know where each File is used, or "Not attached" would offer note photos for cleanup and
-- a teammate who can open the Request could not see them. So, exactly as a quote line's photo does, every
-- record a Note sits on also carries the File with the file_links role 'note_file'. That link is kept by the
-- triggers below, exists only once the File has passed its checks, and stays off the record's Files card.
--
-- Mentions. HubSpot and Pipedrive alert a teammate tagged in a note, and only someone who can open the record.
-- A mention is a row in public.note_mentions; the Note's text keeps the plain "@Name". Only a teammate who may
-- see the Pipeline can be mentioned. Each newly mentioned teammate gets one bell alert and one email that
-- opens the card; mentioning yourself, or keeping a mention when the Note is edited, sends nothing.

-- 1. Where a Note's Files and mentions live -------------------------------------------------------------------

create table public.note_files (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  note_id uuid not null,
  file_id uuid not null,
  position smallint not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint note_files_pkey primary key (note_id, file_id),
  constraint note_files_position_check check (position between 0 and 9),
  constraint note_files_note_fk
    foreign key (organization_id, note_id) references public.notes (organization_id, id) on delete cascade,
  constraint note_files_file_fk
    foreign key (organization_id, file_id) references public.files (organization_id, id) on delete cascade
);

comment on table public.note_files is
  'The photos and files a Note carries, in the order they were added. Each record the Note is on also holds the File with file_links role ''note_file'', kept by trigger, so the File Manager knows where it is used.';

create index note_files_file_idx on public.note_files (organization_id, file_id);
create index note_files_created_by_idx on public.note_files (created_by) where created_by is not null;

create table public.note_mentions (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  note_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint note_mentions_pkey primary key (note_id, user_id),
  constraint note_mentions_note_fk
    foreign key (organization_id, note_id) references public.notes (organization_id, id) on delete cascade
);

comment on table public.note_mentions is
  'Teammates tagged in a Note. The Note text keeps the plain "@Name"; this row is what alerted them.';

create index note_mentions_user_idx on public.note_mentions (user_id);

-- Readable by whoever can read the Note itself; written only by the checked functions below.
alter table public.note_files enable row level security;
alter table public.note_mentions enable row level security;

create policy "members can view files on notes they can see" on public.note_files
  for select to authenticated
  using (
    exists (
      select 1 from public.note_links as link
      where link.note_id = note_files.note_id
        and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
    )
  );

create policy "members can view mentions on notes they can see" on public.note_mentions
  for select to authenticated
  using (
    exists (
      select 1 from public.note_links as link
      where link.note_id = note_mentions.note_id
        and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
    )
  );

revoke all on public.note_files, public.note_mentions from anon, authenticated;
grant select on public.note_files, public.note_mentions to authenticated;

-- 2. The 'note_file' role and upload origin ------------------------------------------------------------------

alter table public.file_links drop constraint file_links_role_check;
alter table public.file_links add constraint file_links_role_check
  check (role = any (array[
    'attachment', 'work_photo', 'report_photo', 'line_photo', 'logo', 'campaign_image', 'item_photo', 'note_file'
  ]));

alter table public.files drop constraint files_origin_role_check;
alter table public.files add constraint files_origin_role_check
  check (origin_role = any (array['attachment', 'line_photo', 'logo', 'campaign_image', 'item_photo', 'note_file']));

-- 3. Keeping the 'note_file' links true ---------------------------------------------------------------------
--
-- A link exists while some Note on that record holds that File and the File is available. Each prune reads
-- only what is left in the tables, so a Note deleted with its links and files in one cascade ends correct
-- whichever side Postgres removes first.

create function private.link_note_files()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_table_name = 'note_files' then
    insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
    select new.organization_id, new.file_id, link.entity_type, link.entity_id, 'note_file', new.created_by
    from public.note_links as link
    join public.files as file on file.organization_id = new.organization_id and file.id = new.file_id
    where link.note_id = new.note_id
      and file.processing_state = 'available'
      and file.trashed_at is null
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  else
    insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
    select new.organization_id, held.file_id, new.entity_type, new.entity_id, 'note_file', held.created_by
    from public.note_files as held
    join public.files as file on file.organization_id = held.organization_id and file.id = held.file_id
    where held.note_id = new.note_id
      and file.processing_state = 'available'
      and file.trashed_at is null
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;
  return null;
end;
$$;

create function private.prune_note_file_links()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  delete from public.file_links as link
  where link.organization_id = old.organization_id
    and link.role = 'note_file'
    and (
      (tg_table_name = 'note_files' and link.file_id = old.file_id)
      or (tg_table_name = 'note_links' and link.entity_type = old.entity_type and link.entity_id = old.entity_id)
    )
    and not exists (
      select 1
      from public.note_files as held
      join public.note_links as placed on placed.note_id = held.note_id
      where held.file_id = link.file_id
        and placed.entity_type = link.entity_type
        and placed.entity_id = link.entity_id
    );
  return null;
end;
$$;

revoke all on function private.link_note_files() from public, anon, authenticated;
revoke all on function private.prune_note_file_links() from public, anon, authenticated;

create trigger note_files_link after insert on public.note_files
  for each row execute function private.link_note_files();
create trigger note_links_link_files after insert on public.note_links
  for each row execute function private.link_note_files();
create trigger note_files_prune after delete on public.note_files
  for each row execute function private.prune_note_file_links();
create trigger note_links_prune_files after delete on public.note_links
  for each row execute function private.prune_note_file_links();

-- Trash lets go of every editable use (trash_file); a Note is editable, so it lets go of the File too.
-- Restoring the File does not put it back, as the Trash dialog already says.
create function private.release_trashed_note_files()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  delete from public.note_files where organization_id = new.organization_id and file_id = new.id;
  return null;
end;
$$;

revoke all on function private.release_trashed_note_files() from public, anon, authenticated;

create trigger files_release_note_files
  after update of trashed_at on public.files
  for each row when (old.trashed_at is null and new.trashed_at is not null)
  execute function private.release_trashed_note_files();

-- 4. A Note's File joins its records once it passes its checks -------------------------------------------------
--
-- Unchanged from 20260928230000 except: a 'note_file' upload is not linked to the record it was uploaded from
-- (it may never be saved onto a Note), and is linked instead to every record a Note holding it is on.

create or replace function public.finalize_file_processing(
  target_file_id uuid,
  target_claim_token uuid,
  target_state text,
  target_checksum_sha256 text default null,
  target_error text default null,
  target_thumbnail_object_key text default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed public.files;
  finalized public.files;
begin
  if target_state not in ('available', 'failed', 'quarantined') then
    raise exception 'A file can only finish processing as available, failed or quarantined.'
      using errcode = 'check_violation';
  end if;

  if target_state = 'available' and target_checksum_sha256 is null then
    raise exception 'A file cannot be made available without the checksum from its verification pass.'
      using errcode = 'check_violation';
  end if;

  select * into claimed
  from public.files
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending'
  for update;

  if claimed.id is null then
    raise exception 'That file processing claim is no longer current.'
      using errcode = 'no_data_found';
  end if;

  if target_thumbnail_object_key is not null
     and target_thumbnail_object_key is distinct from claimed.object_key || '.thumb.jpg' then
    raise exception 'That preview does not belong to this file.'
      using errcode = 'check_violation';
  end if;

  if target_state <> 'available' and target_thumbnail_object_key is not null then
    raise exception 'Only an available file can carry a preview.'
      using errcode = 'check_violation';
  end if;

  update public.files
  set processing_state = target_state,
      checksum_sha256 = coalesce(target_checksum_sha256, checksum_sha256),
      thumbnail_object_key = coalesce(target_thumbnail_object_key, thumbnail_object_key),
      scanned_at = case when target_state = 'available' then now() else scanned_at end,
      processing_error = case when target_state = 'available' then null else target_error end,
      claimed_at = null,
      claim_token = null
  where id = claimed.id
  returning * into finalized;

  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_id is not null
    and finalized.origin_role <> 'note_file'
    and finalized.origin_type = any (
      array[
        'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization',
        'marketing_campaign'
      ]
    )
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    values (
      finalized.organization_id, finalized.id, finalized.origin_type, finalized.origin_id,
      finalized.origin_role, finalized.uploaded_by
    )
    on conflict (file_id, entity_type, entity_id, role) do nothing;

    -- The logo is a singleton: this File becomes the one the sidebar, quotes and invoices render from, and
    -- whatever File held that job before is unlinked (not trashed -- an already-sent quote freezes its own
    -- copy of the object_key text below, so the old File and its R2 object must survive).
    if finalized.origin_type = 'organization' and finalized.origin_role = 'logo' then
      delete from public.file_links
      where organization_id = finalized.organization_id
        and entity_type = 'organization'
        and role = 'logo'
        and file_id <> finalized.id
        and not protected;

      update public.organization_settings
      set logo_object_key = finalized.object_key,
          branding_revision = branding_revision + 1,
          branding_updated_by = finalized.uploaded_by,
          branding_updated_at = now()
      where organization_id = finalized.organization_id;

      insert into public.organization_settings_audit (
        organization_id, section, changed_fields, actor_user_id
      )
      values (finalized.organization_id, 'branding', array['logo'], finalized.uploaded_by);
    end if;
  end if;

  -- An item photo is linked only while the item still holds it. The item's own trigger links it when the
  -- photo is chosen after this point; a photo picked and then abandoned is never linked at all.
  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_type = 'catalog_item'
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    select finalized.organization_id, finalized.id, 'catalog_item', item.id, 'item_photo', finalized.uploaded_by
    from public.catalog_items item
    where item.organization_id = finalized.organization_id
      and item.id = finalized.origin_id
      and item.image_file_id = finalized.id
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  -- A Note's File, the same way: linked only to the records of the Notes that hold it.
  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_role = 'note_file'
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    select finalized.organization_id, finalized.id, link.entity_type, link.entity_id, 'note_file', held.created_by
    from public.note_files as held
    join public.note_links as link on link.note_id = held.note_id
    where held.organization_id = finalized.organization_id
      and held.file_id = finalized.id
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  return finalized;
end;
$$;

-- 5. A record's Files card leaves a Note's Files in the Note ----------------------------------------------------
--
-- Unchanged from its live definition except that 'note_file' joins the roles a record's own card skips.

create or replace function public.list_files(
  target_organization_id uuid,
  target_view text default 'all'::text,
  target_folder_id uuid default null::uuid,
  target_search text default null::text,
  target_limit integer default 40,
  cursor_created_at timestamp with time zone default null::timestamp with time zone,
  cursor_id uuid default null::uuid,
  target_entity_type text default null::text,
  target_entity_id uuid default null::uuid,
  only_attachable boolean default false,
  target_label_id uuid default null::uuid
)
returns table(
  id uuid, display_name text, mime_type text, kind text, size_bytes bigint, has_thumbnail boolean,
  folder_id uuid, folder_name text, origin_type text, origin_id uuid, processing_state text, uploaded_by uuid,
  uploaded_by_name text, created_at timestamp with time zone, trashed_at timestamp with time zone,
  usage_count integer, caption text
)
language plpgsql
stable
set search_path to 'pg_catalog', 'public'
as $function$
declare
  search_pattern text := case
    when target_search is null or btrim(target_search) = '' then null
    else '%' || replace(replace(btrim(target_search), '\', '\\'), '%', '\%') || '%'
  end;
  search_number bigint := nullif(regexp_replace(coalesce(target_search, ''), '\D', '', 'g'), '')::bigint;
  -- Start from the record's links, so the files policy runs only on the record's files.
  record_join text := case
    when target_view = 'on_record' then $j$
      join (
        select distinct link.file_id
        from public.file_links link
        where link.organization_id = $1
          and link.entity_type = $8
          and link.entity_id = $9
          and link.role not in ('line_photo', 'report_photo', 'note_file')
      ) on_record on on_record.file_id = file.id
    $j$
    else ''
  end;
  not_attached_filter text := case
    when target_view = 'not_attached' then $j$
      and not exists (
        select 1
        from public.file_links link
        where link.organization_id = file.organization_id
          and link.file_id = file.id
      )
    $j$
    else ''
  end;
begin
  return query execute format($q$
      with matched_records (entity_type, entity_id) as (
        -- Records whose name or number matches, found once per search under each record table's own policy,
        -- rather than once per file per link.
        select 'client', record.id from public.clients record
        where $12 is not null and record.organization_id = $1 and record.display_name ilike $12
        union all
        select 'property', record.id from public.properties record
        where $12 is not null and record.organization_id = $1
          and (record.address_line1 ilike $12 or record.city ilike $12 or record.label ilike $12)
        union all
        select 'request', record.id from public.requests record
        where $12 is not null and record.organization_id = $1 and record.title ilike $12
        union all
        select 'quote', record.id from public.quotes record
        where $12 is not null and record.organization_id = $1
          and (record.title ilike $12 or record.quote_number = $13)
        union all
        select 'invoice', record.id from public.invoices record
        where $12 is not null and record.organization_id = $1
          and (record.subject ilike $12 or record.invoice_number = $13)
        union all
        select 'job', record.id from public.jobs record
        where $12 is not null and record.organization_id = $1
          and (record.title ilike $12 or record.job_number = $13)
        union all
        select 'visit', visit.id from public.job_visits visit
        join public.jobs record on record.id = visit.job_id
        where $12 is not null and visit.organization_id = $1
          and (visit.title ilike $12 or record.title ilike $12 or record.job_number = $13)
        union all
        select 'job_expense', expense.id from public.job_expenses expense
        join public.jobs record on record.id = expense.job_id
        where $12 is not null and expense.organization_id = $1
          and (expense.name ilike $12 or record.title ilike $12 or record.job_number = $13)
      ),
      matched_files as (
        select link.file_id
        from public.file_links link
        join matched_records matched
          on matched.entity_type = link.entity_type
         and matched.entity_id = link.entity_id
        where link.organization_id = $1
      )
      select
        file.id,
        file.display_name,
        file.mime_type,
        file.kind,
        file.size_bytes,
        file.thumbnail_object_key is not null as has_thumbnail,
        file.folder_id,
        folder.name as folder_name,
        file.origin_type,
        file.origin_id,
        file.processing_state,
        file.uploaded_by,
        uploader.full_name as uploaded_by_name,
        file.created_at,
        file.trashed_at,
        (
          select count(distinct (link.entity_type, link.entity_id))
          from public.file_links link
          where link.organization_id = file.organization_id
            and link.file_id = file.id
        )::integer as usage_count,
        file.caption
      from public.files file
      %1$s
      left join public.file_folders folder
        on folder.organization_id = file.organization_id
       and folder.id = file.folder_id
      left join public.profiles uploader
        on uploader.id = file.uploaded_by
      where file.organization_id = $1
        and (
          case when $2 = 'trash' then file.trashed_at is not null and file.purged_at is null
          else file.trashed_at is null end
        )
        and ($2 <> 'recent' or file.created_at >= now() - interval '30 days')
        and ($2 <> 'photos' or file.kind = 'image')
        and ($2 <> 'videos' or file.kind = 'video')
        and ($2 <> 'documents' or file.kind = 'document')
        and ($3 is null or file.folder_id = $3)
        and (
          $11 is null
          or exists (
            select 1
            from public.file_label_assignments assignment
            where assignment.organization_id = file.organization_id
              and assignment.file_id = file.id
              and assignment.label_id = $11
          )
        )
        %2$s
        and (not $10 or file.processing_state = 'available')
        and (
          $12 is null
          or file.display_name ilike $12
          or file.caption ilike $12
          or file.id in (select matched_files.file_id from matched_files)
        )
        and (
          $6 is null
          or $7 is null
          or (file.created_at, file.id) < ($6, $7)
        )
      order by file.created_at desc, file.id desc
      limit least(greatest(coalesce($5, 40), 1), 100)
  $q$, record_join, not_attached_filter)
  using target_organization_id, target_view, target_folder_id, target_search, target_limit, cursor_created_at, cursor_id, target_entity_type, target_entity_id, only_attachable, target_label_id,
    search_pattern, search_number;
end;
$function$;

-- 6. The mention alert -------------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check check (kind = any (array[
  'website_inquiry.received', 'website_inquiry.customer_replied', 'invoice.paid_online',
  'invoice.online_payment_failed', 'invoice.online_overpayment', 'quote.deposit_paid_online',
  'quote.deposit_payment_failed', 'quote.deposit_overpaid', 'invoice.online_refund_failed',
  'invoice.payment_disputed', 'quote.deposit_refund_failed', 'quote.deposit_disputed',
  'review.private_feedback', 'quote.delivery_failed', 'quote.customer_declined', 'pipeline.task_assigned',
  'pipeline.note_mention'
]));

create function private.alert_note_mentions(p_note_id uuid, p_opportunity_id uuid, p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor uuid := (select auth.uid());
  card record;
  note_body text;
  actor_name text;
  snippet text;
begin
  if actor is null or coalesce(cardinality(p_user_ids), 0) = 0 then
    return;
  end if;

  select opportunity.organization_id, opportunity.title into card
  from public.opportunities as opportunity where opportunity.id = p_opportunity_id;
  select note.body into note_body from public.notes as note where note.id = p_note_id;
  if card.organization_id is null or note_body is null then
    return;
  end if;

  -- Named as the Task alert names a teammate: their name, else their sign-in email.
  select coalesce(
    nullif(btrim(profile.full_name), ''),
    (select account.email::text from auth.users as account where account.id = actor),
    'A teammate'
  )
  into actor_name
  from (select 1) as anchor
  left join public.profiles as profile on profile.id = actor;

  snippet := btrim(regexp_replace(note_body, '\s+', ' ', 'g'));
  if char_length(snippet) > 160 then
    snippet := rtrim(left(snippet, 159)) || '…';
  end if;

  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_state
  )
  select
    card.organization_id,
    mentioned.user_id,
    'pipeline.note_mention',
    'opportunity',
    p_opportunity_id,
    left(actor_name || ' mentioned you in a note', 200),
    left('On ' || coalesce(nullif(btrim(card.title), ''), 'a pipeline card') || ': "' || snippet || '"', 500),
    -- Once per person per Note: removing a mention and adding it back is not a second alert.
    'note_mention:' || p_note_id || ':' || mentioned.user_id,
    'pending'
  from (select distinct listed.user_id from unnest(p_user_ids) as listed(user_id)) as mentioned
  where mentioned.user_id is not null and mentioned.user_id <> actor
  on conflict (organization_id, user_id, source_key) do nothing;
end;
$$;

revoke all on function private.alert_note_mentions(uuid, uuid, uuid[]) from public, anon, authenticated;

-- 7. Saving a Brief Note's Files and mentions -----------------------------------------------------------------
--
-- p_file_ids is the Note's whole list, in order; null leaves the Files as they are. A File new to the Note must
-- be one this person uploaded for this card's Request or Client and that is still pending or available, so a
-- Note cannot be used to reach a File the person could not otherwise see. p_mention_user_ids is the same: the
-- whole set, or null to keep it. Everyone mentioned must be an active member who may see the Pipeline.

create function private.pipeline_note_save_extras(
  p_scope_organization_id uuid,
  p_scope_request_id uuid,
  p_scope_client_id uuid,
  p_opportunity_id uuid,
  p_note_id uuid,
  p_file_ids uuid[],
  p_mention_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  wanted_files uuid[];
  wanted_mentions uuid[];
  added_mentions uuid[];
begin
  if p_file_ids is not null then
    select coalesce(array_agg(listed.file_id order by listed.first_at), '{}')
    into wanted_files
    from (
      select entry.file_id, min(entry.at) as first_at
      from unnest(p_file_ids) with ordinality as entry(file_id, at)
      where entry.file_id is not null
      group by entry.file_id
    ) as listed;

    if cardinality(wanted_files) > 10 then
      raise exception 'A note can hold up to 10 photos and files.' using errcode = 'check_violation';
    end if;

    if exists (
      select 1 from unnest(wanted_files) as wanted(file_id)
      where not exists (
          select 1 from public.note_files as held
          where held.note_id = p_note_id and held.file_id = wanted.file_id
        )
        and not exists (
          select 1 from public.files as file
          where file.organization_id = p_scope_organization_id
            and file.id = wanted.file_id
            and file.trashed_at is null
            and file.processing_state in ('pending', 'available')
            and file.origin_role = 'note_file'
            and file.uploaded_by = actor
            and (
              (file.origin_type = 'request' and file.origin_id = p_scope_request_id)
              or (file.origin_type = 'client' and file.origin_id = p_scope_client_id)
            )
        )
    ) then
      raise exception 'One of the files could not be added. Try uploading it again.'
        using errcode = 'check_violation';
    end if;

    delete from public.note_files as held
    where held.note_id = p_note_id and not (held.file_id = any (wanted_files));

    insert into public.note_files as held (organization_id, note_id, file_id, position, created_by)
    select p_scope_organization_id, p_note_id, wanted.file_id, (wanted.at - 1)::smallint, actor
    from unnest(wanted_files) with ordinality as wanted(file_id, at)
    on conflict (note_id, file_id) do update set position = excluded.position
      where held.position is distinct from excluded.position;
  end if;

  if p_mention_user_ids is not null then
    select coalesce(array_agg(distinct listed.user_id), '{}')
    into wanted_mentions
    from unnest(p_mention_user_ids) as listed(user_id)
    where listed.user_id is not null;

    if cardinality(wanted_mentions) > 10 then
      raise exception 'A note can mention up to 10 teammates.' using errcode = 'check_violation';
    end if;

    if exists (
      select 1 from unnest(wanted_mentions) as wanted(user_id)
      where not private.member_receives_task_alerts(p_scope_organization_id, wanted.user_id)
    ) then
      raise exception 'Someone you mentioned cannot see the Pipeline, so they would not be able to open this card.'
        using errcode = 'check_violation';
    end if;

    select coalesce(array_agg(wanted.user_id), '{}')
    into added_mentions
    from unnest(wanted_mentions) as wanted(user_id)
    where not exists (
      select 1 from public.note_mentions as mention
      where mention.note_id = p_note_id and mention.user_id = wanted.user_id
    );

    delete from public.note_mentions as mention
    where mention.note_id = p_note_id and not (mention.user_id = any (wanted_mentions));

    insert into public.note_mentions (organization_id, note_id, user_id)
    select p_scope_organization_id, p_note_id, added.user_id
    from unnest(added_mentions) as added(user_id);

    perform private.alert_note_mentions(p_note_id, p_opportunity_id, added_mentions);
  end if;
end;
$$;

revoke all on function private.pipeline_note_save_extras(uuid, uuid, uuid, uuid, uuid, uuid[], uuid[])
  from public, anon, authenticated;

-- What a Note carries, as the Brief reads it. Only Files still pending or available, in their order.
create function private.pipeline_note_files_json(p_note_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', file.id,
      'display_name', file.display_name,
      'mime_type', file.mime_type,
      'kind', file.kind,
      'size_bytes', file.size_bytes,
      'has_thumbnail', file.thumbnail_object_key is not null,
      'processing_state', file.processing_state
    ) order by held.position, held.created_at), '[]'::jsonb)
  from public.note_files as held
  join public.files as file on file.organization_id = held.organization_id and file.id = held.file_id
  where held.note_id = p_note_id
    and file.trashed_at is null
    and file.processing_state in ('pending', 'available');
$$;

create function private.note_mention_ids(p_note_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(array_agg(mention.user_id order by mention.created_at, mention.user_id), '{}')
  from public.note_mentions as mention where mention.note_id = p_note_id;
$$;

revoke all on function private.pipeline_note_files_json(uuid) from public, anon, authenticated;
revoke all on function private.note_mention_ids(uuid) from public, anon, authenticated;

-- 8. The Brief's Note functions carry Files and mentions --------------------------------------------------------
--
-- Their answers gain two columns, so each is dropped and created again; the rules are unchanged.

drop function public.pipeline_opportunity_notes(uuid);
drop function public.pipeline_create_opportunity_note(uuid, text, text);
drop function public.pipeline_update_opportunity_note(uuid, uuid, text);

create function public.pipeline_opportunity_notes(target_opportunity_id uuid)
returns table (
  id uuid, body text, pinned boolean, created_by uuid, edited_by uuid, edited_at timestamptz,
  created_at timestamptz, updated_at timestamptz, entity_type text, entity_id uuid, files jsonb,
  mention_user_ids uuid[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.view');

  return query
  select
    note.id, note.body, note.pinned, note.created_by, note.edited_by, note.edited_at,
    note.created_at, note.updated_at, link.entity_type, link.entity_id,
    private.pipeline_note_files_json(note.id), private.note_mention_ids(note.id)
  from public.note_links as link
  join public.notes as note on note.id = link.note_id
  where link.organization_id = scope.organization_id
    and (
      (link.entity_type = 'request' and link.entity_id = scope.request_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  order by note.pinned desc, note.created_at desc;
end;
$$;

create function public.pipeline_create_opportunity_note(
  target_opportunity_id uuid,
  target_entity_type text,
  new_body text,
  new_file_ids uuid[] default '{}',
  new_mention_user_ids uuid[] default '{}'
)
returns table (
  id uuid, body text, pinned boolean, created_by uuid, edited_by uuid, edited_at timestamptz,
  created_at timestamptz, updated_at timestamptz, entity_type text, entity_id uuid, files jsonb,
  mention_user_ids uuid[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  resolved_entity_id uuid;
  inserted_note public.notes;
  inserted_link public.note_links;
begin
  if target_entity_type not in ('request', 'client') then
    raise exception 'A Brief Note can only target the Request or the Client.'
      using errcode = 'check_violation';
  end if;

  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');

  resolved_entity_id := case target_entity_type
    when 'request' then scope.request_id
    else scope.client_id
  end;

  if resolved_entity_id is null then
    raise exception 'This opportunity has no % to attach a note to.', target_entity_type
      using errcode = 'check_violation';
  end if;

  insert into public.notes (organization_id, body, created_by)
  values (scope.organization_id, new_body, (select auth.uid()))
  returning * into inserted_note;

  insert into public.note_links (organization_id, note_id, entity_type, entity_id)
  values (scope.organization_id, inserted_note.id, target_entity_type, resolved_entity_id)
  returning * into inserted_link;

  perform private.pipeline_note_save_extras(
    scope.organization_id, scope.request_id, scope.client_id, target_opportunity_id, inserted_note.id,
    coalesce(new_file_ids, '{}'), coalesce(new_mention_user_ids, '{}')
  );

  return query
  select
    inserted_note.id, inserted_note.body, inserted_note.pinned, inserted_note.created_by,
    inserted_note.edited_by, inserted_note.edited_at, inserted_note.created_at, inserted_note.updated_at,
    inserted_link.entity_type, inserted_link.entity_id,
    private.pipeline_note_files_json(inserted_note.id), private.note_mention_ids(inserted_note.id);
end;
$$;

create function public.pipeline_update_opportunity_note(
  target_note_id uuid,
  target_opportunity_id uuid,
  new_body text,
  new_file_ids uuid[] default null,
  new_mention_user_ids uuid[] default null
)
returns table (
  id uuid, body text, pinned boolean, created_by uuid, edited_by uuid, edited_at timestamptz,
  created_at timestamptz, updated_at timestamptz, entity_type text, entity_id uuid, files jsonb,
  mention_user_ids uuid[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
  target_link public.note_links;
  updated_note public.notes;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.edit');

  select link.* into target_link
  from public.note_links as link
  where link.note_id = target_note_id
    and link.organization_id = scope.organization_id
    and (
      (link.entity_type = 'request' and link.entity_id = scope.request_id)
      or (link.entity_type = 'client' and link.entity_id = scope.client_id)
    )
  limit 1;

  if target_link.id is null then
    raise exception 'That note is not on this opportunity.' using errcode = 'insufficient_privilege';
  end if;

  -- Only a real change of text marks the Note edited; changing its Files or mentions alone does not.
  update public.notes as note
  set body = new_body,
      edited_by = case when note.body is distinct from new_body then (select auth.uid()) else note.edited_by end,
      edited_at = case when note.body is distinct from new_body then now() else note.edited_at end
  where note.id = target_note_id
  returning * into updated_note;

  perform private.pipeline_note_save_extras(
    scope.organization_id, scope.request_id, scope.client_id, target_opportunity_id, target_note_id,
    new_file_ids, new_mention_user_ids
  );

  return query
  select
    updated_note.id, updated_note.body, updated_note.pinned, updated_note.created_by,
    updated_note.edited_by, updated_note.edited_at, updated_note.created_at, updated_note.updated_at,
    target_link.entity_type, target_link.entity_id,
    private.pipeline_note_files_json(updated_note.id), private.note_mention_ids(updated_note.id);
end;
$$;

revoke all on function public.pipeline_opportunity_notes(uuid) from public, anon;
revoke all on function public.pipeline_create_opportunity_note(uuid, text, text, uuid[], uuid[]) from public, anon;
revoke all on function public.pipeline_update_opportunity_note(uuid, uuid, text, uuid[], uuid[]) from public, anon;
grant execute on function public.pipeline_opportunity_notes(uuid) to authenticated, service_role;
grant execute on function public.pipeline_create_opportunity_note(uuid, text, text, uuid[], uuid[])
  to authenticated, service_role;
grant execute on function public.pipeline_update_opportunity_note(uuid, uuid, text, uuid[], uuid[])
  to authenticated, service_role;

-- 9. Showing a Brief Note's File --------------------------------------------------------------------------
--
-- The Brief is authorized by pipeline.view, not by the Request's or Client's own view right, so the File is
-- found through the card: it must be on a Note on this card's Request or Client. The route streams it.

create function public.pipeline_opportunity_note_file(target_opportunity_id uuid, target_file_id uuid)
returns table (
  display_name text, mime_type text, object_key text, thumbnail_object_key text, processing_state text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  scope record;
begin
  select * into scope from private.pipeline_note_scope(target_opportunity_id, 'pipeline.view');

  return query
  select file.display_name, file.mime_type, file.object_key, file.thumbnail_object_key, file.processing_state
  from public.files as file
  where file.organization_id = scope.organization_id
    and file.id = target_file_id
    and file.trashed_at is null
    and exists (
      select 1
      from public.note_files as held
      join public.note_links as link on link.note_id = held.note_id
      where held.organization_id = scope.organization_id
        and held.file_id = file.id
        and (
          (link.entity_type = 'request' and link.entity_id = scope.request_id)
          or (link.entity_type = 'client' and link.entity_id = scope.client_id)
        )
    );
end;
$$;

revoke all on function public.pipeline_opportunity_note_file(uuid, uuid) from public, anon;
grant execute on function public.pipeline_opportunity_note_file(uuid, uuid) to authenticated, service_role;

-- 10. Who can be mentioned --------------------------------------------------------------------------------
--
-- Active teammates who may see the Pipeline, named the way the Task owner list names them. Asked by someone
-- who may write Notes there.

create function public.pipeline_mentionable_teammates(target_organization_id uuid)
returns table (user_id uuid, full_name text, avatar_url text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.edit')) then
    raise exception 'You do not have access to this sales pipeline.' using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    membership.user_id,
    coalesce(nullif(btrim(profile.full_name), ''), account.email::text) as full_name,
    profile.avatar_url
  from public.organization_members as membership
  left join public.profiles as profile on profile.id = membership.user_id
  left join auth.users as account on account.id = membership.user_id
  where membership.organization_id = target_organization_id
    and membership.status = 'active'
    and private.member_receives_task_alerts(target_organization_id, membership.user_id)
  order by lower(coalesce(nullif(btrim(profile.full_name), ''), account.email::text, '')), membership.user_id
  limit 200;
end;
$$;

revoke all on function public.pipeline_mentionable_teammates(uuid) from public, anon;
grant execute on function public.pipeline_mentionable_teammates(uuid) to authenticated, service_role;

-- 11. Who is emailed --------------------------------------------------------------------------------------
--
-- Unchanged from 20261003220000 except that a mention alert follows the Task alert's rule.

create or replace function public.claim_team_notification_emails(
  p_batch_size integer default 25,
  p_lease_seconds integer default 120
)
returns table (
  notification_id uuid, claim_token uuid, organization_id uuid, organization_name text, recipient_email text,
  kind text, subject_type text, subject_id uuid, title text, body text, attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  token uuid;
  receives boolean;
begin
  if p_batch_size < 1 or p_batch_size > 100 or p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The alert email claim is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select q.id, q.organization_id, q.user_id, q.kind, q.subject_type, q.subject_id, q.title, q.body,
      q.email_attempts, o.name as organization_name, nullif(btrim(u.email), '') as email
    from public.team_notifications as q
    join public.organizations as o on o.id = q.organization_id
    left join auth.users as u on u.id = q.user_id
    where q.email_state = 'pending' and q.email_available_at <= now()
      and (q.email_claimed_until is null or q.email_claimed_until < now())
    order by q.email_available_at, q.id
    limit p_batch_size
    for update of q skip locked
  loop
    -- Set first: PL/pgSQL ends an IF condition at its first THEN, so a CASE cannot sit inside one.
    receives := case when candidate.kind in ('pipeline.task_assigned', 'pipeline.note_mention')
      then private.member_receives_task_alerts(candidate.organization_id, candidate.user_id)
      else private.member_receives_inquiry_alerts(candidate.organization_id, candidate.user_id)
    end;

    if candidate.email is null or not receives then
      update public.team_notifications
      set email_state = 'not_needed', email_claim_token = null, email_claimed_until = null
      where id = candidate.id;
      continue;
    end if;

    token := gen_random_uuid();
    update public.team_notifications
    set email_claim_token = token, email_claimed_until = now() + make_interval(secs => p_lease_seconds)
    where id = candidate.id;

    notification_id := candidate.id;
    claim_token := token;
    organization_id := candidate.organization_id;
    organization_name := candidate.organization_name;
    recipient_email := candidate.email;
    kind := candidate.kind;
    subject_type := candidate.subject_type;
    subject_id := candidate.subject_id;
    title := candidate.title;
    body := candidate.body;
    attempts := candidate.email_attempts;
    return next;
  end loop;
end;
$$;
