-- Marketing M6f: earned warm-up for the Marketing sending domain.
--
-- Until now Marketing used the same calendar-only warm-up as operational email: 100/day for days 1-3,
-- 250/day for days 4-7, 500/day for days 8-14, then no cap at all -- whether or not the domain had sent anything
-- or how that mail performed. This replaces it, for Marketing only, with HighLevel's behavior-based ramp-up
-- (docs/marketing-first-release-plan.md §3 M6f; docs/research/email-warmup-graduation-2026-09-23.md):
--
--   * Ladder per Marketing domain: 100, 250, 500, 1,000, 2,500, 5,000 a day, then graduated (no warm-up cap).
--     Minimum days per step: 3, 4, 7, 7, 7, 7.
--   * A step advances only when its minimum days have passed, the real recipients accepted during the step reach
--     that step's daily limit, and the step's hard-bounce and complaint rates are below the pause thresholds.
--   * One step down when a Marketing reputation pause engages, and one per full 30 days without a real send.
--   * Amazon SES mailbox-simulator recipients never count as earned volume or in the step's rates.
--
-- Advancing is evaluated lazily, only when an organization reaches today's limit: an organization that never
-- needs more than its current limit sends exactly the same either way, and the hot claim path stays one
-- primary-key read plus the daily count it already made. A capped organization is marked until the next UTC
-- day and filtered out of the claim's candidate query, so its queue can no longer fill all 50 candidate slots
-- and starve other organizations' campaigns.
--
-- Operational email keeps private.resolve_communication_email_warmup_ceiling unchanged, so a quote or invoice
-- is never held by Marketing's ladder.

-- ---------------------------------------------------------------------------------------------------
-- Per-domain warm-up state
-- ---------------------------------------------------------------------------------------------------

create table if not exists "public"."marketing_warmup_state" (
    "domain_id" uuid primary key,
    "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
    "step" smallint not null default 1,
    "step_started_at" timestamptz not null,
    "capped_until" timestamptz,
    "limit_override" integer,
    "created_at" timestamptz not null default now(),
    "updated_at" timestamptz not null default now(),
    constraint "marketing_warmup_state_domain_fkey"
        foreign key ("organization_id", "domain_id")
        references "public"."communication_email_domains" ("organization_id", "id") on delete cascade,
    constraint "marketing_warmup_state_step_check" check ("step" between 1 and 7),
    constraint "marketing_warmup_state_limit_override_check"
        check ("limit_override" is null or "limit_override" between 0 and 10000000)
);

comment on table "public"."marketing_warmup_state" is
    'Earned warm-up per Marketing sending domain. step 1-6 is a ladder step (see private.marketing_warmup_ladder), 7 is graduated. capped_until marks an organization that reached today''s limit so the claim skips it until then. limit_override is a Jafar-set fixed daily limit that replaces the ladder while set (testing, load tests). Service role only.';

-- Backs the claim's "is this organization capped today" filter and the organization FK.
create index if not exists "marketing_warmup_state_organization_idx"
    on "public"."marketing_warmup_state" using btree ("organization_id");

alter table "public"."marketing_warmup_state" enable row level security;
revoke all on table "public"."marketing_warmup_state" from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- The ladder and what counts as a real send
-- ---------------------------------------------------------------------------------------------------

create or replace function "private"."marketing_warmup_ladder"()
returns table ("step" smallint, "daily_limit" integer, "min_days" integer)
    language sql immutable
    set search_path to ''
    as $$
    values
        (1::smallint, 100, 3),
        (2::smallint, 250, 4),
        (3::smallint, 500, 7),
        (4::smallint, 1000, 7),
        (5::smallint, 2500, 7),
        (6::smallint, 5000, 7);
$$;

alter function "private"."marketing_warmup_ladder"() owner to "postgres";
revoke all on function "private"."marketing_warmup_ladder"() from public, anon, authenticated;

