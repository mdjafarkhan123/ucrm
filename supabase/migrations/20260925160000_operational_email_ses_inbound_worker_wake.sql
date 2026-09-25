-- Operational email SES Part 4: cron dispatch for the customer-reply inbound drain worker.
--
-- Same shape as dispatch_communication_marketing_events_worker_wake: installed but inert until Jafar sets the
-- 'communications_ses_inbound_worker_target_url' Vault secret once the worker route is deployed. Deliberately
-- its own one-minute job and worker name, kept separate from the marketing/operational delivery-events wake so
-- a stuck reply drain can never delay outgoing mail's event processing and vice versa.

create or replace function "public"."dispatch_communication_ses_inbound_worker_wake"() returns void
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    v_worker_name constant text := 'communications-ses-inbound';
    v_job_name constant text := 'communications-ses-inbound-wake-one-minute';
    v_correlation uuid := gen_random_uuid();
    v_target_url text;
    v_bearer text;
    v_request_id bigint;
begin
    select decrypted_secret into v_target_url
    from vault.decrypted_secrets
    where name = 'communications_ses_inbound_worker_target_url';
    select decrypted_secret into v_bearer
    from vault.decrypted_secrets
    where name = 'communications_worker_secret';

    if v_target_url is null or v_bearer is null then
        raise exception 'The SES inbound worker cron target url or bearer secret is not configured.'
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

alter function "public"."dispatch_communication_ses_inbound_worker_wake"() owner to "postgres";

comment on function "public"."dispatch_communication_ses_inbound_worker_wake"() is
    'Cron entry point: records a wake, calls the protected ses-inbound-worker route via pg_net, prunes old ledger rows. Installed inert until the communications_ses_inbound_worker_target_url Vault secret is set and customer replies are activated for at least one organization.';

revoke all on function "public"."dispatch_communication_ses_inbound_worker_wake"() from public;
grant all on function "public"."dispatch_communication_ses_inbound_worker_wake"() to "service_role";

select cron.schedule(
    'communications-ses-inbound-wake-one-minute',
    '* * * * *',
    $job$select public.dispatch_communication_ses_inbound_worker_wake();$job$
);
