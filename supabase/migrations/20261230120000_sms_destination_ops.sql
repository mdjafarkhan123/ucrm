-- Stage 10 Part 5b: Uplift's Texting setup work.
--
-- The Control Room's to-do queue of countries waiting to be switched on in Twilio, and a business's own list of
-- countries. People in the Control Room sign in by email and have no Supabase user, so each history row also
-- keeps the name of whoever did it ("Sam already did this").

-- 1. Who did it ------------------------------------------------------------------------------------------------

alter table public.communication_sms_destination_events
  add column actor_name text,
  add constraint communication_sms_destination_events_actor_name_check
    check (actor_name is null or char_length(actor_name) between 1 and 200);

comment on column public.communication_sms_destination_events.actor_name is
  'Stage 10 Part 5b: the Control Room person who switched the country on or off, as shown in its history.';

-- 2. The commands, now with the person's name ------------------------------------------------------------------

drop function public.communication_sms_switch_on_destination(uuid, uuid);
drop function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean);

create function public.communication_sms_switch_on_destination(
  p_destination_id uuid,
  p_actor uuid,
  p_actor_name text default null
) returns public.communication_sms_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  destination public.communication_sms_destinations;
begin
  update public.communication_sms_destinations
  set status = 'ready', ready_by = p_actor, ready_at = now(), updated_at = now()
  where id = p_destination_id and status = 'setting_up'
  returning * into destination;

  if destination.id is not null then
    insert into public.communication_sms_destination_events (
      organization_id, destination_id, event_kind, actor, actor_name
    ) values (
      destination.organization_id, destination.id, 'switched_on', p_actor, nullif(trim(p_actor_name), '')
    );
  end if;
  return destination;
end;
$$;

comment on function public.communication_sms_switch_on_destination(uuid, uuid, text) is
  'Stage 10 Part 5: an Uplift admin records that the country is switched on in Twilio. Only a waiting country moves; null means it was not waiting.';

create function public.communication_sms_turn_off_destination(
  p_destination_id uuid,
  p_actor uuid,
  p_reason text,
  p_business_message text,
  p_closing boolean,
  p_actor_name text default null
) returns public.communication_sms_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  destination public.communication_sms_destinations;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'Give a reason.' using errcode = 'check_violation';
  end if;

  update public.communication_sms_destinations
  set status = 'off', off_by = p_actor, off_at = now(), off_reason = trim(p_reason),
    business_message = nullif(trim(coalesce(p_business_message, '')), ''), updated_at = now()
  where id = p_destination_id
    and status = case when p_closing then 'setting_up' else 'ready' end
  returning * into destination;

  if destination.id is not null then
    insert into public.communication_sms_destination_events (
      organization_id, destination_id, event_kind, actor, actor_name, note
    ) values (
      destination.organization_id, destination.id,
      case when p_closing then 'closed' else 'turned_off' end, p_actor, nullif(trim(p_actor_name), ''),
      trim(p_reason)
    );
  end if;
  return destination;
end;
$$;

comment on function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean, text) is
  'Stage 10 Part 5: closes a waiting country Uplift could not switch on, or turns a ready one off, with a reason and what the business is told.';

revoke all on function public.communication_sms_switch_on_destination(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_switch_on_destination(uuid, uuid, text) to service_role;
grant execute on function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean, text)
  to service_role;

-- 3. What one country costs ------------------------------------------------------------------------------------

-- The selling price of a text segment and a picture text to one country today, from a local number (the kind
-- every business has), else from any number kind that has a price. Twilio's cost rides along for Uplift.
create or replace function private.communication_sms_country_price(p_country text)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'segment', (
      select jsonb_build_object('rate', r.retail_rate_major, 'cost', r.provider_cost_major, 'currency', r.currency_code)
      from public.communication_sms_retail_rates r
      where r.destination = p_country and r.message_unit = 'segment' and r.effective_from <= now()
      order by (r.sender_type = 'long_code') desc, r.effective_from desc
      limit 1
    ),
    'mms', (
      select jsonb_build_object('rate', r.retail_rate_major, 'cost', r.provider_cost_major, 'currency', r.currency_code)
      from public.communication_sms_retail_rates r
      where r.destination = p_country and r.message_unit = 'mms' and r.effective_from <= now()
      order by (r.sender_type = 'long_code') desc, r.effective_from desc
      limit 1
    )
  );
$$;

revoke all on function private.communication_sms_country_price(text) from public, anon, authenticated;

