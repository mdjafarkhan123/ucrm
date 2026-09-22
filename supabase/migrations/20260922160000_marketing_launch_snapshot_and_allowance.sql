-- Marketing M4 stage 2: the launch snapshot, the Marketing allowance, and the launch command.
--
-- Confirming a campaign freezes it. From that moment the audience is a stored list of rows, not a rule
-- that keeps re-evaluating, so the contractor can be told exactly who the campaign went to and why
-- anyone was left out -- and so a customer who unsubscribes tomorrow is handled by the dispatcher's
-- recheck rather than by the audience silently changing underneath a half-sent campaign.

-- ---------------------------------------------------------------------------------------------------
-- Marketing allowance
-- ---------------------------------------------------------------------------------------------------

-- Marketing gets its own allowance period table for the same reason website chat has one: each product
-- must account for its own usage, and putting the marketing launch lock on
-- communication_email_allowance_periods would make every operational email wait behind a launch.
-- The window itself is the organization's ordinary monthly commercial window, from the shared
-- private.current_communication_allowance_window.
create table if not exists "public"."marketing_email_allowance_periods" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "starts_at" timestamptz not null,
    "ends_at" timestamptz not null,
    "opened_by_commercial_event_id" uuid,
    "created_at" timestamptz not null default now(),
    constraint "marketing_email_allowance_periods_pkey" primary key ("id"),
    constraint "marketing_email_allowance_periods_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete cascade,
    constraint "marketing_email_allowance_periods_check" check ("ends_at" > "starts_at")
);

create unique index if not exists "marketing_email_allowance_periods_org_start_idx"
    on "public"."marketing_email_allowance_periods" using btree ("organization_id", "starts_at");

comment on table "public"."marketing_email_allowance_periods" is
    'One monthly Marketing allowance window per organization. Opened on demand by marketing_launch_campaign, which is the only writer.';

alter table "public"."marketing_email_allowance_periods" enable row level security;

-- One reservation per campaign, not one per message: a campaign reserves its whole eligible count at
-- launch, so the contractor cannot be told a campaign is sending and then discover halfway through that
-- the allowance ran out. reserved_count is what the launch held; accepted_count is what SES actually
-- took, and it replaces the reservation once the campaign is finished.
create table if not exists "public"."marketing_email_capacity_reservations" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "campaign_id" uuid not null,
    "allowance_period_id" uuid not null,
    "reserved_count" integer not null,
    "accepted_count" integer not null default 0,
    "reservation_state" text not null default 'reserved',
    "reserved_at" timestamptz not null default now(),
    "settled_at" timestamptz,
    "created_at" timestamptz not null default now(),
    "updated_at" timestamptz not null default now(),
    constraint "marketing_email_capacity_reservations_pkey" primary key ("id"),
    constraint "marketing_email_capacity_reservations_campaign_key" unique ("campaign_id"),
    constraint "marketing_email_capacity_reservations_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete cascade,
    constraint "marketing_email_capacity_reservations_campaign_fkey"
        foreign key ("organization_id", "campaign_id")
        references "public"."marketing_campaigns"("organization_id", "id") on delete cascade,
    constraint "marketing_email_capacity_reservations_period_fkey"
        foreign key ("allowance_period_id")
        references "public"."marketing_email_allowance_periods"("id") on delete restrict,
    constraint "marketing_email_capacity_reservations_reserved_count_check"
        check ("reserved_count" > 0),
    constraint "marketing_email_capacity_reservations_accepted_count_check"
        check ("accepted_count" >= 0),
    constraint "marketing_email_capacity_reservations_state_check"
        check ("reservation_state" = any (array['reserved'::text, 'settled'::text, 'released'::text])),
    constraint "marketing_email_capacity_reservations_settled_at_check"
        check (("reservation_state" = 'reserved') = ("settled_at" is null))
);

-- The launch allowance sum reads exactly this: every still-open reservation in one organization's
-- current period.
create index if not exists "marketing_email_capacity_reservations_open_idx"
    on "public"."marketing_email_capacity_reservations" using btree ("organization_id", "allowance_period_id")
    where ("reservation_state" = 'reserved');

