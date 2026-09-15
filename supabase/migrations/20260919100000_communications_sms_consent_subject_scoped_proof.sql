-- Communications A2 / Stage 4A part 1: subject-scoped, exact-number SMS consent proof.
--
-- Approved behavior (docs/communications-a2-implementation-plan.md §4A; durable rules in
-- docs/unified-inbox-behavior-contract.md §SMS). Stage 1 stored append-only consent evidence keyed to a
-- customer contact method, but its projection treated any opt-in as a single per-method global permission.
-- The approved 4A rule is finer: consent evidence covers one exact customer phone number AND one or more plain
-- operational subjects, a customer STOP/opt-out is a global legal block, and an older opt-in can never clear a
-- newer opt-out. This part evolves the evidence model to record subjects and the accepted proof method, replaces
-- the now-incorrect global projection with a subject-aware eligibility read computed on demand, and adds the one
-- owner/admin command that records external proof. It enqueues nothing and sends nothing; the consent-aware
-- enqueue command that consumes this is 4A part 2.
--
-- Operational subjects (marketing consent stays separate for A3):
--   * service        — direct service conversations with the customer.
--   * work_updates   — requests, quotes, jobs and appointments.
--   * billing_updates— invoices, receipts and payment reminders.
--
-- Accepted proof of an opt-in: a customer SMS (client_reply), explicit web-form consent, or a signed
-- paper/digital agreement. Verbal consent is not accepted and is not a representable value. Old client-level SMS
-- timestamps are not promoted here because they lack the required phone-number and evidence scope.

-- ---------------------------------------------------------------------------------------------------------------
-- Evidence model: add the covered subjects and the accepted proof method to the append-only evidence.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_consent_events
  add column subjects text[],
  add column proof_method text;

-- An opt-in names at least one valid operational subject and how it was proven; an opt-out or a HELP request is
-- global and carries no subject list. Verbal is absent from the allowed methods, so it cannot be recorded.
alter table public.communication_sms_consent_events
  add constraint communication_sms_consent_events_subject_scope_check check (
    (
      event_kind = 'opt_in'
      and subjects is not null
      and array_length(subjects, 1) >= 1
      and subjects <@ array['service', 'work_updates', 'billing_updates']::text[]
      and array_position(subjects, null) is null
      and proof_method in ('customer_sms', 'web_form', 'signed_agreement', 'client_reply')
    )
    or (
      event_kind in ('opt_out', 'help_requested')
      and subjects is null
      and (proof_method is null or proof_method in ('customer_sms', 'client_reply', 'provider_keyword'))
    )
  );

comment on column public.communication_sms_consent_events.subjects is
  'For an opt-in, the operational subjects the customer agreed to (service, work_updates, billing_updates). '
  'Null for a global opt-out or HELP request. Marketing consent is separate and out of A2 scope.';
comment on column public.communication_sms_consent_events.proof_method is
  'How an opt-in was proven: customer_sms, web_form or signed_agreement for recorded proof, client_reply for a '
  'customer text. Verbal is not an accepted method and cannot be stored.';

-- ---------------------------------------------------------------------------------------------------------------
-- Replace the Stage 1 per-method global projection: it predates subjects and would mark a number opted-in for
-- every subject the moment any subject was granted. Eligibility is now derived on read per (number, subject) from
-- the append-only events, so it is subject-correct and can never go stale — the same compute-on-read approach used
-- for readiness, outbound state and promotional balance.
-- ---------------------------------------------------------------------------------------------------------------

drop trigger if exists communication_sms_consent_events_project_after_insert
  on public.communication_sms_consent_events;
drop function if exists private.project_communication_sms_consent_event();
drop table if exists public.communication_sms_consent_state;

-- The current consent status of one exact customer number for one operational subject. The governing event is the
-- most recent one that affects this pair: any opt-out (global), or an opt-in whose subjects include this subject.
-- HELP requests never change eligibility. Delayed evidence is ordered by occurred_at, then received_at, then id,
-- so a late-arriving older event can never overwrite a newer decision.
create function public.communication_sms_consent_status(
  p_organization_id uuid,
  p_client_contact_method_id uuid,
  p_subject text
) returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (
      select case when governing.event_kind = 'opt_in' then 'opted_in' else 'opted_out' end
      from public.communication_sms_consent_events governing
      where governing.organization_id = p_organization_id
        and governing.client_contact_method_id = p_client_contact_method_id
        and (
          governing.event_kind = 'opt_out'
          or (governing.event_kind = 'opt_in' and p_subject = any(governing.subjects))
        )
      order by governing.occurred_at desc, governing.received_at desc, governing.id desc
      limit 1
    ),
    'unknown'
  );
$$;

