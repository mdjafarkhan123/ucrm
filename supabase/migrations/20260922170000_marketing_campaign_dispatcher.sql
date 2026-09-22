-- Marketing M4 stage 3: the Marketing dispatcher.
--
-- A launched campaign leaves marketing_launch_campaign as a frozen list of 'waiting' recipients. This stage
-- adds the claim/finalize RPC pair that actually sends them through Amazon SES, one at a time, safely shared
-- with every other organization's campaigns -- the same competing-consumer shape as the operational email
-- outbox (claim_communication_outbox_event / finalize_communication_outbox_event), simplified because a
-- campaign's whole audience is already frozen and its Marketing allowance was already reserved at launch.
-- What is genuinely reused, not reinvented: communication_email_suppressions, communication_email_sending_
-- pauses, communication_email_warmup_stages (read via the existing private.resolve_communication_email_
-- warmup_ceiling), and the generic worker lease/wake-ledger functions (acquire/release_communication_worker_
-- lease, record_communication_worker_wake_result) -- all already keyed by a free-form worker_name, not by
-- channel, so nothing about them needed to change.
--
-- No available_at/backoff schedule exists here on purpose: marketing sends are not time-sensitive the way a
-- receipt or reminder is, so a recipient that cannot be sent right now (an organization-level pause, a
-- domain that dropped out of verification, a warmup ceiling) is simply left 'waiting' and picked up again on
-- the next one-minute wake, instead of carrying its own per-row retry clock.

-- ---------------------------------------------------------------------------------------------------
-- marketing_campaign_recipients: claim/finalize columns
-- ---------------------------------------------------------------------------------------------------

alter table "public"."marketing_campaign_recipients"
    add column if not exists "claim_token" uuid,
    add column if not exists "claimed_at" timestamptz,
    add column if not exists "attempt_count" integer not null default 0,
    add column if not exists "submitted_at" timestamptz,
    add column if not exists "provider_message_id" text,
    add column if not exists "failure_code" text,
    add column if not exists "failure_message" text;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'marketing_campaign_recipients_attempt_count_check'
    ) then
        alter table "public"."marketing_campaign_recipients"
            add constraint "marketing_campaign_recipients_attempt_count_check" check ("attempt_count" >= 0);
    end if;

    if not exists (
        select 1 from pg_constraint where conname = 'marketing_campaign_recipients_claim_check'
    ) then
        -- Mirrors communication_outbox_events_claim_check: a row is 'checking' exactly when it carries a live
        -- claim, so a stray claim_token can never linger on a row that finished, and a 'checking' row can
        -- never be missing the identity a finalize call must match.
        alter table "public"."marketing_campaign_recipients"
            add constraint "marketing_campaign_recipients_claim_check"
            check (("status" = 'checking') = ("claimed_at" is not null and "claim_token" is not null));
    end if;
end
$$;

-- 'submission_unknown' is what a quarantined claim becomes: the worker vanished after asking SES to send and
-- before this row could be finalized, so whether SES actually took it is genuinely unknown and must never be
-- retried blindly (a real accept plus a blind retry is a duplicate send to a real customer). This mirrors why
-- communication_outbox_events keeps 'submission_unknown' distinct from 'failed' rather than reusing it.
alter table "public"."marketing_campaign_recipients"
    drop constraint "marketing_campaign_recipients_status_check";

alter table "public"."marketing_campaign_recipients"
    add constraint "marketing_campaign_recipients_status_check"
    check ("status" = any (array[
        'waiting'::text, 'submitted'::text, 'delivered'::text, 'bounced'::text, 'complained'::text,
        'unsubscribed'::text, 'cancelled'::text, 'failed'::text, 'checking'::text, 'excluded'::text,
        'submission_unknown'::text
    ]));

-- Backs quarantine's scan for abandoned claims.
create index if not exists "marketing_campaign_recipients_checking_idx"
    on "public"."marketing_campaign_recipients" using btree ("claimed_at")
    where ("status" = 'checking');

