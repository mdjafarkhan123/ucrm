-- Adding and removing a client's properties.
--
-- Two things blocked it. A client could not hold two properties without names, because names were unique
-- per client and a deleted property kept holding its name. And deleting a client's primary property always
-- failed: `private.set_first_property_primary` demotes it, nothing promotes a replacement, and the deferred
-- `properties_enforce_primary` check then refuses the transaction.

-- 1. Property names are labels, not keys ----------------------------------------------------------------

-- Two sites can reasonably share a name ("Front unit" on either side of a duplex), the index counted
-- soft-deleted rows so a name could never be reused, and Jobber does not enforce it either.
drop index if exists public.properties_client_label_unique_idx;

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

-- 2. Deleting a property --------------------------------------------------------------------------------

-- Soft-deletes one property and, when it was the primary, promotes the client's oldest remaining property
-- in the same transaction so the deferred primary check still sees exactly one. Deleting the last property
-- leaves the client with none, which that check allows.
--
-- `security invoker` on purpose: every statement here passes through the properties RLS policies, so the
-- caller can only ever reach their own organization's rows.
create or replace function public.delete_property(p_property_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_client_id uuid;
  v_was_primary boolean;
  v_next_property_id uuid;
begin
  -- Read before writing: the before-trigger clears `is_primary` on the way out, so the row cannot tell us
  -- afterwards whether a replacement is needed. The lock holds the row while a concurrent save waits.
  select client_id, is_primary
    into v_client_id, v_was_primary
    from public.properties
   where id = p_property_id
     and deleted_at is null
     for update;

  if not found then
    raise exception 'That property could not be found.' using errcode = 'P0002';
  end if;

  -- The billing flag goes with it; a deleted property is not allowed to keep it.
  update public.properties
     set deleted_at = now(),
         is_billing_address = false
   where id = p_property_id;

  if v_was_primary then
    select id
      into v_next_property_id
      from public.properties
     where client_id = v_client_id
       and deleted_at is null
     order by created_at, id
     limit 1;

    if v_next_property_id is not null then
      update public.properties set is_primary = true where id = v_next_property_id;
    end if;
  end if;
end;
$$;

revoke all on function public.delete_property(uuid) from public;
grant execute on function public.delete_property(uuid) to authenticated;
