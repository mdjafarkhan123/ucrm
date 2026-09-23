-- Marketing M5c: read functions the campaign detail page's Overview and Results tabs call.
--
-- No new tables. Everything here reads marketing_campaign_recipients, marketing_campaign_result_credits
-- (M5a/M5b), and the existing invoice chain (invoice_sources, invoice_payment_allocations) that already backs
-- the accounts-receivable report's own "money actually applied to an invoice" arithmetic
-- (sum(applied) - sum(unapplied) from invoice_payment_allocations, see private.client_financial_report).
-- Campaign revenue never invents a payment from quoted value (blueprint §12): it is this same real-money sum.

-- ---------------------------------------------------------------------------------------------------
-- 1. Recipient status counts for the Overview tab's five buckets (Waiting, Submitted, Delivered,
--    Failed/Excluded, Cancelled) and the Results tab's delivered/bounced/complained/unsubscribed/opened/
--    clicked breakdown. One indexed scan of this campaign's own recipient rows.
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."marketing_campaign_recipient_counts"(
    "target_organization_id" uuid,
    "target_campaign_id" uuid
) returns table(
    "waiting_count" bigint,
    "submitted_count" bigint,
    "delivered_count" bigint,
    "failed_count" bigint,
    "excluded_count" bigint,
    "cancelled_count" bigint,
    "bounced_count" bigint,
    "complained_count" bigint,
    "unsubscribed_count" bigint,
    "opened_count" bigint,
    "clicked_count" bigint
)
    language sql stable
    set search_path to 'pg_catalog', 'public'
    as $$
    select
        count(*) filter (where recipient.status = 'waiting') as waiting_count,
        count(*) filter (where recipient.status in ('checking', 'submitted')) as submitted_count,
        count(*) filter (where recipient.delivered_at is not null) as delivered_count,
        count(*) filter (where recipient.status in ('bounced', 'complained', 'failed')) as failed_count,
        count(*) filter (where recipient.status = 'excluded') as excluded_count,
        count(*) filter (where recipient.status = 'cancelled') as cancelled_count,
        count(*) filter (where recipient.status = 'bounced') as bounced_count,
        count(*) filter (where recipient.status = 'complained') as complained_count,
        count(*) filter (where recipient.unsubscribed_at is not null) as unsubscribed_count,
        count(*) filter (where recipient.first_opened_at is not null) as opened_count,
        count(*) filter (where recipient.first_clicked_at is not null) as clicked_count
    from public.marketing_campaign_recipients recipient
    where recipient.organization_id = target_organization_id
      and recipient.campaign_id = target_campaign_id;
$$;

revoke all on function "public"."marketing_campaign_recipient_counts"(uuid, uuid)
    from public, anon, authenticated;
grant execute on function "public"."marketing_campaign_recipient_counts"(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2. Credited work (tracked + declared, M5b) with the real revenue it holds, for the Results tab's "what
--    Requests and Jobs followed" list. A request carries no money of its own -- its revenue is whatever
--    job(s) followed it through the CRM's own lineage (Request -> Quote -> Job: quotes.request_id,
--    jobs.quote_id, both already indexed by quotes_request_lineage_idx / jobs_quote_lineage_idx). A job's
--    revenue is its own invoice chain. Every join here starts from this campaign's own credited rows
--    (bounded, typically small), never from a scan of the organization's full quote/job/invoice history.
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."marketing_campaign_credited_work"(
    "target_organization_id" uuid,
    "target_campaign_id" uuid
) returns table(
    "credit_id" uuid,
    "source" text,
    "request_id" uuid,
    "job_id" uuid,
    "client_id" uuid,
    "client_name" text,
    "credited_at" timestamptz,
    "work_title" text,
    "work_created_at" timestamptz,
    "revenue_minor" bigint
)
    language sql stable
    set search_path to 'pg_catalog', 'public'
    as $$
    with credits as (
        select credit.id as credit_id, credit.source, credit.request_id, credit.job_id, credit.client_id,
            credit.credited_at
        from public.marketing_campaign_result_credits credit
        where credit.organization_id = target_organization_id and credit.campaign_id = target_campaign_id
    ),
    -- Every job this campaign's credits could possibly own: a credited job directly, or a job produced by a
    -- quote that came from a credited request. Bounded by `credits`, not by the organization's quote/job
    -- tables.
    relevant_jobs as (
        select job.id as job_id, credits.credit_id
        from credits
        join public.jobs job
            on job.organization_id = target_organization_id and job.id = credits.job_id
        union all
        select job.id as job_id, credits.credit_id
        from credits
        join public.quotes quote
            on quote.organization_id = target_organization_id and quote.request_id = credits.request_id
        join public.jobs job
            on job.organization_id = target_organization_id and job.quote_id = quote.id
    ),
    job_revenue as (
        select relevant_jobs.job_id,
            sum(case when allocation.entry_type = 'applied'
                then allocation.amount_minor else -allocation.amount_minor end) as revenue_minor
        from relevant_jobs
        join public.invoice_sources source
            on source.organization_id = target_organization_id and source.job_id = relevant_jobs.job_id
        join public.invoices invoice
            on invoice.organization_id = source.organization_id
            and invoice.root_invoice_id = source.root_invoice_id
        join public.invoice_payment_allocations allocation on allocation.invoice_id = invoice.id
        group by relevant_jobs.job_id
    ),
    credit_revenue as (
        select relevant_jobs.credit_id, sum(coalesce(job_revenue.revenue_minor, 0)) as revenue_minor
        from relevant_jobs
        left join job_revenue on job_revenue.job_id = relevant_jobs.job_id
        group by relevant_jobs.credit_id
    )
    select
        credits.credit_id,
        credits.source,
        credits.request_id,
        credits.job_id,
        credits.client_id,
        client.display_name as client_name,
        credits.credited_at,
        coalesce(job.title, request.title) as work_title,
        coalesce(job.created_at, request.created_at) as work_created_at,
        coalesce(credit_revenue.revenue_minor, 0)::bigint as revenue_minor
    from credits
    join public.clients client
        on client.organization_id = target_organization_id and client.id = credits.client_id
    left join public.jobs job
        on job.organization_id = target_organization_id and job.id = credits.job_id
    left join public.requests request
        on request.organization_id = target_organization_id and request.id = credits.request_id
    left join credit_revenue on credit_revenue.credit_id = credits.credit_id
    order by credits.credited_at desc;
