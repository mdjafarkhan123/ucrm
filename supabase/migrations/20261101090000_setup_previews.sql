-- Client onboarding E3: the preview and the one correction round (plan §6, §10 journey 10).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §6. Jafar's choices of 2026-10-05: once
-- Ready is recorded, Jafar writes the preview as cards — one per part of the package, each with a summary, an
-- optional link and optional screenshots — and releases it. On each card the client's owners and administrators
-- pick Looks right or Needs a change with a note; notes save as drafts and one Send sends them all, once, using
-- the correction round. Jafar sorts each note as Correction, Our mistake (free) or New request, and the client
-- sees the label. On a preview released after the round is used, a card's choices are Looks right, Uplift made a
-- mistake, or something new, which arrives already sorted as New request. Each release is a new version; earlier
-- versions and their notes stay readable. Industry reference: Filestage and Ziflow proofing (versions, a decision
-- per item, one Submit), Rocketlane and GuideCX deliverable review, agencies' "one revision round included".
--
-- 1. organization_setup_previews keeps every version: its cards, when Jafar released it, whether it opened the
--    correction round, and when the client sent their notes. Frozen once released, except that one send.
-- 2. organization_setup_preview_notes keeps the client's choice and note on each card of a version, and Jafar's
--    label once sent.
-- 3. Shape checks for cards and screenshots.
-- 4. Jafar's commands: save the draft, discard it, release it, sort a note. Releases and labels are in
--    platform_owner_audit_events.
-- 5. The client's commands: save a note, send them all.
-- 6. public.owner_client_onboarding_list shows a released preview as the client's move, and sent notes as
--    Uplift's (sort them, then make the corrections).

-- 1. The previews -------------------------------------------------------------------------------------------

create table public.organization_setup_previews (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  version integer not null check (version >= 1),
  -- [{ id, title, summary, link, screenshots: [...] }], checked by private.check_setup_preview_cards.
  cards jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by_email text not null check (char_length(updated_by_email) between 3 and 320),
  released_at timestamptz,
  released_by_email text check (released_by_email is null or char_length(released_by_email) between 3 and 320),
  -- Set at release: true while the client has not yet used their one correction round.
  correction_round boolean,
  -- The client's one Send for this version.
  notes_sent_at timestamptz,
  notes_sent_by uuid references auth.users (id) on delete set null,
  notes_sent_by_name text check (notes_sent_by_name is null or char_length(notes_sent_by_name) between 1 and 320),
  primary key (organization_id, version),
  constraint organization_setup_previews_release_check check (
    (released_at is null) = (released_by_email is null)
    and (released_at is null) = (correction_round is null)
  ),
  constraint organization_setup_previews_sent_check check (
    (notes_sent_at is null or released_at is not null)
    and (notes_sent_at is null) = (notes_sent_by_name is null)
  )
);

-- One draft at a time per client.
create unique index organization_setup_previews_one_draft
  on public.organization_setup_previews (organization_id)
  where released_at is null;

comment on table public.organization_setup_previews is
  'Client onboarding E3: each version of the preview Jafar writes for a client. Administrators read released versions; rows change only through the owner_* and client_* setup preview commands.';

-- A released version is what the client reviewed; only its one send may still be recorded on it.
create function private.refuse_setup_preview_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.released_at is not null and (
    new.cards is distinct from old.cards
    or new.version is distinct from old.version
    or new.released_at is distinct from old.released_at
    or new.released_by_email is distinct from old.released_by_email
    or new.correction_round is distinct from old.correction_round
    or (old.notes_sent_at is not null and (
      new.notes_sent_at is distinct from old.notes_sent_at
      or new.notes_sent_by_name is distinct from old.notes_sent_by_name
    ))
  ) then
    raise exception 'A released preview cannot be changed.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger organization_setup_previews_frozen
  before update on public.organization_setup_previews
  for each row execute function private.refuse_setup_preview_change();

alter table public.organization_setup_previews enable row level security;
revoke all on table public.organization_setup_previews from public, anon, authenticated;
grant select on table public.organization_setup_previews to authenticated;
grant all on table public.organization_setup_previews to service_role;