create index if not exists "marketing_email_capacity_reservations_period_idx"
    on "public"."marketing_email_capacity_reservations" using btree ("allowance_period_id");

create trigger "marketing_email_capacity_reservations_set_updated_at"
    before update on "public"."marketing_email_capacity_reservations"
    for each row execute function "public"."set_updated_at"();

comment on table "public"."marketing_email_capacity_reservations" is
    'One Marketing allowance reservation per campaign. reserved_count is held from launch; accepted_count replaces it once the campaign settles, so a period never counts a campaign twice.';

alter table "public"."marketing_email_capacity_reservations" enable row level security;

-- ---------------------------------------------------------------------------------------------------
-- The recipient snapshot
-- ---------------------------------------------------------------------------------------------------

-- One row per Customer the campaign's rules matched at launch -- including the ones it cannot reach, so
-- the contractor sees the real reason instead of a smaller number with no explanation. The email address
-- and display name are copied, not joined, because a campaign's history must not change when a Customer
-- later edits their details.
create table if not exists "public"."marketing_campaign_recipients" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "campaign_id" uuid not null,
    "client_id" uuid not null,
    "client_contact_method_id" uuid,
    "recipient_email" text,
    "display_name" text not null,
    "status" text not null,
    "excluded_reason" text,
    "created_at" timestamptz not null default now(),
    "updated_at" timestamptz not null default now(),
    constraint "marketing_campaign_recipients_pkey" primary key ("id"),
    constraint "marketing_campaign_recipients_campaign_client_key" unique ("campaign_id", "client_id"),
    constraint "marketing_campaign_recipients_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete cascade,
    constraint "marketing_campaign_recipients_campaign_fkey"
        foreign key ("organization_id", "campaign_id")
        references "public"."marketing_campaigns"("organization_id", "id") on delete cascade,
    constraint "marketing_campaign_recipients_client_fkey"
        foreign key ("organization_id", "client_id")
        references "public"."clients"("organization_id", "id") on delete cascade,
    constraint "marketing_campaign_recipients_contact_method_fkey"
        foreign key ("organization_id", "client_contact_method_id")
        references "public"."client_contact_methods"("organization_id", "id") on delete set null,
    constraint "marketing_campaign_recipients_status_check"
        check ("status" = any (array[
            'waiting'::text, 'submitted'::text, 'delivered'::text, 'bounced'::text, 'complained'::text,
            'unsubscribed'::text, 'cancelled'::text, 'failed'::text, 'checking'::text, 'excluded'::text
        ])),
    constraint "marketing_campaign_recipients_excluded_reason_check"
        check ("excluded_reason" is null or "excluded_reason" = any (array[
            'inactive_customer'::text, 'missing_email'::text, 'complaint'::text, 'unsubscribed'::text,
            'hard_bounce'::text, 'do_not_disturb'::text, 'no_marketing'::text, 'no_consent'::text,
            'duplicate_destination'::text
        ])),
    -- A row is excluded exactly when it carries a reason, and only a reachable row has an address.
    constraint "marketing_campaign_recipients_exclusion_check"
        check (("status" = 'excluded') = ("excluded_reason" is not null)),
    constraint "marketing_campaign_recipients_address_check"
        check ("status" = 'excluded' or ("recipient_email" is not null and "client_contact_method_id" is not null))
);

-- Serves both reads that matter: the dispatcher asking a campaign for its waiting recipients, and the
-- campaign detail page's status counts and filtered pages.
create index if not exists "marketing_campaign_recipients_campaign_status_idx"
    on "public"."marketing_campaign_recipients" using btree ("campaign_id", "status", "display_name", "id");

comment on table "public"."marketing_campaign_recipients" is
    'The frozen audience of one launched campaign: one row per matched Customer, reachable or not. Written once by marketing_launch_campaign and afterwards only advanced in status by the Marketing dispatcher and the SES event consumer.';

alter table "public"."marketing_campaign_recipients" enable row level security;

-- ---------------------------------------------------------------------------------------------------
-- What a launched campaign remembers
-- ---------------------------------------------------------------------------------------------------

