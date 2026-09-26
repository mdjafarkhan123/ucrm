-- Google review campaign Part 5B: private-feedback recovery.
--
-- Product truth: docs/google-review-campaign-owner-brief.md (§ Private-feedback recovery).
--
-- 1. The header bell can carry a "new private feedback" alert (a new kind and subject type).
-- 2. submit_review_feedback now also creates that alert, in the same transaction as the feedback itself, for
--    each active owner and administrator who may handle private feedback. Bell only: a customer's private words
--    are never put into an email.
-- 3. list_review_feedback is one keyset page of an organization's feedback, newest first, walking
--    review_feedback_organization_submitted_idx, so a page costs the same however much feedback there is.
-- 4. set_review_feedback_status moves one item New -> Contacting customer -> Resolved -> Closed (any order, so a
--    closed item can be reopened).
--
-- Both new functions are read/written by the server only and re-check reviews.feedback for the whole
-- organization. Additive; rolling back is dropping the two functions and restoring the earlier
-- submit_review_feedback and check constraints.

-- 1. Alert kind and subject ---------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check check (kind = any (array[
  'website_inquiry.received', 'website_inquiry.customer_replied', 'invoice.paid_online',
  'invoice.online_payment_failed', 'invoice.online_overpayment', 'quote.deposit_paid_online',
  'quote.deposit_payment_failed', 'quote.deposit_overpaid', 'invoice.online_refund_failed',
  'invoice.payment_disputed', 'quote.deposit_refund_failed', 'quote.deposit_disputed',
  'review.private_feedback'
]));

alter table public.team_notifications drop constraint team_notifications_subject_type_check;
alter table public.team_notifications add constraint team_notifications_subject_type_check
  check (subject_type = any (array['form_submission', 'website_chat_session', 'invoice', 'quote', 'review_feedback']));

-- 2. The alert ----------------------------------------------------------------------------------------------

create or replace function private.create_review_feedback_alert(
  p_organization_id uuid,
  p_feedback_id uuid,
  p_client_id uuid,
  p_job_id uuid,
  p_rating smallint
)
returns void
language sql
security definer
set search_path = pg_catalog, public, private
as $$
  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_state
  )
  select
    p_organization_id, membership.user_id, 'review.private_feedback', 'review_feedback', p_feedback_id,
    left('New private feedback from ' || coalesce(
      (select client.display_name from public.clients as client
       where client.organization_id = p_organization_id and client.id = p_client_id),
      'a customer'), 200),
    left(
      case when p_rating is null then 'They chose to tell you privately' else
        p_rating || case when p_rating = 1 then ' star' else ' stars' end end
      || coalesce((select ' after job #' || job.job_number from public.jobs as job
                   where job.organization_id = p_organization_id and job.id = p_job_id), '')
      || '. Reach out to make it right.', 500),
    'review_feedback:' || p_feedback_id,
    'not_needed'
  from public.organization_members as membership
  where membership.organization_id = p_organization_id
    and membership.status = 'active'
    and membership.role in ('owner', 'admin')
    and private.member_has_permission(p_organization_id, membership.user_id, 'reviews.feedback')
  on conflict (organization_id, user_id, source_key) do nothing;
$$;

revoke all on function private.create_review_feedback_alert(uuid, uuid, uuid, uuid, smallint)
  from public, anon, authenticated;

