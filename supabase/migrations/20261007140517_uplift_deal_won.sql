-- Jafar business management B5: Won and handover.
--
-- 1. A Deal becomes Won by itself when payment is confirmed on an Application linked to its business, or when an
--    already-paid Application is linked (Jafar, 2026-10-07). Nobody marks a Deal Won by hand. The Deal records
--    the Application that paid for it, so one payment wins one Deal and a later Deal waits for its own.
-- 2. Won is closed like Lost: it leaves the board for a Won list, cannot be moved, lost or removed, and lets the
--    business start a new Deal later. A payment reversed afterwards leaves the Deal Won; the reads say so.
-- 3. The business's setup is looked after by Jafar unless he picks a teammate (setup_owner_member_id).
-- 4. Reads: the Won list on the board, Won in the summary and the business's Deals, the Client box, and the
--    Leads list's "Clients" filter.
-- 5. owner_client_onboarding_list can return one client, for the Client box's onboarding stage.
--
-- Nothing here sends a message. Platform owner's server only.

-- 1. Won on the Deal --------------------------------------------------------------------------------------------

alter table public.platform_deals
  add column won_at timestamptz,
  add column won_from_stage text,
  -- Who confirmed the payment that won it.
  add column won_by_email text,
  add column won_application_id uuid references public.platform_onboarding_applications (id) on delete set null;

alter table public.platform_deals drop constraint platform_deals_stage_check;
alter table public.platform_deals add constraint platform_deals_stage_check check (
  stage in ('interested', 'call_booked', 'needs_understood', 'pricing_shared', 'awaiting_decision', 'later', 'lost', 'won')
);
alter table public.platform_deals add constraint platform_deals_won_shape check (
  (stage = 'won') = (won_at is not null)
  and (stage = 'won') = (won_from_stage is not null)
  and (stage = 'won') = (won_by_email is not null)
  and (stage = 'won' or won_application_id is null)
);
alter table public.platform_deals add constraint platform_deals_won_from_check check (
  won_from_stage is null
  or won_from_stage in ('interested', 'call_booked', 'needs_understood', 'pricing_shared', 'awaiting_decision', 'later')
);

-- One payment wins one Deal.
create unique index platform_deals_won_application_idx
  on public.platform_deals (won_application_id) where won_application_id is not null;

-- Open now means neither Lost nor Won.
drop index public.platform_deals_one_open_idx;
create unique index platform_deals_one_open_idx
  on public.platform_deals (relationship_id) where stage not in ('lost', 'won');
drop index public.platform_deals_stage_idx;
create index platform_deals_stage_idx
  on public.platform_deals (stage) where stage not in ('lost', 'won');
create index platform_deals_won_idx
  on public.platform_deals (won_at desc, id desc) where stage = 'won';

comment on column public.platform_deals.won_application_id is
  'The Application whose confirmed payment made this Deal Won (B5). One payment wins one Deal.';

-- 2. History and the setup owner ------------------------------------------------------------------------------

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed',
    'contact_approved', 'approval_withdrawn', 'sent_back', 'do_not_contact_set', 'do_not_contact_cleared',
    'deal_started', 'deal_stage_changed', 'pricing_shared', 'deal_lost', 'deal_reopened', 'deal_terms_changed',
    'deal_removed', 'deal_won', 'setup_owner_changed'
  )
);

-- Null is Jafar. A teammate removed later falls back to Jafar when read.
alter table public.platform_business_relationships
  add column setup_owner_member_id uuid references public.platform_team_members (id) on delete set null;
create index platform_business_relationships_setup_owner_idx
  on public.platform_business_relationships (setup_owner_member_id) where setup_owner_member_id is not null;

-- 3. Won by payment ---------------------------------------------------------------------------------------------

-- Makes the business's open Deal Won when this Application is linked to it and has a confirmed payment that has
-- not been reversed, and has not already won a Deal. The sales next step ends with it. Returns the Deal's id, or
-- null when nothing changed.
create or replace function private.deal_win_if_paid(target_application_id uuid)
returns uuid
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  application public.platform_onboarding_applications%rowtype;
  payment public.platform_onboarding_application_payment_confirmations%rowtype;
  deal public.platform_deals%rowtype;
  rel public.platform_business_relationships%rowtype;
begin
  select * into application from public.platform_onboarding_applications where id = target_application_id;
  if not found or application.business_relationship_id is null then
    return null;
  end if;
  payment := private.onboarding_application_current_payment(target_application_id);
  if payment.id is null then
    return null;
  end if;
  if exists (select 1 from public.platform_deals where won_application_id = target_application_id) then
    return null;
  end if;

  select * into deal from public.platform_deals
  where relationship_id = application.business_relationship_id and stage not in ('lost', 'won')
  for update;
  if not found then
    return null;
  end if;

  update public.platform_deals
  set stage = 'won', stage_entered_at = now(), won_at = now(), won_from_stage = deal.stage,
    won_by_email = lower(btrim(payment.actor_owner_email)), won_application_id = target_application_id
  where id = deal.id;
  -- clock_timestamp: Won reads after the payment or link that caused it.
  insert into public.platform_business_history (relationship_id, deal_id, kind, application_id, details, actor_email, occurred_at)
  values (deal.relationship_id, deal.id, 'deal_won', target_application_id,
    jsonb_strip_nulls(jsonb_build_object(
      'from', deal.stage,
      'amount_usd_cents', payment.amount_usd_cents,
      'package_name', application.package_snapshot ->> 'display_name'
    )),
    lower(btrim(payment.actor_owner_email)), clock_timestamp());

  select * into rel from public.platform_business_relationships where id = deal.relationship_id for update;
  if rel.next_action is not null then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email, occurred_at)
    values (deal.relationship_id, 'next_action_cleared',
      jsonb_build_object('next_action', rel.next_action, 'due_on', rel.next_action_due_on), lower(btrim(payment.actor_owner_email)),
      clock_timestamp());
    update public.platform_business_relationships
    set next_action = null, next_action_due_on = null, next_action_kind = null
    where id = deal.relationship_id;
  end if;
  return deal.id;
