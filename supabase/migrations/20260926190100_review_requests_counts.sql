-- Google review campaign Part 5A: the four numbers above the Reviews workspace.
--
-- public.review_request_counts counts an organization's review requests from the last 30 days by what the
-- customer did, from stored columns only (review_requests_organization_created_idx bounds the range). It also
-- counts private feedback still marked New, which only a member holding reviews.feedback may see (null
-- otherwise). Read by the server only. Additive: rolling back is dropping the function.

create or replace function public.review_request_counts(
  p_organization_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  since timestamptz := now() - interval '30 days';
  may_see_feedback boolean;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.view')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.view') is distinct from 'all' then
    return null;
  end if;

  may_see_feedback := private.member_has_permission(p_organization_id, p_actor_id, 'reviews.feedback')
    and private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.feedback') = 'all';

  return (
    select jsonb_build_object(
      'asked', count(*) filter (where request.cancelled_at is null),
      'opened', count(*) filter (where request.first_opened_at is not null),
      'went_to_google', count(*) filter (where request.continued_to_google_at is not null),
      'private_feedback', count(*) filter (where request.feedback_submitted_at is not null),
      'new_feedback', case when may_see_feedback then (
        select count(*) from public.review_feedback as feedback
        where feedback.organization_id = p_organization_id and feedback.status = 'new'
      ) else null end
    )
    from public.review_requests as request
    where request.organization_id = p_organization_id and request.created_at >= since
  );
end;
$$;

comment on function public.review_request_counts(uuid, uuid) is
  'Last-30-day review request counts by customer action, plus private feedback still New for a member who may see it. Null unless the actor holds reviews.view for the whole organization. Service role only.';

revoke all on function public.review_request_counts(uuid, uuid) from public, anon, authenticated;
grant execute on function public.review_request_counts(uuid, uuid) to service_role;
