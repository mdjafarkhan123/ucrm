-- The Quotes Overview card counted every quote in the organization on each read (Seq Scan, 12.9 ms at
-- 20,000 quotes; a narrow (organization_id, status) index measured worse). Jafar chose on 2026-09-28 to fix
-- it before any tenant gets that big.
--
-- A counter cache: one row per organization and status, kept by statement-level triggers inside the same
-- transaction as the quote write, so it is never stale and the read touches at most one row per status.
-- Every member who can view quotes sees all of the organization's quotes (the quotes select policy is
-- organization-wide), so a per-organization tally shows each of them exactly what the live count did.
create table public.quote_status_tallies (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  status text not null,
  -- No check (total >= 0): a tally must never be able to block a quote write. Reads skip rows <= 0.
  total bigint not null,
  primary key (organization_id, status)
);

alter table public.quote_status_tallies enable row level security;

create policy "permitted members can view quote status tallies"
  on public.quote_status_tallies
  for select
  to authenticated
  using (organization_id in (select private.permitted_organizations('quotes.view')));

-- Only the trigger below writes here.
revoke all on table public.quote_status_tallies from anon, authenticated;
grant select on table public.quote_status_tallies to authenticated;

create or replace function private.apply_quote_status_tally_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- One statement for every changed (organization, status) pair, applied in key order so two writers
  -- moving quotes in opposite directions always lock the same rows in the same order and cannot deadlock.
  -- A negative delta only touches a row that already exists: when an organization is deleted its tally
  -- rows cascade away first, and inserting a fresh row for it would fail its foreign key.
  with changes as (
    select organization_id, status, count(*) as delta
    from new_rows
    group by organization_id, status
    union all
    select organization_id, status, -count(*)
    from old_rows
    group by organization_id, status
  ),
  deltas as (
    select organization_id, status, sum(delta)::bigint as delta
    from changes
    group by organization_id, status
    having sum(delta) <> 0
  )
  insert into public.quote_status_tallies as tally (organization_id, status, total)
  select deltas.organization_id, deltas.status, deltas.delta
  from deltas
  where deltas.delta > 0
     or exists (
       select 1 from public.quote_status_tallies as existing
       where existing.organization_id = deltas.organization_id
         and existing.status = deltas.status
     )
  order by deltas.organization_id, deltas.status
  on conflict (organization_id, status)
  do update set total = tally.total + excluded.total;

  return null;
end;
$$;

-- Transition tables allow only one event per trigger, so insert and delete get their own small functions.
create or replace function private.apply_quote_status_tally_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.quote_status_tallies as tally (organization_id, status, total)
  select inserted.organization_id, inserted.status, count(*)
  from new_rows as inserted
  group by inserted.organization_id, inserted.status
  order by inserted.organization_id, inserted.status
  on conflict (organization_id, status)
  do update set total = tally.total + excluded.total;

  return null;
end;
$$;

create or replace function private.apply_quote_status_tally_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- Lock in key order first, like the update path, so concurrent deletes cannot deadlock. Only rows that
  -- still exist are touched: an organization delete cascades its tally rows away as its quotes go.
  perform 1
  from public.quote_status_tallies as tally
  where (tally.organization_id, tally.status) in (
    select deleted.organization_id, deleted.status from old_rows as deleted
  )
  order by tally.organization_id, tally.status
  for update;

  update public.quote_status_tallies as tally
  set total = tally.total - removed.total
  from (
    select deleted.organization_id, deleted.status, count(*) as total
    from old_rows as deleted
    group by deleted.organization_id, deleted.status
  ) as removed
  where tally.organization_id = removed.organization_id
    and tally.status = removed.status;

  return null;
end;
$$;

create trigger quotes_status_tally_insert
  after insert on public.quotes
  referencing new table as new_rows
  for each statement execute function private.apply_quote_status_tally_insert();

create trigger quotes_status_tally_update
  after update on public.quotes
  referencing old table as old_rows new table as new_rows
  for each statement execute function private.apply_quote_status_tally_update();

create trigger quotes_status_tally_delete
  after delete on public.quotes
  referencing old table as old_rows
  for each statement execute function private.apply_quote_status_tally_delete();

revoke all on function private.apply_quote_status_tally_update() from public, anon, authenticated;
revoke all on function private.apply_quote_status_tally_insert() from public, anon, authenticated;
revoke all on function private.apply_quote_status_tally_delete() from public, anon, authenticated;

-- Backfill while no quote can change underneath it: CREATE TRIGGER above took a SHARE ROW EXCLUSIVE lock
-- on quotes that holds until this migration commits, and the triggers cover every write after that.

insert into public.quote_status_tallies (organization_id, status, total)
select quote.organization_id, quote.status, count(*)
from public.quotes as quote
group by quote.organization_id, quote.status;

-- Same signature and security as before: SECURITY INVOKER, so the tally's select policy decides access.
-- Statuses with no row simply do not appear, exactly as the live group-by behaved; the API fills zeros.
create or replace function public.quote_status_counts(target_organization_id uuid)
returns table (status text, total bigint)
language sql
stable
set search_path = pg_catalog, public
as $$
  select tally.status, tally.total
  from public.quote_status_tallies as tally
  where tally.organization_id = target_organization_id
    and tally.total > 0;
$$;