end;
$function$;

revoke all on function private.deal_win_if_paid(uuid) from public, anon, authenticated;

-- Confirming a payment (confirm_onboarding_application_payment, or any later path) wins the Deal in the same
-- transaction.
create or replace function private.payment_confirmed_wins_deal()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  perform private.deal_win_if_paid(new.application_id);
  return null;
end;
$function$;

revoke all on function private.payment_confirmed_wins_deal() from public, anon, authenticated;

create trigger platform_payment_confirmed_wins_deal
  after insert on public.platform_onboarding_application_payment_confirmations
  for each row execute function private.payment_confirmed_wins_deal();

-- An Application that paid for a Won Deal stays with that business: unlinking or moving it is refused.
create or replace function private.application_keeps_won_link()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if exists (
    select 1 from public.platform_deals
    where won_application_id = new.id and relationship_id = old.business_relationship_id
  ) then
    raise exception 'This Application paid for a Won Deal, so it stays linked to that business.' using errcode = '22023';
  end if;
  return new;
end;
$function$;

revoke all on function private.application_keeps_won_link() from public, anon, authenticated;

create trigger platform_application_keeps_won_link
  before update of business_relationship_id on public.platform_onboarding_applications
  for each row
  when (old.business_relationship_id is not null and old.business_relationship_id is distinct from new.business_relationship_id)
  execute function private.application_keeps_won_link();

-- Linking an already-paid Application wins the Deal. Deferred to the end of the transaction, so the link's own
-- history line comes first and Won reads after it.
create or replace function private.application_link_wins_deal()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  perform private.deal_win_if_paid(new.id);
  return null;
end;
$function$;

revoke all on function private.application_link_wins_deal() from public, anon, authenticated;

create constraint trigger platform_application_link_wins_deal
  after update of business_relationship_id on public.platform_onboarding_applications
  deferrable initially deferred
  for each row
  when (new.business_relationship_id is not null and old.business_relationship_id is distinct from new.business_relationship_id)
  execute function private.application_link_wins_deal();

-- 4. Won is closed ----------------------------------------------------------------------------------------------

create or replace function private.deal_lock_open(target_deal_id uuid)
returns public.platform_deals
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  found_row public.platform_deals%rowtype;
begin
  select * into found_row from public.platform_deals where id = target_deal_id for update;
  if found and found_row.stage = 'lost' then
    raise exception 'This Deal is Lost. Reopen it first.' using errcode = '22023';
  end if;
  if found and found_row.stage = 'won' then
    raise exception 'This Deal is Won: the business has paid.' using errcode = '22023';
  end if;
  return found_row;
end;
$function$;

