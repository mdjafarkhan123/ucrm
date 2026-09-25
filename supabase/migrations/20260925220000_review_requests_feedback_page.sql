-- Google review campaign Part 2: review requests and the customer's feedback page.
--
-- Product truth: docs/google-review-campaign-owner-brief.md ("Rating page and private-feedback form").
--
-- 1. review_requests: one row per review request, each with its own customer link. The link is the shape
--    file_shares already proved: only a SHA-256 hash of the token is stored, and the customer's page reaches
--    the row only through the service-role functions below, which answer null for every failure alike.
--    A link never expires; it works until the request is cancelled (Jafar, 2026-09-25). Part 3 creates the
--    rows and adds the sending facts (channel, contact, schedule, delivery state).
-- 2. review_feedback: at most one private-feedback submission per request (Jafar, 2026-09-25). It starts as
--    New; the Reviews workspace (Part 5) moves it through Contacting customer, Resolved and Closed.
--
-- Both tables are read and written by the server only, like review_settings. Additive: rolling back is
-- dropping them and the four functions.

-- 1. Requests ----------------------------------------------------------------------------------------------

create table public.review_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  client_id uuid not null,
  -- Null when a request is sent from the client page without a particular job.
  job_id uuid,
  token_hash bytea not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  first_opened_at timestamptz,
  last_opened_at timestamptz,
  open_count integer not null default 0,
  continued_to_google_at timestamptz,
  -- The star the customer picked on the routed page. Null while routing is off: nobody is asked for one.
  rating smallint,
  feedback_submitted_at timestamptz,
  constraint review_requests_token_hash_check check (octet_length(token_hash) = 32),
  constraint review_requests_token_hash_key unique (token_hash),
  constraint review_requests_open_count_check check (open_count >= 0),
  constraint review_requests_rating_check check (rating is null or rating between 1 and 5),
  constraint review_requests_organization_id_id_key unique (organization_id, id),
  constraint review_requests_client_fkey
    foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete cascade,
  constraint review_requests_job_fkey
    foreign key (organization_id, job_id)
    references public.jobs (organization_id, id) on delete cascade
);

comment on table public.review_requests is
  'One review request and its customer link. Stores only the token hash. The link works until cancelled_at is set. Read and written by the server only.';

create index review_requests_organization_created_idx
  on public.review_requests (organization_id, created_at desc);
create index review_requests_client_idx on public.review_requests (organization_id, client_id);
create index review_requests_job_idx
  on public.review_requests (organization_id, job_id) where job_id is not null;
create index review_requests_created_by_idx
  on public.review_requests (created_by) where created_by is not null;

-- 2. Private feedback --------------------------------------------------------------------------------------

create table public.review_feedback (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  request_id uuid not null,
  rating smallint,
  -- The questions exactly as the customer saw them, so a later edit to the form never changes what an
  -- answer meant.
  questions jsonb not null,
  answers jsonb not null,
  status text not null default 'new',
  submitted_at timestamptz not null default now(),
  constraint review_feedback_request_key unique (request_id),
  constraint review_feedback_rating_check check (rating is null or rating between 1 and 5),
  constraint review_feedback_status_check
    check (status in ('new', 'contacting', 'resolved', 'closed')),
  constraint review_feedback_questions_check
    check (jsonb_typeof(questions) = 'array' and octet_length(questions::text) <= 65536),
  constraint review_feedback_answers_check
    check (jsonb_typeof(answers) = 'object' and octet_length(answers::text) <= 131072),
  constraint review_feedback_request_fkey
    foreign key (organization_id, request_id)
    references public.review_requests (organization_id, id) on delete cascade
);

comment on table public.review_feedback is
  'A customer''s private feedback on one review request (at most one), and its recovery status. Read and written by the server only.';

create index review_feedback_organization_submitted_idx
  on public.review_feedback (organization_id, submitted_at desc);

alter table public.review_requests enable row level security;
alter table public.review_feedback enable row level security;
revoke all on table public.review_requests, public.review_feedback from public, anon, authenticated;
grant all on table public.review_requests, public.review_feedback to service_role;

-- 3. The customer's page -----------------------------------------------------------------------------------

-- The request behind a hashed token, or null when it never existed, was cancelled, or its client was
-- deleted -- all alike, so the page cannot be used to learn whether a business or a customer exists.
create or replace function private.live_review_request(supplied_token_hash bytea)
returns public.review_requests
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select request.*
  from public.review_requests as request
  join public.clients as client
    on client.organization_id = request.organization_id and client.id = request.client_id
  where supplied_token_hash is not null
    and octet_length(supplied_token_hash) = 32
    and request.token_hash = supplied_token_hash
    and request.cancelled_at is null
    and client.deleted_at is null;
