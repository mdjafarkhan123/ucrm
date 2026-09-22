-- Marketing M4 stage 4: the SES event consumer.
--
-- The dispatcher (stage 3) only knows a send reached SES; this stage drains the provisioned SNS -> SQS
-- pipeline to learn what actually happened afterwards -- delivered, bounced, complained -- and projects that
-- idempotently onto marketing_campaign_recipients. Reused as-is: communication_email_suppressions (already
-- provider-agnostic). Not reused: communication_provider_callback_events, because its provider/channel check
-- constraint is locked to Brevo/Twilio and its delivery_intent_id column is operational-only -- mirrors stage
-- 2's own-table precedent instead of widening a table shaped for something else.
--
-- See Memory/campaigns/marketing-growth/parts/M4.md "Stage 4 decisions" for the full reasoning, including the
-- deliberate choice not to feed marketing bounces into communication_email_reputation_state.

-- ---------------------------------------------------------------------------------------------------
-- The idempotent event log
-- ---------------------------------------------------------------------------------------------------

create table if not exists "public"."marketing_campaign_recipient_events" (
    "id" uuid not null default gen_random_uuid(),
    "provider_event_key" text not null,
    "provider_message_id" text not null,
    "event_kind" text not null,
    "normalized_kind" text,
    "occurred_at" timestamptz,
    "received_at" timestamptz not null default now(),
    "payload" jsonb not null,
    "organization_id" uuid,
    "processed_at" timestamptz,
    "processing_attempts" integer not null default 0,
    "processing_error" text,
    constraint "marketing_campaign_recipient_events_pkey" primary key ("id"),
    constraint "marketing_campaign_recipient_events_provider_event_key_key" unique ("provider_event_key"),
    constraint "marketing_campaign_recipient_events_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete set null,
    constraint "marketing_campaign_recipient_events_event_kind_check"
        check (char_length(trim("event_kind")) >= 1 and char_length(trim("event_kind")) <= 80),
    constraint "marketing_campaign_recipient_events_provider_event_key_check"
        check (char_length(trim("provider_event_key")) >= 1 and char_length(trim("provider_event_key")) <= 300),
    constraint "marketing_campaign_recipient_events_normalized_kind_check"
        check ("normalized_kind" is null or "normalized_kind" = any (array[
            'delivered'::text, 'hard_bounce'::text, 'soft_bounce'::text, 'complaint'::text,
            'rejected'::text, 'delayed'::text, 'sent'::text, 'other'::text
        ])),
    constraint "marketing_campaign_recipient_events_payload_check"
        check (jsonb_typeof("payload") = 'object')
);

-- Backs the batch drain: oldest unprocessed row first, same shape as
-- communication_provider_callback_events_email_unprocessed_idx.
create index if not exists "marketing_campaign_recipient_events_unprocessed_idx"
    on "public"."marketing_campaign_recipient_events" using btree ("received_at", "id")
    where ("processed_at" is null);

comment on table "public"."marketing_campaign_recipient_events" is
    'Idempotent log of raw SES events drained from the SQS pipeline for one recipient send. provider_event_key (ses:<messageId>:<eventType>) is the dedupe key an at-least-once SQS delivery relies on. Service-role only, like communication_provider_callback_events.';

alter table "public"."marketing_campaign_recipient_events" enable row level security;

-- ---------------------------------------------------------------------------------------------------
-- The projector
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."project_marketing_campaign_recipient_events"(
    "batch_size" integer default 200
) returns integer
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    candidate record;
    norm text;
    bounce_kind text;
    processed_count integer := 0;
    max_processing_attempts constant integer := 5;
    recipient public.marketing_campaign_recipients;
    new_status text;
