-- Google review campaign Part 3: the manual "Request a review" action.
--
-- Product truth: docs/google-review-campaign-owner-brief.md (§ Contractor control, owner decisions 2026-09-26).
--
-- A request is a review_requests row plus one message in the existing Communications pipeline, so delivery,
-- quiet hours, STOP, suppression, SMS credit and the unified inbox all behave exactly as they do for every
-- other customer message:
--   * SMS goes through private.communication_sms_enqueue_operational_core with the 'service' subject; the
--     SMS worker re-checks consent, the sending number and quiet hours at send time.
--   * Email goes from the business's default automated sender as an 'optional' message, so an address that
--     unsubscribed, bounced or complained is suppressed.
--   * "Schedule" is the outbox's own available_at, the same mechanism the inbox's scheduled email uses.
--
-- 1. review_requests gains its sending facts (the table is empty: nothing has created a request yet).
-- 2. private helpers: job eligibility and the plain-language status.
-- 3. public.get_review_request_context: everything the Request a review panel needs.
-- 4. public.create_review_request: creates the request and queues its message in one transaction.
-- 5. public.cancel_review_request: cancels a request whose message has not started sending.
-- All three public functions are service-role only and re-check the actor's reviews.request permission and
-- scope; the app has already checked the plan's Reputation feature.

-- 1. Sending facts ------------------------------------------------------------------------------------------

alter table public.review_requests
  add column channel text not null,
  -- 'automation' arrives with Part 4.
  add column origin text not null default 'manual',
  add column delivery_intent_id uuid references public.communication_delivery_intents (id) on delete set null,
  add column cancelled_by uuid references auth.users (id) on delete set null,
  add constraint review_requests_channel_check check (channel in ('sms', 'email')),
  add constraint review_requests_origin_check check (origin in ('manual', 'automation'));

create unique index review_requests_delivery_intent_key
  on public.review_requests (delivery_intent_id) where delivery_intent_id is not null;
create index review_requests_cancelled_by_idx
  on public.review_requests (cancelled_by) where cancelled_by is not null;

-- 2. Helpers ------------------------------------------------------------------------------------------------

-- A job the business may ask about: work was actually done (at least one completed Visit), and it is either
-- closed or an ongoing recurring job (owner decision 2026-09-26).
create or replace function private.review_request_job_is_eligible(
  p_organization_id uuid,
  p_job_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.jobs as job
    where job.organization_id = p_organization_id
      and job.id = p_job_id
      and (job.status = 'closed' or job.job_type = 'recurring')
      and exists (
        select 1 from public.job_visits as visit
        where visit.organization_id = job.organization_id
          and visit.job_id = job.id
          and visit.completed_at is not null
      )
  );
$$;

revoke all on function private.review_request_job_is_eligible(uuid, uuid) from public, anon, authenticated;