-- Backs the warmup ceiling's "how many has this organization sent today" count. submitted_at is set once at
-- finalize and is never cleared by a later delivery/bounce/complaint projection (stage 4), so this stays a
-- correct count of what was actually asked of SES today even after a row's status moves on.
create index if not exists "marketing_campaign_recipients_org_submitted_idx"
    on "public"."marketing_campaign_recipients" using btree ("organization_id", "submitted_at")
    where ("submitted_at" is not null);

comment on column "public"."marketing_campaign_recipients"."attempt_count" is
    'Claim attempts so far. finalize_marketing_campaign_send gives up (status=failed) after 3 rather than retrying forever, since there is no per-row backoff clock to space attempts out.';

comment on column "public"."marketing_campaign_recipients"."submitted_at" is
    'Set once, when SES accepts the send. Never cleared by a later delivery/bounce/complaint status change, so it stays the correct answer to "did this count against today''s warmup ceiling and this campaign''s allowance reservation".';

-- ---------------------------------------------------------------------------------------------------
-- marketing_campaigns: indexes the dispatcher's cross-organization scan needs
-- ---------------------------------------------------------------------------------------------------

-- The dispatcher looks across every organization's 'sending' campaigns at once (it is one shared worker, not
-- one per organization), so it needs a global index on status -- marketing_campaigns_org_status_created_idx
-- is scoped to one organization and does not serve that.
create index if not exists "marketing_campaigns_dispatch_status_idx"
    on "public"."marketing_campaigns" using btree ("status")
    where ("status" = any (array['sending'::text, 'scheduled'::text]));

create index if not exists "marketing_campaigns_scheduled_due_idx"
    on "public"."marketing_campaigns" using btree ("scheduled_for")
    where ("status" = 'scheduled');

-- ---------------------------------------------------------------------------------------------------
-- Per-recipient eligibility recheck
-- ---------------------------------------------------------------------------------------------------

-- A campaign's audience is frozen at launch, but a customer can still unsubscribe, complain, or be archived
-- before their turn to actually send comes up (a 50,000-row campaign can take a while to drain). This checks
-- exactly the same facts and in the same priority order as private.marketing_evaluated_recipients_sql's
-- per-row CTE, so a recipient who would be excluded from a launch today is excluded from a send today too --
-- just against the one client/method/email this row already froze, not a freshly re-evaluated rule.
create or replace function "private"."marketing_recipient_blocked_reason"(
    "p_organization_id" uuid,
    "p_client_id" uuid,
    "p_client_contact_method_id" uuid,
    "p_recipient_email" text
) returns text
    language sql stable security definer
    set search_path to 'pg_catalog', 'public'
    as $$
    select
        case
            when client.archived_at is not null then 'inactive_customer'
            when method.id is null
                or method.kind <> 'email'
                or method.client_id <> p_client_id
                or method.normalized_value <> p_recipient_email then 'missing_email'
            when consent.state = 'opted_out' and event.source = 'complaint' then 'complaint'
            when consent.state = 'opted_out' then 'unsubscribed'
            when suppression.reason = 'complaint' then 'complaint'
            when suppression.reason = 'hard_bounce' then 'hard_bounce'
            when preference.contact_policy = 'do_not_disturb' then 'do_not_disturb'
            when preference.contact_policy = 'no_marketing' then 'no_marketing'
            when consent.state is distinct from 'opted_in' then 'no_consent'
            else null
        end
    from public.clients client
    left join public.client_contact_methods method
        on method.organization_id = p_organization_id and method.id = p_client_contact_method_id
    left join public.client_marketing_consent_state consent
        on consent.organization_id = p_organization_id
        and consent.client_contact_method_id = p_client_contact_method_id
    left join public.client_marketing_consent_events event
        on event.organization_id = consent.organization_id and event.id = consent.source_event_id
    left join public.client_communication_preferences preference
        on preference.organization_id = p_organization_id and preference.client_id = p_client_id
    left join lateral (
        select active.reason
        from public.communication_email_suppressions active
        where active.organization_id = p_organization_id
            and active.recipient_email = p_recipient_email
            and active.released_at is null
        order by case active.reason when 'complaint' then 0 else 1 end
        limit 1
    ) suppression on true
    where client.organization_id = p_organization_id and client.id = p_client_id;
