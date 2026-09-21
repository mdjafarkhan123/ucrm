-- "Stop texting this customer": a staff member records that a customer asked (by phone, in person, or in
-- writing) to stop getting texts, and can take back their own stop if it was a mistake.
--
-- Rules, matching how SMS consent already works (append-only evidence, newest event wins):
--   * A staff stop is an ordinary `opt_out` event with source `staff`, marked evidence.kind = 'staff_stop'.
--     It blocks every text to that one number through the existing consent gate -- nothing else changes.
--   * A customer's own STOP is locked. Staff can neither stack a stop on it nor undo it; only the customer's
--     START (or an owner/admin recording real proof) lifts it.
--   * Undoing a staff stop does not invent new consent. It re-records exactly the subjects, with the same
--     proof method, that the customer had agreed to just before the stop. If there was no earlier consent,
--     there is nothing to restore and the undo is refused.
--
-- Permission (who may press the button) is checked by the /api layer; these commands only require an active
-- member so the actor is always recorded. All three are server-only, like the other consent commands.

create or replace function public.communication_sms_client_stop_state(
  p_organization_id uuid,
  p_client_id uuid
)
returns table (
  contact_method_id uuid,
  value text,
  is_primary boolean,
  state text,
  stopped_by text,
  stopped_at timestamptz,
  stopped_by_user uuid,
  note text,
  can_undo boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    phone.id,
    phone.value,
    phone.is_primary,
    status.state,
    case when status.state = 'opted_out' then
      case when stop.source = 'staff' and stop.evidence ->> 'kind' = 'staff_stop' then 'staff' else 'customer' end
    end,
    case when status.state = 'opted_out' then stop.occurred_at end,
    case when status.state = 'opted_out' then stop.created_by end,
    case when status.state = 'opted_out' then nullif(stop.evidence ->> 'note', '') end,
    status.state = 'opted_out'
      and stop.source = 'staff' and stop.evidence ->> 'kind' = 'staff_stop'
      and exists (
        select 1
        from public.communication_sms_consent_events earlier
        where earlier.organization_id = p_organization_id
          and earlier.client_contact_method_id = phone.id
          and earlier.event_kind = 'opt_in'
          and (earlier.occurred_at, earlier.received_at, earlier.id) < (stop.occurred_at, stop.received_at, stop.id)
      )
  from public.client_contact_methods phone
  join public.clients client
    on client.organization_id = phone.organization_id and client.id = phone.client_id
  cross join lateral (
    select public.communication_sms_consent_status(p_organization_id, phone.id, 'service') as state
  ) status
  left join lateral (
    select event.*
    from public.communication_sms_consent_events event
    where event.organization_id = p_organization_id
      and event.client_contact_method_id = phone.id
      and event.event_kind = 'opt_out'
    order by event.occurred_at desc, event.received_at desc, event.id desc
    limit 1
  ) stop on status.state = 'opted_out'
  where phone.organization_id = p_organization_id
    and phone.client_id = p_client_id
    and phone.kind = 'phone'
    and client.deleted_at is null
  order by phone.is_primary desc, phone.created_at, phone.id;
$$;

comment on function public.communication_sms_client_stop_state(uuid, uuid) is
  'Per phone number of one customer: whether texts may be sent, and when stopped, whether the customer or staff stopped them, who, why, and whether staff may take that stop back (only their own, and only when earlier consent exists). Read-only; derived from the consent evidence.';

create or replace function public.communication_sms_staff_stop(
  p_organization_id uuid,
  p_actor uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_note text,
  p_source_event_key text
)
returns public.communication_sms_consent_events
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_status text;
  method public.client_contact_methods;
  event public.communication_sms_consent_events;
  clean_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if p_actor is null then
    raise exception 'Stopping texts must record who did it.' using errcode = 'P0001';
  end if;

  select membership.status into actor_status
  from public.organization_members membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_actor
    and membership.status = 'active';
  if actor_status is null then
    raise exception 'Only an active team member can stop texts.' using errcode = 'insufficient_privilege';
  end if;

  if p_source_event_key is null or char_length(btrim(p_source_event_key)) = 0 then
    raise exception 'Stopping texts must carry an idempotency key.' using errcode = 'P0001';
  end if;
  if clean_note is not null and char_length(clean_note) > 500 then
    raise exception 'Keep the note under 500 characters.' using errcode = 'P0001';
  end if;

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

  -- One stop or undo at a time per number, so two people cannot cross each other.
  perform pg_advisory_xact_lock(hashtextextended(method.id::text, 0));

  select * into event
  from public.communication_sms_consent_events
  where organization_id = p_organization_id and source = 'staff' and source_event_key = btrim(p_source_event_key);
  if event.id is not null then
    return event;
  end if;

  -- Never stack a staff stop on top of a stop that already stands. In particular a customer's own STOP must
  -- stay the governing event, because staff cannot undo that one.
  if public.communication_sms_consent_status(p_organization_id, method.id, 'service') = 'opted_out' then
    raise exception 'Texts to this number are already stopped.' using errcode = 'P0001';
  end if;

  insert into public.communication_sms_consent_events (
    organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
    evidence, occurred_at, created_by
  ) values (
    p_organization_id, p_client_id, method.id, 'opt_out', 'staff', btrim(p_source_event_key),
    jsonb_strip_nulls(jsonb_build_object('kind', 'staff_stop', 'note', clean_note)), clock_timestamp(), p_actor
  )
  returning * into event;

  return event;
end;
$$;

comment on function public.communication_sms_staff_stop(uuid, uuid, uuid, uuid, text, text) is
  'Records that a customer asked staff to stop texting one exact phone number. Blocks every text to that number through the ordinary consent gate. Refused when the number is already stopped, so a customer STOP is never replaced by a takeback-able staff stop. Idempotent by (organization, staff source, source_event_key).';

create or replace function public.communication_sms_staff_stop_undo(
  p_organization_id uuid,
  p_actor uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_source_event_key text
)
returns public.communication_sms_consent_events
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_status text;
  method public.client_contact_methods;
  stop public.communication_sms_consent_events;
  event public.communication_sms_consent_events;
  restored_subjects text[];
  restored_proof text;
begin
  if p_actor is null then
    raise exception 'Turning texts back on must record who did it.' using errcode = 'P0001';
  end if;

  select membership.status into actor_status
  from public.organization_members membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_actor
    and membership.status = 'active';
  if actor_status is null then
    raise exception 'Only an active team member can turn texts back on.' using errcode = 'insufficient_privilege';
  end if;

  if p_source_event_key is null or char_length(btrim(p_source_event_key)) = 0 then
    raise exception 'Turning texts back on must carry an idempotency key.' using errcode = 'P0001';
  end if;

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

  perform pg_advisory_xact_lock(hashtextextended(method.id::text, 0));

  select * into event
  from public.communication_sms_consent_events
  where organization_id = p_organization_id and source = 'staff' and source_event_key = btrim(p_source_event_key);
  if event.id is not null then
    return event;
  end if;

  -- The stop that stands is the newest opt-out. Only a staff stop can be taken back; a customer's own STOP
  -- is theirs to lift by texting START.
  select * into stop
  from public.communication_sms_consent_events
  where organization_id = p_organization_id
    and client_contact_method_id = method.id
    and event_kind = 'opt_out'
  order by occurred_at desc, received_at desc, id desc
  limit 1;

  if stop.id is null
     or public.communication_sms_consent_status(p_organization_id, method.id, 'service') <> 'opted_out' then
    raise exception 'Texts to this number are not stopped.' using errcode = 'P0001';
  end if;
  if stop.source <> 'staff' or stop.evidence ->> 'kind' is distinct from 'staff_stop' then
    raise exception 'The customer stopped these texts themselves. Only they can turn them back on, by replying START.'
      using errcode = 'P0001';
  end if;

  -- What the customer had agreed to just before the stop: for each subject, the newest earlier event that
  -- speaks to it, kept only when that event is an opt-in. The proof method comes from the newest of them.
  with subjects as (
    select subject from unnest(array['service', 'work_updates', 'billing_updates']::text[]) as subject
  ), governing as (
    select distinct on (subjects.subject) subjects.subject, earlier.event_kind, earlier.proof_method,
           earlier.occurred_at, earlier.received_at, earlier.id
    from subjects
    join public.communication_sms_consent_events earlier
      on earlier.organization_id = p_organization_id
     and earlier.client_contact_method_id = method.id
     and (earlier.occurred_at, earlier.received_at, earlier.id) < (stop.occurred_at, stop.received_at, stop.id)
     and (earlier.event_kind = 'opt_out'
          or (earlier.event_kind = 'opt_in' and subjects.subject = any(earlier.subjects)))
    order by subjects.subject, earlier.occurred_at desc, earlier.received_at desc, earlier.id desc
  )
  select array_agg(governing.subject order by governing.subject),
         (array_agg(governing.proof_method order by governing.occurred_at desc, governing.received_at desc, governing.id desc))[1]
    into restored_subjects, restored_proof
  from governing
  where governing.event_kind = 'opt_in';

  if restored_subjects is null or restored_proof is null then
    raise exception 'This customer had not agreed to texts before the stop, so there is nothing to turn back on.'
      using errcode = 'P0001';
  end if;

  insert into public.communication_sms_consent_events (
    organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
    subjects, proof_method, evidence, occurred_at, created_by
  ) values (
    p_organization_id, p_client_id, method.id, 'opt_in', 'staff', btrim(p_source_event_key),
    restored_subjects, restored_proof,
    jsonb_build_object('kind', 'staff_stop_undone', 'reverses', stop.id), clock_timestamp(), p_actor
  )
  returning * into event;

  return event;
end;
$$;

comment on function public.communication_sms_staff_stop_undo(uuid, uuid, uuid, uuid, text) is
  'Takes back a staff-recorded stop for one exact phone number by re-recording the consent the customer had just before it (same subjects, same proof method). Refused for a customer STOP and when no earlier consent exists. Idempotent by (organization, staff source, source_event_key).';

revoke all on function public.communication_sms_client_stop_state(uuid, uuid) from public, anon, authenticated;
revoke all on function public.communication_sms_staff_stop(uuid, uuid, uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.communication_sms_staff_stop_undo(uuid, uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.communication_sms_client_stop_state(uuid, uuid) to service_role;
grant execute on function public.communication_sms_staff_stop(uuid, uuid, uuid, uuid, text, text) to service_role;
grant execute on function public.communication_sms_staff_stop_undo(uuid, uuid, uuid, uuid, text) to service_role;
