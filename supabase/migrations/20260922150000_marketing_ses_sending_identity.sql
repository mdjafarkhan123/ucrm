-- Marketing M4 stage 1: a per-organization Amazon SES sending identity for Marketing email.
--
-- Marketing sends from its own subdomain (news.<root>) through SES, separate from the operational
-- mail.<root> identity on Brevo. Separating the marketing stream from the transactional stream is the
-- standard deliverability practice: a campaign that draws complaints must not be able to damage the
-- reputation that quotes, invoices, and receipts depend on. The separate subdomain also sidesteps
-- communication_email_domains_live_claim_idx, which allows one live row per domain_name.

alter table "public"."communication_email_domains"
    drop constraint "communication_email_domains_provider_check";

alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_provider_check"
    check ("provider" = any (array['brevo'::text, 'ses'::text]));

-- A marketing sending row is its own purpose rather than another 'sending' row, so every existing query
-- that selects purpose='sending' (the operational sender picker, the manual-sender-ready index) keeps
-- excluding it without being changed. A contractor must never be able to attach an operational sender to
-- the marketing domain.
alter table "public"."communication_email_domains"
    drop constraint "communication_email_domains_purpose_check";

alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_purpose_check"
    check ("purpose" = any (array['sending'::text, 'receiving'::text, 'marketing_sending'::text]));

alter table "public"."communication_email_domains"
    drop constraint "communication_email_domains_purpose_health_check";

alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_purpose_health_check"
    check (
        ("purpose" = any (array['sending'::text, 'marketing_sending'::text])
            and "inbound_mx_status" = 'unchecked'::text)
        or ("purpose" = 'receiving'::text
            and "dkim_status" = 'unchecked'::text
            and "dmarc_status" = 'unchecked'::text
            and "spf_status" = 'unchecked'::text
            and "provider_authenticated" = false)
    );

-- A marketing row additionally requires spf_status='passing': the custom MAIL FROM subdomain is what gives
-- a bulk stream SPF alignment, so an identity without it is not honestly "verified" for marketing.
alter table "public"."communication_email_domains"
    drop constraint "communication_email_domains_verified_state_check";

alter table "public"."communication_email_domains"
    add constraint "communication_email_domains_verified_state_check"
    check (
        "lifecycle_state" <> 'verified'::text
        or (
            "provider_verified"
            and "ownership_status" = 'passing'::text
            and (
                ("purpose" = 'sending'::text
                    and "provider_authenticated"
                    and "dkim_status" = 'passing'::text)
                or ("purpose" = 'receiving'::text
                    and "inbound_mx_status" = 'passing'::text)
                or ("purpose" = 'marketing_sending'::text
                    and "provider_authenticated"
                    and "dkim_status" = 'passing'::text
                    and "spf_status" = 'passing'::text)
            )
        )
    );

comment on constraint "communication_email_domains_purpose_check" on "public"."communication_email_domains" is
    'marketing_sending is the SES Marketing identity (news.<root>); sending/receiving stay the operational Brevo pair.';

-- The SES tenant and configuration set are per organization, not per domain: they outlive a marketing
-- domain replacement, and one contractor's reputation enforcement and suppression must never reach another's.
create table if not exists "public"."communication_ses_tenants" (
    "organization_id" uuid not null,
    "tenant_name" text not null,
    "tenant_arn" text,
    "configuration_set_name" text not null,
    "event_destination_ready" boolean not null default false,
    "created_at" timestamptz not null default now(),
    "updated_at" timestamptz not null default now(),
    constraint "communication_ses_tenants_pkey" primary key ("organization_id"),
    constraint "communication_ses_tenants_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete cascade,
    constraint "communication_ses_tenants_tenant_name_check"
        check ("tenant_name" ~ '^[A-Za-z0-9_-]{1,64}$'),
    constraint "communication_ses_tenants_configuration_set_name_check"
        check ("configuration_set_name" ~ '^[A-Za-z0-9_-]{1,64}$')
);

-- Both names are global within the AWS account, so a collision between organizations is corruption.
create unique index if not exists "communication_ses_tenants_tenant_name_idx"
    on "public"."communication_ses_tenants" using btree ("tenant_name");

create unique index if not exists "communication_ses_tenants_configuration_set_name_idx"
    on "public"."communication_ses_tenants" using btree ("configuration_set_name");

create trigger "communication_ses_tenants_set_updated_at"
    before update on "public"."communication_ses_tenants"
    for each row execute function "public"."set_updated_at"();

comment on table "public"."communication_ses_tenants" is
    'One SES tenant and configuration set per organization. Holds provider resource names only; the contractor never reads it, so RLS is enabled with no policy and only service_role reaches it.';

alter table "public"."communication_ses_tenants" enable row level security;
