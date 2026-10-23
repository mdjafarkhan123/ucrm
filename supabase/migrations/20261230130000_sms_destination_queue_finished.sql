-- Stage 10 Part 5b: the Texting setup queue also lists tasks finished in the last day and who finished them.
-- A person whose open task vanishes because a teammate finished it first sees "Sam already did this" instead
-- of the panel moving on to another task under their hand.

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
    -- Tasks someone finished in the last day, so a panel whose task vanished can say who did it.
    'recently_finished', coalesce((
      select jsonb_agg(jsonb_build_object('id', f.destination_id, 'kind', f.event_kind, 'at', f.occurred_at, 'who', f.actor_name))
      from (
        select distinct on (e.destination_id) e.destination_id, e.event_kind, e.occurred_at, e.actor_name
        from public.communication_sms_destination_events e
        where e.event_kind in ('switched_on', 'closed') and e.occurred_at > now() - interval '1 day'
        order by e.destination_id, e.occurred_at desc
      ) f
    ), '[]'::jsonb),
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
  'Stage 10 Part 5b: the Control Room Texting setup queue (countries waiting to be switched on in Twilio), tasks finished in the last day, and the page numbers. Server only.';
