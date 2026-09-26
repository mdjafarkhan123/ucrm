-- Google review campaign Part 5A: the Reviews workspace's Requests tab.
--
-- Product truth: docs/google-review-campaign-owner-brief.md (§ Reviews workspace and activity).
--
-- public.list_review_requests is one page of an organization's review requests, newest first, with the
-- plain-language status, what the customer did and every message the request sent. Keyset pagination on
-- (created_at, id) walks review_requests_organization_created_idx, so a page costs the same however many
-- requests the business has. A status filter evaluates private.review_request_status per candidate row; the
-- page still stops as soon as it has enough rows. Read by the server only; the caller holds reviews.view for
-- the whole organization, re-checked here.
--
-- Additive: rolling back is dropping the function.

create or replace function public.list_review_requests(
  p_organization_id uuid,
  p_actor_id uuid,
  p_status text default null,
  p_channel text default null,
  p_search text default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  page_size integer := least(greatest(coalesce(p_limit, 25), 1), 50);
  search_pattern text := null;
  rows_json jsonb;
  cursor_created_at timestamptz;
  cursor_id uuid;
  has_more boolean;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.view')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.view') is distinct from 'all' then
    return null;
  end if;

  if p_status is not null and p_status not in (
    'queued', 'scheduled', 'sent', 'delivered', 'failed', 'cancelled', 'not_sent',
    'opened', 'continued_to_google', 'feedback_submitted'
  ) then
    raise exception 'Unknown review request status.' using errcode = 'check_violation';
  end if;
  if p_channel is not null and p_channel not in ('sms', 'email') then
    raise exception 'Unknown review request channel.' using errcode = 'check_violation';
  end if;
  if nullif(btrim(p_search), '') is not null then
    search_pattern := '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with picked as (
    select request.id, request.created_at
    from public.review_requests as request
    where request.organization_id = p_organization_id
      and (p_channel is null or request.channel = p_channel)
      and (p_cursor_created_at is null
           or (request.created_at, request.id) < (p_cursor_created_at, p_cursor_id))
      and (p_status is null or private.review_request_status(request) = p_status)
      and (search_pattern is null or exists (
        select 1 from public.clients as client
        where client.organization_id = request.organization_id
          and client.id = request.client_id
          and client.display_name ilike search_pattern
      ))
    order by request.created_at desc, request.id desc
    limit page_size + 1
  ),
  numbered as (
    select picked.id, picked.created_at,
           row_number() over (order by picked.created_at desc, picked.id desc) as position
    from picked
  )
  select
    coalesce(jsonb_agg(
      private.review_request_summary(request) || jsonb_build_object(
        'client', case when client.id is null then null else jsonb_build_object(
          'id', client.id, 'name', client.display_name) end,
        'job_title', job.title,
        'rating', request.rating,
        'opened_at', request.first_opened_at,
        'continued_to_google_at', request.continued_to_google_at,
        'feedback_submitted_at', request.feedback_submitted_at,
        'cancelled_at', request.cancelled_at
      ) order by numbered.position
    ) filter (where numbered.position <= page_size), '[]'::jsonb),
    coalesce(bool_or(numbered.position > page_size), false),
    (array_agg(numbered.created_at order by numbered.position) filter (where numbered.position = page_size))[1],
    (array_agg(numbered.id order by numbered.position) filter (where numbered.position = page_size))[1]
  into rows_json, has_more, cursor_created_at, cursor_id
  from numbered
  join public.review_requests as request on request.id = numbered.id
  left join public.clients as client
    on client.organization_id = request.organization_id and client.id = request.client_id
   and client.deleted_at is null
  left join public.jobs as job
    on job.organization_id = request.organization_id and job.id = request.job_id;

  return jsonb_build_object(
    'requests', rows_json,
    'next_cursor', case when has_more then jsonb_build_object(
      'created_at', cursor_created_at, 'id', cursor_id) else null end
  );
end;
$$;

comment on function public.list_review_requests(uuid, uuid, text, text, text, timestamptz, uuid, integer) is
  'One keyset page (newest first) of an organization''s review requests for the Reviews workspace, with status, customer actions and messages. Null unless the actor holds reviews.view for the whole organization. Service role only.';

revoke all on function public.list_review_requests(uuid, uuid, text, text, text, timestamptz, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.list_review_requests(uuid, uuid, text, text, text, timestamptz, uuid, integer)
  to service_role;
