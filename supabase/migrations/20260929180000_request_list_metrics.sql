-- The Requests list's "New requests" and "Conversion rate" cards, defined as Jobber defines them
-- (help.getjobber.com, "List Pages and Key Metrics", checked 2026-09-29):
--   New requests    = requests created in the last 30 days.
--   Conversion rate = of those, the share that became a quote or job — so it can never pass 100%.
-- Both come with the same two numbers for the 30 days before, for the page's trend.
--
-- A request here converts through convert_request_to_quote, which links the quote (quotes.request_id) and
-- marks the request converted; either one counts, so a request whose quote later went away still counts.
--
-- Security invoker, like request_status_counts: the caller's own row-level security decides which requests
-- are counted, so a member who sees only assigned work gets figures about that work alone. Reads at most 60
-- days of one organization's requests through requests_organization_created_idx.
create or replace function public.request_list_metrics(target_organization_id uuid)
returns table (
  new_current bigint,
  new_previous bigint,
  converted_current bigint,
  converted_previous bigint
)
  language sql stable
  set search_path to 'pg_catalog', 'public'
  as $$
  with window_requests as (
    select
      r.created_at >= now() - interval '30 days' as is_current,
      (
        r.status = 'converted'
        or exists (
          select 1 from public.quotes q
          where q.organization_id = r.organization_id and q.request_id = r.id
        )
      ) as is_converted
    from public.requests r
    where r.organization_id = target_organization_id
      and r.created_at >= now() - interval '60 days'
      and r.created_at < now()
  )
  select
    count(*) filter (where is_current),
    count(*) filter (where not is_current),
    count(*) filter (where is_current and is_converted),
    count(*) filter (where not is_current and is_converted)
  from window_requests;
$$;

alter function public.request_list_metrics(uuid) owner to postgres;

revoke all on function public.request_list_metrics(uuid) from public, anon;
grant execute on function public.request_list_metrics(uuid) to authenticated, service_role;