$$;

alter function "private"."marketing_recipient_blocked_reason"(uuid, uuid, uuid, text) owner to "postgres";

revoke all on function "private"."marketing_recipient_blocked_reason"(uuid, uuid, uuid, text)
    from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- Claim
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
        order by campaign.launched_at, recipient.created_at, recipient.id
        limit 50
        for update of recipient skip locked
    loop
        if exists (
            select 1 from public.organizations org
            where org.id = candidate.organization_id and org.lifecycle_status = 'suspended'
        ) or exists (
            select 1 from public.organization_closure_records closure
            where closure.organization_id = candidate.organization_id
                and closure.status in ('pending_closure', 'purge_in_progress')
        ) or exists (
            select 1 from public.communication_email_sending_pauses pause
            where pause.scope = 'organization'
                and pause.organization_id = candidate.organization_id
                and pause.released_at is null
        ) then
            -- Left 'waiting' on purpose: the next one-minute wake tries again once the hold lifts.
            continue;
        end if;

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

        warmup_ceiling := private.resolve_communication_email_warmup_ceiling(
            candidate.organization_id, marketing_domain.id, now());
        if warmup_ceiling is not null then
            select count(*) into warmup_used_today
            from public.marketing_campaign_recipients mr
            where mr.organization_id = candidate.organization_id
                and (
                    (mr.status = 'checking' and mr.claimed_at >= today_start)
                    or (mr.submitted_at is not null and mr.submitted_at >= today_start)
                );

            if warmup_used_today + 1 > warmup_ceiling then
                continue;
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
end;
$$;

alter function "public"."claim_marketing_campaign_recipient"() owner to "postgres";

comment on function "public"."claim_marketing_campaign_recipient"() is
    'Claims exactly one waiting recipient from any organization''s sending campaign, rechecking consent/suppression/pause/warmup at claim time. Returns no rows when nothing is claimable right now.';

revoke all on function "public"."claim_marketing_campaign_recipient"() from public, anon, authenticated;
grant all on function "public"."claim_marketing_campaign_recipient"() to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- Finalize
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."finalize_marketing_campaign_send"(
    "target_recipient_id" uuid,
    "target_claim_token" uuid,
    "target_outcome" text,
    "target_provider_message_id" text default null,
    "target_failure_code" text default null,
    "target_failure_message" text default null
) returns table("recipient_status" text, "campaign_status" text)
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    claimed_recipient public.marketing_campaign_recipients;
    max_attempts constant integer := 3;
    new_status text;
    remaining_count integer;
    accepted_send_count integer;
    completed_campaign public.marketing_campaigns;