-- A client's owners and administrators see what Jafar has released, never his draft.
create policy "administrators can view their released previews"
  on public.organization_setup_previews
  for select
  to authenticated
  using (released_at is not null and (select private.is_organization_admin(organization_id)));

-- 2. The client's notes ----------------------------------------------------------------------------------------

create table public.organization_setup_preview_notes (
  organization_id uuid not null,
  version integer not null,
  card_id text not null check (char_length(card_id) between 1 and 64),
  -- Mirrors PREVIEW_CHOICES in src/lib/setup/preview.ts. The first two on a version that opened the correction
  -- round; the others after it.
  choice text not null check (choice in ('looks_right', 'needs_change', 'uplift_mistake', 'new_request')),
  note text check (note is null or char_length(note) between 1 and 2000),
  screenshots jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  -- Jafar's label, once the notes are sent.
  sorted_kind text check (sorted_kind in ('correction', 'uplift_error', 'new_request')),
  sorted_at timestamptz,
  sorted_by_email text check (sorted_by_email is null or char_length(sorted_by_email) between 3 and 320),
  primary key (organization_id, version, card_id),
  foreign key (organization_id, version)
    references public.organization_setup_previews (organization_id, version) on delete cascade,
  constraint organization_setup_preview_notes_note_check check (
    case when choice = 'looks_right'
      then note is null and screenshots = '[]'::jsonb and sorted_kind is null
      else note is not null
    end
  ),
  constraint organization_setup_preview_notes_sorted_check check ((sorted_kind is null) = (sorted_at is null))
);

comment on table public.organization_setup_preview_notes is
  'Client onboarding E3: the client''s choice and note on each card of a released preview, and Jafar''s label once sent. Administrators may read; rows change only through the setup preview commands.';

alter table public.organization_setup_preview_notes enable row level security;
revoke all on table public.organization_setup_preview_notes from public, anon, authenticated;
grant select on table public.organization_setup_preview_notes to authenticated;
grant all on table public.organization_setup_preview_notes to service_role;

create policy "administrators can view their preview notes"
  on public.organization_setup_preview_notes
  for select
  to authenticated
  using ((select private.is_organization_admin(organization_id)));

-- 3. Shape checks -------------------------------------------------------------------------------------------------

-- Screenshots are photos uploaded straight to storage under the client's `setup-previews/` prefix, as Chat with
-- Uplift's files are: at most 5, each a photo of at most 10 MB, 20 MB together. The route measures each upload in
-- storage before it names one here.
create function private.check_setup_preview_screenshots(target_organization_id uuid, screenshots jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if jsonb_typeof(screenshots) is distinct from 'array' or jsonb_array_length(screenshots) > 5 then
    raise exception 'Add up to 5 screenshots.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(screenshots) as item(shot)
    where jsonb_typeof(item.shot) is distinct from 'object'
      or not starts_with(coalesce(item.shot ->> 'object_key', ''), target_organization_id::text || '/setup-previews/')
      or char_length(item.shot ->> 'object_key') > 600
      or char_length(coalesce(item.shot ->> 'file_name', '')) not between 1 and 255
      or coalesce(item.shot ->> 'mime_type', '') not in ('image/jpeg', 'image/png', 'image/webp', 'image/gif')
      or jsonb_typeof(item.shot -> 'byte_size') is distinct from 'number'
      or (item.shot ->> 'byte_size')::numeric not between 1 and 10485760
      or jsonb_typeof(item.shot -> 'has_thumbnail') is distinct from 'boolean'
  ) then
    raise exception 'A screenshot must be a photo of up to 10 MB.' using errcode = 'check_violation';
  end if;
  if (select coalesce(sum((item.shot ->> 'byte_size')::numeric), 0) from jsonb_array_elements(screenshots) as item(shot))
      > 20971520 then
    raise exception 'Keep the screenshots to 20 MB together.' using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function private.check_setup_preview_screenshots(uuid, jsonb) from public;

