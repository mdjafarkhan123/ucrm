-- The status commands are the first thing that writes status_changed_by, and that column points at
-- auth.users with ON DELETE SET NULL. Deleting one Auth account made Postgres read every membership row in
-- the database looking for the ones to blank. Item 4 fixed the same hazard on the history table; this is the
-- membership table's turn. Partial, because the column is null on every row nobody has deactivated.
create index if not exists organization_members_status_changed_by_idx
  on public.organization_members (status_changed_by)
  where status_changed_by is not null;