begin
    if batch_size < 1 or batch_size > 2000 then
        raise exception 'The marketing event batch size is outside its safe bounds.'
            using errcode = 'check_violation';
    end if;

    for candidate in
        select event.id, event.event_kind, event.payload, event.occurred_at, event.received_at,
            event.processing_attempts, event.provider_message_id
        from public.marketing_campaign_recipient_events event
        where event.processed_at is null
        order by event.received_at, event.id
        limit batch_size
        for update of event skip locked
    loop
        norm := case candidate.event_kind
            when 'Send' then 'sent'
            when 'Delivery' then 'delivered'
            when 'Complaint' then 'complaint'
            when 'Reject' then 'rejected'
            when 'DeliveryDelay' then 'delayed'
            when 'Bounce' then (
                case candidate.payload -> 'bounce' ->> 'bounceType'
                    when 'Permanent' then 'hard_bounce'
                    else 'soft_bounce'
                end
            )
            else 'other'
        end;

        begin
            select * into recipient
            from public.marketing_campaign_recipients
            where provider_message_id = candidate.provider_message_id
            for update;

            if not found then
                -- The event arrived before the recipient's own finalize commit became visible, or names a
                -- message id this database never sent (a stray test send). Left unprocessed to retry on the
                -- next drain, capped like the operational processor so a permanently unknown id cannot spin
                -- forever.
                if candidate.processing_attempts + 1 >= max_processing_attempts then
                    update public.marketing_campaign_recipient_events
                    set processed_at = now(), normalized_kind = norm,
                        processing_attempts = candidate.processing_attempts + 1,
                        processing_error = 'No marketing_campaign_recipients row matches this provider_message_id.'
                    where id = candidate.id;
                else
                    update public.marketing_campaign_recipient_events
                    set processing_attempts = candidate.processing_attempts + 1
                    where id = candidate.id;
                end if;
                continue;
            end if;

            if norm = 'delivered' then
                update public.marketing_campaign_recipients
                set status = 'delivered', updated_at = now()
                where id = recipient.id and status not in ('bounced', 'complained', 'unsubscribed');
            elsif norm in ('hard_bounce', 'complaint') then
                new_status := case norm when 'hard_bounce' then 'bounced' else 'complained' end;
                update public.marketing_campaign_recipients
                set status = new_status, failure_code = 'ses_' || norm, updated_at = now()
                where id = recipient.id and status <> 'unsubscribed';

                bounce_kind := case norm when 'hard_bounce' then 'hard_bounce' else 'complaint' end;
                insert into public.communication_email_suppressions (
                    organization_id, recipient_email, reason, source, evidence
                ) values (
                    recipient.organization_id, recipient.recipient_email, bounce_kind, 'provider_callback',
                    jsonb_build_object(
                        'event_kind', candidate.event_kind,
                        'occurred_at', candidate.occurred_at,
                        'received_at', candidate.received_at,
                        'campaign_id', recipient.campaign_id,
                        'marketing_campaign_recipient_id', recipient.id
                    )
                )
                on conflict (organization_id, recipient_email, reason) where released_at is null
                do nothing;
            elsif norm = 'rejected' then
                update public.marketing_campaign_recipients
                set status = 'failed', failure_code = 'ses_reject', updated_at = now()
                where id = recipient.id and status not in ('bounced', 'complained', 'unsubscribed');
            end if;
            -- soft_bounce, delayed, sent, other: logged only, SES retries a soft bounce on its own.

            update public.marketing_campaign_recipient_events
            set processed_at = now(), normalized_kind = norm, organization_id = recipient.organization_id
            where id = candidate.id;
            processed_count := processed_count + 1;
        exception
            when others then
                update public.marketing_campaign_recipient_events
                set processing_attempts = coalesce(processing_attempts, 0) + 1,
                    processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
                    normalized_kind = coalesce(normalized_kind, norm),
                    processed_at = case
                        when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
                        else processed_at
                    end
                where id = candidate.id;
        end;
    end loop;

    return processed_count;
end;
$$;

alter function "public"."project_marketing_campaign_recipient_events"(integer) owner to "postgres";

comment on function "public"."project_marketing_campaign_recipient_events"(integer) is
    'Bounded drain of unprocessed marketing_campaign_recipient_events rows. bounced and complained are sticky (never overwritten by a later event); a soft bounce and a delivery delay leave status alone since SES retries them on its own. Service role only.';

revoke all on function "public"."project_marketing_campaign_recipient_events"(integer)
    from public, anon, authenticated;
grant all on function "public"."project_marketing_campaign_recipient_events"(integer) to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- Cron dispatch
-- ---------------------------------------------------------------------------------------------------

-- Same shape as dispatch_communication_marketing_worker_wake. Installed but inert until Jafar sets the
-- 'communications_marketing_events_worker_target_url' Vault secret once the worker route is deployed, and the
-- AWS_SES_* values (stage 1's remaining blocker) are in place.
create or replace function "public"."dispatch_communication_marketing_events_worker_wake"() returns void
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    v_worker_name constant text := 'communications-marketing-events';
    v_job_name constant text := 'communications-marketing-events-wake-one-minute';
    v_correlation uuid := gen_random_uuid();
    v_target_url text;
    v_bearer text;
    v_request_id bigint;
begin
    select decrypted_secret into v_target_url
    from vault.decrypted_secrets
    where name = 'communications_marketing_events_worker_target_url';
    select decrypted_secret into v_bearer
    from vault.decrypted_secrets
    where name = 'communications_worker_secret';

    if v_target_url is null or v_bearer is null then
        raise exception 'The communications marketing events worker cron target url or bearer secret is not configured.'
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

alter function "public"."dispatch_communication_marketing_events_worker_wake"() owner to "postgres";

comment on function "public"."dispatch_communication_marketing_events_worker_wake"() is
    'Cron entry point: records a wake, calls the protected marketing-events-worker route via pg_net, prunes old ledger rows. Installed inert until the communications_marketing_events_worker_target_url Vault secret and the AWS_SES_* values are set.';

revoke all on function "public"."dispatch_communication_marketing_events_worker_wake"() from public;
grant all on function "public"."dispatch_communication_marketing_events_worker_wake"() to "service_role";

select cron.schedule(
    'communications-marketing-events-wake-one-minute',
    '* * * * *',
    $job$select public.dispatch_communication_marketing_events_worker_wake();$job$
);