alter table "public"."marketing_campaigns"
    add column if not exists "scheduled_for" timestamptz,
    add column if not exists "launched_at" timestamptz,
    add column if not exists "launched_by" uuid,
    add column if not exists "launch_idempotency_key" text,
    -- The campaign list shows a recipient count per row; counting snapshot rows per campaign would be
    -- one query per row. These three are frozen at launch and never move again.
    add column if not exists "recipient_total_count" integer,
    add column if not exists "recipient_eligible_count" integer,
    add column if not exists "recipient_excluded_count" integer;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'marketing_campaigns_launched_by_fkey'
    ) then
        alter table "public"."marketing_campaigns"
            add constraint "marketing_campaigns_launched_by_fkey"
            foreign key ("launched_by") references "auth"."users"("id") on delete set null;
    end if;

    if not exists (
        select 1 from pg_constraint where conname = 'marketing_campaigns_launch_state_check'
    ) then
        -- Draft is the only state that was never launched; every other state is reached through
        -- marketing_launch_campaign, so a launched_at must exist for it.
        alter table "public"."marketing_campaigns"
            add constraint "marketing_campaigns_launch_state_check"
            check (("status" = 'draft') = ("launched_at" is null));
    end if;

    if not exists (
        select 1 from pg_constraint where conname = 'marketing_campaigns_launch_counts_check'
    ) then
        alter table "public"."marketing_campaigns"
            add constraint "marketing_campaigns_launch_counts_check"
            check (
                ("launched_at" is null
                    and "recipient_total_count" is null
                    and "recipient_eligible_count" is null
                    and "recipient_excluded_count" is null
                    and "launch_idempotency_key" is null)
                or ("launched_at" is not null
                    and "recipient_total_count" >= 0
                    and "recipient_eligible_count" >= 0
                    and "recipient_excluded_count" >= 0
                    and "recipient_total_count" = "recipient_eligible_count" + "recipient_excluded_count"
                    and "launch_idempotency_key" is not null)
            );
    end if;
end
$$;

-- A retried launch request must find its own earlier launch rather than start a second one.
create unique index if not exists "marketing_campaigns_launch_idempotency_idx"
    on "public"."marketing_campaigns" using btree ("organization_id", "launch_idempotency_key")
    where ("launch_idempotency_key" is not null);

-- ---------------------------------------------------------------------------------------------------
-- The launch command
-- ---------------------------------------------------------------------------------------------------

create or replace function "private"."ensure_marketing_allowance_period"(
    "target_organization_id" uuid,
    "at" timestamptz default now()
) returns uuid
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    allowance_window record;
    period_id uuid;
begin
    -- The returned row is locked, so it is also this organization's launch queue: a second launch waits
    -- here instead of reading an allowance total the first launch is about to change.
    select period.id into period_id
    from public.marketing_email_allowance_periods as period
    where period.organization_id = target_organization_id
      and period.starts_at <= at
      and period.ends_at > at
    for update;
    if found then
        return period_id;
    end if;

    select * into allowance_window
    from private.current_communication_allowance_window(target_organization_id, at);
    if not found then
        return null;
    end if;

    insert into public.marketing_email_allowance_periods (
        organization_id, starts_at, ends_at, opened_by_commercial_event_id
    ) values (
        target_organization_id,
        allowance_window.window_starts_at,
        allowance_window.window_ends_at,
        allowance_window.commercial_event_id
    ) on conflict ("organization_id", "starts_at") do nothing;

    select period.id into period_id
    from public.marketing_email_allowance_periods as period
    where period.organization_id = target_organization_id
      and period.starts_at <= at
      and period.ends_at > at
    for update;

    return period_id;
end;
$$;

alter function "private"."ensure_marketing_allowance_period"("target_organization_id" uuid, "at" timestamptz)
    owner to "postgres";

comment on function "private"."ensure_marketing_allowance_period"("target_organization_id" uuid, "at" timestamptz) is
    'Opens (if needed) and locks the organization''s current Marketing allowance window. Null means the organization has no current access, so launch fails closed.';

revoke all on function "private"."ensure_marketing_allowance_period"("target_organization_id" uuid, "at" timestamptz)
    from public, anon, authenticated;