create or replace function public.owner_deal_start(
  actor_email text,
  target_relationship_id uuid,
  target_stage text,
  target_next_action text,
  target_due_on date
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  rel public.platform_business_relationships%rowtype;
  new_id uuid;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if target_stage not in ('interested', 'call_booked') then
    raise exception 'A Deal starts at Interested or Call booked.' using errcode = '22023';
  end if;

  select * into rel from public.platform_business_relationships where id = target_relationship_id for update;
  if not found then
    return null;
  end if;
  if rel.do_not_contact_at is not null then
    raise exception 'This business asked not to be contacted, so it cannot have a Deal.' using errcode = '22023';
  end if;
  if exists (select 1 from public.platform_deals where relationship_id = rel.id and stage not in ('lost', 'won')) then
    raise exception 'This business already has an open Deal.' using errcode = '22023';
  end if;

  insert into public.platform_deals (relationship_id, stage, created_by_email)
  values (rel.id, target_stage, actor)
  returning id into new_id;
  insert into public.platform_business_history (relationship_id, deal_id, kind, details, actor_email)
  values (rel.id, new_id, 'deal_started', jsonb_build_object('stage', target_stage), actor);

  perform public.owner_lead_change(actor, rel.id, null, 'set', target_next_action, target_due_on);
  perform private.deal_require_next_action(rel.id);
  return new_id;
end;
$function$;

create or replace function public.owner_deal_reopen(
  actor_email text,
  target_deal_id uuid,
  target_next_action text,
  target_due_on date
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  deal public.platform_deals%rowtype;
  rel public.platform_business_relationships%rowtype;
  reopened_stage text;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;

  select * into deal from public.platform_deals where id = target_deal_id for update;
  if not found then
    return false;
  end if;
  if deal.stage = 'won' then
    raise exception 'This Deal is Won: the business has paid.' using errcode = '22023';
  end if;
  if deal.stage <> 'lost' then
    raise exception 'This Deal is already open.' using errcode = '22023';
  end if;
  select * into rel from public.platform_business_relationships where id = deal.relationship_id for update;
  if rel.do_not_contact_at is not null then
    raise exception 'This business asked not to be contacted, so its Deal cannot be reopened.' using errcode = '22023';
  end if;
  if exists (select 1 from public.platform_deals where relationship_id = rel.id and stage not in ('lost', 'won')) then
    raise exception 'This business already has an open Deal.' using errcode = '22023';
  end if;

  reopened_stage := deal.lost_from_stage;
  update public.platform_deals
  set stage = reopened_stage, stage_entered_at = now(), lost_reason = null, lost_note = null,
    lost_from_stage = null, lost_at = null, lost_by_email = null
  where id = deal.id;
  insert into public.platform_business_history (relationship_id, deal_id, kind, details, actor_email)
  values (deal.relationship_id, deal.id, 'deal_reopened', jsonb_build_object('to', reopened_stage), actor);

  perform public.owner_lead_change(actor, deal.relationship_id, null, 'set', target_next_action, target_due_on);
  perform private.deal_require_next_action(deal.relationship_id);
  return true;
end;
$function$;

create or replace function public.owner_deal_remove(actor_email text, target_deal_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  deal public.platform_deals%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  select * into deal from public.platform_deals where id = target_deal_id for update;
  if not found then
    return false;
  end if;
  if deal.stage = 'won' then
    raise exception 'A Won Deal is a paid sale, so it stays in the history.' using errcode = '22023';
  end if;
  delete from public.platform_deals where id = deal.id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (deal.relationship_id, 'deal_removed', jsonb_build_object('stage', deal.stage), actor);
  return true;
end;
$function$;

create or replace function private.platform_business_do_not_contact_closes_deal()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  deal public.platform_deals%rowtype;
begin
  select * into deal from public.platform_deals
  where relationship_id = new.id and stage not in ('lost', 'won')
  for update;
  if found then
    perform private.deal_close_lost(deal, 'asked_not_to_contact', new.do_not_contact_reason, new.do_not_contact_by_email);
  end if;
  return null;
end;
$function$;

-- 5. Setup owner ------------------------------------------------------------------------------------------------

-- Jafar (null) or an active teammate looks after the business's setup. The server checks the teammate may open
-- Onboarding before calling. Returns false when the business no longer exists.
create or replace function public.owner_business_set_setup_owner(
  actor_email text,
  target_relationship_id uuid,
  target_member_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  rel public.platform_business_relationships%rowtype;
  member public.platform_team_members%rowtype;
  previous public.platform_team_members%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  select * into rel from public.platform_business_relationships where id = target_relationship_id for update;
  if not found then
    return false;
  end if;
  if not exists (select 1 from public.platform_deals where relationship_id = rel.id and stage = 'won') then
    raise exception 'Setup is looked after once the business has paid.' using errcode = '22023';
  end if;
  if target_member_id is not null then
    select * into member from public.platform_team_members
    where id = target_member_id and status = 'active' and removed_at is null;
    if not found then
      raise exception 'That teammate is no longer on the team.' using errcode = '22023';
    end if;
  end if;
  if rel.setup_owner_member_id is not distinct from target_member_id then
    return true;
  end if;

  select * into previous from public.platform_team_members where id = rel.setup_owner_member_id;
  update public.platform_business_relationships set setup_owner_member_id = target_member_id where id = rel.id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (rel.id, 'setup_owner_changed', jsonb_build_object(
    'from', case when previous.id is null then null else coalesce(previous.full_name, previous.email) end,
    'to', case when member.id is null then null else coalesce(member.full_name, member.email) end
  ), actor);
  return true;
end;
$function$;

revoke all on function public.owner_business_set_setup_owner(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.owner_business_set_setup_owner(text, uuid, uuid) to service_role;

-- 6. Reads ------------------------------------------------------------------------------------------------------

-- One board column, page_size cards at a time. Open stages: no next step first, then the soonest due; cursor
-- (due key, id). Lost and Won: most recently closed first; cursor (closed_at, id), passed as cursor_lost_at.
create or replace function public.owner_deal_board(
  target_stage text,
  cursor_due_on date default null,
  cursor_lost_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 30
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with params as (
    select least(greatest(coalesce(page_size, 30), 1), 100) as size, target_stage in ('lost', 'won') as closed
  ),
  page as (
    select d.*, r.business_name, r.country_code, r.trade, r.contact_name, r.next_action, r.next_action_due_on,
      coalesce(r.next_action_due_on, date '0001-01-01') as due_key,
      coalesce(d.lost_at, d.won_at) as closed_at
    from public.platform_deals d
    join public.platform_business_relationships r on r.id = d.relationship_id
    cross join params p
    where d.stage = target_stage
      and case
        when target_stage = 'lost' then cursor_id is null or (d.lost_at, d.id) < (cursor_lost_at, cursor_id)
        when target_stage = 'won' then cursor_id is null or (d.won_at, d.id) < (cursor_lost_at, cursor_id)
        else cursor_id is null or (coalesce(r.next_action_due_on, date '0001-01-01'), d.id) > (cursor_due_on, cursor_id)
      end
    order by
      case when target_stage = 'lost' then d.lost_at end desc,
      case when target_stage = 'won' then d.won_at end desc,
      case when p.closed then d.id end desc,
      case when not p.closed then coalesce(r.next_action_due_on, date '0001-01-01') end asc,
      case when not p.closed then d.id end asc
    limit (select size from params)
  ),
  numbered as (
    select page.*, row_number() over (
      order by
        case when (select closed from params) then closed_at end desc,
        case when (select closed from params) then id end desc,
        case when not (select closed from params) then due_key end asc,
        case when not (select closed from params) then id end asc
    ) as row_index
    from page
  ),
  latest_share as (
    select distinct on (s.deal_id) s.deal_id, s.shared_at
    from public.platform_deal_price_shares s
    where s.deal_id in (select id from page)
    order by s.deal_id, s.shared_at desc
  ),
  shared_names as (
    select s.deal_id, jsonb_agg(s.package_name order by s.position) as names
    from public.platform_deal_price_shares s
    join latest_share l on l.deal_id = s.deal_id and l.shared_at = s.shared_at
    group by s.deal_id
  )
  select jsonb_build_object(
    'deals', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', n.id,
            'relationship_id', n.relationship_id,
            'business_name', n.business_name,
            'country_code', n.country_code,
            'trade', n.trade,
            'contact_name', n.contact_name,
            'stage', n.stage,
            'stage_entered_at', n.stage_entered_at,
            'value_monthly_usd_cents', n.value_monthly_usd_cents,
            'shared_packages', coalesce(sn.names, '[]'::jsonb),
            'has_agreed_terms', n.agreed_terms is not null,
            'next_action', n.next_action,
            'next_action_due_on', n.next_action_due_on,
            'lost_reason', n.lost_reason,
            'lost_at', n.lost_at,
            'won_at', n.won_at,
            'payment_reversed', coalesce(a.payment_reversed_at is not null, false),
            'won_package_name', a.package_snapshot ->> 'display_name'
          )
          order by n.row_index
        )
        from numbered n
        left join shared_names sn on sn.deal_id = n.id
        left join public.platform_onboarding_applications a on a.id = n.won_application_id
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params) then (
        select jsonb_build_object('due_on', n.due_key, 'lost_at', n.closed_at, 'id', n.id)
        from numbered n order by n.row_index desc limit 1
      )
      else null
    end
  );
$function$;

-- Every open column's count and monthly total, and how many are Lost and Won, in one read.
create or replace function public.owner_deal_board_summary()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select jsonb_build_object(
    'columns', coalesce(
      (
        select jsonb_object_agg(stage, jsonb_build_object('count', n, 'value_monthly_usd_cents', total))
        from (
          select stage, count(*) as n, coalesce(sum(value_monthly_usd_cents), 0) as total
          from public.platform_deals where stage not in ('lost', 'won') group by stage
        ) c
      ),
      '{}'::jsonb
    ),
    'lost', (select count(*) from public.platform_deals where stage = 'lost'),
    'won', (select count(*) from public.platform_deals where stage = 'won')
  );
$function$;

-- One business's Deals, newest first, with what was shared; a Won one says which payment won it.
create or replace function public.owner_business_deals(target_relationship_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'stage', d.stage,
        'stage_entered_at', d.stage_entered_at,
        'value_monthly_usd_cents', d.value_monthly_usd_cents,
        'agreed_terms', d.agreed_terms,
        'agreed_terms_by_email', d.agreed_terms_by_email,
        'agreed_terms_at', d.agreed_terms_at,
        'lost_reason', d.lost_reason,
        'lost_note', d.lost_note,
        'lost_from_stage', d.lost_from_stage,
        'lost_at', d.lost_at,
        'won_at', d.won_at,
        'won_by_email', d.won_by_email,
        'won_application_id', d.won_application_id,
        'created_at', d.created_at,
        'shares', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'shared_at', s.shared_at,
                'package_slug', s.package_slug,
                'package_name', s.package_name,
                'monthly_price_usd_cents', s.monthly_price_usd_cents,
                'yearly_price_usd_cents', s.yearly_price_usd_cents,
                'offers', s.offers,
                'link', s.link,
                'actor_email', s.actor_email
              )
              order by s.shared_at desc, s.position
            )
            from public.platform_deal_price_shares s
            where s.deal_id = d.id
          ),
          '[]'::jsonb
        )
      )
      order by d.created_at desc
    ),
    '[]'::jsonb
  )
  from public.platform_deals d
  where d.relationship_id = target_relationship_id;