create or replace function "private"."is_marketing_simulator_address"("p_email" text)
returns boolean
    language sql immutable
    set search_path to ''
    as $$
    select lower(split_part(coalesce(p_email, ''), '@', 2)) = 'simulator.amazonses.com';
$$;

alter function "private"."is_marketing_simulator_address"(text) owner to "postgres";
revoke all on function "private"."is_marketing_simulator_address"(text) from public, anon, authenticated;

-- Real recipients SES accepted since a step began, and how many of those sends drew a hard bounce or a
-- complaint. Bounded by one organization's sends inside one step (at most a few tens of thousands).
create or replace function "private"."marketing_warmup_step_measure"(
    "p_organization_id" uuid,
    "p_since" timestamptz,
    "p_at" timestamptz
) returns table ("real_sent" bigint, "hard_bounces" bigint, "complaints" bigint)
    language sql stable security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
    with sent as (
        select recipient.provider_message_id
        from public.marketing_campaign_recipients recipient
        where recipient.organization_id = p_organization_id
            and recipient.submitted_at is not null
            and recipient.submitted_at >= p_since
            and recipient.submitted_at <= p_at
            and not private.is_marketing_simulator_address(recipient.recipient_email)
    ),
    problems as (
        select event.normalized_kind, count(distinct event.provider_message_id) as sends
        from public.marketing_campaign_recipient_events event
        where event.organization_id = p_organization_id
            and event.processed_at is not null
            and event.normalized_kind in ('hard_bounce', 'complaint')
            and event.received_at >= p_since
            and event.received_at <= p_at
            and event.provider_message_id in (select sent.provider_message_id from sent)
        group by event.normalized_kind
    )
    select
        (select count(*) from sent),
        coalesce((select sends from problems where normalized_kind = 'hard_bounce'), 0),
        coalesce((select sends from problems where normalized_kind = 'complaint'), 0);
$$;

alter function "private"."marketing_warmup_step_measure"(uuid, timestamptz, timestamptz) owner to "postgres";
revoke all on function "private"."marketing_warmup_step_measure"(uuid, timestamptz, timestamptz)
    from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- Reading a domain's effective state (no writes)
-- ---------------------------------------------------------------------------------------------------

-- The step a domain is on right now: its stored step, or step 1 from the domain's warm-up start when nothing
-- is stored yet, lowered by one for every full 30 days without a real send. daily_limit is null when the
-- domain has graduated and no override is set.
create or replace function "private"."marketing_warmup_snapshot"(
    "p_domain_id" uuid,
    "p_at" timestamptz default now()
) returns table (
    "organization_id" uuid, "stored_step" smallint, "step" smallint, "step_started_at" timestamptz,
    "quiet_drops" integer, "capped_until" timestamptz, "limit_override" integer, "daily_limit" integer
)
    language plpgsql stable security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
#variable_conflict use_variable
declare
    state public.marketing_warmup_state;
    domain_row public.communication_email_domains;
    last_real_send timestamptz;
    quiet_reference timestamptz;
begin
    select * into state from public.marketing_warmup_state s where s.domain_id = p_domain_id;

    if found then
        organization_id := state.organization_id;
        stored_step := state.step;
        step := state.step;
        step_started_at := state.step_started_at;
        capped_until := state.capped_until;
        limit_override := state.limit_override;
    else
        select * into domain_row from public.communication_email_domains d where d.id = p_domain_id;
        if not found then
            return;
        end if;
        organization_id := domain_row.organization_id;
        stored_step := null;
        step := 1;
        step_started_at := least(coalesce(domain_row.warmup_started_at, domain_row.verified_at, p_at), p_at);
        capped_until := null;
        limit_override := null;
    end if;

    quiet_drops := 0;
    if step > 1 then
        select recipient.submitted_at into last_real_send
        from public.marketing_campaign_recipients recipient
        where recipient.organization_id = organization_id
            and recipient.submitted_at is not null
            and recipient.submitted_at <= p_at
            and not private.is_marketing_simulator_address(recipient.recipient_email)
        order by recipient.submitted_at desc
        limit 1;

        -- Quiet time counts from the later of the last real send and the step's own start, so a step that was
        -- just set (by a drop, an advance, or a pause) is never dropped again for the same silence.
        quiet_reference := greatest(coalesce(last_real_send, step_started_at), step_started_at);
        quiet_drops := floor(extract(epoch from (p_at - quiet_reference)) / (30 * 86400.0))::integer;
        if quiet_drops > 0 then
            step := greatest(1, step - quiet_drops)::smallint;
            step_started_at := p_at;
        else
            quiet_drops := 0;
        end if;
    end if;

    daily_limit := coalesce(
        limit_override,
        (select ladder.daily_limit from private.marketing_warmup_ladder() ladder where ladder.step = step)
    );
    return next;