-- May this member ask for a review about this job (or, with no job, about this client in general)?
-- 'all' may ask about anything; 'assigned' (a fieldworker) only about a job they worked on.
create or replace function private.review_request_actor_may_ask(
  p_organization_id uuid,
  p_actor_id uuid,
  p_job_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  scope text;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.request') then
    return false;
  end if;
  scope := private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.request');
  if scope = 'all' then
    return true;
  end if;
  return scope = 'assigned' and p_job_id is not null and exists (
    select 1 from public.job_visit_assignments as assignment
    where assignment.organization_id = p_organization_id
      and assignment.job_id = p_job_id
      and assignment.user_id = p_actor_id
  );
end;
$$;

revoke all on function private.review_request_actor_may_ask(uuid, uuid, uuid) from public, anon, authenticated;

-- The one plain-language status the brief names, furthest step first: what the customer did beats what the
-- message did. 'scheduled' also covers a text held back by quiet hours -- it is genuinely waiting to go.
create or replace function private.review_request_status(p_request public.review_requests)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  intent public.communication_delivery_intents;
  outbox public.communication_outbox_events;
begin
  if p_request.cancelled_at is not null then return 'cancelled'; end if;
  if p_request.feedback_submitted_at is not null then return 'feedback_submitted'; end if;
  if p_request.continued_to_google_at is not null then return 'continued_to_google'; end if;
  if p_request.first_opened_at is not null then return 'opened'; end if;

  select * into intent from public.communication_delivery_intents where id = p_request.delivery_intent_id;
  if intent.id is null then return 'queued'; end if;
  if intent.status = 'cancelled' then return 'cancelled'; end if;
  if intent.status = 'failed'
    or intent.delivery_outcome in ('hard_bounce', 'complaint', 'blocked', 'unsubscribed', 'sms_undelivered', 'sms_failed') then
    return 'failed';
  end if;
  if intent.delivery_outcome in ('delivered', 'sms_delivered') then return 'delivered'; end if;
  if intent.status = 'submitted' then return 'sent'; end if;

  select * into outbox from public.communication_outbox_events where delivery_intent_id = intent.id;
  if outbox.status = 'pending' and outbox.available_at > now() then return 'scheduled'; end if;
  return 'queued';
end;
$$;

revoke all on function private.review_request_status(public.review_requests) from public, anon, authenticated;

-- A request as the app shows it.
create or replace function private.review_request_summary(p_request public.review_requests)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'id', p_request.id,
    'job_id', p_request.job_id,
    'job_number', (select job.job_number from public.jobs as job
                   where job.organization_id = p_request.organization_id and job.id = p_request.job_id),
    'channel', p_request.channel,
    'recipient', coalesce(intent.recipient_phone, intent.recipient_email),
    'status', private.review_request_status(p_request),
    'created_at', p_request.created_at,
    'send_at', outbox.available_at,
    'sent_at', intent.accepted_at,
    'failure_message', case when intent.status = 'failed' or intent.status = 'cancelled'
                            then intent.failure_message end,
    'cancellable', p_request.cancelled_at is null and outbox.status = 'pending' and outbox.available_at > now()
  )
  from (select 1) as anchor
  left join public.communication_delivery_intents as intent on intent.id = p_request.delivery_intent_id
  left join public.communication_outbox_events as outbox on outbox.delivery_intent_id = intent.id;
$$;

revoke all on function private.review_request_summary(public.review_requests) from public, anon, authenticated;

-- 3. Panel context ------------------------------------------------------------------------------------------