$function$;

-- The Client box: the newest Won Deal's paid Application, its payments, the account made from it, and who looks
-- after setup. Null while the business has no Won Deal.
create or replace function public.owner_business_client(target_relationship_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with won as (
    select d.* from public.platform_deals d
    where d.relationship_id = target_relationship_id and d.stage = 'won'
    order by d.won_at desc
    limit 1
  )
  select jsonb_build_object(
    'deal_id', w.id,
    'won_at', w.won_at,
    'won_by_email', w.won_by_email,
    'application', case when a.id is null then null else jsonb_build_object(
      'id', a.id,
      'stage', a.stage,
      'package_name', a.package_snapshot ->> 'display_name',
      'billing_interval', a.billing_interval,
      'monthly_price_usd_cents', (a.package_snapshot ->> 'monthly_price_usd_cents')::integer,
      'yearly_price_usd_cents', (a.package_snapshot ->> 'yearly_price_usd_cents')::integer,
      'payment_reversed_at', a.payment_reversed_at
    ) end,
    'payments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', c.id,
            'amount_usd_cents', c.amount_usd_cents,
            'received_on', c.received_on,
            'method', c.method,
            'reversed_at', r.reversed_at
          )
          order by c.confirmed_at desc
        )
        from public.platform_onboarding_application_payment_confirmations c
        left join public.platform_onboarding_application_payment_reversals r on r.confirmation_id = c.id
        where c.application_id = a.id
      ),
      '[]'::jsonb
    ),
    'account', case when p.application_id is null then null else jsonb_build_object(
      'status', p.status,
      'organization_id', o.id,
      'organization_name', o.name,
      'lifecycle_status', o.lifecycle_status
    ) end,
    'setup_owner', case when m.id is null then null else jsonb_build_object(
      'id', m.id,
      'name', coalesce(m.full_name, m.email),
      'avatar_url', m.avatar_url
    ) end
  )
  from won w
  left join public.platform_onboarding_applications a on a.id = w.won_application_id
  left join public.platform_onboarding_application_provisions p on p.application_id = a.id
  left join public.organizations o on o.id = p.organization_id and p.status = 'succeeded'
  left join public.platform_business_relationships rel on rel.id = w.relationship_id
  left join public.platform_team_members m
    on m.id = rel.setup_owner_member_id and m.status = 'active' and m.removed_at is null;
