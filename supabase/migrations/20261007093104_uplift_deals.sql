-- Jafar business management B4: Uplift's sales Deals.
--
-- 1. platform_deals: a buying conversation with one business. At most one open Deal per business; a Lost one
--    stays as history and a new one can start later. The Deal's next step is the business's one next action
--    (platform_business_relationships.next_action), so the Lead page, the board and the home page agree.
-- 2. platform_deal_price_shares: each package Jafar shared, copied from the pricing page as it stood that day,
--    so a later price change never rewrites what the business saw.
-- 3. The business history gains Deal lines; a Deal's own lines go with it if it is removed as a mistake.
-- 4. Commands: start, move, share pricing, mark Lost, reopen, agree special terms, remove. Each writes its
--    history in the same transaction. Turning on Do not contact closes an open Deal as Lost.
-- 5. Reads: the board (per stage, one page at a time), its column counts and totals, and one business's Deals.
-- 6. owner_lead_list: a business with a Deal leaves the Leads list unless asked for.
--
-- Won arrives with B5 (payment confirmation). Nothing here sends a message. Platform owner's server only.

-- 1. Deals ----------------------------------------------------------------------------------------------------

create table public.platform_deals (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references public.platform_business_relationships (id) on delete cascade,
  stage text not null,
  stage_entered_at timestamptz not null default now(),
  -- The monthly value of the main package last shared (a yearly-only package counts a twelfth). Set only by
  -- owner_deal_share_pricing; the board's column totals add it up.
  value_monthly_usd_cents integer,
  -- Anything agreed beyond the pricing page ("first month free"). Its own sensitive action.
  agreed_terms text,
  agreed_terms_by_email text,
  agreed_terms_at timestamptz,
  lost_reason text,
  lost_note text,
  lost_from_stage text,
  lost_at timestamptz,
  lost_by_email text,
  created_by_email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_deals_stage_check check (
    stage in ('interested', 'call_booked', 'needs_understood', 'pricing_shared', 'awaiting_decision', 'later', 'lost')
  ),
  constraint platform_deals_value_check check (value_monthly_usd_cents is null or value_monthly_usd_cents >= 0),
  constraint platform_deals_terms_check check (
    (agreed_terms is null) = (agreed_terms_by_email is null)
    and (agreed_terms is null) = (agreed_terms_at is null)
    and (agreed_terms is null or (agreed_terms = btrim(agreed_terms) and char_length(agreed_terms) between 1 and 1000))
  ),
  -- A Lost Deal says why, from which stage, who and when; an open one carries none of it.
  constraint platform_deals_lost_shape check (
    (stage = 'lost') = (lost_reason is not null)
    and (stage = 'lost') = (lost_from_stage is not null)
    and (stage = 'lost') = (lost_at is not null)
    and (stage = 'lost') = (lost_by_email is not null)
    and (stage = 'lost' or lost_note is null)
  ),
  constraint platform_deals_lost_reason_check check (
    lost_reason is null or lost_reason in (
      'price', 'chose_other', 'timing', 'no_response', 'not_a_fit', 'asked_not_to_contact', 'other'
    )
  ),
  constraint platform_deals_lost_from_check check (
    lost_from_stage is null
    or lost_from_stage in ('interested', 'call_booked', 'needs_understood', 'pricing_shared', 'awaiting_decision', 'later')
  ),
  constraint platform_deals_lost_note_check check (
    lost_note is null or (lost_note = btrim(lost_note) and char_length(lost_note) between 1 and 1000)
  )
);

comment on table public.platform_deals is
  'Uplift sales Deals (Jafar business management B4): one buying conversation with a platform_business_relationships row. Platform owner only (service role).';

-- One open Deal per business; also serves "this business's Deals" and the Leads list's has-a-Deal check.
create unique index platform_deals_one_open_idx
  on public.platform_deals (relationship_id) where stage <> 'lost';
create index platform_deals_relationship_idx
  on public.platform_deals (relationship_id, created_at desc);
