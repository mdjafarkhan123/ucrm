-- Pipeline D3: saved filters on the board.
--
-- A saved filter is a name for one combination of the board's controls — sort, salesperson, lead source, and
-- created date — so a salesperson can get back to "My Google leads, oldest first" in one click (Pipedrive and
-- HubSpot both work this way). Two kinds:
--
--   * Personal: belongs to the person who saved it. Only they see it and only they change or delete it.
--   * Shared: saved by an owner or administrator for the whole team. Every member who can see the board sees
--     it; only owners and administrators rename, update, or delete it, whoever first saved it.
--
-- A filter stores the controls exactly as the board's address writes them (`owner=…&source=…`), so applying
-- one is the same as opening a link to it, and the board reads it with the same forgiving parser it uses for
-- a hand-edited address. The search box is never saved: a filter is a standing view, not a one-off lookup.
--
-- Writes go straight to the table under row level security; the API checks the same rules first so a member
-- gets a clear answer instead of a database error.
--
-- Growth: at most 50 personal filters per person and 50 shared filters per organization, enforced by a
-- trigger. The board reads one person's list by (organization_id, user_id) and the shared list by
-- (organization_id) where user_id is null — both index lookups over at most 100 rows.

create table public.pipeline_saved_filters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- The person a personal filter belongs to. Null means the filter is shared with everyone.
  user_id uuid references auth.users (id) on delete cascade,
  name text not null,
  -- The board's controls as its address writes them, without the leading `?` and without a search term.
  query text not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pipeline_saved_filters_name_check check (
    name = btrim(name) and char_length(name) between 1 and 60
  ),
  constraint pipeline_saved_filters_query_check check (
    char_length(query) between 1 and 500 and query !~ '(^|&)q='
  )
);

comment on table public.pipeline_saved_filters is
  'Named combinations of the Pipeline board''s controls. user_id set: a personal filter only that person sees and changes. user_id null: shared with every member; only owners and administrators change it.';
comment on column public.pipeline_saved_filters.query is
  'The board''s controls as its URL query string writes them (sort, direction, owner, date, from, to, source). Never a search term.';

-- One name per list: "Hot leads" twice in my list, or twice in the shared list, is a mistake. A personal and a
-- shared filter may share a name; the menu shows them under separate headings.
create unique index pipeline_saved_filters_personal_name_idx
  on public.pipeline_saved_filters (organization_id, user_id, lower(name))
  where user_id is not null;
create unique index pipeline_saved_filters_shared_name_idx
  on public.pipeline_saved_filters (organization_id, lower(name))
  where user_id is null;

create index pipeline_saved_filters_user_idx
  on public.pipeline_saved_filters (user_id) where user_id is not null;
create index pipeline_saved_filters_created_by_idx
  on public.pipeline_saved_filters (created_by) where created_by is not null;

-- ---------------------------------------------------------------------------------------------------------
-- The two caps, and keeping updated_at honest
-- ---------------------------------------------------------------------------------------------------------

create function private.pipeline_saved_filters_guard()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  existing_count integer;
begin
  if tg_op = 'UPDATE' then
    -- Which list a filter is on, and whose it is, never changes. Sharing a filter is saving it again as shared.
    if new.organization_id <> old.organization_id or new.user_id is distinct from old.user_id then
      raise exception 'A saved filter cannot move to another list.' using errcode = 'check_violation';
    end if;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_at := now();
    return new;
  end if;

  select count(*) into existing_count
  from public.pipeline_saved_filters
  where organization_id = new.organization_id
    and user_id is not distinct from new.user_id;

  if existing_count >= 50 then
    raise exception 'You can keep up to 50 saved filters here. Delete one before saving another.'
      using errcode = 'check_violation';
  end if;

  new.created_by := (select auth.uid());
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.pipeline_saved_filters_guard() from public, anon, authenticated;

create trigger pipeline_saved_filters_guard
  before insert or update on public.pipeline_saved_filters
  for each row execute function private.pipeline_saved_filters_guard();

-- ---------------------------------------------------------------------------------------------------------
-- Who sees and changes what
-- ---------------------------------------------------------------------------------------------------------

alter table public.pipeline_saved_filters enable row level security;

create policy "members see their own and shared saved filters" on public.pipeline_saved_filters
  for select to authenticated
  using (
    private.has_permission(organization_id, 'pipeline.view')
    and (user_id is null or user_id = (select auth.uid()))
  );

create policy "members save their own filters; administrators save shared ones" on public.pipeline_saved_filters
  for insert to authenticated
  with check (
    private.has_permission(organization_id, 'pipeline.view')
    and (
      user_id = (select auth.uid())
      or (user_id is null and private.is_organization_admin(organization_id))
    )
  );

create policy "members change their own filters; administrators change shared ones" on public.pipeline_saved_filters
  for update to authenticated
  using (
    private.has_permission(organization_id, 'pipeline.view')
    and (
      user_id = (select auth.uid())
      or (user_id is null and private.is_organization_admin(organization_id))
    )
  )
  with check (
    private.has_permission(organization_id, 'pipeline.view')
    and (
      user_id = (select auth.uid())
      or (user_id is null and private.is_organization_admin(organization_id))
    )
  );

create policy "members delete their own filters; administrators delete shared ones" on public.pipeline_saved_filters
  for delete to authenticated
  using (
    private.has_permission(organization_id, 'pipeline.view')
    and (
      user_id = (select auth.uid())
      or (user_id is null and private.is_organization_admin(organization_id))
    )
  );

revoke all on table public.pipeline_saved_filters from anon;
revoke truncate, references, trigger on table public.pipeline_saved_filters from authenticated;
grant select, insert, delete on table public.pipeline_saved_filters to authenticated;
-- Only the name and the controls change after saving.
revoke update on table public.pipeline_saved_filters from authenticated;
grant update (name, query) on table public.pipeline_saved_filters to authenticated;