$function$;

revoke all on function public.owner_business_client(uuid) from public, anon, authenticated;
grant execute on function public.owner_business_client(uuid) to service_role;

-- 7. The Leads list ---------------------------------------------------------------------------------------------

-- deal_filter: 'without' (default) hides businesses with a Deal; 'with' shows those with a Deal that are not yet
-- clients; 'clients' shows those with a Won Deal; 'any' shows all.
create or replace function public.owner_lead_list(
  search_term text default null,
  status_filter text[] default null,
  country_filter text[] default null,
  source_filter text[] default null,
  sort_order text default 'newest',
  cursor_created_at timestamptz default null,
  cursor_due_on date default null,
  cursor_id uuid default null,
  page_size integer default 50,
  deal_filter text default 'without'
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with params as (
    select
      nullif(btrim(coalesce(search_term, '')), '') as term,
      least(greatest(coalesce(page_size, 50), 1), 100) as size,
      coalesce(sort_order, 'newest') = 'next_action' as by_due
  ),
  -- B4: a business with a Deal lives on the Deals board; B5: one with a Won Deal is a client.
  scoped as (
    select r.*
    from public.platform_business_relationships r
    where case coalesce(deal_filter, 'without')
      when 'any' then true
      when 'with' then exists (select 1 from public.platform_deals d where d.relationship_id = r.id)
        and not exists (select 1 from public.platform_deals d where d.relationship_id = r.id and d.stage = 'won')
      when 'clients' then exists (
        select 1 from public.platform_deals d where d.relationship_id = r.id and d.stage = 'won'
      )
      else not exists (select 1 from public.platform_deals d where d.relationship_id = r.id)
    end
  ),
  -- Contact details matching the search, read once (not once per Lead).
  method_hits as (
    select m.relationship_id
    from public.platform_business_contact_methods m, params p
    where p.term is not null and m.removed_at is null and m.value ilike '%' || p.term || '%'
  ),
  matching as (
    select r.*, coalesce(r.next_action_due_on, date '0001-01-01') as due_key
    from scoped r, params p
    where p.term is null
      or r.business_name ilike '%' || p.term || '%'
      or r.website_host ilike '%' || p.term || '%'
      or r.contact_name ilike '%' || p.term || '%'
      or r.id in (select relationship_id from method_hits)
  ),
  filtered as (
    select m.*
    from matching m
    where (status_filter is null or cardinality(status_filter) = 0 or m.lead_status = any(status_filter))
      and (country_filter is null or cardinality(country_filter) = 0 or m.country_code = any(country_filter))
      and (source_filter is null or cardinality(source_filter) = 0 or m.source = any(source_filter))
  ),
  page as (
    select f.*
    from filtered f, params p
    where
      case
        when p.by_due then cursor_id is null or (f.due_key, f.id) > (cursor_due_on, cursor_id)
        else cursor_id is null or (f.created_at, f.id) < (cursor_created_at, cursor_id)
      end
    order by
      case when p.by_due then f.due_key end asc,
      case when p.by_due then f.id end asc,
      case when not p.by_due then f.created_at end desc,
      case when not p.by_due then f.id end desc
    limit (select size from params)
  ),
  numbered as (
    select page.*, row_number() over (
      order by
        case when (select by_due from params) then due_key end asc,
        case when (select by_due from params) then id end asc,
        case when not (select by_due from params) then created_at end desc,
        case when not (select by_due from params) then id end desc
    ) as row_index
    from page
  ),
  page_last as (
    select * from numbered order by row_index desc limit 1
  ),
  contact_methods as (
    select
      m.relationship_id,
      jsonb_agg(jsonb_build_object('kind', m.kind, 'value', m.value) order by m.position, m.created_at) as methods
    from public.platform_business_contact_methods m
    where m.relationship_id in (select id from page) and m.removed_at is null
    group by m.relationship_id
  ),
  status_counts as (
    select lead_status, count(*) as n from scoped group by lead_status
  ),
  country_counts as (
    select country_code, count(*) as n from scoped group by country_code
  ),
  source_counts as (
    select source, count(*) as n from scoped group by source
  ),
  client_ids as (
    select distinct d.relationship_id from public.platform_deals d where d.stage = 'won'
  )
  select jsonb_build_object(
    'leads', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', n.id,
            'business_name', n.business_name,
            'country_code', n.country_code,
            'trade', n.trade,
            'source', n.source,
            'website_host', n.website_host,
            'contact_name', n.contact_name,
            'contact_methods', coalesce(cm.methods, '[]'::jsonb),
            'lead_status', n.lead_status,
            'next_action', n.next_action,
            'next_action_due_on', n.next_action_due_on,
            'created_at', n.created_at,
            'deal_stage', (
              select d.stage from public.platform_deals d where d.relationship_id = n.id
              order by d.created_at desc limit 1
            ),
            'is_client', n.id in (select relationship_id from client_ids)
          )
          order by n.row_index
        )
        from numbered n
        left join contact_methods cm on cm.relationship_id = n.id
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params)
        then (select jsonb_build_object('created_at', pl.created_at, 'due_on', pl.due_key, 'id', pl.id) from page_last pl)
      else null
    end,
    'totals', jsonb_build_object(
      'all', (select count(*) from scoped),
      'in_deal', (
        select count(distinct d.relationship_id) from public.platform_deals d
        where d.relationship_id not in (select relationship_id from client_ids)
      ),
      'clients', (select count(*) from client_ids),
      'matching', (select count(*) from filtered),
      'statuses', coalesce((select jsonb_object_agg(lead_status, n) from status_counts), '{}'::jsonb),
      'countries', coalesce(
        (select jsonb_agg(jsonb_build_object('code', country_code, 'count', n) order by n desc, country_code)
         from country_counts),
        '[]'::jsonb
      ),
      'sources', coalesce((select jsonb_object_agg(source, n) from source_counts), '{}'::jsonb)
    )
  );
