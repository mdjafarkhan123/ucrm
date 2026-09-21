-- Closes the unindexed-FK advisory the previous migration triggered, matching catalog_items_created_by_idx:
-- without this, a user deletion's ON DELETE SET NULL against communications_snippets is a sequential scan.
create index communications_snippets_created_by_idx
  on public.communications_snippets(created_by)
  where created_by is not null;
