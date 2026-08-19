-- That index was also the only one leading with `client_id`, and three things lean on exactly that lookup on
-- every property write: both primary-property triggers, and the foreign key back to clients. Every other
-- index here leads with `organization_id` or is partial, so dropping the unique index on its own would leave
-- them all on a sequential scan of the whole tenant's properties. This replaces the access path without
-- reintroducing the uniqueness.
--
-- Columns in this order on purpose: `client_id` is the equality every caller has, `deleted_at` filters the
-- active rows, and `created_at` gives the promotion query in `delete_property` its ordering for free.
create index if not exists properties_client_active_idx
  on public.properties (client_id, deleted_at, created_at);