-- The board's open columns and the Lost list.
create index platform_deals_stage_idx
  on public.platform_deals (stage) where stage <> 'lost';
create index platform_deals_lost_idx
  on public.platform_deals (lost_at desc, id desc) where stage = 'lost';

create trigger platform_deals_set_updated_at
  before update on public.platform_deals
  for each row execute function public.set_updated_at();

-- 2. Pricing shared -------------------------------------------------------------------------------------------

create table public.platform_deal_price_shares (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.platform_deals (id) on delete cascade,
  -- One share can hold several packages ("Pro and Growth"); they share shared_at and keep their order.
  shared_at timestamptz not null default now(),
  position smallint not null default 0,
  -- The edition shown, while it exists. The copied fields below are what the business saw.
  edition_id uuid references public.package_editions (id) on delete set null,
  package_slug text not null,
  package_name text not null,
  monthly_price_usd_cents integer,
  yearly_price_usd_cents integer,
  -- The intro offers shown with it, as the pricing page showed them: { "month": {...} | null, "year": ... }.
  offers jsonb not null default '{}'::jsonb,
  link text not null,
  actor_email text not null,
  constraint platform_deal_price_shares_price_check check (
    (monthly_price_usd_cents is not null or yearly_price_usd_cents is not null)
    and coalesce(monthly_price_usd_cents, 0) >= 0 and coalesce(yearly_price_usd_cents, 0) >= 0
  ),
  constraint platform_deal_price_shares_name_check check (char_length(package_name) between 1 and 200),
  constraint platform_deal_price_shares_slug_check check (package_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint platform_deal_price_shares_link_check check (char_length(link) between 1 and 500),
  constraint platform_deal_price_shares_offers_check check (jsonb_typeof(offers) = 'object')
);

comment on table public.platform_deal_price_shares is
  'Packages shared with a Deal, copied as the pricing page showed them that day (B4). Platform owner only (service role).';

create index platform_deal_price_shares_deal_idx
  on public.platform_deal_price_shares (deal_id, shared_at desc, position);
create index platform_deal_price_shares_edition_idx
  on public.platform_deal_price_shares (edition_id) where edition_id is not null;

alter table public.platform_deals enable row level security;
alter table public.platform_deal_price_shares enable row level security;
revoke all on table public.platform_deals from public, anon, authenticated;
revoke all on table public.platform_deal_price_shares from public, anon, authenticated;
grant all on table public.platform_deals to service_role;
grant all on table public.platform_deal_price_shares to service_role;

-- 3. History ----------------------------------------------------------------------------------------------------

alter table public.platform_business_history
  add column deal_id uuid references public.platform_deals (id) on delete cascade;

create index platform_business_history_deal_idx
  on public.platform_business_history (deal_id) where deal_id is not null;

alter table public.platform_business_history drop constraint platform_business_history_kind_check;
alter table public.platform_business_history add constraint platform_business_history_kind_check check (
  kind in (
    'note', 'contact', 'status_changed', 'next_action_set', 'next_action_done', 'next_action_cleared',
    'application_linked', 'application_unlinked', 'details_changed',
    'contact_approved', 'approval_withdrawn', 'sent_back', 'do_not_contact_set', 'do_not_contact_cleared',
    'deal_started', 'deal_stage_changed', 'pricing_shared', 'deal_lost', 'deal_reopened', 'deal_terms_changed',
    'deal_removed'
  )
);

-- Agreeing special terms on a Deal is its own sensitive action.
alter table public.platform_team_members drop constraint platform_team_members_action_grants_known;
alter table public.platform_team_members add constraint platform_team_members_action_grants_known check (
  action_grants <@ array['payments', 'client_setup', 'packages', 'client_accounts', 'approve_outreach', 'deal_terms']::text[]
);

-- 4. Commands -------------------------------------------------------------------------------------------------

-- Errors meant for Jafar are raised with errcode 22023 and a plain message. Each command returns false when the
-- Deal or business no longer exists.

-- The open Deal, locked for this change.
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
  return found_row;
end;
$function$;

-- Records a stage change on the Deal and in the history. No-op when the stage is unchanged.
create or replace function private.deal_set_stage(deal public.platform_deals, target_stage text, actor text)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if target_stage = deal.stage then
    return;
  end if;
  update public.platform_deals set stage = target_stage, stage_entered_at = now() where id = deal.id;
  insert into public.platform_business_history (relationship_id, deal_id, kind, details, actor_email)
  values (deal.relationship_id, deal.id, 'deal_stage_changed',
    jsonb_build_object('from', deal.stage, 'to', target_stage), actor);
end;
$function$;

-- An open Deal always has a dated next step (plan § 6).
create or replace function private.deal_require_next_action(target_relationship_id uuid)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if not exists (
    select 1 from public.platform_business_relationships
    where id = target_relationship_id and next_action is not null
  ) then
    raise exception 'Give the Deal its next step and when.' using errcode = '22023';
  end if;
end;
$function$;

-- Closes an open Deal as Lost and clears the business's next step, which belonged to the Deal.
create or replace function private.deal_close_lost(deal public.platform_deals, reason text, note text, actor text)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  rel public.platform_business_relationships%rowtype;
begin
  update public.platform_deals
  set stage = 'lost', stage_entered_at = now(), lost_reason = reason, lost_note = note,
    lost_from_stage = deal.stage, lost_at = now(), lost_by_email = actor
  where id = deal.id;
  insert into public.platform_business_history (relationship_id, deal_id, kind, details, actor_email)
  values (deal.relationship_id, deal.id, 'deal_lost',
    jsonb_strip_nulls(jsonb_build_object('reason', reason, 'note', note, 'from', deal.stage)), actor);

  select * into rel from public.platform_business_relationships where id = deal.relationship_id;
  if rel.next_action is not null then
    insert into public.platform_business_history (relationship_id, kind, details, actor_email)
    values (deal.relationship_id, 'next_action_cleared',
      jsonb_build_object('next_action', rel.next_action, 'due_on', rel.next_action_due_on), actor);
    update public.platform_business_relationships
    set next_action = null, next_action_due_on = null, next_action_kind = null
    where id = deal.relationship_id;
  end if;
end;
$function$;

revoke all on function private.deal_lock_open(uuid) from public, anon, authenticated;
revoke all on function private.deal_set_stage(public.platform_deals, text, text) from public, anon, authenticated;
revoke all on function private.deal_require_next_action(uuid) from public, anon, authenticated;
revoke all on function private.deal_close_lost(public.platform_deals, text, text, text) from public, anon, authenticated;

-- Start a Deal at Interested or Call booked, with its next step. Returns the Deal's id, or null when the
-- business no longer exists.
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
  if exists (select 1 from public.platform_deals where relationship_id = rel.id and stage <> 'lost') then
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

-- Move an open Deal to another open stage (not Pricing shared, which needs the packages shared, and not Lost,
-- which needs a reason). next_action_mode 'keep' or 'set', as in owner_lead_change.
create or replace function public.owner_deal_move(
  actor_email text,
  target_deal_id uuid,
  target_stage text,
  next_action_mode text default 'keep',
  target_next_action text default null,
  target_due_on date default null
)
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
  if target_stage = 'pricing_shared' then
    raise exception 'Choose the packages you shared to move a Deal to Pricing shared.' using errcode = '22023';
  end if;
  if target_stage not in ('interested', 'call_booked', 'needs_understood', 'awaiting_decision', 'later') then
    raise exception 'Unknown Deal stage.' using errcode = '22023';
  end if;
  if next_action_mode not in ('keep', 'set') then
    raise exception 'Unknown next step change.' using errcode = '22023';
  end if;

  deal := private.deal_lock_open(target_deal_id);
  if deal.id is null then
    return false;
  end if;
  -- Later, Call booked and Awaiting decision each come with their own date (plan, B4 decisions).
  if target_stage <> deal.stage and target_stage in ('later', 'call_booked', 'awaiting_decision')
    and next_action_mode <> 'set' then
    raise exception 'Give the date for this stage.' using errcode = '22023';
  end if;

  perform private.deal_set_stage(deal, target_stage, actor);
  perform public.owner_lead_change(actor, deal.relationship_id, null, next_action_mode, target_next_action, target_due_on);
  perform private.deal_require_next_action(deal.relationship_id);
  return true;
end;
$function$;

-- Record the packages shared, as the server read them from the pricing page:
-- [{ "edition_id", "slug", "name", "monthly_price_usd_cents", "yearly_price_usd_cents", "offers", "link" }].
-- The first is the main package; its monthly value goes on the Deal. A Deal before Pricing shared moves there;
-- one already past it stays. The follow-up becomes the next step.
create or replace function public.owner_deal_share_pricing(
  actor_email text,
  target_deal_id uuid,
  shared_packages jsonb,
  follow_up text,
  follow_up_on date
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  deal public.platform_deals%rowtype;
  shared_time timestamptz := clock_timestamp();
  main jsonb;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if jsonb_typeof(shared_packages) <> 'array' or jsonb_array_length(shared_packages) not between 1 and 5 then
    raise exception 'Choose between one and five packages.' using errcode = '22023';
  end if;

  deal := private.deal_lock_open(target_deal_id);
  if deal.id is null then
    return false;
  end if;

  insert into public.platform_deal_price_shares (
    deal_id, shared_at, position, edition_id, package_slug, package_name, monthly_price_usd_cents,
    yearly_price_usd_cents, offers, link, actor_email
  )
  select deal.id, shared_time, (ordinality - 1)::smallint, (item ->> 'edition_id')::uuid, item ->> 'slug',
    item ->> 'name', (item ->> 'monthly_price_usd_cents')::integer, (item ->> 'yearly_price_usd_cents')::integer,
    coalesce(item -> 'offers', '{}'::jsonb), item ->> 'link', actor
  from jsonb_array_elements(shared_packages) with ordinality as t(item, ordinality);

  main := shared_packages -> 0;
  update public.platform_deals
  set value_monthly_usd_cents = coalesce(
    (main ->> 'monthly_price_usd_cents')::integer,
    round((main ->> 'yearly_price_usd_cents')::numeric / 12)::integer
  )
  where id = deal.id;

  insert into public.platform_business_history (relationship_id, deal_id, kind, details, actor_email, occurred_at)
  values (deal.relationship_id, deal.id, 'pricing_shared',
    jsonb_build_object('packages', (
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'name', item ->> 'name',
        'monthly_price_usd_cents', (item ->> 'monthly_price_usd_cents')::integer,
        'yearly_price_usd_cents', (item ->> 'yearly_price_usd_cents')::integer
      )) order by ordinality)
      from jsonb_array_elements(shared_packages) with ordinality as t(item, ordinality)
    )), actor, shared_time);

  if deal.stage in ('interested', 'call_booked', 'needs_understood', 'later') then
    perform private.deal_set_stage(deal, 'pricing_shared', actor);
  end if;
  perform public.owner_lead_change(actor, deal.relationship_id, null, 'set', follow_up, follow_up_on);
  perform private.deal_require_next_action(deal.relationship_id);
  return true;
