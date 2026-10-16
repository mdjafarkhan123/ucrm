-- The Clients list's overview cards (Pencil frame TaIwn): the Client book card counts leads, customers and
-- archived clients and names the four most used tags; the dark card says how many clients became
-- customers in the past 30 days against the 30 before, how many new leads arrived, and how many new
-- clients this year.
--
-- Counted live on each read rather than kept in a tally like quote_status_tallies: the 30-day and
-- year windows move with the clock, so a counter would need a nightly job per timezone, and one pass over
-- a tenant's clients measured fast enough at 20,000 clients (see the a1b-clients-requests part note).
--
-- SECURITY INVOKER, so the clients and tag_assignments select policies decide what is counted. The API
-- route only calls these for members holding customers.view, who see every client in the organization,
-- so the numbers match the list below them. The windows are worked out by the caller in the
-- organization's timezone (one place owns that rule) and handed in as instants.

create or replace function public.client_overview_counts(
  target_organization_id uuid,
  current_since timestamptz,
  previous_since timestamptz,
  year_since timestamptz
)
returns table (
  leads bigint,
  customers bigint,
  archived bigint,
  new_clients_current bigint,
  new_clients_previous bigint,
  new_leads_current bigint,
  new_clients_year bigint
)
language sql
stable
set search_path = pg_catalog, public
as $$
  select
    count(*) filter (where c.archived_at is null and c.lifecycle_status = 'lead'),
    count(*) filter (where c.archived_at is null and c.lifecycle_status = 'customer'),
    count(*) filter (where c.archived_at is not null),
    -- "New clients" the way Jobber counts them: the moment a client became a customer, whether they
    -- were converted from a lead or added as a customer straight away.
    count(*) filter (where c.converted_to_customer_at >= current_since),
    count(*) filter (
      where c.converted_to_customer_at >= previous_since
        and c.converted_to_customer_at < current_since
    ),
    -- A client added straight in as a customer is stamped converted in the same statement that creates
    -- it, so it never arrived as a lead.
    count(*) filter (
      where c.created_at >= current_since
        and (c.converted_to_customer_at is null or c.converted_to_customer_at > c.created_at)
    ),
    count(*) filter (where c.converted_to_customer_at >= year_since)
  from public.clients as c
  where c.organization_id = target_organization_id
    and c.deleted_at is null;
$$;

-- The most used tags on clients still on the working list, most used first, name breaking ties so the
-- order is stable. Picking one filters the list to that tag.
create or replace function public.client_popular_tags(
  target_organization_id uuid,
  tag_limit integer default 4
)
returns table (tag_id uuid, name text, total bigint)
language sql
stable
set search_path = pg_catalog, public
as $$
  select t.id, t.name, count(*) as total
  from public.tag_assignments as ta
  join public.clients as c
    on c.organization_id = ta.organization_id
   and c.id = ta.entity_id
  join public.tags as t
    on t.organization_id = ta.organization_id
   and t.id = ta.tag_id
  where ta.organization_id = target_organization_id
    and ta.entity_type = 'client'
    and c.deleted_at is null
    and c.archived_at is null
  group by t.id, t.name
  order by count(*) desc, t.name asc, t.id asc
  limit least(greatest(tag_limit, 1), 12);
$$;

revoke all on function public.client_overview_counts(uuid, timestamptz, timestamptz, timestamptz)
  from public, anon;
revoke all on function public.client_popular_tags(uuid, integer) from public, anon;
grant execute on function public.client_overview_counts(uuid, timestamptz, timestamptz, timestamptz)
  to authenticated;
grant execute on function public.client_popular_tags(uuid, integer) to authenticated;
