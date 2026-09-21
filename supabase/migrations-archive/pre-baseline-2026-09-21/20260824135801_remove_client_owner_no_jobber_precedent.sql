-- Removes clients.owner_user_id and everything built on it.
--
-- Jobber has no persistent client-level owner. Ownership/assignment lives on each work object
-- separately (Request/Quote `salesperson`, later Job and Invoice `salesperson`) and is reassignable at
-- every stage — never one fixed owner for the whole customer relationship. We already built the correct
-- equivalent for the Request/Quote stage as `opportunities.owner_user_id` (untouched by this migration).
-- `clients.owner_user_id` was added speculatively before that existed, was never written by any code
-- path, and has no Jobber precedent. Per Jafar's decision on 2026-08-24 ("follow Jobber, delete what
-- doesn't match"), it is removed rather than built out.
--
-- The Field role's "assigned work only" scope is unaffected: it was always meant to key off Visit/Job
-- assignment (see the `private.client_is_assigned_to_current_user` stub added 2026-08-16), which still
-- correctly returns false until Scheduling exists.

drop trigger if exists clients_validate_owner on public.clients;
drop function if exists private.validate_client_owner();
drop index if exists public.clients_organization_owner_idx;

alter table public.clients
  drop column if exists owner_user_id;

-- create_client, minus the owner_user_id column it used to write.
create or replace function public.create_client(payload jsonb)
returns public.clients
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  created_client public.clients;
  new_property_id uuid;
  new_note_id uuid;
  email_value text := nullif(trim(payload->>'email'), '');
  phone_value text := nullif(trim(payload->>'phone'), '');
  property_payload jsonb := payload->'property';
  initial_note_value text := nullif(trim(payload->>'initial_note'), '');
  preferences jsonb := payload->'preferences';
  tag_ids jsonb := payload->'tag_ids';
begin
  insert into public.clients (
    organization_id,
    display_name,
    client_type,
    first_name,
    last_name,
    company_name,
    lifecycle_status,
    lead_source,
    lead_temperature,
    next_follow_up_at
  )
  values (
    (payload->>'organization_id')::uuid,
    payload->>'display_name',
    coalesce(nullif(payload->>'client_type', ''), 'person'),
    nullif(trim(payload->>'first_name'), ''),
    nullif(trim(payload->>'last_name'), ''),
    nullif(trim(payload->>'company_name'), ''),
    coalesce(nullif(payload->>'lifecycle_status', ''), 'lead'),
    nullif(trim(payload->>'lead_source'), ''),
    nullif(payload->>'lead_temperature', ''),
    nullif(payload->>'next_follow_up_at', '')::timestamptz
  )
  returning * into created_client;

  if email_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'email', email_value, true);
  end if;

  if phone_value is not null then
    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (created_client.organization_id, created_client.id, 'phone', phone_value, true);
  end if;

  if property_payload is not null and jsonb_typeof(property_payload) = 'object' then
    insert into public.properties (
      organization_id,
      client_id,
      label,
      address_line1,
      address_line2,
      city,
      state_region,
      postal_code,
      country,
      access_notes,
      is_billing_address
    )
    values (
      created_client.organization_id,
      created_client.id,
      coalesce(nullif(trim(property_payload->>'label'), ''), 'Primary property'),
      property_payload->>'address_line1',
      nullif(trim(property_payload->>'address_line2'), ''),
      property_payload->>'city',
      nullif(trim(property_payload->>'state_region'), ''),
      nullif(trim(property_payload->>'postal_code'), ''),
      coalesce(nullif(property_payload->>'country', ''), 'US'),
      nullif(trim(property_payload->>'access_notes'), ''),
      coalesce((property_payload->>'is_billing_address')::boolean, false)
    )
    returning id into new_property_id;
  end if;

  if initial_note_value is not null then
    insert into public.notes (organization_id, body, created_by)
    values (created_client.organization_id, initial_note_value, (select auth.uid()))
    returning id into new_note_id;

    insert into public.note_links (organization_id, note_id, entity_type, entity_id)
    values (created_client.organization_id, new_note_id, 'client', created_client.id);
  end if;

  -- The preference row already exists: an after-insert trigger creates it for every client.
  if preferences is not null and jsonb_typeof(preferences) = 'object' then
    update public.client_communication_preferences as saved
    set
      appointment_reminders = coalesce((preferences->>'appointment_reminders')::boolean, saved.appointment_reminders),
      quote_follow_ups = coalesce((preferences->>'quote_follow_ups')::boolean, saved.quote_follow_ups),
      invoice_reminders = coalesce((preferences->>'invoice_reminders')::boolean, saved.invoice_reminders),
      job_follow_ups = coalesce((preferences->>'job_follow_ups')::boolean, saved.job_follow_ups),
      review_requests = coalesce((preferences->>'review_requests')::boolean, saved.review_requests),
      marketing = coalesce((preferences->>'marketing')::boolean, saved.marketing),
      contact_policy = coalesce(nullif(preferences->>'contact_policy', ''), saved.contact_policy)
    where saved.organization_id = created_client.organization_id
      and saved.client_id = created_client.id;
  end if;

  -- The tag has to belong to this organization; the composite foreign key enforces that.
  if tag_ids is not null and jsonb_typeof(tag_ids) = 'array' then
    insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id, created_by)
    select
      created_client.organization_id,
      chosen.value::uuid,
      'client',
      created_client.id,
      (select auth.uid())
    from jsonb_array_elements_text(tag_ids) as chosen(value)
    on conflict (tag_id, entity_type, entity_id) do nothing;
  end if;

  return created_client;
end;
$$;

revoke all on function public.create_client(jsonb) from public;
grant execute on function public.create_client(jsonb) to authenticated;