create or replace function public.submit_review_feedback(
  supplied_token_hash bytea,
  supplied_rating smallint,
  supplied_questions jsonb,
  supplied_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
  feedback_id uuid;
begin
  if supplied_rating is not null and supplied_rating not between 1 and 5 then
    raise exception 'A rating is 1 to 5 stars.' using errcode = 'check_violation';
  end if;

  -- Locked so two taps of Send at once cannot both pass the "not yet submitted" test.
  select request.* into request_row
  from public.review_requests as request
  where request.id = (private.live_review_request(supplied_token_hash)).id
  for update;
  if request_row.id is null then
    return null;
  end if;

  if request_row.feedback_submitted_at is not null then
    return jsonb_build_object('state', 'already_submitted');
  end if;

  insert into public.review_feedback (organization_id, request_id, rating, questions, answers)
  values (request_row.organization_id, request_row.id, supplied_rating, supplied_questions, supplied_answers)
  returning id into feedback_id;

  update public.review_requests
  set feedback_submitted_at = now(),
      rating = coalesce(supplied_rating, rating)
  where id = request_row.id;

  perform private.review_request_stop(request_row.id, 'feedback_submitted', null);
  perform private.create_review_feedback_alert(
    request_row.organization_id, feedback_id, request_row.client_id, request_row.job_id, supplied_rating
  );

  return jsonb_build_object('state', 'submitted', 'feedback_id', feedback_id);
end;
$$;

-- 3. The list -----------------------------------------------------------------------------------------------

-- p_status: null = everything, 'open' = New and Contacting customer, or one exact status.
create or replace function public.list_review_feedback(
  p_organization_id uuid,
  p_actor_id uuid,
  p_status text default null,
  p_search text default null,
  p_cursor_submitted_at timestamptz default null,
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
  cursor_submitted_at timestamptz;
  cursor_id uuid;
  has_more boolean;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.feedback')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.feedback') is distinct from 'all' then
    return null;
  end if;

  if p_status is not null and p_status not in ('open', 'new', 'contacting', 'resolved', 'closed') then
    raise exception 'Unknown feedback status.' using errcode = 'check_violation';
  end if;
  if nullif(btrim(p_search), '') is not null then
    search_pattern := '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with picked as (
    select feedback.id, feedback.submitted_at
    from public.review_feedback as feedback
    join public.review_requests as request
      on request.organization_id = feedback.organization_id and request.id = feedback.request_id
    where feedback.organization_id = p_organization_id
      and (p_status is null
           or (p_status = 'open' and feedback.status in ('new', 'contacting'))
           or feedback.status = p_status)
      and (p_cursor_submitted_at is null
           or (feedback.submitted_at, feedback.id) < (p_cursor_submitted_at, p_cursor_id))
      and (search_pattern is null or exists (
        select 1 from public.clients as client
        where client.organization_id = request.organization_id
          and client.id = request.client_id
          and client.display_name ilike search_pattern
      ))
    order by feedback.submitted_at desc, feedback.id desc
    limit page_size + 1
  ),
  numbered as (
    select picked.id, picked.submitted_at,
           row_number() over (order by picked.submitted_at desc, picked.id desc) as position
    from picked
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'id', feedback.id,
        'request_id', feedback.request_id,
        'status', feedback.status,
        'rating', feedback.rating,
        'submitted_at', feedback.submitted_at,
        'questions', feedback.questions,
        'answers', feedback.answers,
        'channel', request.channel,
        'client', case when client.id is null then null else jsonb_build_object(
          'id', client.id,
          'name', client.display_name,
          'email', (select method.value from public.client_contact_methods as method
                    where method.organization_id = client.organization_id and method.client_id = client.id
                      and method.kind = 'email'
                    order by method.is_primary desc, method.created_at limit 1),
          'phone', (select method.value from public.client_contact_methods as method
                    where method.organization_id = client.organization_id and method.client_id = client.id
                      and method.kind = 'phone'
                    order by method.is_primary desc, method.created_at limit 1)
        ) end,
        'job_id', request.job_id,
        'job_number', job.job_number,
        'job_title', job.title
      ) order by numbered.position
    ) filter (where numbered.position <= page_size), '[]'::jsonb),
    coalesce(bool_or(numbered.position > page_size), false),
    (array_agg(numbered.submitted_at order by numbered.position) filter (where numbered.position = page_size))[1],
    (array_agg(numbered.id order by numbered.position) filter (where numbered.position = page_size))[1]
  into rows_json, has_more, cursor_submitted_at, cursor_id
  from numbered
  join public.review_feedback as feedback on feedback.id = numbered.id
  join public.review_requests as request
    on request.organization_id = feedback.organization_id and request.id = feedback.request_id
  left join public.clients as client
    on client.organization_id = request.organization_id and client.id = request.client_id
   and client.deleted_at is null
  left join public.jobs as job
    on job.organization_id = request.organization_id and job.id = request.job_id;

  return jsonb_build_object(
    'feedback', rows_json,
    'next_cursor', case when has_more then jsonb_build_object(
      'submitted_at', cursor_submitted_at, 'id', cursor_id) else null end
  );
end;
$$;

comment on function public.list_review_feedback(uuid, uuid, text, text, timestamptz, uuid, integer) is
  'One keyset page (newest first) of an organization''s private review feedback with its client, job and contact details. Null unless the actor holds reviews.feedback for the whole organization. Service role only.';

revoke all on function public.list_review_feedback(uuid, uuid, text, text, timestamptz, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.list_review_feedback(uuid, uuid, text, text, timestamptz, uuid, integer)
  to service_role;

-- 4. The status change --------------------------------------------------------------------------------------

create or replace function public.set_review_feedback_status(
  p_organization_id uuid,
  p_actor_id uuid,
  p_feedback_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  feedback_row public.review_feedback;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.feedback')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.feedback') is distinct from 'all' then
    raise exception 'You do not have access to private feedback.' using errcode = 'insufficient_privilege';
  end if;
  if p_status is null or p_status not in ('new', 'contacting', 'resolved', 'closed') then
    raise exception 'Unknown feedback status.' using errcode = 'check_violation';
  end if;

  update public.review_feedback
  set status = p_status
  where organization_id = p_organization_id and id = p_feedback_id
  returning * into feedback_row;
  if feedback_row.id is null then
    raise exception 'That private feedback was not found.' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object('id', feedback_row.id, 'status', feedback_row.status);
end;
$$;

comment on function public.set_review_feedback_status(uuid, uuid, uuid, text) is
  'Moves one private-feedback item to a recovery status. Requires reviews.feedback for the whole organization. Service role only.';

revoke all on function public.set_review_feedback_status(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.set_review_feedback_status(uuid, uuid, uuid, text) to service_role;