$$;

revoke all on function private.live_review_request(bytea) from public, anon, authenticated;

-- Everything the feedback page needs. `settings` is null while the organization is on UCRM's defaults; the
-- server fills those in. The logo object key stays on the server.
create or replace function public.resolve_review_request(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.review_requests;
begin
  request_row := private.live_review_request(supplied_token_hash);
  if request_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'business', (
      select jsonb_build_object('name', organization.name, 'logo_object_key', settings.logo_object_key)
      from public.organizations as organization
      left join public.organization_settings as settings on settings.organization_id = organization.id
      where organization.id = request_row.organization_id
    ),
    'customer_first_name', (
      select nullif(btrim(client.first_name), '')
      from public.clients as client
      where client.organization_id = request_row.organization_id and client.id = request_row.client_id
    ),
    'settings', (
      select jsonb_build_object(
        'google_review_url', review.google_review_url,
        'routing_enabled', review.routing_enabled,
        'routing_google_min_rating', review.routing_google_min_rating,
        'feedback_form', review.feedback_form
      )
      from public.review_settings as review
      where review.organization_id = request_row.organization_id
    ),
    'rating', request_row.rating,
    'feedback_submitted', request_row.feedback_submitted_at is not null
  );
end;
$$;

comment on function public.resolve_review_request(bytea) is
  'The customer''s reader for a review request link. Hashed token in; business, customer first name, saved review settings (null = defaults) and progress out, or null for unknown, cancelled or deleted-client alike. Service role only.';

-- "The customer actually looked at it": called by the customer's browser once the page is on screen, since
-- mail scanners and link previews fetch URLs before any person does.
create or replace function public.record_review_request_open(supplied_token_hash bytea)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.review_requests;
begin
  request_row := private.live_review_request(supplied_token_hash);
  if request_row.id is null then
    return;
  end if;

  update public.review_requests
  set first_opened_at = coalesce(first_opened_at, now()),
      last_opened_at = now(),
      open_count = open_count + 1
  where id = request_row.id;
end;
$$;

comment on function public.record_review_request_open(bytea) is
  'The customer''s browser saying the feedback page is on screen. Stamps the request''s open facts. Service role only.';

-- The customer chose Google: tapped "Leave a Google review", or picked a star at or above the routing
-- threshold. `supplied_rating` is null when routing is off.
create or replace function public.record_review_request_google(
  supplied_token_hash bytea,
  supplied_rating smallint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.review_requests;
begin
  if supplied_rating is not null and supplied_rating not between 1 and 5 then
    raise exception 'A rating is 1 to 5 stars.' using errcode = 'check_violation';
  end if;

  request_row := private.live_review_request(supplied_token_hash);
  if request_row.id is null then
    return;
  end if;

  update public.review_requests
  set continued_to_google_at = coalesce(continued_to_google_at, now()),
      rating = coalesce(supplied_rating, rating)
  where id = request_row.id;
end;
$$;

comment on function public.record_review_request_google(bytea, smallint) is
  'The customer continued to the Google review destination. Stamps the first time and any star picked. Service role only.';

-- The customer's private feedback. One per request: a second submission changes nothing and says so.
-- The server has already validated `supplied_answers` against `supplied_questions`, the form as it stands.
create or replace function public.submit_review_feedback(
  supplied_token_hash bytea,
  supplied_rating smallint,
  supplied_questions jsonb,
  supplied_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
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

  return jsonb_build_object('state', 'submitted', 'feedback_id', feedback_id);
end;
$$;

comment on function public.submit_review_feedback(bytea, smallint, jsonb, jsonb) is
  'Stores a customer''s private feedback on a review request, at most once, and stamps the request. Null for an unknown or cancelled link. Service role only.';

revoke all on function public.resolve_review_request(bytea) from public, anon, authenticated;
revoke all on function public.record_review_request_open(bytea) from public, anon, authenticated;
revoke all on function public.record_review_request_google(bytea, smallint) from public, anon, authenticated;
revoke all on function public.submit_review_feedback(bytea, smallint, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.resolve_review_request(bytea) to service_role;
grant execute on function public.record_review_request_open(bytea) to service_role;
grant execute on function public.record_review_request_google(bytea, smallint) to service_role;
grant execute on function public.submit_review_feedback(bytea, smallint, jsonb, jsonb) to service_role;