create function private.check_setup_preview_cards(target_organization_id uuid, cards jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  card jsonb;
begin
  if jsonb_typeof(cards) is distinct from 'array' or jsonb_array_length(cards) not between 1 and 15 then
    raise exception 'A preview has between 1 and 15 cards.' using errcode = 'check_violation';
  end if;
  if (select count(distinct item.card ->> 'id') from jsonb_array_elements(cards) as item(card))
      <> jsonb_array_length(cards) then
    raise exception 'Each card needs its own id.' using errcode = 'check_violation';
  end if;
  for card in select item.card from jsonb_array_elements(cards) as item(card) loop
    if jsonb_typeof(card) is distinct from 'object'
      or char_length(coalesce(card ->> 'id', '')) not between 1 and 64 then
      raise exception 'Each card needs its own id.' using errcode = 'check_violation';
    end if;
    if char_length(btrim(coalesce(card ->> 'title', ''))) not between 1 and 80 then
      raise exception 'Give each card a title of up to 80 characters.' using errcode = 'check_violation';
    end if;
    if char_length(btrim(coalesce(card ->> 'summary', ''))) not between 1 and 2000 then
      raise exception 'Give each card a summary of up to 2000 characters.' using errcode = 'check_violation';
    end if;
    if jsonb_typeof(card -> 'link') is distinct from 'null'
      and (jsonb_typeof(card -> 'link') is distinct from 'string'
        or card ->> 'link' !~ '^https://[^\s]+$'
        or char_length(card ->> 'link') > 500) then
      raise exception 'A card''s link must be a full https:// address.' using errcode = 'check_violation';
    end if;
    perform private.check_setup_preview_screenshots(target_organization_id, coalesce(card -> 'screenshots', 'null'::jsonb));
  end loop;
end;
$$;

revoke all on function private.check_setup_preview_cards(uuid, jsonb) from public;

-- 4. Jafar's commands ---------------------------------------------------------------------------------------------

-- Saves the draft, starting the next version when there is none. A preview follows Ready: there is nothing to
-- show before the build has started.
create function public.owner_save_setup_preview(
  target_organization_id uuid,
  new_cards jsonb,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  draft public.organization_setup_previews;
  next_version integer;
begin
  if target_organization_id is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  perform private.check_setup_preview_cards(target_organization_id, new_cards);
  if not exists (select 1 from public.organization_setup_ready where organization_id = target_organization_id) then
    raise exception 'Record Ready for Uplift before writing the preview.' using errcode = 'check_violation';
  end if;

  -- One preview change at a time per client.
  insert into public.organization_setup (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;
  perform 1 from public.organization_setup where organization_id = target_organization_id for update;

  select * into draft
  from public.organization_setup_previews
  where organization_id = target_organization_id and released_at is null;

  if draft.organization_id is not null then
    update public.organization_setup_previews
    set cards = new_cards, updated_at = now(), updated_by_email = clean_email
    where organization_id = target_organization_id and version = draft.version
    returning * into draft;
  else
    select coalesce(max(version), 0) + 1 into next_version
    from public.organization_setup_previews
    where organization_id = target_organization_id;
    insert into public.organization_setup_previews (organization_id, version, cards, updated_by_email)
    values (target_organization_id, next_version, new_cards, clean_email)
    returning * into draft;
  end if;

  return jsonb_build_object('status', 'saved', 'version', draft.version, 'updated_at', draft.updated_at);
end;
$$;

revoke all on function public.owner_save_setup_preview(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.owner_save_setup_preview(uuid, jsonb, text) to service_role;

create function public.owner_discard_setup_preview_draft(target_organization_id uuid, actor_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if target_organization_id is null or nullif(btrim(coalesce(actor_email, '')), '') is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  delete from public.organization_setup_previews
  where organization_id = target_organization_id and released_at is null;
  return jsonb_build_object('status', case when found then 'discarded' else 'unchanged' end);
end;
$$;

revoke all on function public.owner_discard_setup_preview_draft(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_discard_setup_preview_draft(uuid, text) to service_role;

-- Releases the draft Jafar was looking at. It opens the correction round unless the client already used it: they
-- sent notes on a version that had it, and at least one asked for a change. Releasing what is already released
-- returns 'unchanged', so a double press emails nobody twice.
create function public.owner_release_setup_preview(
  target_organization_id uuid,
  target_version integer,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  draft public.organization_setup_previews;
  round_open boolean;
begin
  if target_organization_id is null or target_version is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organization_setup where organization_id = target_organization_id for update;

  select * into draft
  from public.organization_setup_previews
  where organization_id = target_organization_id and version = target_version;
  if draft.organization_id is null then
    raise exception 'That preview could not be found.' using errcode = 'check_violation';
  end if;
  if draft.released_at is not null then
    return jsonb_build_object('status', 'unchanged', 'version', draft.version);
  end if;
  if not exists (select 1 from public.organization_setup_ready where organization_id = target_organization_id) then
    raise exception 'Record Ready for Uplift before releasing the preview.' using errcode = 'check_violation';
  end if;

  round_open := not exists (
    select 1
    from public.organization_setup_previews as earlier
    join public.organization_setup_preview_notes as note
      on note.organization_id = earlier.organization_id and note.version = earlier.version
    where earlier.organization_id = target_organization_id
      and earlier.correction_round
      and earlier.notes_sent_at is not null
      and note.choice = 'needs_change'
  );

  update public.organization_setup_previews
  set released_at = now(), released_by_email = clean_email, correction_round = round_open
  where organization_id = target_organization_id and version = target_version
  returning * into draft;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_preview_released',
    'organization',
    target_organization_id::text,
    null,
    jsonb_build_object('version', draft.version, 'correction_round', round_open, 'cards', jsonb_array_length(draft.cards))
  );

  return jsonb_build_object(
    'status', 'released',
    'version', draft.version,
    'released_at', draft.released_at,
    'correction_round', round_open
  );
end;
$$;

revoke all on function public.owner_release_setup_preview(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.owner_release_setup_preview(uuid, integer, text) to service_role;

-- Labels one sent note. A note on "Looks right" has nothing to sort.
create function public.owner_sort_setup_preview_note(
  target_organization_id uuid,
  target_version integer,
  target_card_id text,
  new_kind text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  before_row public.organization_setup_preview_notes;
  after_row public.organization_setup_preview_notes;
begin
  if target_organization_id is null or target_version is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  if new_kind is null or new_kind not in ('correction', 'uplift_error', 'new_request') then
    raise exception 'That is not one of the labels.' using errcode = 'check_violation';
  end if;

  select note.* into before_row
  from public.organization_setup_preview_notes as note
  join public.organization_setup_previews as preview
    on preview.organization_id = note.organization_id and preview.version = note.version
  where note.organization_id = target_organization_id
    and note.version = target_version
    and note.card_id = target_card_id
    and preview.notes_sent_at is not null
    and note.choice <> 'looks_right'
  for update of note;
  if before_row.organization_id is null then
    raise exception 'That note could not be found.' using errcode = 'check_violation';
  end if;
  if before_row.sorted_kind = new_kind then
    return jsonb_build_object('status', 'unchanged');
  end if;

  update public.organization_setup_preview_notes
  set sorted_kind = new_kind, sorted_at = now(), sorted_by_email = clean_email
  where organization_id = target_organization_id and version = target_version and card_id = target_card_id
  returning * into after_row;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_preview_note_sorted',
    'organization',
    target_organization_id::text,
    jsonb_build_object('version', target_version, 'card', target_card_id, 'kind', before_row.sorted_kind),
    jsonb_build_object('version', target_version, 'card', target_card_id, 'kind', after_row.sorted_kind)
  );

  return jsonb_build_object('status', 'saved', 'sorted_at', after_row.sorted_at);
end;
$$;

revoke all on function public.owner_sort_setup_preview_note(uuid, integer, text, text, text)
  from public, anon, authenticated;
grant execute on function public.owner_sort_setup_preview_note(uuid, integer, text, text, text) to service_role;

-- 5. The client's commands ---------------------------------------------------------------------------------------

-- The newest released version, locked so a save and the send cannot cross: saves share the lock, the send takes
-- it alone. Refuses a version that is not the newest, or whose notes were already sent.
create function private.lock_open_setup_preview(
  target_organization_id uuid,
  target_version integer,
  exclusive boolean
) returns public.organization_setup_previews
language plpgsql
security definer
set search_path = ''
as $$
declare
  preview public.organization_setup_previews;
begin
  if exclusive then
    select * into preview from public.organization_setup_previews
    where organization_id = target_organization_id and version = target_version and released_at is not null
    for update;
  else
    select * into preview from public.organization_setup_previews
    where organization_id = target_organization_id and version = target_version and released_at is not null
    for share;
  end if;
  if preview.organization_id is null then
    raise exception 'That preview could not be found.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.organization_setup_previews as newer
    where newer.organization_id = target_organization_id
      and newer.version > target_version
      and newer.released_at is not null
  ) then
    raise exception 'Uplift has released a newer preview. Reload to see it.' using errcode = 'check_violation';
  end if;
  return preview;
end;
$$;

revoke all on function private.lock_open_setup_preview(uuid, integer, boolean) from public;

-- Saves one card's choice and note as a draft; `new_choice` null clears it. Notes cannot change once sent.
create function public.client_save_setup_preview_note(
  target_organization_id uuid,
  target_version integer,
  target_card_id text,
  new_choice text,
  new_note text,
  new_screenshots jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  preview public.organization_setup_previews;
  clean_note text := nullif(btrim(coalesce(new_note, '')), '');
  clean_shots jsonb := coalesce(new_screenshots, '[]'::jsonb);
  saved public.organization_setup_preview_notes;
begin
  perform private.require_organization_setup_editor(target_organization_id);
  preview := private.lock_open_setup_preview(target_organization_id, target_version, false);
  if preview.notes_sent_at is not null then
    return jsonb_build_object('status', 'already_sent');
  end if;
  if not exists (
    select 1 from jsonb_array_elements(preview.cards) as item(card) where item.card ->> 'id' = target_card_id
  ) then
    raise exception 'That card could not be found.' using errcode = 'check_violation';
  end if;

  if new_choice is null then
    delete from public.organization_setup_preview_notes
    where organization_id = target_organization_id and version = target_version and card_id = target_card_id;
    return jsonb_build_object('status', 'saved', 'updated_at', null);
  end if;

  if new_choice <> 'looks_right' and not (
    (preview.correction_round and new_choice = 'needs_change')
    or (not preview.correction_round and new_choice in ('uplift_mistake', 'new_request'))
  ) then
    raise exception 'That choice is not offered on this preview.' using errcode = 'check_violation';
  end if;
  if new_choice = 'looks_right' then
    clean_note := null;
    clean_shots := '[]'::jsonb;
  elsif clean_note is null then
    raise exception 'Say what should change.' using errcode = 'check_violation';
  elsif char_length(clean_note) > 2000 then
    raise exception 'Keep the note to 2000 characters.' using errcode = 'check_violation';
  end if;
  perform private.check_setup_preview_screenshots(target_organization_id, clean_shots);

  insert into public.organization_setup_preview_notes (
    organization_id, version, card_id, choice, note, screenshots, updated_by
  ) values (
    target_organization_id, target_version, target_card_id, new_choice, clean_note, clean_shots, (select auth.uid())
  )
  on conflict (organization_id, version, card_id) do update
    set choice = excluded.choice,
        note = excluded.note,
        screenshots = excluded.screenshots,
        updated_at = now(),
        updated_by = excluded.updated_by
  returning * into saved;

  return jsonb_build_object('status', 'saved', 'updated_at', saved.updated_at);
end;
$$;

revoke all on function public.client_save_setup_preview_note(uuid, integer, text, text, text, jsonb) from public, anon;
grant execute on function public.client_save_setup_preview_note(uuid, integer, text, text, text, jsonb)
  to authenticated, service_role;

-- Sends this version's notes, once. At least one must ask for something: a preview where everything looks right
-- is approved instead (E4). A note the client marked as something new arrives already sorted as New request.
-- A second press, or a second device, returns 'already_sent'.
create function public.client_send_setup_preview_notes(target_organization_id uuid, target_version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  preview public.organization_setup_previews;
  sender_name text;
begin
  perform private.require_organization_setup_editor(target_organization_id);
  preview := private.lock_open_setup_preview(target_organization_id, target_version, true);
  if preview.notes_sent_at is not null then
    return jsonb_build_object('status', 'already_sent', 'sent_at', preview.notes_sent_at);
  end if;
  if not exists (
    select 1 from public.organization_setup_preview_notes
    where organization_id = target_organization_id and version = target_version and choice <> 'looks_right'
  ) then
    raise exception 'Mark a card that needs a change before sending.' using errcode = 'check_violation';
  end if;

  update public.organization_setup_preview_notes
  set sorted_kind = 'new_request', sorted_at = now(), sorted_by_email = null
  where organization_id = target_organization_id and version = target_version and choice = 'new_request';

  select coalesce(nullif(btrim(p.full_name), ''), u.email)
  into sender_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = (select auth.uid());

  update public.organization_setup_previews
  set notes_sent_at = now(), notes_sent_by = (select auth.uid()), notes_sent_by_name = coalesce(sender_name, 'Unknown')
  where organization_id = target_organization_id and version = target_version
  returning * into preview;

  return jsonb_build_object('status', 'sent', 'sent_at', preview.notes_sent_at);
end;
$$;

revoke all on function public.client_send_setup_preview_notes(uuid, integer) from public, anon;
grant execute on function public.client_send_setup_preview_notes(uuid, integer) to authenticated, service_role;

-- 6. Jafar's onboarding list ---------------------------------------------------------------------------------
-- Unchanged from 20261031090000_setup_provider_waits.sql except: the newest released preview is returned with its
-- send and unsorted notes; a released preview not yet answered makes the row the client's move
-- ('review_preview'), after the client's other moves; sent notes are Uplift's to sort ('sort_corrections'), then
-- to make ('make_corrections'), before building; a release and a send count as activity.

create or replace function public.owner_client_onboarding_list(
  setup_catalogue jsonb,
  search_term text default null,
  waiting_filter text default null,
  cursor_account_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50
) returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  with catalogue as (
    select
      section.position,
      section.value ->> 'key' as section_key,
      nullif(section.value ->> 'service_key', '') as service_key,
      array(select jsonb_array_elements_text(section.value -> 'facts')) as fact_keys,
      array(select jsonb_array_elements_text(section.value -> 'required')) as required_keys
    from jsonb_array_elements(setup_catalogue) with ordinality as section(value, position)
  ),
  clients as (
    select
      organization.id,
      organization.name,
      organization.lifecycle_status,
      provision.created_at as account_created_at,
      application.payment_reversed_at,
      agreement.package_name,
      coalesce(agreement.service_keys, '{}'::text[]) as service_keys
    from public.platform_onboarding_application_provisions as provision
    join public.platform_onboarding_applications as application on application.id = provision.application_id
    join public.organizations as organization on organization.id = provision.organization_id
    left join lateral (
      select
        edition.name as package_name,
        array(
          select service ->> 'service_key'
          from jsonb_array_elements(edition.included_services) as service
          where service ->> 'service_key' is not null
        ) as service_keys
      from public.organization_package_agreements as current_agreement
      join public.package_editions as edition on edition.id = current_agreement.edition_id
      where current_agreement.organization_id = organization.id
        and current_agreement.cancelled_at is null
        and current_agreement.effective_from <= now()
      order by current_agreement.effective_from desc, current_agreement.created_at desc
      limit 1
    ) as agreement on true
    where provision.status = 'succeeded'
  ),
  measured as (
    select
      client.*,
      setup.welcome_seen_at,
      own.sections_total,
      cardinality(shown.fact_keys) as facts_total,
      answers.answered,
      answers.help_count,
      answers.last_answer_at,
      sections.done_count,
      sections.next_section_key,
      sections.last_section_at,
      support.unread_count,
      sent.submission_number as sent_number,
      sent.submitted_at as sent_at,
      returns.returned_count,
      returns.returned_at,
      ready.submission_number as ready_number,
      ready.ready_at,
      ready.target_from,
      ready.target_to,
      waits.open_count as waits_open,
      waits.action_count as waits_action,
      waits.changed_at as waits_changed_at,
      preview.version as preview_version,
      preview.released_at as preview_released_at,
      preview.notes_sent_at as preview_sent_at,
      preview.unsorted_count as preview_unsorted
    from clients as client
    left join public.organization_setup as setup on setup.organization_id = client.id
    cross join lateral (
      -- The stages this client is asked: everyone's, and those of a service their package includes.
      select
        (select count(*)::integer from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys))
          as sections_total,
        array(
          select unnest(catalogue.fact_keys) from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
        ) as fact_keys
    ) as own
    -- Questions an earlier answer or the package hides are neither counted nor required.
    cross join lateral (
      select public.setup_hidden_fact_keys(setup_catalogue, own.fact_keys, client.id, client.service_keys)
        as fact_keys
    ) as hidden
    cross join lateral (
      select array(
        select fact.fact_key from unnest(own.fact_keys) as fact(fact_key)
        where not (fact.fact_key = any (hidden.fact_keys))
      ) as fact_keys
    ) as shown
    cross join lateral (
      select
        count(*)::integer as answered,
        (count(*) filter (where answer.availability = 'need_help'))::integer as help_count,
        max(answer.updated_at) as last_answer_at
      from public.organization_setup_answers as answer
      where answer.organization_id = client.id
        and answer.fact_key = any (shown.fact_keys)
    ) as answers
    cross join lateral (
      select
        (count(*) filter (where status.done))::integer as done_count,
        (array_agg(status.section_key order by status.position) filter (where not status.done))[1]
          as next_section_key,
        max(status.completed_at) as last_section_at
      from (
        select
          catalogue.position,
          catalogue.section_key,
          marked.completed_at,
          marked.completed_at is not null and not exists (
            select 1
            from unnest(catalogue.required_keys) as required(fact_key)
            where not (required.fact_key = any (hidden.fact_keys))
              and not exists (
              select 1
              from public.organization_setup_answers as answer
              where answer.organization_id = client.id
                and answer.fact_key = required.fact_key
            )
          ) as done
        from catalogue
        left join public.organization_setup_sections as marked
          on marked.organization_id = client.id
         and marked.section_key = catalogue.section_key
        where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
      ) as status
    ) as sections
    cross join lateral (
      select count(*)::integer as unread_count
      from public.support_threads as thread
      where thread.organization_id = client.id
        and thread.last_message_sender_kind = 'member'
        and thread.last_message_at > coalesce(thread.uplift_last_read_at, '-infinity'::timestamptz)
    ) as support
    -- The newest Send to Uplift, if any; the (organization, number) key makes this one index probe.
    left join lateral (
      select submission.submission_number, submission.submitted_at
      from public.organization_setup_submissions as submission
      where submission.organization_id = client.id
      order by submission.submission_number desc
      limit 1
    ) as sent on true
    -- Sections Uplift sent back on that send; a later send hands them back to Uplift. Keyed by organization.
    cross join lateral (
      select count(*)::integer as returned_count, max(review.reviewed_at) as returned_at
      from public.organization_setup_section_reviews as review
      where review.organization_id = client.id
        and review.decision = 'returned'
        and review.submission_number = sent.submission_number
    ) as returns
    -- C4: Ready for Uplift, if recorded; one primary-key probe.
    left join public.organization_setup_ready as ready on ready.organization_id = client.id
    -- E2: outside waits still open, and those needing the client; at most four rows, keyed by organization.
    cross join lateral (
      select
        (count(*) filter (where wait.status not in ('approved', 'unavailable')))::integer as open_count,
        (count(*) filter (where wait.status = 'action_needed'))::integer as action_count,
        max(wait.updated_at) as changed_at
      from public.organization_setup_provider_waits as wait
      where wait.organization_id = client.id
    ) as waits
    -- E3: the newest released preview, its send, and its sent notes not yet sorted; at most 15 notes.
    left join lateral (
      select
        released.version,
        released.released_at,
        released.notes_sent_at,
        (
          select count(*)::integer
          from public.organization_setup_preview_notes as note
          where note.organization_id = released.organization_id
            and note.version = released.version
            and note.choice <> 'looks_right'
            and note.sorted_kind is null
        ) as unsorted_count
      from public.organization_setup_previews as released
      where released.organization_id = client.id
        and released.released_at is not null
      order by released.version desc
      limit 1
    ) as preview on true
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message is Uplift's; a section sent back on the newest send, or an outside wait needing
  -- the client (E2), is the client's; a setup sent to Uplift and a "need Uplift's help" answer are Uplift's;
  -- everything else is the client's.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.waits_action > 0 then 'client'
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'client'
        when measured.help_count > 0 or measured.sent_number is not null then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        when measured.waits_action > 0 then 'provider_action'
        -- E3: a released preview is the client's to review; their notes are Uplift's to sort, then make.
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'review_preview'
        when measured.preview_unsorted > 0 then 'sort_corrections'
        when measured.preview_sent_at is not null then 'make_corrections'
        -- Ready on the newest send: Uplift builds. A send after Ready has changes to look at first.
        when measured.ready_number = measured.sent_number then 'build_system'
        when measured.sent_number is not null then 'review_setup'
        when measured.help_count > 0 then 'help_with_answers'
        when measured.welcome_seen_at is null and measured.answered = 0 then 'start_setup'
        when measured.next_section_key is not null then 'finish_section'
        else 'send_to_uplift'
      end as next_action,
      greatest(
        measured.account_created_at,
        measured.welcome_seen_at,
        measured.last_answer_at,
        measured.last_section_at,
        measured.sent_at,
        measured.returned_at,
        measured.ready_at,
        measured.waits_changed_at,
        measured.preview_released_at,
        measured.preview_sent_at
      ) as last_activity_at
    from measured
  ),
  tagged as (
    select
      decided.*,
      -- The plan's first reminder goes out after about 24 hours of inactivity and the second at 3 days
      -- (§5); a client quiet for 3 days is the one Jafar should look at himself.
      (decided.waiting_on = 'client' and decided.last_activity_at < now() - interval '3 days') as is_quiet
    from decided
  ),
  matching as (
    select tagged.*
    from tagged
    where search_term is null
      or btrim(search_term) = ''
      or tagged.name ilike '%' || btrim(search_term) || '%'
  ),
  filtered as (
    select matching.*
    from matching
    where waiting_filter is null
      or (waiting_filter = 'quiet' and matching.is_quiet)
      or matching.waiting_on = waiting_filter
  ),
  page as (
    select filtered.*
    from filtered
    where cursor_account_created_at is null
      or (filtered.account_created_at, filtered.id) < (cursor_account_created_at, cursor_id)
    order by filtered.account_created_at desc, filtered.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  )
  select jsonb_build_object(
    'clients', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'name', page.name,
            'lifecycle_status', page.lifecycle_status,
            'package_name', page.package_name,
            'account_created_at', page.account_created_at,
            'payment_reversed', page.payment_reversed_at is not null,
            'welcome_seen', page.welcome_seen_at is not null,
            'sections_done', page.done_count,
            'sections_total', page.sections_total,
            'facts_answered', page.answered,
            'facts_total', page.facts_total,
            'help_count', page.help_count,
            'unread_support', page.unread_count,
            'next_section_key', page.next_section_key,
            'sent_number', page.sent_number,
            'sent_at', page.sent_at,
            'returned_count', page.returned_count,
            'ready_at', page.ready_at,
            'target_from', page.target_from,
            'target_to', page.target_to,
            'provider_waits_open', page.waits_open,
            'provider_waits_action', page.waits_action,
            'preview_version', page.preview_version,
            'preview_released_at', page.preview_released_at,
            'preview_sent_at', page.preview_sent_at,
            'preview_unsorted', coalesce(page.preview_unsorted, 0),
            'waiting_on', page.waiting_on,
            'next_action', page.next_action,
            'last_activity_at', page.last_activity_at,
            'quiet', page.is_quiet
          )
          order by page.account_created_at desc, page.id desc
        )
        from page
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= least(greatest(coalesce(page_size, 50), 1), 100) then (
        select jsonb_build_object('account_created_at', last.account_created_at, 'id', last.id)
        from page as last
        order by last.account_created_at asc, last.id asc
        limit 1
      )
    end,
    'totals', (
      select jsonb_build_object(
        'all', count(*),
        'uplift', count(*) filter (where tagged.waiting_on = 'uplift'),
        'client', count(*) filter (where tagged.waiting_on = 'client'),
        'quiet', count(*) filter (where tagged.is_quiet),
        'matching', (select count(*) from filtered)
      )
      from tagged
    )
  );
$$;
