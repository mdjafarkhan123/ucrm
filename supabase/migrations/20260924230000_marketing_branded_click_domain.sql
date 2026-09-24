-- Marketing M6d: a branded click-tracking domain (click.news.<root>) per Marketing sending domain.
--
-- SES rewrites every tracked link and the open pixel onto a tracking host. By default that host is Amazon's
-- shared awstrack.me; a custom redirect domain on the organization's configuration set makes the links show
-- the contractor's own name instead. SES requires HTTPS for that domain, so each organization gets a
-- CloudFront distribution tenant (with a CloudFront-managed certificate) on one shared multi-tenant
-- distribution that forwards to SES's regional tracking endpoint
-- (docs/research/ses-branded-click-tracking-domain-2026-09-24.md).
--
-- The state lives on the marketing domain row because the click domain is derived from it and is removed
-- with it. click_domain_status is both health and intent: 'turned_off' is the owner's decision, and a
-- Recheck never turns a turned-off click domain back on.

alter table "public"."communication_email_domains"
    add column "click_domain_status" text not null default 'not_set_up',
    add column "click_domain_name" text,
    add column "click_distribution_tenant_id" text,
    add column "click_domain_error" text,
    add column "click_domain_checked_at" timestamp with time zone;

alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_click_domain_status_check"
    check ("click_domain_status" = any (array[
        'not_set_up'::text,
        'waiting_certificate'::text,
        'working'::text,
        'turned_off'::text,
        'problem'::text
    ]));

-- Only a Marketing sending row can carry a click domain; operational and receiving rows stay untouched.
alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_click_domain_purpose_check"
    check (
        "purpose" = 'marketing_sending'::text
        or (
            "click_domain_status" = 'not_set_up'::text
            and "click_domain_name" is null
            and "click_distribution_tenant_id" is null
            and "click_domain_error" is null
        )
    );

-- 'working' means links are actually being rewritten onto the domain, which needs a tenant to exist.
alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_click_domain_working_check"
    check (
        "click_domain_status" <> 'working'::text
        or ("click_domain_name" is not null and "click_distribution_tenant_id" is not null)
    );
