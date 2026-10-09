-- Jafar business management C3: the activity report (plan § 6).
--
-- What happened in a period, grouped by where each business was found (its source as it is now). Each step counts
-- businesses once each -- calls once per call and Won or Lost once per Deal -- from the business's own history, and
-- the period runs midnight to midnight in the viewer's time zone (My preferences). People reached are kept apart
-- from messages sent, and replies count only contact they started or answered, never a delivery. A source is
-- where a business came from; nothing here claims a message caused a sale.
--
-- Read only. Platform owner's server only.

-- The report reads one period's worth of these kinds and nothing else, newest history included.
create index platform_business_history_report_idx
  on public.platform_business_history (occurred_at, kind)
  where kind in ('contact', 'contact_approved', 'call_booked', 'call_held', 'pricing_shared', 'deal_won', 'deal_lost');

-- from_date null: since the beginning. Both dates are days in the viewer's time zone; to_date is included.
create or replace function public.owner_activity_report(
  from_date date,
  to_date date,
  viewer_member_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with bounds as (
    select
      p.zone,
      case when from_date is null then '-infinity'::timestamptz
        else from_date::timestamp at time zone p.zone end as from_at,
      (to_date + 1)::timestamp at time zone p.zone as to_at
    from private.calendar_preferences_for(viewer_member_id) p
  ),
  added as (
    select r.source, count(*)::int as researched
    from bounds b
    join public.platform_business_relationships r on r.created_at >= b.from_at and r.created_at < b.to_at
    group by r.source
  ),
  happened as (
    select
      r.source,
      count(distinct h.relationship_id) filter (where h.kind = 'contact_approved')::int as approved,
      count(distinct h.relationship_id)
        filter (where h.kind = 'contact' and h.contact_direction = 'outbound')::int as reached,
      count(*) filter (where h.kind = 'contact' and h.contact_direction = 'outbound')::int as messages_sent,
      count(distinct h.relationship_id)
        filter (where h.kind = 'contact' and h.contact_direction = 'inbound')::int as replied,
      count(*) filter (where h.kind = 'contact' and h.contact_direction = 'inbound')::int as messages_received,
      count(distinct h.details ->> 'entry_id') filter (where h.kind = 'call_booked')::int as calls_booked,
      count(distinct h.details ->> 'entry_id') filter (where h.kind = 'call_held')::int as calls_held,
      count(distinct h.relationship_id) filter (where h.kind = 'pricing_shared')::int as pricing_shared,
      count(distinct h.deal_id) filter (where h.kind = 'deal_won')::int as won,
      coalesce(sum((h.details ->> 'amount_usd_cents')::bigint) filter (where h.kind = 'deal_won'), 0)::bigint
        as won_usd_cents,
      count(distinct h.deal_id) filter (where h.kind = 'deal_lost')::int as lost
    from bounds b
    join public.platform_business_history h
      on h.occurred_at >= b.from_at and h.occurred_at < b.to_at
      and h.kind in ('contact', 'contact_approved', 'call_booked', 'call_held', 'pricing_shared', 'deal_won', 'deal_lost')
    join public.platform_business_relationships r on r.id = h.relationship_id
    group by r.source
  )
  select jsonb_build_object(
    'time_zone', (select zone from bounds),
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source', coalesce(a.source, e.source),
        'researched', coalesce(a.researched, 0),
        'approved', coalesce(e.approved, 0),
        'reached', coalesce(e.reached, 0),
        'messages_sent', coalesce(e.messages_sent, 0),
        'replied', coalesce(e.replied, 0),
        'messages_received', coalesce(e.messages_received, 0),
        'calls_booked', coalesce(e.calls_booked, 0),
        'calls_held', coalesce(e.calls_held, 0),
        'pricing_shared', coalesce(e.pricing_shared, 0),
        'won', coalesce(e.won, 0),
        'won_usd_cents', coalesce(e.won_usd_cents, 0),
        'lost', coalesce(e.lost, 0)
      ) order by coalesce(a.source, e.source))
      from added a
      full join happened e on e.source = a.source
    ), '[]'::jsonb)
  );
$function$;

revoke all on function public.owner_activity_report(date, date, uuid) from public, anon, authenticated;