-- One country's history, newest first, with the business person's name for a request.
create or replace function private.communication_sms_destination_history(p_destination_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', e.event_kind,
    'at', e.occurred_at,
    'who', coalesce(e.actor_name, p.full_name),
    'note', e.note
  ) order by e.occurred_at desc), '[]'::jsonb)
  from public.communication_sms_destination_events e
  left join public.profiles p on p.id = e.actor
  where e.destination_id = p_destination_id;
$$;

revoke all on function private.communication_sms_destination_history(uuid) from public, anon, authenticated;

-- 4. The Control Room's to-do queue ----------------------------------------------------------------------------

-- Every country waiting on Uplift, oldest first, with what the task panel shows, and the page's four numbers.
create or replace function public.communication_sms_destination_queue()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  with priced as (
    select distinct r.destination as country
    from public.communication_sms_retail_rates r
    where r.message_unit = 'segment' and r.effective_from <= now()
  ),
  asked as (
    select d.country_code from public.communication_sms_destinations d where d.status <> 'off'
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'to_do', (select count(*) from public.communication_sms_destinations where status = 'setting_up'),
      'oldest_at', (select min(requested_at) from public.communication_sms_destinations where status = 'setting_up'),
      'waiting_on_twilio',
        (select count(*) from public.communication_sms_registrations where status = 'under_review')
        + (select count(*) from public.communication_sms_number_paperwork where status = 'under_review')
        + (select count(*) from public.communication_sms_tollfree_verifications where status = 'under_review'),
      'countries_live',
        (select count(distinct country_code) from public.communication_sms_destinations where status = 'ready'),
      'businesses_live',
        (select count(distinct organization_id) from public.communication_sms_destinations where status = 'ready'),
      'countries_without_price', (
        select coalesce(jsonb_agg(jsonb_build_object('country', c.country_code, 'businesses', c.businesses)
          order by c.businesses desc, c.country_code), '[]'::jsonb)
        from (
          select a.country_code, count(*) as businesses
          from asked a
          where not exists (select 1 from priced p where p.country = a.country_code)
          group by a.country_code
        ) c
      )
    ),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'organization_id', d.organization_id,
        'organization_name', o.name,
        'country', d.country_code,
        'is_home', d.is_home,
        'requested_at', d.requested_at,
        'requested_by', p.full_name,
        'account_sid', account.subaccount_sid,
        'price', private.communication_sms_country_price(d.country_code),
        'history', private.communication_sms_destination_history(d.id)
      ) order by d.requested_at, d.id)
      from public.communication_sms_destinations d
      join public.organizations o on o.id = d.organization_id
      left join public.profiles p on p.id = d.requested_by
      left join lateral (
        select a.subaccount_sid
        from public.communication_twilio_accounts a
        where a.organization_id = d.organization_id and a.lifecycle_state <> 'closed'
        order by a.created_at desc
        limit 1
      ) account on true
      where d.status = 'setting_up'
    ), '[]'::jsonb)
  );
$$;

comment on function public.communication_sms_destination_queue() is
  'Stage 10 Part 5b: the Control Room Texting setup queue (countries waiting to be switched on in Twilio) and its page numbers. Server only.';

revoke all on function public.communication_sms_destination_queue() from public, anon, authenticated;
grant execute on function public.communication_sms_destination_queue() to service_role;

-- 5. A business's countries ------------------------------------------------------------------------------------

-- Every country one business asked for, home first, then by when it was asked, with who switched it on or
-- off and its price, and the business's Twilio account for "See it in Twilio".
create or replace function public.communication_sms_organization_destinations(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'account_sid', (
      select a.subaccount_sid
      from public.communication_twilio_accounts a
      where a.organization_id = p_organization_id and a.lifecycle_state <> 'closed'
      order by a.created_at desc
      limit 1
    ),
    'destinations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'country', d.country_code,
        'status', d.status,
        'is_home', d.is_home,
        'requested_at', d.requested_at,
        'ready_at', d.ready_at,
        'off_at', d.off_at,
        'off_reason', d.off_reason,
        'price', private.communication_sms_country_price(d.country_code),
        'history', private.communication_sms_destination_history(d.id)
      ) order by d.is_home desc, d.requested_at, d.id)
      from public.communication_sms_destinations d
      where d.organization_id = p_organization_id
    ), '[]'::jsonb)
  );
$$;

comment on function public.communication_sms_organization_destinations(uuid) is
  'Stage 10 Part 5b: the countries one business asked to text, for its Control Room Texting view. Server only.';

revoke all on function public.communication_sms_organization_destinations(uuid) from public, anon, authenticated;
grant execute on function public.communication_sms_organization_destinations(uuid) to service_role;
