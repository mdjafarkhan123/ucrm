-- Marketing M4 stage 5: cancelling a campaign that is scheduled or already sending.
--
-- Cancel stops UCRM's own unreleased work; it never claims to recall a message SES already accepted
-- (blueprint §7, §9). claim_marketing_campaign_recipient only ever claims from a campaign whose status is
-- 'sending', so flipping the campaign row to 'cancelled' is already enough to stop every future claim -- this
-- function only additionally needs to (1) turn the frozen-but-unclaimed 'waiting' recipients into 'cancelled'
-- so the results page can tell them apart from the ones that never existed, and (2) settle the campaign's
-- single Marketing allowance reservation now that no more of it will ever be spent, the same settlement
-- finalize_marketing_campaign_send already does when a campaign finishes on its own.
--
-- A recipient already 'checking' (claimed by the dispatcher in the moment before cancel) is left alone: it is
-- genuinely in flight and must reach its real provider outcome, not be overwritten. If any such recipient
-- exists when cancel runs, settlement is deferred to finalize_marketing_campaign_send, which is widened below
-- to also settle a 'cancelled' campaign's reservation once nothing is left waiting or checking -- it already
-- did the equivalent for 'sending' -> 'completed'.

alter table "public"."marketing_campaigns"
    add column if not exists "cancelled_at" timestamptz,
    add column if not exists "cancelled_by" uuid;

comment on column "public"."marketing_campaigns"."cancelled_at" is
    'Set once, by marketing_cancel_campaign. Never cleared -- a cancelled campaign is historical, the same as a completed one.';

-- ---------------------------------------------------------------------------------------------------
-- Cancel
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."marketing_cancel_campaign"(
    "target_organization_id" uuid,
    "target_campaign_id" uuid,
    "actor_user_id" uuid
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $_$
declare
    campaign_row public.marketing_campaigns;
    newly_cancelled_count integer;
    in_flight_count integer;
    submitted_count integer;
begin
    select * into campaign_row
    from public.marketing_campaigns
    where id = target_campaign_id and organization_id = target_organization_id
    for update;

    if campaign_row.id is null then
        raise exception 'This campaign no longer exists.' using errcode = 'check_violation';
    end if;

    -- A second cancel (a double click, a second tab) finds nothing left to change and simply reports the
    -- campaign's current counts rather than failing -- the button's own visibility already keeps this rare.
    if campaign_row.status = 'cancelled' then
        select
            count(*) filter (where status = 'checking'),
            count(*) filter (where status = 'submitted')
        into in_flight_count, submitted_count
        from public.marketing_campaign_recipients
        where campaign_id = target_campaign_id;

        return jsonb_build_object(
            'campaign_id', campaign_row.id,
            'status', 'cancelled',
            'cancelled_at', campaign_row.cancelled_at,
            'cancelled_count', 0,
            'in_flight_count', in_flight_count,
            'submitted_count', submitted_count
        );
    end if;

    if campaign_row.status not in ('scheduled', 'sending') then
        raise exception 'This campaign is not something that can be cancelled right now.'
            using errcode = 'check_violation';
    end if;

    update public.marketing_campaigns
    set status = 'cancelled', cancelled_at = now(), cancelled_by = actor_user_id, updated_by = actor_user_id
    where id = target_campaign_id
    returning * into campaign_row;

    update public.marketing_campaign_recipients
    set status = 'cancelled', updated_at = now()
    where campaign_id = target_campaign_id and status = 'waiting';
    get diagnostics newly_cancelled_count = row_count;

    select
        count(*) filter (where status = 'checking'),
        count(*) filter (where status = 'submitted')
    into in_flight_count, submitted_count
    from public.marketing_campaign_recipients
    where campaign_id = target_campaign_id;

    -- Nothing is still being sent, so this is the only settlement this campaign will ever get. Otherwise the
    -- last in-flight recipient's own finalize call settles it (see the widened guard below).
    if in_flight_count = 0 then
        update public.marketing_email_capacity_reservations
        set reservation_state = 'settled', accepted_count = submitted_count, settled_at = now()
        where campaign_id = target_campaign_id and reservation_state = 'reserved';
    end if;

    return jsonb_build_object(
        'campaign_id', campaign_row.id,
        'status', campaign_row.status,
        'cancelled_at', campaign_row.cancelled_at,
        'cancelled_count', newly_cancelled_count,
        'in_flight_count', in_flight_count,
        'submitted_count', submitted_count
    );
end;
$_$;

alter function "public"."marketing_cancel_campaign"(uuid, uuid, uuid) owner to "postgres";

comment on function "public"."marketing_cancel_campaign"(uuid, uuid, uuid) is
    'Cancels a scheduled or sending campaign: stops new claims (by leaving the campaign row not "sending"), turns its still-waiting recipients into "cancelled", and settles the Marketing allowance reservation once nothing is left in flight. A recipient already claimed keeps sending to its real outcome. Idempotent: cancelling an already-cancelled campaign reports its current counts instead of failing. The marketing.launch permission is enforced by the calling route, as with every other marketing command.';

revoke all on function "public"."marketing_cancel_campaign"(uuid, uuid, uuid) from public, anon, authenticated;
grant all on function "public"."marketing_cancel_campaign"(uuid, uuid, uuid) to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- Widen finalize_marketing_campaign_send's settlement guard to also cover a campaign cancelled while one of
-- its recipients was still 'checking' -- unchanged in every other respect.
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
        -- A cancelled campaign stays cancelled; only a 'sending' one completes. Either way, once nothing is
        -- left waiting or in flight, this recipient's own finalize is the only thing that could still settle
        -- the reservation -- covering the case marketing_cancel_campaign left open, a recipient still
        -- 'checking' at the moment of cancel.
        update public.marketing_campaigns
        set status = case when status = 'sending' then 'completed' else status end,
            updated_at = now()
        where id = claimed_recipient.campaign_id and status in ('sending', 'cancelled')
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
    'Records one claimed recipient''s provider outcome. A retry goes back to waiting until the third attempt, then fails permanently -- there is no per-row backoff clock, so an unbounded retry would spin every wake. Settles the campaign''s single allowance reservation the moment its last recipient leaves waiting/checking, whether the campaign finishes on its own (sending -> completed) or was cancelled mid-flight (stays cancelled).';

revoke all on function "public"."finalize_marketing_campaign_send"(uuid, uuid, text, text, text, text)
    from public, anon, authenticated;
grant all on function "public"."finalize_marketing_campaign_send"(uuid, uuid, text, text, text, text)
    to "service_role";