begin
    if target_outcome not in ('submitted', 'retry', 'cancelled', 'submission_unknown') then
        raise exception 'The marketing send outcome is invalid.' using errcode = 'check_violation';
    end if;

    select * into claimed_recipient
    from public.marketing_campaign_recipients
    where id = target_recipient_id
    for update;

    if not found then
        raise exception 'The marketing campaign recipient does not exist.' using errcode = 'no_data_found';
    end if;

    if claimed_recipient.status <> 'checking'
        or claimed_recipient.claim_token is distinct from target_claim_token then
        raise exception 'The marketing claim is no longer current.'
            using errcode = 'object_not_in_prerequisite_state';
    end if;

    if target_outcome = 'submitted' then
        if nullif(trim(target_provider_message_id), '') is null then
            raise exception 'A submitted marketing email requires a provider message identifier.'
                using errcode = 'not_null_violation';
        end if;
        new_status := 'submitted';
        update public.marketing_campaign_recipients
        set status = 'submitted', provider_message_id = trim(target_provider_message_id), submitted_at = now(),
            claim_token = null, claimed_at = null, failure_code = null, failure_message = null, updated_at = now()
        where id = claimed_recipient.id;
    elsif target_outcome = 'retry' then
        new_status := case when claimed_recipient.attempt_count >= max_attempts then 'failed' else 'waiting' end;
        update public.marketing_campaign_recipients
        set status = new_status, claim_token = null, claimed_at = null,
            failure_code = nullif(trim(target_failure_code), ''),
            failure_message = nullif(trim(target_failure_message), ''), updated_at = now()
        where id = claimed_recipient.id;
    elsif target_outcome = 'submission_unknown' then
        new_status := 'submission_unknown';
        update public.marketing_campaign_recipients
        set status = 'submission_unknown', claim_token = null, claimed_at = null,
            failure_code = coalesce(nullif(trim(target_failure_code), ''), 'worker_submission_unknown'),
            failure_message = nullif(trim(target_failure_message), ''), updated_at = now()
        where id = claimed_recipient.id;
    else
        new_status := 'cancelled';
        update public.marketing_campaign_recipients
        set status = 'cancelled', claim_token = null, claimed_at = null,
            failure_code = nullif(trim(target_failure_code), ''),
            failure_message = nullif(trim(target_failure_message), ''), updated_at = now()
        where id = claimed_recipient.id;
    end if;

    -- A campaign is done, win or lose, once nothing of its audience is still waiting or in flight. Checked
    -- cheaply first, without a lock, then re-checked under the campaign row's lock so two recipients
    -- finishing at the same instant cannot both try to complete and settle the same campaign.
    select count(*) into remaining_count
    from public.marketing_campaign_recipients
    where campaign_id = claimed_recipient.campaign_id and status in ('waiting', 'checking');

    if remaining_count = 0 then
        update public.marketing_campaigns
        set status = 'completed', updated_at = now()
        where id = claimed_recipient.campaign_id and status = 'sending'
        returning * into completed_campaign;

        if found then
            select count(*) into accepted_send_count
            from public.marketing_campaign_recipients
            where campaign_id = completed_campaign.id and status = 'submitted';

            update public.marketing_email_capacity_reservations reservation
            set reservation_state = 'settled', accepted_count = accepted_send_count, settled_at = now()
            where reservation.campaign_id = completed_campaign.id and reservation.reservation_state = 'reserved';
        end if;
    end if;

    return query
    select new_status, campaign.status
    from public.marketing_campaigns campaign
    where campaign.id = claimed_recipient.campaign_id;
end;
$$;

alter function "public"."finalize_marketing_campaign_send"(uuid, uuid, text, text, text, text) owner to "postgres";

comment on function "public"."finalize_marketing_campaign_send"(uuid, uuid, text, text, text, text) is
    'Records one claimed recipient''s provider outcome. A retry goes back to waiting until the third attempt, then fails permanently -- there is no per-row backoff clock, so an unbounded retry would spin every wake. Settles the campaign''s single allowance reservation the moment its last recipient leaves waiting/checking.';

revoke all on function "public"."finalize_marketing_campaign_send"(uuid, uuid, text, text, text, text)
    from public, anon, authenticated;