-- Opened from a job (p_job_id; its client is used) or from a client page (p_client_id, no job). Null when
-- the client or job does not exist here or the actor may not ask about it -- all alike.
create or replace function public.get_review_request_context(
  p_organization_id uuid,
  p_actor_id uuid,
  p_client_id uuid,
  p_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  scope text;
  client_row public.clients;
  job_row public.jobs;
  sms_sender public.communication_sms_sender_identities;
  sms_registration public.communication_sms_registrations;
  sms_state text;
  sms_reason text;
  email_ready boolean;
begin
  if p_job_id is not null then
    select * into job_row from public.jobs where organization_id = p_organization_id and id = p_job_id;
    if job_row.id is null then return null; end if;
  end if;
  select * into client_row from public.clients
  where organization_id = p_organization_id
    and id = coalesce(job_row.client_id, p_client_id)
    and deleted_at is null;
  if client_row.id is null then return null; end if;

  if not private.review_request_actor_may_ask(p_organization_id, p_actor_id, p_job_id) then
    return null;
  end if;
  scope := private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.request');

  -- Texting is ready when the default number could send right now (the same test the send itself runs).
  select * into sms_sender from public.communication_sms_sender_identities
  where organization_id = p_organization_id and is_default_sender and lifecycle_state = 'ready' and capable_sms;
  if sms_sender.id is null or sms_sender.registration_id is null then
    sms_reason := 'no_number';
  else
    select * into sms_registration from public.communication_sms_registrations
    where organization_id = p_organization_id and id = sms_sender.registration_id;
    select state into sms_state from public.communication_sms_outbound_state(
      p_organization_id, sms_sender.country_code, sms_sender.sender_type, sms_registration.use_case);
    if sms_state = 'outbound_paused' then sms_reason := 'paused';
    elsif sms_state is distinct from 'ready' then sms_reason := 'not_ready';
    end if;
  end if;

  select exists (
    select 1
    from public.communication_email_senders as sender
    join public.communication_email_domains as domain
      on domain.organization_id = sender.organization_id and domain.id = sender.domain_id
    where sender.organization_id = p_organization_id
      and sender.lifecycle_state = 'enabled' and sender.allows_automated and sender.is_organization_default
      and domain.purpose = 'sending' and domain.lifecycle_state = 'verified'
      and domain.provider_verified and domain.provider_authenticated
      and domain.ownership_status = 'passing' and domain.dkim_status = 'passing'
  ) into email_ready;

  return jsonb_build_object(
    'business_name', (select name from public.organizations where id = p_organization_id),
    'client', jsonb_build_object(
      'id', client_row.id,
      'name', client_row.display_name,
      'first_name', nullif(btrim(client_row.first_name), '')
    ),
    'job', case when job_row.id is null then null else jsonb_build_object(
      'id', job_row.id,
      'job_number', job_row.job_number,
      'title', job_row.title,
      'eligible', private.review_request_job_is_eligible(p_organization_id, job_row.id)
    ) end,
    -- The client's jobs that can be asked about, most recently completed first. Only from the client page.
    'jobs', case when p_job_id is not null then '[]'::jsonb else coalesce((
      select jsonb_agg(item.body order by item.last_completed_at desc)
      from (
        select jsonb_build_object(
                 'id', job.id, 'job_number', job.job_number, 'title', job.title,
                 'last_completed_at', max(visit.completed_at)
               ) as body,
               max(visit.completed_at) as last_completed_at
        from public.jobs as job
        join public.job_visits as visit
          on visit.organization_id = job.organization_id and visit.job_id = job.id
         and visit.completed_at is not null
        where job.organization_id = p_organization_id
          and job.client_id = client_row.id
          and (job.status = 'closed' or job.job_type = 'recurring')
          and (scope = 'all' or exists (
            select 1 from public.job_visit_assignments as assignment
            where assignment.organization_id = job.organization_id
              and assignment.job_id = job.id and assignment.user_id = p_actor_id))
        group by job.id
        order by max(visit.completed_at) desc
        limit 25
      ) as item
    ), '[]'::jsonb) end,
    'phones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', method.id, 'value', method.value, 'label', method.label, 'is_primary', method.is_primary,
               'contact_name', nullif(btrim(concat_ws(' ', contact.first_name, contact.last_name)), ''),
               'sms_consent', public.communication_sms_consent_status(p_organization_id, method.id, 'service')
             ) order by method.is_primary desc, method.created_at, method.id)
      from public.client_contact_methods as method
      left join public.client_contacts as contact
        on contact.organization_id = method.organization_id and contact.id = method.client_contact_id
      where method.organization_id = p_organization_id and method.client_id = client_row.id
        and method.kind = 'phone'
    ), '[]'::jsonb),
    'emails', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', method.id, 'value', method.value, 'label', method.label, 'is_primary', method.is_primary,
               'contact_name', nullif(btrim(concat_ws(' ', contact.first_name, contact.last_name)), ''),
               'suppressed', (
                 select suppression.reason from public.communication_email_suppressions as suppression
                 where suppression.organization_id = p_organization_id
                   and suppression.recipient_email = method.normalized_value
                   and suppression.released_at is null
                 order by suppression.reason limit 1)
             ) order by method.is_primary desc, method.created_at, method.id)
      from public.client_contact_methods as method
      left join public.client_contacts as contact
        on contact.organization_id = method.organization_id and contact.id = method.client_contact_id
      where method.organization_id = p_organization_id and method.client_id = client_row.id
        and method.kind = 'email'
    ), '[]'::jsonb),
    'sms_ready', sms_reason is null,
    'sms_reason', sms_reason,
    'email_ready', email_ready,
    -- The newest request to this client about anything, so the panel can say "already asked on ...".
    'last_asked_at', (
      select max(request.created_at) from public.review_requests as request
      where request.organization_id = p_organization_id and request.client_id = client_row.id
        and request.cancelled_at is null
    ),
    'requests', coalesce((
      select jsonb_agg(private.review_request_summary(request) order by request.created_at desc)
      from (
        select * from public.review_requests as request
        where request.organization_id = p_organization_id and request.client_id = client_row.id
          and (p_job_id is null or request.job_id = p_job_id)
        order by request.created_at desc
        limit 5
      ) as request
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.get_review_request_context(uuid, uuid, uuid, uuid) is
  'Everything the Request a review panel needs for a job or a client: contacts with texting consent and email suppression, channel readiness, askable jobs and recent requests. Null when not found or not allowed. Service role only.';

-- 4. Create -------------------------------------------------------------------------------------------------

-- The app renders the message (it holds the new link) and passes the body with the link inside it. A retry
-- with the same p_idempotency_key returns the first request instead of sending twice.
create or replace function public.create_review_request(
  p_organization_id uuid,
  p_actor_id uuid,
  p_client_id uuid,
  p_job_id uuid,
  p_channel text,
  p_contact_method_id uuid,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_link_url text,
  p_token_hash bytea,
  p_send_at timestamptz,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  send_key text;
  existing_request public.review_requests;
  client_row public.clients;
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  alias public.communication_reply_aliases;
  request_row public.review_requests;
  intent public.communication_delivery_intents;
begin
  if p_organization_id is null or p_actor_id is null or p_client_id is null then
    raise exception 'An organization, an actor and a client are required.' using errcode = 'check_violation';
  end if;
  if p_channel is null or p_channel not in ('sms', 'email') then
    raise exception 'Choose text message or email.' using errcode = 'check_violation';
  end if;
  if coalesce(btrim(p_idempotency_key), '') = '' then
    raise exception 'A send key is required.' using errcode = 'check_violation';
  end if;
  if p_link_url is null or p_link_url !~ '^https?://[^[:space:]]+$'
    or p_token_hash is null or octet_length(p_token_hash) <> 32 then
    raise exception 'The review link is not available.' using errcode = 'check_violation';
  end if;
  if p_body_text is null or position(p_link_url in p_body_text) = 0
    or (p_channel = 'email' and (p_body_html is null or position(p_link_url in p_body_html) = 0)) then
    raise exception 'The message must include the review link.' using errcode = 'check_violation';
  end if;
  if p_channel = 'email' and coalesce(btrim(p_subject), '') = '' then
    raise exception 'An email needs a subject.' using errcode = 'check_violation';
  end if;
  if p_send_at is not null and (p_send_at <= now() or p_send_at > now() + interval '90 days') then
    raise exception 'Choose a send time within the next 90 days.' using errcode = 'check_violation';
  end if;

  send_key := 'review_request:' || btrim(p_idempotency_key);

  -- A retry of the same send returns what the first attempt made.
  select request.* into existing_request
  from public.review_requests as request
  join public.communication_delivery_intents as intent on intent.id = request.delivery_intent_id
  where intent.organization_id = p_organization_id and intent.logical_send_key = send_key;
  if existing_request.id is not null then
    return private.review_request_summary(existing_request);
  end if;

  if not private.review_request_actor_may_ask(p_organization_id, p_actor_id, p_job_id) then
    raise exception 'You do not have permission to ask this customer for a review.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.organizations where id = p_organization_id and lifecycle_status = 'active'
  ) then
    raise exception 'This business cannot send messages right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  select * into client_row from public.clients
  where organization_id = p_organization_id and id = p_client_id and deleted_at is null
  for share;
  if client_row.id is null then
    raise exception 'That client was not found.' using errcode = 'no_data_found';
  end if;

  if p_job_id is not null then
    if not exists (
      select 1 from public.jobs where organization_id = p_organization_id and id = p_job_id and client_id = p_client_id
    ) then
      raise exception 'That job was not found for this client.' using errcode = 'no_data_found';
    end if;
    if not private.review_request_job_is_eligible(p_organization_id, p_job_id) then
      raise exception 'Ask for a review once work on this job has been completed.' using errcode = 'check_violation';
    end if;
  end if;

  select * into recipient from public.client_contact_methods
  where organization_id = p_organization_id and client_id = p_client_id and id = p_contact_method_id
    and kind = case when p_channel = 'sms' then 'phone' else 'email' end
  for share;
  if recipient.id is null then
    raise exception 'Choose one of this client''s saved % for the review request.',
      case when p_channel = 'sms' then 'mobile numbers' else 'email addresses' end
      using errcode = 'foreign_key_violation';
  end if;

  insert into public.review_requests (organization_id, client_id, job_id, token_hash, created_by, channel, origin)
  values (p_organization_id, p_client_id, p_job_id, p_token_hash, p_actor_id, p_channel, 'manual')
  returning * into request_row;

  if p_channel = 'sms' then
    -- Consent, the sending number, SMS credit and quiet hours are all the shared core's job; its refusal
    -- rolls back the request row above with it.
    intent := private.communication_sms_enqueue_operational_core(
      p_organization_id, p_client_id, recipient.id, null, 'service', p_body_text, 'manual', send_key,
      p_actor_id, '[]'::jsonb);
    if p_send_at is not null then
      update public.communication_outbox_events
      set available_at = greatest(available_at, p_send_at)
      where delivery_intent_id = intent.id and status = 'pending';
    end if;
  else
    if exists (
      select 1 from public.communication_email_suppressions as suppression
      where suppression.organization_id = p_organization_id
        and suppression.recipient_email = recipient.normalized_value
        and suppression.released_at is null
    ) then
      raise exception 'This email address unsubscribed or could not receive email, so it cannot be asked.'
        using errcode = 'check_violation';
    end if;

    -- The business's own default sender, as for every automated customer email. The worker repeats these
    -- checks before submission.
    select email_sender.* into sender
    from public.communication_email_senders as email_sender
    join public.communication_email_domains as domain
      on domain.organization_id = email_sender.organization_id and domain.id = email_sender.domain_id
    where email_sender.organization_id = p_organization_id
      and email_sender.lifecycle_state = 'enabled' and email_sender.allows_automated
      and email_sender.is_organization_default
      and domain.purpose = 'sending' and domain.lifecycle_state = 'verified'
      and domain.provider_verified and domain.provider_authenticated
      and domain.ownership_status = 'passing' and domain.dkim_status = 'passing'
    order by email_sender.created_at, email_sender.id
    limit 1
    for share of email_sender, domain;
    if sender.id is null then
      raise exception 'Your business email is not set up to send yet.' using errcode = 'object_not_in_prerequisite_state';
    end if;

    alias := public.ensure_communication_reply_alias(p_organization_id, sender.id, p_client_id, recipient.id);

    -- 'optional': a review request is not an essential service message, so an unsubscribe suppresses it.
    insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
      subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by
    ) values (
      p_organization_id, p_client_id, recipient.id, send_key, recipient.normalized_value,
      btrim(p_subject), p_body_html, p_body_text, 'manual', 'optional', sender.id, alias.id, p_actor_id
    )
    returning * into intent;

    insert into public.communication_outbox_events (organization_id, delivery_intent_id, available_at)
    values (p_organization_id, intent.id, coalesce(p_send_at, now()));
  end if;

  update public.review_requests set delivery_intent_id = intent.id
  where id = request_row.id
  returning * into request_row;

  return private.review_request_summary(request_row);
end;
$$;

comment on function public.create_review_request(uuid, uuid, uuid, uuid, text, uuid, text, text, text, text, bytea, timestamptz, text) is
  'Creates a manual review request and queues its SMS or email (optionally scheduled) through the Communications outbox, in one transaction. Idempotent on p_idempotency_key. Service role only.';

-- 5. Cancel -------------------------------------------------------------------------------------------------

-- Only before the message starts sending: afterwards the customer already has the link.
create or replace function public.cancel_review_request(
  p_organization_id uuid,
  p_actor_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
  intent public.communication_delivery_intents;
  outbox public.communication_outbox_events;
begin
  select * into request_row from public.review_requests
  where organization_id = p_organization_id and id = p_request_id
  for update;
  if request_row.id is null
    or not private.review_request_actor_may_ask(p_organization_id, p_actor_id, request_row.job_id) then
    raise exception 'That review request was not found.' using errcode = 'no_data_found';
  end if;
  if request_row.cancelled_at is not null then
    return private.review_request_summary(request_row);
  end if;

  select * into intent from public.communication_delivery_intents
  where organization_id = p_organization_id and id = request_row.delivery_intent_id
  for update;
  select * into outbox from public.communication_outbox_events
  where delivery_intent_id = intent.id
  for update;
  if outbox.id is null or outbox.status <> 'pending' or outbox.available_at <= now() then
    raise exception 'This review request has already been sent and can no longer be cancelled.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  update public.communication_outbox_events set status = 'cancelled' where id = outbox.id;
  update public.communication_delivery_intents
  set status = 'cancelled', failure_code = 'review_request_cancelled',
      failure_message = 'The review request was cancelled before it was sent.'
  where id = intent.id;
  if intent.channel = 'sms' then
    perform private.communication_sms_release_reservation(intent.id);
  end if;

  update public.review_requests
  set cancelled_at = now(), cancelled_by = p_actor_id
  where id = request_row.id
  returning * into request_row;

  return private.review_request_summary(request_row);
end;
$$;

comment on function public.cancel_review_request(uuid, uuid, uuid) is
  'Cancels a review request whose message has not started sending, releasing any held SMS credit and switching its link off. Service role only.';

revoke all on function public.get_review_request_context(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.create_review_request(uuid, uuid, uuid, uuid, text, uuid, text, text, text, text, bytea, timestamptz, text) from public, anon, authenticated;
revoke all on function public.cancel_review_request(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.get_review_request_context(uuid, uuid, uuid, uuid) to service_role;
grant execute on function public.create_review_request(uuid, uuid, uuid, uuid, text, uuid, text, text, text, text, bytea, timestamptz, text) to service_role;
grant execute on function public.cancel_review_request(uuid, uuid, uuid) to service_role;