end;
$function$;

-- Mark an open Deal Lost with a reason (not 'asked_not_to_contact', which only Do not contact sets).
create or replace function public.owner_deal_mark_lost(
  actor_email text,
  target_deal_id uuid,
  reason text,
  note text default null
)
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
  if reason is null or reason not in ('price', 'chose_other', 'timing', 'no_response', 'not_a_fit', 'other') then
    raise exception 'Choose why the Deal was lost.' using errcode = '22023';
  end if;

  deal := private.deal_lock_open(target_deal_id);
  if deal.id is null then
    return false;
  end if;
  perform private.deal_close_lost(deal, reason, nullif(btrim(coalesce(note, '')), ''), actor);
  return true;
end;
$function$;

-- Reopen a Lost Deal into an open stage with a next step. Refused while the business has another open Deal or
-- asked not to be contacted.
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
  if deal.stage <> 'lost' then
    raise exception 'This Deal is already open.' using errcode = '22023';
  end if;
  select * into rel from public.platform_business_relationships where id = deal.relationship_id for update;
  if rel.do_not_contact_at is not null then
    raise exception 'This business asked not to be contacted, so its Deal cannot be reopened.' using errcode = '22023';
  end if;
  if exists (select 1 from public.platform_deals where relationship_id = rel.id and stage <> 'lost') then
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