create or replace function "public"."marketing_launch_campaign"(
    "target_organization_id" uuid,
    "target_campaign_id" uuid,
    "actor_user_id" uuid,
    "expected_revision" integer,
    "send_at" timestamptz,
    "idempotency_key" text
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $_$
declare
    -- A launch writes one row per matched Customer in one transaction. Past this many, the campaign is
    -- not a contractor sending to their own customer list any more, and the write would hold locks far
    -- too long, so the launch is refused rather than silently accepted.
    max_snapshot_rows constant integer := 50000;
    campaign_row public.marketing_campaigns;
    group_rules jsonb;
    clean_key text;
    period_id uuid;
    limit_row record;
    used_count integer;
    total_count integer;
    eligible_count integer;
    excluded_count integer;
    new_status text;
    effective_send_at timestamptz;
    new_revision integer;
begin
    clean_key := nullif(btrim(coalesce(idempotency_key, '')), '');
    if clean_key is null or char_length(clean_key) > 200 then
        raise exception 'A launch needs an idempotency key.' using errcode = 'check_violation';
    end if;

    select * into campaign_row
    from public.marketing_campaigns
    where id = target_campaign_id and organization_id = target_organization_id
    for update;

    if campaign_row.id is null then
        raise exception 'This campaign no longer exists.' using errcode = 'check_violation';
    end if;

    -- A retry of the same request finds its own earlier launch and answers with it, so a lost response
    -- never turns into a second campaign to the same people.
    if campaign_row.launch_idempotency_key = clean_key then
        return jsonb_build_object(
            'campaign_id', campaign_row.id,
            'status', campaign_row.status,
            'revision', campaign_row.revision,
            'scheduled_for', campaign_row.scheduled_for,
            'launched_at', campaign_row.launched_at,
            'total_count', campaign_row.recipient_total_count,
            'eligible_count', campaign_row.recipient_eligible_count,
            'excluded_count', campaign_row.recipient_excluded_count,
            'replayed', true
        );
    end if;

    if campaign_row.status <> 'draft' then
        raise exception 'This campaign has already been sent.' using errcode = 'check_violation';
    end if;

    if expected_revision is distinct from campaign_row.revision then
        raise exception 'Someone else changed this campaign while you were editing. Reload and try again.'
            using errcode = 'P0409';
    end if;

    if campaign_row.customer_group_id is null then
        raise exception 'Choose who this campaign goes to before sending it.' using errcode = 'check_violation';
    end if;

    select "group".rules into group_rules
    from public.marketing_customer_groups as "group"
    where "group".id = campaign_row.customer_group_id
      and "group".organization_id = target_organization_id
      and "group".archived_at is null;

    if group_rules is null then
        raise exception 'This campaign''s customer group is no longer available.' using errcode = 'check_violation';
    end if;

    effective_send_at := case when send_at is not null and send_at > now() then send_at end;

    period_id := private.ensure_marketing_allowance_period(target_organization_id, now());
    if period_id is null then
        raise exception 'This account does not have current access, so Marketing cannot send.'
            using errcode = 'check_violation';
    end if;

    -- The audience is evaluated once, here, and stored. Exclusions are kept so the contractor can see
    -- the real reason a Customer was left out; duplicate_destination uses the same window the preview
    -- uses, so the numbers the contractor confirmed are the numbers that get written.
    execute format($sql$
        insert into public.marketing_campaign_recipients (
            organization_id, campaign_id, client_id, client_contact_method_id,
            recipient_email, display_name, status, excluded_reason
        )
        select
            $2::uuid,
            $3::uuid,
            evaluated.client_id,
            case when evaluated.excluded_reason is null then evaluated.method_id end,
            case when evaluated.excluded_reason is null then evaluated.email end,
            evaluated.display_name,
            case when evaluated.excluded_reason is null then 'waiting' else 'excluded' end,
            evaluated.excluded_reason
        from (
            select
                client_id,
                display_name,
                method_id,
                email,
                coalesce(
                    blocked_reason,
                    case
                        when row_number() over (
                            partition by (case when blocked_reason is null then email end)
                            order by display_name, client_id
                        ) > 1 then 'duplicate_destination'
                    end
                ) as excluded_reason
            from (%s) reachable
        ) evaluated
    $sql$, private.marketing_evaluated_recipients_sql(group_rules))
    using group_rules, target_organization_id, target_campaign_id;

    select count(*)::integer, count(*) filter (where recipient.status = 'waiting')::integer
    into total_count, eligible_count
    from public.marketing_campaign_recipients as recipient
    where recipient.campaign_id = target_campaign_id;
    excluded_count := total_count - eligible_count;

    if total_count > max_snapshot_rows then
        raise exception 'This campaign matches more than % customers. Narrow the customer group and try again.',
            max_snapshot_rows using errcode = 'check_violation';
    end if;

    if eligible_count = 0 then
        raise exception 'No one in this customer group can receive this campaign right now.'
            using errcode = 'check_violation';
    end if;

    select * into limit_row from private.effective_marketing_email_limit(target_organization_id, now());
    if limit_row.state = 'not_included' then
        raise exception 'Marketing email is not included in this plan.' using errcode = 'check_violation';
    end if;
    if limit_row.state not in ('numeric', 'unlimited')
        or (limit_row.state = 'numeric' and limit_row.value is null) then
        raise exception 'Marketing allowance is not configured yet.' using errcode = 'check_violation';
    end if;

    if limit_row.state = 'numeric' then
        -- A still-open reservation counts what it held; a settled one counts what SES actually took.
        select coalesce(sum(
            case reservation.reservation_state
                when 'reserved' then reservation.reserved_count
                when 'settled' then reservation.accepted_count
                else 0
            end
        ), 0)::integer
        into used_count
        from public.marketing_email_capacity_reservations as reservation
        where reservation.organization_id = target_organization_id
          and reservation.allowance_period_id = period_id;

        if used_count + eligible_count > limit_row.value then
            raise exception 'This campaign needs % marketing emails but only % are left this month.',
                eligible_count, greatest(limit_row.value - used_count, 0)
                using errcode = 'check_violation';
        end if;
    end if;

    insert into public.marketing_email_capacity_reservations (
        organization_id, campaign_id, allowance_period_id, reserved_count
    ) values (
        target_organization_id, target_campaign_id, period_id, eligible_count
    );

    new_status := case when effective_send_at is null then 'sending' else 'scheduled' end;

    update public.marketing_campaigns
    set status = new_status,
        scheduled_for = effective_send_at,
        launched_at = now(),
        launched_by = actor_user_id,
        launch_idempotency_key = clean_key,
        recipient_total_count = total_count,
        recipient_eligible_count = eligible_count,
        recipient_excluded_count = excluded_count,
        revision = revision + 1,
        updated_by = actor_user_id
    where id = campaign_row.id
    returning revision into new_revision;

    return jsonb_build_object(
        'campaign_id', campaign_row.id,
        'status', new_status,
        'revision', new_revision,
        'scheduled_for', effective_send_at,
        'launched_at', now(),
        'total_count', total_count,
        'eligible_count', eligible_count,
        'excluded_count', excluded_count,
        'replayed', false
    );
end;
$_$;

alter function "public"."marketing_launch_campaign"("target_organization_id" uuid, "target_campaign_id" uuid, "actor_user_id" uuid, "expected_revision" integer, "send_at" timestamptz, "idempotency_key" text)
    owner to "postgres";

comment on function "public"."marketing_launch_campaign"("target_organization_id" uuid, "target_campaign_id" uuid, "actor_user_id" uuid, "expected_revision" integer, "send_at" timestamptz, "idempotency_key" text) is
    'Confirms a campaign: freezes the audience into marketing_campaign_recipients, reserves the Marketing allowance, and moves the campaign out of draft -- all in one transaction. Refuses a stale edit with P0409 and answers a repeated idempotency key with the original launch. The marketing.launch permission and the readiness checks are enforced by the calling route, as with every other marketing command.';

revoke all on function "public"."marketing_launch_campaign"("target_organization_id" uuid, "target_campaign_id" uuid, "actor_user_id" uuid, "expected_revision" integer, "send_at" timestamptz, "idempotency_key" text)
    from public, anon, authenticated;

grant all on function "public"."marketing_launch_campaign"("target_organization_id" uuid, "target_campaign_id" uuid, "actor_user_id" uuid, "expected_revision" integer, "send_at" timestamptz, "idempotency_key" text)
    to "service_role";