$function$;

-- 8. One client's onboarding row ------------------------------------------------------------------------------

drop function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean);

create function public.owner_client_onboarding_list(
  setup_catalogue jsonb,
  search_term text default null,
  waiting_filter text default null,
  cursor_account_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50,
  include_delivered boolean default false,
  only_organization_id uuid default null
) returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  with catalogue as (
    select
      section.position,
      section.value ->> 'key' as section_key,
      nullif(section.value ->> 'service_key', '') as service_key,
      array(select jsonb_array_elements_text(section.value -> 'facts')) as fact_keys,
      array(select jsonb_array_elements_text(section.value -> 'required')) as required_keys
    from jsonb_array_elements(setup_catalogue) with ordinality as section(value, position)
  ),
  clients as (
    select
      organization.id,
      organization.name,
      organization.lifecycle_status,
      provision.created_at as account_created_at,
      application.payment_reversed_at,
      handover.live_at,
      handover.delivered_at,
      agreement.package_name,
      coalesce(agreement.service_keys, '{}'::text[]) as service_keys
    from public.platform_onboarding_application_provisions as provision
    join public.platform_onboarding_applications as application on application.id = provision.application_id
    join public.organizations as organization on organization.id = provision.organization_id
    left join lateral (
      select
        edition.name as package_name,
        array(
          select service ->> 'service_key'
          from jsonb_array_elements(edition.included_services) as service
          where service ->> 'service_key' is not null
        ) as service_keys
      from public.organization_package_agreements as current_agreement
      join public.package_editions as edition on edition.id = current_agreement.edition_id
      where current_agreement.organization_id = organization.id
        and current_agreement.cancelled_at is null
        and current_agreement.effective_from <= now()
      order by current_agreement.effective_from desc, current_agreement.created_at desc
      limit 1
    ) as agreement on true
    left join public.organization_setup_handover as handover on handover.organization_id = organization.id
    where provision.status = 'succeeded'
      -- E6: a delivered client leaves the list unless Jafar asks for them, before any of the work below.
      and (include_delivered or handover.delivered_at is null)
      -- B5: one client's row for the business page, before any of the work below.
      and (only_organization_id is null or organization.id = only_organization_id)
  ),
  measured as (
    select
      client.*,
      setup.welcome_seen_at,
      own.sections_total,
      cardinality(shown.fact_keys) as facts_total,
      answers.answered,
      answers.help_count,
      answers.last_answer_at,
      sections.done_count,
      sections.next_section_key,
      sections.last_section_at,
      support.unread_count,
      sent.submission_number as sent_number,
      sent.submitted_at as sent_at,
      returns.returned_count,
      returns.returned_at,
      ready.submission_number as ready_number,
      ready.ready_at,
      ready.target_from,
      ready.target_to,
      waits.open_count as waits_open,
      waits.action_count as waits_action,
      waits.changed_at as waits_changed_at,
      preview.version as preview_version,
      preview.released_at as preview_released_at,
      preview.notes_sent_at as preview_sent_at,
      preview.unsorted_count as preview_unsorted,
      approval.status as approval_status,
      approval.requested_at as approval_requested_at,
      approval.not_yet_at as approval_not_yet_at,
      approval.approved_at as approval_approved_at,
      approval.version as approval_version,
      training.meeting_at as training_meeting_at,
      training.skipped_at as training_skipped_at,
      training.details_at as training_details_at
    from clients as client
    left join public.organization_setup as setup on setup.organization_id = client.id
    cross join lateral (
      -- The stages this client is asked: everyone's, and those of a service their package includes.
      select
        (select count(*)::integer from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys))
          as sections_total,
        array(
          select unnest(catalogue.fact_keys) from catalogue
          where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
        ) as fact_keys
    ) as own
    -- Questions an earlier answer or the package hides are neither counted nor required.
    cross join lateral (
      select public.setup_hidden_fact_keys(setup_catalogue, own.fact_keys, client.id, client.service_keys)
        as fact_keys
    ) as hidden
    cross join lateral (
      select array(
        select fact.fact_key from unnest(own.fact_keys) as fact(fact_key)
        where not (fact.fact_key = any (hidden.fact_keys))
      ) as fact_keys
    ) as shown
    cross join lateral (
      select
        count(*)::integer as answered,
        (count(*) filter (where answer.availability = 'need_help'))::integer as help_count,
        max(answer.updated_at) as last_answer_at
      from public.organization_setup_answers as answer
      where answer.organization_id = client.id
        and answer.fact_key = any (shown.fact_keys)
    ) as answers
    cross join lateral (
      select
        (count(*) filter (where status.done))::integer as done_count,
        (array_agg(status.section_key order by status.position) filter (where not status.done))[1]
          as next_section_key,
        max(status.completed_at) as last_section_at
      from (
        select
          catalogue.position,
          catalogue.section_key,
          marked.completed_at,
          marked.completed_at is not null and not exists (
            select 1
            from unnest(catalogue.required_keys) as required(fact_key)
            where not (required.fact_key = any (hidden.fact_keys))
              and not exists (
              select 1
              from public.organization_setup_answers as answer
              where answer.organization_id = client.id
                and answer.fact_key = required.fact_key
            )
          ) as done
        from catalogue
        left join public.organization_setup_sections as marked
          on marked.organization_id = client.id
         and marked.section_key = catalogue.section_key
        where catalogue.service_key is null or catalogue.service_key = any (client.service_keys)
      ) as status
    ) as sections
    cross join lateral (
      select count(*)::integer as unread_count
      from public.support_threads as thread
      where thread.organization_id = client.id
        and thread.last_message_sender_kind = 'member'
        and thread.last_message_at > coalesce(thread.uplift_last_read_at, '-infinity'::timestamptz)
    ) as support
    -- The newest Send to Uplift, if any; the (organization, number) key makes this one index probe.
    left join lateral (
      select submission.submission_number, submission.submitted_at
      from public.organization_setup_submissions as submission
      where submission.organization_id = client.id
      order by submission.submission_number desc
      limit 1
    ) as sent on true
    -- Sections Uplift sent back on that send; a later send hands them back to Uplift. Keyed by organization.
    cross join lateral (
      select count(*)::integer as returned_count, max(review.reviewed_at) as returned_at
      from public.organization_setup_section_reviews as review
      where review.organization_id = client.id
        and review.decision = 'returned'
        and review.submission_number = sent.submission_number
    ) as returns
    -- C4: Ready for Uplift, if recorded; one primary-key probe.
    left join public.organization_setup_ready as ready on ready.organization_id = client.id
    -- E2: outside waits still open, and those needing the client; at most four rows, keyed by organization.
    cross join lateral (
      select
        (count(*) filter (where wait.status not in ('approved', 'unavailable')))::integer as open_count,
        (count(*) filter (where wait.status = 'action_needed'))::integer as action_count,
        max(wait.updated_at) as changed_at
      from public.organization_setup_provider_waits as wait
      where wait.organization_id = client.id
    ) as waits
    -- E3: the newest released preview, its send, and its sent notes not yet sorted; at most 15 notes.
    left join lateral (
      select
        released.version,
        released.released_at,
        released.notes_sent_at,
        (
          select count(*)::integer
          from public.organization_setup_preview_notes as note
          where note.organization_id = released.organization_id
            and note.version = released.version
            and note.choice <> 'looks_right'
            and note.sorted_kind is null
        ) as unsorted_count
      from public.organization_setup_previews as released
      where released.organization_id = client.id
        and released.released_at is not null
      order by released.version desc
      limit 1
    ) as preview on true
    -- E4: the open launch approval request or the standing approval; at most one of each, keyed by organization.
    left join lateral (
      select request.status, request.requested_at, request.not_yet_at, request.approved_at, request.version
      from public.organization_setup_launch_approvals as request
      where request.organization_id = client.id
        and (request.status = 'open' or (request.status = 'approved' and request.replaced_at is null))
      order by request.requested_at desc
      limit 1
    ) as approval on true
    -- E6: the training row; one primary-key probe.
    left join lateral (
      select
        own_training.meeting_at,
        own_training.skipped_at,
        case when jsonb_array_length(own_training.attendees) > 0 then own_training.details_updated_at end as details_at
      from public.organization_setup_training as own_training
      where own_training.organization_id = client.id
    ) as training on true
  ),
  -- Whose move it is, most urgent first. A paused account or a reversed payment is nobody's onboarding move;
  -- an unread support message is Uplift's; a section sent back on the newest send, or an outside wait needing
  -- the client (E2), is the client's; a setup sent to Uplift and a "need Uplift's help" answer are Uplift's;
  -- everything else is the client's.
  decided as (
    select
      measured.*,
      case
        when measured.lifecycle_status <> 'active' or measured.payment_reversed_at is not null then 'nobody'
        when measured.delivered_at is not null then 'nobody'
        when measured.unread_count > 0 then 'uplift'
        when measured.returned_count > 0 then 'client'
        when measured.waits_action > 0 then 'client'
        -- E6: once live, training details are the client's to give; booking and handing over are Uplift's.
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null and measured.training_details_at is null then 'client'
        when measured.live_at is not null then 'uplift'
        when measured.approval_status = 'approved' then 'uplift'
        when measured.approval_status = 'open' and measured.approval_not_yet_at is not null then 'uplift'
        when measured.approval_status = 'open' then 'client'
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'client'
        when measured.help_count > 0 or measured.sent_number is not null then 'uplift'
        else 'client'
      end as waiting_on,
      case
        when measured.lifecycle_status <> 'active' then 'account_paused'
        when measured.payment_reversed_at is not null then 'payment_reversed'
        when measured.delivered_at is not null then 'delivered'
        when measured.unread_count > 0 then 'reply_to_support'
        when measured.returned_count > 0 then 'fix_returned'
        when measured.waits_action > 0 then 'provider_action'
        -- E6: live — training settled first, then the handover.
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null and measured.training_details_at is null
          then 'give_training_details'
        when measured.live_at is not null and measured.training_meeting_at is null
          and measured.training_skipped_at is null then 'book_training'
        when measured.live_at is not null then 'finish_handover'
        -- E4: an approval is Uplift's to launch; an open request is the approver's, unless they said not yet.
        when measured.approval_status = 'approved' then 'prepare_launch'
        when measured.approval_status = 'open' and measured.approval_not_yet_at is not null then 'approver_not_yet'
        when measured.approval_status = 'open' then 'approve_launch'
        -- E3: a released preview is the client's to review; their notes are Uplift's to sort, then make.
        when measured.preview_released_at is not null and measured.preview_sent_at is null then 'review_preview'
        when measured.preview_unsorted > 0 then 'sort_corrections'
        when measured.preview_sent_at is not null then 'make_corrections'
        -- Ready on the newest send: Uplift builds. A send after Ready has changes to look at first.
        when measured.ready_number = measured.sent_number then 'build_system'
        when measured.sent_number is not null then 'review_setup'
        when measured.help_count > 0 then 'help_with_answers'
        when measured.welcome_seen_at is null and measured.answered = 0 then 'start_setup'
        when measured.next_section_key is not null then 'finish_section'
        else 'send_to_uplift'
      end as next_action,
      greatest(
        measured.account_created_at,
        measured.welcome_seen_at,
        measured.last_answer_at,
        measured.last_section_at,
        measured.sent_at,
        measured.returned_at,
        measured.ready_at,
        measured.waits_changed_at,
        measured.preview_released_at,
        measured.preview_sent_at,
        measured.approval_requested_at,
        measured.approval_not_yet_at,
        measured.approval_approved_at,
        measured.live_at,
        measured.delivered_at,
        measured.training_details_at
      ) as last_activity_at
    from measured
  ),
  tagged as (
    select
      decided.*,
      -- The plan's first reminder goes out after about 24 hours of inactivity and the second at 3 days
      -- (§5); a client quiet for 3 days is the one Jafar should look at himself.
      (decided.waiting_on = 'client' and decided.last_activity_at < now() - interval '3 days') as is_quiet
    from decided
  ),
  matching as (
    select tagged.*
    from tagged
    where search_term is null
      or btrim(search_term) = ''
      or tagged.name ilike '%' || btrim(search_term) || '%'
  ),
  filtered as (
    select matching.*
    from matching
    where waiting_filter is null
      or (waiting_filter = 'quiet' and matching.is_quiet)
      or matching.waiting_on = waiting_filter
  ),
  page as (
    select filtered.*
    from filtered
    where cursor_account_created_at is null
      or (filtered.account_created_at, filtered.id) < (cursor_account_created_at, cursor_id)
    order by filtered.account_created_at desc, filtered.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  )
  select jsonb_build_object(
    'clients', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'name', page.name,
            'lifecycle_status', page.lifecycle_status,
            'package_name', page.package_name,
            'account_created_at', page.account_created_at,
            'payment_reversed', page.payment_reversed_at is not null,
            'welcome_seen', page.welcome_seen_at is not null,
            'sections_done', page.done_count,
            'sections_total', page.sections_total,
            'facts_answered', page.answered,
            'facts_total', page.facts_total,
            'help_count', page.help_count,
            'unread_support', page.unread_count,
            'next_section_key', page.next_section_key,
            'sent_number', page.sent_number,
            'sent_at', page.sent_at,
            'returned_count', page.returned_count,
            'ready_at', page.ready_at,
            'target_from', page.target_from,
            'target_to', page.target_to,
            'provider_waits_open', page.waits_open,
            'provider_waits_action', page.waits_action,
            'preview_version', page.preview_version,
            'preview_released_at', page.preview_released_at,
            'preview_sent_at', page.preview_sent_at,
            'preview_unsorted', coalesce(page.preview_unsorted, 0),
            'approval_status', page.approval_status,
            'approval_version', page.approval_version,
            'approval_requested_at', page.approval_requested_at,
            'approval_not_yet_at', page.approval_not_yet_at,
            'approved_at', page.approval_approved_at,
            'live_at', page.live_at,
            'delivered_at', page.delivered_at,
            'training_booked_at', page.training_meeting_at,
            'training_skipped', page.training_skipped_at is not null,
            'waiting_on', page.waiting_on,
            'next_action', page.next_action,
            'last_activity_at', page.last_activity_at,
            'quiet', page.is_quiet
          )
          order by page.account_created_at desc, page.id desc
        )
        from page
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= least(greatest(coalesce(page_size, 50), 1), 100) then (
        select jsonb_build_object('account_created_at', last.account_created_at, 'id', last.id)
        from page as last
        order by last.account_created_at asc, last.id asc
        limit 1
      )
    end,
    'totals', (
      select jsonb_build_object(
        'all', count(*),
        'uplift', count(*) filter (where tagged.waiting_on = 'uplift'),
        'client', count(*) filter (where tagged.waiting_on = 'client'),
        'quiet', count(*) filter (where tagged.is_quiet),
        'matching', (select count(*) from filtered),
        -- E6: delivered clients, counted whether or not they are listed.
        'delivered', (
          select count(*)
          from public.organization_setup_handover as delivered
          join public.platform_onboarding_application_provisions as provision
            on provision.organization_id = delivered.organization_id and provision.status = 'succeeded'
          where delivered.delivered_at is not null
        )
      )
      from tagged
    )
  );
$$;

comment on function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean, uuid) is
  'Jafar''s client onboarding list (client onboarding C1, E6): every paid client with package, setup progress, project state, whose move it is, the next action, last activity, and unread support; delivered clients only when asked; one client by organization for the business page (Jafar business B5). Service role only.';

revoke all on function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean, uuid)
  from public, anon, authenticated;
grant execute on function public.owner_client_onboarding_list(jsonb, text, text, timestamptz, uuid, integer, boolean, uuid)
  to service_role;