$$;

revoke all on function "public"."marketing_campaign_credited_work"(uuid, uuid)
    from public, anon, authenticated;
grant execute on function "public"."marketing_campaign_credited_work"(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. Window-attribution candidates (blueprint §13 method 3) for THIS campaign: uncredited work from a
--    client this campaign delivered to, created within the window after delivery, where this campaign is
--    the winning (most-recent-delivered) touch -- reusing marketing_campaign_window_attribution's own
--    last-touch rule per candidate rather than re-deriving it, so the two never disagree.
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."marketing_campaign_window_attribution_candidates"(
    "target_organization_id" uuid,
    "target_campaign_id" uuid,
    "window_days" integer default 30
) returns table(
    "work_kind" text,
    "request_id" uuid,
    "job_id" uuid,
    "client_id" uuid,
    "client_name" text,
    "work_title" text,
    "work_created_at" timestamptz,
    "delivered_at" timestamptz
)
    language sql stable
    set search_path to 'pg_catalog', 'public'
    as $$
    with campaign_recipients as (
        select recipient.client_id, recipient.delivered_at
        from public.marketing_campaign_recipients recipient
        where recipient.organization_id = target_organization_id
          and recipient.campaign_id = target_campaign_id
          and recipient.delivered_at is not null
    ),
    candidate_work as (
        select 'request'::text as work_kind, request.id as request_id, null::uuid as job_id,
            request.client_id, request.title as work_title, request.created_at as work_created_at
        from public.requests request
        join campaign_recipients recipient on recipient.client_id = request.client_id
        where request.organization_id = target_organization_id
          and request.created_at > recipient.delivered_at
          and request.created_at <= recipient.delivered_at + make_interval(days => window_days)
          and not exists (
              select 1 from public.marketing_campaign_result_credits credit
              where credit.request_id = request.id
          )
        union all
        -- A job that came from a request (through a quote) is represented by that request above, per the
        -- blueprint's "a Request, or a Job with no Request (a phone booking)" wording -- never both. A job
        -- has no request when it has no quote at all, or its quote itself has no request_id.
        select 'job'::text as work_kind, null::uuid as request_id, job.id as job_id,
            job.client_id, job.title as work_title, job.created_at as work_created_at
        from public.jobs job
        left join public.quotes quote
            on quote.organization_id = target_organization_id and quote.id = job.quote_id
        join campaign_recipients recipient on recipient.client_id = job.client_id
        where job.organization_id = target_organization_id
          and (job.quote_id is null or quote.request_id is null)
          and job.created_at > recipient.delivered_at
          and job.created_at <= recipient.delivered_at + make_interval(days => window_days)
          and not exists (
              select 1 from public.marketing_campaign_result_credits credit
              where credit.job_id = job.id
          )
    ),
    scored as (
        select candidate.*, winner.campaign_id as winning_campaign_id, winner.delivered_at as winning_delivered_at
        from candidate_work candidate
        cross join lateral public.marketing_campaign_window_attribution(
            target_organization_id, candidate.client_id, candidate.work_created_at, window_days
        ) as winner
    )
    select scored.work_kind, scored.request_id, scored.job_id, scored.client_id,
        client.display_name as client_name, scored.work_title, scored.work_created_at,
        scored.winning_delivered_at as delivered_at
    from scored
    join public.clients client
        on client.organization_id = target_organization_id and client.id = scored.client_id
    where scored.winning_campaign_id = target_campaign_id
    order by scored.work_created_at desc;
$$;

revoke all on function "public"."marketing_campaign_window_attribution_candidates"(uuid, uuid, integer)
    from public, anon, authenticated;
grant execute on function "public"."marketing_campaign_window_attribution_candidates"(uuid, uuid, integer)
    to service_role;