-- Write, change, or clear (null) the special terms agreed on an open Deal.
create or replace function public.owner_deal_set_terms(
  actor_email text,
  target_deal_id uuid,
  terms text
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  actor text := lower(btrim(coalesce(actor_email, '')));
  new_terms text := nullif(btrim(coalesce(terms, '')), '');
  deal public.platform_deals%rowtype;
begin
  if actor = '' then
    raise exception 'An actor is required.' using errcode = '22023';
  end if;
  if new_terms is not null and char_length(new_terms) > 1000 then
    raise exception 'Keep the agreed terms to 1,000 characters.' using errcode = '22023';
  end if;

  deal := private.deal_lock_open(target_deal_id);
  if deal.id is null then
    return false;
  end if;
  if new_terms is not distinct from deal.agreed_terms then
    return true;
  end if;

  update public.platform_deals
  set agreed_terms = new_terms,
    agreed_terms_by_email = case when new_terms is null then null else actor end,
    agreed_terms_at = case when new_terms is null then null else now() end
  where id = deal.id;
  insert into public.platform_business_history (relationship_id, deal_id, kind, details, actor_email)
  values (deal.relationship_id, deal.id, 'deal_terms_changed', jsonb_build_object('terms', new_terms), actor);
  return true;
end;
$function$;

-- Remove a Deal started by mistake. Its own history lines go with it; one line records the removal, and the
-- business returns to the Leads list. The next step stays: it may still be right for the Lead.
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
  delete from public.platform_deals where id = deal.id;
  insert into public.platform_business_history (relationship_id, kind, details, actor_email)
  values (deal.relationship_id, 'deal_removed', jsonb_build_object('stage', deal.stage), actor);
  return true;
end;
$function$;

-- Do not contact closes an open Deal as Lost (Jafar, B4). Runs inside owner_lead_set_do_not_contact's update.
create or replace function private.platform_business_do_not_contact_closes_deal()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  deal public.platform_deals%rowtype;
begin
  select * into deal from public.platform_deals
  where relationship_id = new.id and stage <> 'lost'
  for update;
  if found then
    perform private.deal_close_lost(deal, 'asked_not_to_contact', new.do_not_contact_reason, new.do_not_contact_by_email);
  end if;
  return null;
end;
$function$;

revoke all on function private.platform_business_do_not_contact_closes_deal() from public, anon, authenticated;

create trigger platform_business_do_not_contact_closes_deal
  after update of do_not_contact_at on public.platform_business_relationships
  for each row
  when (old.do_not_contact_at is null and new.do_not_contact_at is not null)
  execute function private.platform_business_do_not_contact_closes_deal();

revoke all on function public.owner_deal_start(text, uuid, text, text, date) from public, anon, authenticated;
revoke all on function public.owner_deal_move(text, uuid, text, text, text, date) from public, anon, authenticated;
revoke all on function public.owner_deal_share_pricing(text, uuid, jsonb, text, date) from public, anon, authenticated;
revoke all on function public.owner_deal_mark_lost(text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.owner_deal_reopen(text, uuid, text, date) from public, anon, authenticated;
revoke all on function public.owner_deal_set_terms(text, uuid, text) from public, anon, authenticated;
revoke all on function public.owner_deal_remove(text, uuid) from public, anon, authenticated;
grant execute on function public.owner_deal_start(text, uuid, text, text, date) to service_role;
grant execute on function public.owner_deal_move(text, uuid, text, text, text, date) to service_role;
grant execute on function public.owner_deal_share_pricing(text, uuid, jsonb, text, date) to service_role;
grant execute on function public.owner_deal_mark_lost(text, uuid, text, text) to service_role;
grant execute on function public.owner_deal_reopen(text, uuid, text, date) to service_role;
grant execute on function public.owner_deal_set_terms(text, uuid, text) to service_role;
grant execute on function public.owner_deal_remove(text, uuid) to service_role;

-- 5. Reads ----------------------------------------------------------------------------------------------------

-- One board column, page_size cards at a time. Open stages: no next step first, then the soonest due, so what
-- needs doing sits on top; cursor (due key, id). Lost: most recently lost first; cursor (lost_at, id).
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
    select least(greatest(coalesce(page_size, 30), 1), 100) as size, target_stage = 'lost' as lost
  ),
  page as (
    select d.*, r.business_name, r.country_code, r.trade, r.contact_name, r.next_action, r.next_action_due_on,
      coalesce(r.next_action_due_on, date '0001-01-01') as due_key
    from public.platform_deals d
    join public.platform_business_relationships r on r.id = d.relationship_id
    cross join params p
    where d.stage = target_stage
      and case
        when p.lost then cursor_id is null or (d.lost_at, d.id) < (cursor_lost_at, cursor_id)
        else cursor_id is null or (coalesce(r.next_action_due_on, date '0001-01-01'), d.id) > (cursor_due_on, cursor_id)
      end
    order by
      case when p.lost then d.lost_at end desc,
      case when p.lost then d.id end desc,
      case when not p.lost then coalesce(r.next_action_due_on, date '0001-01-01') end asc,
      case when not p.lost then d.id end asc
    limit (select size from params)
  ),
  numbered as (
    select page.*, row_number() over (
      order by
        case when (select lost from params) then lost_at end desc,
        case when (select lost from params) then id end desc,
        case when not (select lost from params) then due_key end asc,
        case when not (select lost from params) then id end asc
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
            'lost_at', n.lost_at
          )
          order by n.row_index
        )
        from numbered n
        left join shared_names sn on sn.deal_id = n.id
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select count(*) from page) >= (select size from params) then (
        select jsonb_build_object('due_on', n.due_key, 'lost_at', n.lost_at, 'id', n.id)
        from numbered n order by n.row_index desc limit 1
      )
      else null
    end
  );