comment on function public.communication_sms_consent_status(uuid, uuid, text) is
  'Current SMS consent for one exact customer contact method and one operational subject '
  '(opted_in / opted_out / unknown), derived on read from append-only evidence. Unknown blocks sending.';

-- ---------------------------------------------------------------------------------------------------------------
-- Command: record external opt-in proof. Owner/admin only at launch. All writes to consent evidence for staff
-- proof happen only through this command.
-- ---------------------------------------------------------------------------------------------------------------

create function public.communication_sms_record_consent_proof(
  p_organization_id uuid,
  p_actor uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_proof_method text,
  p_subjects text[],
  p_occurred_at timestamptz,
  p_source_event_key text,
  p_evidence jsonb default '{}'::jsonb
) returns public.communication_sms_consent_events
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_role text;
  method public.client_contact_methods;
  event public.communication_sms_consent_events;
begin
  if p_actor is null then
    raise exception 'recording consent proof must record who did it' using errcode = 'P0001';
  end if;

  -- Only the contractor owner or an administrator may record external consent proof at launch.
  select membership.role into actor_role
  from public.organization_members membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_actor
    and membership.status = 'active';

  if actor_role is null or actor_role not in ('owner', 'admin') then
    raise exception 'Only an owner or administrator can record customer SMS consent proof.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Verbal consent is not accepted; only the three recorded proof methods may be entered here.
  if p_proof_method is null or p_proof_method not in ('customer_sms', 'web_form', 'signed_agreement') then
    raise exception 'Consent proof must be a customer text, web-form consent, or a signed agreement.'
      using errcode = 'P0001';
  end if;

  if p_subjects is null or array_length(p_subjects, 1) is null then
    raise exception 'Choose at least one thing this consent covers.' using errcode = 'P0001';
  end if;
  if not (p_subjects <@ array['service', 'work_updates', 'billing_updates']::text[])
     or array_position(p_subjects, null) is not null then
    raise exception 'Consent can only cover service, work updates, or billing updates.'
      using errcode = 'P0001';
  end if;

  if p_occurred_at is null then
    raise exception 'Consent proof must record when the customer agreed.' using errcode = 'P0001';
  end if;
  if p_occurred_at > now() then
    raise exception 'Consent proof cannot be dated in the future.' using errcode = 'P0001';
  end if;

  if p_source_event_key is null or char_length(btrim(p_source_event_key)) = 0 then
    raise exception 'Consent proof must carry an idempotency key.' using errcode = 'P0001';
  end if;

  -- The proof is scoped to one exact customer phone number belonging to this client in this organization.
  select cm.* into method
  from public.client_contact_methods cm
  join public.clients client
    on client.organization_id = cm.organization_id and client.id = cm.client_id
  where cm.organization_id = p_organization_id
    and cm.id = p_client_contact_method_id
    and cm.client_id = p_client_id
    and cm.kind = 'phone'
    and client.deleted_at is null;

  if method.id is null then
    raise exception 'Choose an active phone number for this customer.' using errcode = 'P0001';
  end if;

  -- Idempotent: the same recorded proof (org, staff source, key) yields the same evidence row, never a duplicate.
  insert into public.communication_sms_consent_events (
    organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
    subjects, proof_method, evidence, occurred_at, created_by
  ) values (
    p_organization_id, p_client_id, p_client_contact_method_id, 'opt_in', 'staff', btrim(p_source_event_key),
    p_subjects, p_proof_method, coalesce(p_evidence, '{}'::jsonb), p_occurred_at, p_actor
  )
  on conflict (organization_id, source, source_event_key) do nothing
  returning * into event;

  if event.id is null then
    select * into event
    from public.communication_sms_consent_events
    where organization_id = p_organization_id and source = 'staff'
      and source_event_key = btrim(p_source_event_key);
  end if;

  return event;
end;
$$;

comment on function public.communication_sms_record_consent_proof(uuid, uuid, uuid, uuid, text, text[], timestamptz, text, jsonb) is
  'Owner/admin-only command to record external SMS opt-in proof for one exact customer phone number and one or '
  'more operational subjects. Idempotent by (organization, staff source, source_event_key). Verbal consent is '
  'refused. The /api/* layer supplies the authenticated actor and a stable idempotency key.';

-- ---------------------------------------------------------------------------------------------------------------
-- Access: the consent-evidence table keeps its Stage 1 server-owned, append-only grants. The new reads and the
-- proof command are server-only; the /api/* layer calls them with service_role and scopes to the caller's org.
-- ---------------------------------------------------------------------------------------------------------------

revoke all on function public.communication_sms_consent_status(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_consent_status(uuid, uuid, text) to service_role;

revoke all on function public.communication_sms_record_consent_proof(uuid, uuid, uuid, uuid, text, text[], timestamptz, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_consent_proof(uuid, uuid, uuid, uuid, text, text[], timestamptz, text, jsonb)
  to service_role;