grant all on function "public"."finalize_marketing_campaign_send"(uuid, uuid, text, text, text, text)
    to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- Quarantine
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."quarantine_stale_marketing_campaign_claims"(
    "batch_size" integer default 50,
    "stale_after" interval default '00:15:00'::interval
) returns integer
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    quarantined_count integer;
begin
    if batch_size < 1 or batch_size > 100 then
        raise exception 'The stale marketing claim batch is outside its safe bounds.' using errcode = 'check_violation';
    end if;
    if stale_after < interval '1 minute' or stale_after > interval '1 day' then
        raise exception 'The stale marketing claim threshold is outside its safe bounds.' using errcode = 'check_violation';
    end if;

    with stale as (
        select id from public.marketing_campaign_recipients
        where status = 'checking' and claimed_at <= now() - stale_after
        order by claimed_at, id
        limit batch_size
        for update skip locked
    )
    update public.marketing_campaign_recipients recipient
    set status = 'submission_unknown', claim_token = null, claimed_at = null,
        failure_code = 'worker_lease_expired',
        failure_message = 'The worker lease expired before its provider outcome was recorded.',
        updated_at = now()
    from stale
    where recipient.id = stale.id;

    get diagnostics quarantined_count = row_count;
    return quarantined_count;
end;
$$;

alter function "public"."quarantine_stale_marketing_campaign_claims"(integer, interval) owner to "postgres";

comment on function "public"."quarantine_stale_marketing_campaign_claims"(integer, interval) is
    'Releases claims abandoned by a crashed worker into submission_unknown, never back into waiting -- SES may have already accepted the send, so a blind retry risks a duplicate.';

revoke all on function "public"."quarantine_stale_marketing_campaign_claims"(integer, interval)
    from public, anon, authenticated;
grant all on function "public"."quarantine_stale_marketing_campaign_claims"(integer, interval)
    to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- Cron dispatch
-- ---------------------------------------------------------------------------------------------------

-- Same shape as dispatch_communication_email_outbox_wake / dispatch_communication_sms_outbox_wake: reads its
-- target URL and the shared worker bearer secret from Vault, wakes the worker route over pg_net, and prunes
-- its own ledger history. The schedule below is installed but inert -- like the SMS job before its own launch
-- gate -- until Jafar sets the 'communications_marketing_worker_target_url' Vault secret once the worker
-- route is deployed and the AWS_SES_* values (Stage 1's remaining blocker) are in place. Until then it raises
-- a cheap, harmless "not configured" error once a minute.
create or replace function "public"."dispatch_communication_marketing_worker_wake"() returns void
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    v_worker_name constant text := 'communications-marketing-outbox';
    v_job_name constant text := 'communications-marketing-outbox-wake-one-minute';
    v_correlation uuid := gen_random_uuid();
    v_target_url text;
    v_bearer text;
    v_request_id bigint;
begin
    select decrypted_secret into v_target_url
    from vault.decrypted_secrets
    where name = 'communications_marketing_worker_target_url';
    select decrypted_secret into v_bearer
    from vault.decrypted_secrets
    where name = 'communications_worker_secret';

    if v_target_url is null or v_bearer is null then
        raise exception 'The communications marketing worker cron target url or bearer secret is not configured.'
            using errcode = 'no_data_found';
    end if;

    select net.http_post(
        url := v_target_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_bearer,
            'X-Wake-Correlation-Id', v_correlation::text
        ),
        body := jsonb_build_object('wake_correlation_id', v_correlation),
        timeout_milliseconds := 50000
    ) into v_request_id;

    perform public.record_communication_worker_wake_dispatch(v_worker_name, v_job_name, v_correlation, v_request_id);

    delete from private.communication_worker_wake_ledger
    where worker_name = v_worker_name
        and dispatched_at < now() - interval '7 days';
end;
$$;

alter function "public"."dispatch_communication_marketing_worker_wake"() owner to "postgres";

comment on function "public"."dispatch_communication_marketing_worker_wake"() is
    'Cron entry point: records a wake, calls the protected marketing-worker route via pg_net, prunes old ledger rows. Installed inert until the communications_marketing_worker_target_url Vault secret and the AWS_SES_* values are set.';

revoke all on function "public"."dispatch_communication_marketing_worker_wake"() from public;
grant all on function "public"."dispatch_communication_marketing_worker_wake"() to "service_role";

select cron.schedule(
    'communications-marketing-outbox-wake-one-minute',
    '* * * * *',
    $job$select public.dispatch_communication_marketing_worker_wake();$job$
);