end;
$$;

alter function "private"."marketing_warmup_snapshot"(uuid, timestamptz) owner to "postgres";
revoke all on function "private"."marketing_warmup_snapshot"(uuid, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- Moving between steps
-- ---------------------------------------------------------------------------------------------------

-- Records every step change for Jafar, whatever moved it.
create or replace function "private"."record_marketing_warmup_step_change"(
    "p_organization_id" uuid,
    "p_domain_id" uuid,
    "p_from_step" smallint,
    "p_to_step" smallint,
    "p_cause" text,
    "p_evidence" jsonb default '{}'::jsonb
) returns void
    language sql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
    insert into public.platform_owner_audit_events (
        actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
        'system', 'communications.marketing_warmup_step_changed', 'organization', p_organization_id::text,
        jsonb_build_object('domain_id', p_domain_id, 'step', p_from_step),
        jsonb_build_object('domain_id', p_domain_id, 'step', p_to_step, 'cause', p_cause) || coalesce(p_evidence, '{}'::jsonb)
    );
$$;

alter function "private"."record_marketing_warmup_step_change"(uuid, uuid, smallint, smallint, text, jsonb)
    owner to "postgres";
revoke all on function "private"."record_marketing_warmup_step_change"(uuid, uuid, smallint, smallint, text, jsonb)
    from public, anon, authenticated;

-- The claim's entry point: stores the domain's state the first time it sends, applies any quiet-time drop,
-- and returns today's limit (null = graduated, no warm-up cap).
create or replace function "private"."resolve_marketing_warmup_limit"(
    "p_domain_id" uuid,
    "p_at" timestamptz default now()
) returns integer
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    snap record;
begin
    select * into snap from private.marketing_warmup_snapshot(p_domain_id, p_at);
    if snap.organization_id is null then
        return null;
    end if;

    if snap.stored_step is null then
        insert into public.marketing_warmup_state (domain_id, organization_id, step, step_started_at)
        values (p_domain_id, snap.organization_id, snap.step, snap.step_started_at)
        on conflict (domain_id) do nothing;
    elsif snap.quiet_drops > 0 then
        -- Guarded on the step read above, so two claims racing through the same drop apply it once.
        update public.marketing_warmup_state
        set step = snap.step, step_started_at = p_at, capped_until = null, updated_at = now()
        where domain_id = p_domain_id and step = snap.stored_step;
        if found then
            perform private.record_marketing_warmup_step_change(
                snap.organization_id, p_domain_id, snap.stored_step, snap.step, 'quiet',
                jsonb_build_object('quiet_periods', snap.quiet_drops));
        end if;
    end if;

    return snap.daily_limit;
end;
$$;

alter function "private"."resolve_marketing_warmup_limit"(uuid, timestamptz) owner to "postgres";
revoke all on function "private"."resolve_marketing_warmup_limit"(uuid, timestamptz) from public, anon, authenticated;

-- Tries to earn the next step. Called only when an organization reaches today's limit. Returns true when the
-- domain moved up.
create or replace function "private"."try_advance_marketing_warmup"(
    "p_domain_id" uuid,
    "p_at" timestamptz default now()
) returns boolean
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    state public.marketing_warmup_state;
    rung record;
    measured record;
    hard_bounce_pause numeric;
    complaint_pause numeric;
begin
    select * into state from public.marketing_warmup_state s where s.domain_id = p_domain_id for update;
    if not found or state.step >= 7 then
        return false;
    end if;

    select * into rung from private.marketing_warmup_ladder() ladder where ladder.step = state.step;
    if p_at < state.step_started_at + make_interval(days => rung.min_days) then
        return false;
    end if;

    select * into measured from private.marketing_warmup_step_measure(state.organization_id, state.step_started_at, p_at);
    if measured.real_sent < rung.daily_limit then
        return false;
    end if;

    select min(t.pause_rate) filter (where t.signal = 'hard_bounce'),
           min(t.pause_rate) filter (where t.signal = 'complaint')
    into hard_bounce_pause, complaint_pause
    from private.communication_email_effective_reputation_thresholds(state.organization_id, p_at) t;

    -- Rates are percentages, as in the reputation thresholds.
    if 100.0 * measured.hard_bounces >= coalesce(hard_bounce_pause, 2.0) * measured.real_sent
        or 100.0 * measured.complaints >= coalesce(complaint_pause, 0.1) * measured.real_sent then
        return false;
    end if;

    update public.marketing_warmup_state
    set step = state.step + 1, step_started_at = p_at, capped_until = null, updated_at = now()
    where domain_id = p_domain_id;

    perform private.record_marketing_warmup_step_change(
        state.organization_id, p_domain_id, state.step, (state.step + 1)::smallint, 'earned',
        jsonb_build_object('real_sent', measured.real_sent, 'hard_bounces', measured.hard_bounces,
            'complaints', measured.complaints));
    return true;
end;
$$;

alter function "private"."try_advance_marketing_warmup"(uuid, timestamptz) owner to "postgres";
revoke all on function "private"."try_advance_marketing_warmup"(uuid, timestamptz) from public, anon, authenticated;

-- One step down for every Marketing domain of an organization, when its Marketing reputation pause engages.
create or replace function "private"."step_down_marketing_warmup"(
    "p_organization_id" uuid,
    "p_cause" text,
    "p_at" timestamptz default now()
) returns void
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    state public.marketing_warmup_state;
begin
    for state in
        select * from public.marketing_warmup_state s
        where s.organization_id = p_organization_id and s.step > 1
        for update
    loop
        update public.marketing_warmup_state
        set step = state.step - 1, step_started_at = p_at, capped_until = null, updated_at = now()
        where domain_id = state.domain_id;

        perform private.record_marketing_warmup_step_change(
            p_organization_id, state.domain_id, state.step, (state.step - 1)::smallint, p_cause);
    end loop;
end;
$$;

alter function "private"."step_down_marketing_warmup"(uuid, text, timestamptz) owner to "postgres";
revoke all on function "private"."step_down_marketing_warmup"(uuid, text, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- The contractor's progress card
-- ---------------------------------------------------------------------------------------------------

-- What the Marketing Overview shows: the current step, today's limit and use, and what unlocks the next step.
-- Read-only. Service role only -- the API route has already checked marketing.view for this organization.
create or replace function "public"."get_marketing_warmup_progress"("p_organization_id" uuid)
returns jsonb
    language plpgsql stable security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    marketing_domain_id uuid;
    snap record;
    rung record;
    next_rung record;
    measured record;
    hard_bounce_pause numeric;
    complaint_pause numeric;
    sent_today bigint;
    today_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
begin
    select domain.id into marketing_domain_id
    from public.communication_email_domains domain
    where domain.organization_id = p_organization_id
        and domain.purpose = 'marketing_sending'
        and domain.lifecycle_state = 'verified'
    order by domain.verified_at desc nulls last
    limit 1;

    if marketing_domain_id is null then
        return jsonb_build_object('status', 'no_domain');
    end if;

    select * into snap from private.marketing_warmup_snapshot(marketing_domain_id, now());

    -- Counted the same way the claim counts it.
    select count(*) into sent_today
    from public.marketing_campaign_recipients recipient
    where recipient.organization_id = p_organization_id
        and (
            (recipient.status = 'checking' and recipient.claimed_at >= today_start)
            or (recipient.submitted_at is not null and recipient.submitted_at >= today_start)
        );

    if snap.step >= 7 then
        return jsonb_build_object(
            'status', 'graduated', 'step', snap.step, 'total_steps', 6,
            'daily_limit', snap.daily_limit, 'sent_today', sent_today);
    end if;

    select * into rung from private.marketing_warmup_ladder() ladder where ladder.step = snap.step;
    select * into next_rung from private.marketing_warmup_ladder() ladder where ladder.step = snap.step + 1;
    select * into measured from private.marketing_warmup_step_measure(p_organization_id, snap.step_started_at, now());

    select min(t.pause_rate) filter (where t.signal = 'hard_bounce'),
           min(t.pause_rate) filter (where t.signal = 'complaint')
    into hard_bounce_pause, complaint_pause
    from private.communication_email_effective_reputation_thresholds(p_organization_id, now()) t;

    return jsonb_build_object(
        'status', 'warming',
        'step', snap.step,
        'total_steps', 6,
        'daily_limit', snap.daily_limit,
        'limit_overridden', snap.limit_override is not null,
        'sent_today', sent_today,
        'next_daily_limit', next_rung.daily_limit,
        'step_started_at', snap.step_started_at,
        'days_remaining', greatest(0, ceil(
            extract(epoch from (snap.step_started_at + make_interval(days => rung.min_days) - now())) / 86400.0
        ))::integer,
        'sends_in_step', measured.real_sent,
        'sends_needed', greatest(0, rung.daily_limit - measured.real_sent),
        'quality_ok',
            100.0 * measured.hard_bounces < coalesce(hard_bounce_pause, 2.0) * greatest(measured.real_sent, 1)
            and 100.0 * measured.complaints < coalesce(complaint_pause, 0.1) * greatest(measured.real_sent, 1)
    );
end;
$$;

alter function "public"."get_marketing_warmup_progress"(uuid) owner to "postgres";
revoke all on function "public"."get_marketing_warmup_progress"(uuid) from public, anon, authenticated;
grant execute on function "public"."get_marketing_warmup_progress"(uuid) to "service_role";


-- ---------------------------------------------------------------------------------------------------
-- Marketing claim: earned warm-up, and a capped organization no longer starves others
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."claim_marketing_campaign_recipient"()
returns table(
    "recipient_id" uuid,
    "campaign_id" uuid,
    "organization_id" uuid,
    "claim_token" uuid,
    "client_id" uuid,
    "client_contact_method_id" uuid,
    "recipient_email" text,
    "display_name" text
)
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    candidate record;
    new_claim_token uuid;
    marketing_domain public.communication_email_domains;
    warmup_ceiling integer;
    warmup_used_today integer;
    blocked_reason text;
    organization_capped boolean;
    today_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
begin
    if exists (
        select 1 from public.communication_email_sending_pauses
        where scope = 'platform' and released_at is null
    ) then
        return;
    end if;

    -- A campaign scheduled for a moment that has now arrived starts sending exactly the way an immediate
    -- launch already does; nothing else needs to change for it to become claimable.
    update public.marketing_campaigns
    set status = 'sending'
    where status = 'scheduled' and scheduled_for <= now();

    -- Each pass that caps an organization starts the candidate query again without it, so one call can still
    -- reach a later organization's recipient. Bounded: each pass removes one organization.
    for pass in 1..5 loop
        organization_capped := false;
        for candidate in
            select
                recipient.id as recipient_id,
                recipient.campaign_id,
                recipient.organization_id,
                recipient.client_id,
                recipient.client_contact_method_id,
                recipient.recipient_email,
                recipient.display_name
            from public.marketing_campaign_recipients recipient
            join public.marketing_campaigns campaign
                on campaign.id = recipient.campaign_id and campaign.organization_id = recipient.organization_id
            where campaign.status = 'sending' and recipient.status = 'waiting'
                -- Organization-wide holds are filtered here rather than skipped inside the loop: a held
                -- organization's queue ahead of everyone else's would otherwise fill all 50 candidate slots and
                -- starve every other organization's campaigns until the hold lifted.
                and not exists (
                    select 1 from public.organizations org
                    where org.id = recipient.organization_id and org.lifecycle_status = 'suspended'
                )
                and not exists (
                    select 1 from public.organization_closure_records closure
                    where closure.organization_id = recipient.organization_id
                        and closure.status in ('pending_closure', 'purge_in_progress')
                )
                -- Every live organization pause holds Marketing: manual, the operational reputation pause, and
                -- the Marketing-only reputation pause.
                and not exists (
                    select 1 from public.communication_email_sending_pauses pause
                    where pause.scope = 'organization'
                        and pause.organization_id = recipient.organization_id
                        and pause.released_at is null
                )
                -- An organization that reached today's warm-up limit waits for the next UTC day here rather than
                -- inside the loop, for the same reason: its queue would otherwise fill every candidate slot.
                and not exists (
                    select 1 from public.marketing_warmup_state warmup
                    where warmup.organization_id = recipient.organization_id
                        and warmup.capped_until > now()
                )
                and exists (
                    select 1 from public.communication_email_domains domain
                    where domain.organization_id = recipient.organization_id
                        and domain.purpose = 'marketing_sending'
                        and domain.lifecycle_state = 'verified'
                )
            order by campaign.launched_at, recipient.created_at, recipient.id
            limit 50
            for update of recipient skip locked
        loop
            blocked_reason := private.marketing_recipient_blocked_reason(
                candidate.organization_id, candidate.client_id, candidate.client_contact_method_id,
                candidate.recipient_email
            );
            if blocked_reason is not null then
                update public.marketing_campaign_recipients
                set status = 'excluded', excluded_reason = blocked_reason, updated_at = now()
                where id = candidate.recipient_id;
                continue;
            end if;

            marketing_domain := null;
            select domain.* into marketing_domain
            from public.communication_email_domains domain
            where domain.organization_id = candidate.organization_id
                and domain.purpose = 'marketing_sending'
                and domain.lifecycle_state = 'verified';

            if marketing_domain.id is null then
                -- The organization's Marketing identity is no longer ready; try again on the next wake.
                continue;
            end if;

            -- Marketing's own earned warm-up (M6f), never the operational calendar ceiling.
            warmup_ceiling := private.resolve_marketing_warmup_limit(marketing_domain.id, now());
            if warmup_ceiling is not null then
                select count(*) into warmup_used_today
                from public.marketing_campaign_recipients mr
                where mr.organization_id = candidate.organization_id
                    and (
                        (mr.status = 'checking' and mr.claimed_at >= today_start)
                        or (mr.submitted_at is not null and mr.submitted_at >= today_start)
                    );

                if warmup_used_today + 1 > warmup_ceiling then
                    -- Reaching today's limit is the only moment a higher step matters, so it is earned here.
                    if private.try_advance_marketing_warmup(marketing_domain.id, now()) then
                        warmup_ceiling := private.resolve_marketing_warmup_limit(marketing_domain.id, now());
                    end if;

                    if warmup_ceiling is not null and warmup_used_today + 1 > warmup_ceiling then
                        update public.marketing_warmup_state
                        set capped_until = today_start + interval '1 day', updated_at = now()
                        where domain_id = marketing_domain.id
                            and (capped_until is null or capped_until < today_start + interval '1 day');
                        -- Start over without this organization rather than walk the rest of its queue.
                        organization_capped := true;
                        exit;
                    end if;
                end if;
            end if;

            new_claim_token := gen_random_uuid();
            update public.marketing_campaign_recipients
            set status = 'checking', claim_token = new_claim_token, claimed_at = now(),
                attempt_count = attempt_count + 1, updated_at = now()
            where id = candidate.recipient_id;

            recipient_id := candidate.recipient_id;
            campaign_id := candidate.campaign_id;
            organization_id := candidate.organization_id;
            claim_token := new_claim_token;
            client_id := candidate.client_id;
            client_contact_method_id := candidate.client_contact_method_id;
            recipient_email := candidate.recipient_email;
            display_name := candidate.display_name;
            return next;
            return;
        end loop;
        exit when not organization_capped;
    end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Marketing reputation pause: engaging it also steps the warm-up down
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."evaluate_marketing_email_reputation"(
    "p_organization_id" uuid,
    "p_at" timestamptz default now()
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    measured jsonb;
    breach jsonb;
    new_pause_id uuid;
    pause_reason text;
begin
    select coalesce(jsonb_agg(to_jsonb(m) order by m.signal, m.window_key), '[]'::jsonb)
    into measured
    from private.marketing_email_reputation_metrics(p_organization_id, p_at) m;

    select entry into breach
    from jsonb_array_elements(measured) entry
    where entry ->> 'status' = 'pause'
    order by ((entry ->> 'rate')::numeric / nullif((entry ->> 'pause_rate')::numeric, 0)) desc nulls last
    limit 1;

    if breach is null then
        return jsonb_build_object('organization_id', p_organization_id, 'paused', false, 'metrics', measured);
    end if;

    pause_reason := format(
        'Automatic Marketing pause: %s rate %s%% over the %s window is at or above the %s%% threshold (%s of %s recipients).',
        replace(breach ->> 'signal', '_', ' '), breach ->> 'rate',
        case breach ->> 'window_key' when 'rolling_24h' then 'rolling 24-hour' else 'rolling 7-day' end,
        breach ->> 'pause_rate', breach ->> 'event_count', breach ->> 'accepted_recipients'
    );

    -- The partial unique index on (organization_id, source) for live organization pauses makes a concurrent
    -- second drain a no-op instead of a duplicate pause.
    insert into public.communication_email_sending_pauses (
        scope, organization_id, reason, engaged_by_owner_email, source, applies_to, evidence
    ) values (
        'organization', p_organization_id, pause_reason, 'system', 'auto_marketing_reputation', 'marketing',
        jsonb_build_object('signal', breach ->> 'signal', 'window_key', breach ->> 'window_key',
            'rate', (breach ->> 'rate')::numeric, 'pause_rate', (breach ->> 'pause_rate')::numeric,
            'event_count', (breach ->> 'event_count')::bigint,
            'accepted_recipients', (breach ->> 'accepted_recipients')::bigint,
            'evaluated_at', p_at)
    )
    on conflict (organization_id, source) where (scope = 'organization' and released_at is null)
    do nothing
    returning id into new_pause_id;

    if new_pause_id is null then
        return jsonb_build_object('organization_id', p_organization_id, 'paused', true, 'metrics', measured);
    end if;

    insert into public.platform_owner_audit_events (
        actor_owner_email, event_type, target_type, target_key, after_state
    ) values (
        'system', 'communications.marketing_reputation_pause_engaged', 'organization',
        p_organization_id::text,
        jsonb_build_object('pause_id', new_pause_id, 'reason', pause_reason, 'metrics', measured)
    );

    -- A domain that drew a pause gives back one warm-up step (M6f).
    perform private.step_down_marketing_warmup(p_organization_id, 'reputation_pause', p_at);

    return jsonb_build_object('organization_id', p_organization_id, 'paused', true,
        'pause_id', new_pause_id, 'metrics', measured);
end;
$$;