$function$;

-- Every column's count and monthly total, and how many are Lost, in one read.
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
          from public.platform_deals where stage <> 'lost' group by stage
        ) c
      ),
      '{}'::jsonb
    ),
    'lost', (select count(*) from public.platform_deals where stage = 'lost')
  );
$function$;

-- One business's Deals, newest first: the open or latest one with what was shared, and earlier ones briefly.
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

revoke all on function public.owner_deal_board(text, date, timestamptz, uuid, integer) from public, anon, authenticated;
revoke all on function public.owner_deal_board_summary() from public, anon, authenticated;
revoke all on function public.owner_business_deals(uuid) from public, anon, authenticated;
grant execute on function public.owner_deal_board(text, date, timestamptz, uuid, integer) to service_role;
grant execute on function public.owner_deal_board_summary() to service_role;
grant execute on function public.owner_business_deals(uuid) to service_role;

-- 6. The Leads list ---------------------------------------------------------------------------------------------

-- deal_filter: 'without' (default) hides businesses with a Deal; 'with' shows only them; 'any' shows all.
drop function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer);

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
  -- B4: a business with a Deal lives on the Deals board; the Leads list shows it only when asked.
  scoped as (
    select r.*
    from public.platform_business_relationships r
    where case coalesce(deal_filter, 'without')
      when 'any' then true
      when 'with' then exists (select 1 from public.platform_deals d where d.relationship_id = r.id)
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
            )
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
      'in_deal', (select count(distinct d.relationship_id) from public.platform_deals d),
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

revoke all on function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer, text)
  from public, anon, authenticated;
grant execute on function public.owner_lead_list(text, text[], text[], text[], text, timestamptz, date, uuid, integer, text)
  to service_role;

