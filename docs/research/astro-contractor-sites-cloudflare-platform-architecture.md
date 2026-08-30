# Hosting contractor-owned Astro sites on Cloudflare at platform scale

Research date: 2026-08-29  
Scope: Up to approximately 40,000 contractor websites, contractor-owned custom domains, UCRM-managed DNS, Astro-generated sites, Cloudflare hosting, TLS, cost, security, and offboarding.  
Evidence standard: Cloudflare and Astro first-party documentation only.

## Conclusion

The core idea is sound: Astro is a strong fit for fast contractor websites, and Cloudflare is a proven edge platform for serving them. The part that must change is the assumption that 40,000 independently deployed custom-domain sites can remain on a free Pages-style setup.

Cloudflare Pages permits only 100 projects per account and says that limit is not routinely increased. Ordinary Workers permit 100 scripts on Free or 500 on Paid. Cloudflare explicitly directs platforms with more sites toward Workers for Platforms or a shared Workers architecture. Cloudflare for SaaS is its native mechanism for routing many customer-owned domains and automatically managing their certificates. At 40,000 active single-hostname sites, the currently published Cloudflare for SaaS charge alone is approximately **$3,990/month**: 100 included hostnames and 39,900 additional hostnames at $0.10/month. Serving both apex and `www` as separate custom hostnames could approach 80,000 hostname objects and exceed the self-service 50,000 maximum, requiring Enterprise/custom terms. [Cloudflare Pages limits](https://developers.cloudflare.com/pages/platform/limits/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Cloudflare for SaaS plans](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/plans/)

The recommended design is:

1. Contractors retain legal ownership of their registrar account, domain, and mailbox subscription.
2. UCRM manages each contractor's Cloudflare DNS through a formal Cloudflare partner/tenant arrangement or another explicitly approved delegated-custody model—not by placing 40,000 zones casually in one ordinary account.
3. A per-site build job generates static Astro output.
4. Immutable, versioned site artifacts are stored under tenant-specific prefixes in R2.
5. Cloudflare for SaaS maps the contractor's apex/`www` hostname to one platform hostname and manages TLS.
6. A small shared Worker routes by the validated `Host` header to that tenant's active R2 release and applies caching and security headers.
7. Use Workers for Platforms only if UCRM later runs arbitrary contractor/AI-generated server code. It is unnecessary for trusted, fully static Astro output.

This is an architecture direction, not a 40,000-user capacity claim. It needs a Cloudflare commercial/limits review and measured load, deployment, cache, certificate, and recovery tests before production commitments.

## Why Astro fits

Astro prerenders pages as static files by default. Astro says a static site does not need a Cloudflare adapter; its Cloudflare adapter is for on-demand routes and server features. Current Astro guidance deploys new Cloudflare projects to Workers, and Astro 6's Cloudflare adapter no longer supports Pages. [Astro on-demand rendering](https://docs.astro.build/en/guides/on-demand-rendering/), [Astro Cloudflare adapter](https://docs.astro.build/en/guides/integrations-guide/cloudflare/), [Astro Cloudflare deployment](https://docs.astro.build/en/guides/deploy/cloudflare/)

For ordinary contractor brochure/service websites, the smallest correct design is therefore static generation:

- build only the contractor whose content or code changed;
- publish an immutable release;
- switch an active-release pointer only after verification;
- serve HTML, CSS, JavaScript, images, and fonts from Cloudflare's edge cache;
- keep forms, scheduling, analytics, and CRM writes in separately authenticated UCRM APIs.

That avoids running Astro server code on every page view and keeps tenant websites isolated from UCRM's authenticated application.

## Architecture options compared

| Option | Current platform fit | 40,000-site result | Decision |
| --- | --- | --- | --- |
| One Pages project per contractor | Simple independent deploys | Fails at 100 Pages projects/account; Free also permits only 500 builds/month and one concurrent build | Reject |
| One Pages project with many custom domains | Shared deploy | 100/250/500 custom domains per project on Free/Pro/Business; Enterprise lists 500 with account-team increases | Reject as the primary tenancy mechanism |
| One ordinary Worker/Static Assets deployment per contractor | Independent deploys, current Cloudflare direction | Fails at 100 Workers on Free or 500 on Paid; each version also has 20,000/100,000 asset-file limits | Reject at target scale |
| One shared Worker with tenant assets in R2 | Simple static multi-tenancy | Good content architecture; pair with Cloudflare for SaaS so one wildcard route receives every customer hostname | Recommend for static sites |
| Workers for Platforms, one isolated script per contractor | Arbitrary or untrusted per-tenant runtime code | Designed for unlimited isolated applications behind a dispatch Worker; paid and more complex | Reserve for dynamic/untrusted code |

Cloudflare Pages documents 500/5,000/20,000 monthly builds and 1/5/20 concurrent builds on Free/Pro/Business, a 20-minute build timeout, 100 projects per account, and 20,000 files on Free or 100,000 files on paid plans. It explicitly recommends Workers for Platforms or Workers Static Assets above 100 sites. [Cloudflare Pages limits](https://developers.cloudflare.com/pages/platform/limits/)

Ordinary Workers have 100 scripts on Free or 500 on Paid, at most 100 custom domains per zone, and at most 1,000 routed zones per Worker. Cloudflare recommends Workers for Platforms when those limits are exceeded. [Cloudflare Workers limits](https://developers.cloudflare.com/workers/platform/limits/)

Workers for Platforms is specifically designed to run customer- or AI-generated code in isolated Workers at scale. Its dispatch architecture can route by hostname without creating one ordinary Worker route per customer. [Workers for Platforms overview](https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/), [hostname routing](https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/configuration/hostname-routing/)

## Recommended request and deployment flow

### Publish

1. UCRM queues a build for one contractor and a pinned source/content revision.
2. The build system runs `astro build` in an isolated job with resource and time limits.
3. It uploads output to an immutable R2 prefix such as `sites/{tenant_id}/releases/{release_id}/`.
4. Automated checks verify expected entry points, content types, CSP/security headers, internal links, and maximum artifact sizes.
5. UCRM atomically changes the tenant's `active_release_id` only after checks pass.
6. Old releases remain for a defined rollback window, then a lifecycle job removes them.

R2 supports unlimited objects and storage per bucket, with up to 1,000,000 buckets per account and 100 directly attached custom domains per bucket. Its public `r2.dev` endpoint is explicitly not intended for production. Standard R2 includes 10 GB-month storage, 1 million Class A operations, and 10 million Class B operations monthly; beyond that it charges $0.015/GB-month, $4.50/million Class A, and $0.36/million Class B operations, with no egress charge. [R2 limits](https://developers.cloudflare.com/r2/platform/limits/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/)

The router should access R2 through a binding rather than create a direct R2 custom domain for every contractor. Store tenant artifacts in a small number of buckets, partitioned by opaque tenant ID and deployment ID. This avoids the 100-custom-domains-per-bucket limit and makes atomic releases and global policy enforcement straightforward.

### Request

1. Browser requests `contractor.com` or `www.contractor.com`.
2. The contractor's Cloudflare zone points that hostname by CNAME to UCRM's SaaS target. Cloudflare flattens an apex CNAME by default on all plans, so this works when Cloudflare is authoritative. [Cloudflare CNAME flattening](https://developers.cloudflare.com/dns/cname-flattening/set-up-cname-flattening/)
3. Cloudflare for SaaS validates the hostname, terminates TLS, and sends it through the platform zone.
4. A single `*/*` Worker route receives all custom-hostname traffic; Cloudflare documents that individual routes are not required for every hostname. [Worker as SaaS fallback origin](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/advanced-settings/worker-as-origin/)
5. The Worker performs an exact normalized-host lookup, rejects unknown/suspended domains, resolves the active release, and returns the matching R2 object.
6. Immutable hashed assets receive long-lived cache headers; HTML receives the shorter approved policy. Cache keys must include the canonical hostname and path so one tenant can never receive another tenant's content.

Do not trust a tenant identifier supplied by a query parameter or request header. The authoritative mapping is the normalized host that UCRM has verified and activated. Do not render an unknown hostname using a default contractor site; fail closed with a platform-controlled error.

## Domains, certificates, and the nameserver plan

Cloudflare for SaaS supports up to 50,000 custom hostnames on self-service Free, Pro, and Business plans, includes the first 100, and charges $0.10/month for each additional hostname. It provisions customer hostnames against one SaaS provider zone and can use a Worker as the fallback origin. [Cloudflare for SaaS overview](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/), [plans](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/plans/)

Each hostname has two separate readiness conditions: hostname ownership status and certificate status must both be `active`, and DNS must point to the SaaS target. UCRM must model and monitor those states rather than treating DNS-record creation as completion. [Cloudflare for SaaS API readiness](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/common-api-calls/)

When a customer zone is on Cloudflare but in a different account from the SaaS provider zone, Cloudflare supports Orange-to-Orange routing through a proxied CNAME. Customer-zone settings apply first, then provider-zone settings. [Cloudflare O2O routing](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/saas-customers/how-it-works/), [product compatibility](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/saas-customers/product-compatibility/)

Moving contractors' nameservers to Cloudflare remains useful because UCRM can preserve their existing website/mail DNS and automate the site CNAME plus Brevo sending/receiving records. It is not required merely to host a SaaS custom hostname, and it creates high-impact custody: one configuration error can affect the contractor's website and business email.

Cloudflare's current official organization documentation exposes only up to 5,000 zones per Enterprise/MSSP organization, well below 40,000. Normal account documentation does not publish a public 40,000-zone entitlement. Cloudflare's tenant guidance says each customer or team should have its own account for security and separation. Therefore the production plan must be reviewed with Cloudflare's partner/tenant or enterprise team before UCRM promises centralized management at this scale. [Cloudflare organization limits](https://developers.cloudflare.com/fundamentals/organizations/limitations/), [Cloudflare tenant account guidance](https://developers.cloudflare.com/tenant/how-to/manage-accounts/), [tenant structure](https://developers.cloudflare.com/tenant/structure/)

Recommended custody model:

- contractor remains registrant and can recover the domain independently;
- customer zone is isolated in a customer-specific Cloudflare account/container under an approved partner/tenant structure;
- UCRM uses least-privilege account tokens and keeps website deploy access separate from DNS/email access;
- all DNS mutations are audited, diffed, recoverable, and protected against changing root MX/SPF/DMARC unintentionally;
- offboarding exports the zone, removes the site's SaaS custom hostname and certificate association, hands DNS control to the contractor, preserves root mail records, and removes site artifacts after the retention period.

Cloudflare explicitly says a churned customer's custom hostname should be removed; merely changing DNS can leave problematic routing state, especially for Cloudflare-hosted customer zones. [Cloudflare custom-hostname removal](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/remove-custom-hostnames/)

## What is free and what is not

| Item | Published position | Meaning for UCRM |
| --- | --- | --- |
| Astro static build | Open build output; no Cloudflare runtime adapter required | Build cost is UCRM's CI compute |
| Workers static-asset requests | Free and unlimited when served as Worker Static Assets | Useful, but per-Worker asset and script limits still prevent 40,000 independent Workers |
| Workers Free | 100,000 requests/day, 100 scripts | Suitable only for prototypes/low traffic, not a 40,000-site promise |
| Workers Paid | Minimum $5/month; 10M dynamic requests and 30M CPU-ms included, then usage pricing | Shared router cost can be low but is measured, not universally free |
| R2 | Small monthly free tier; paid storage/operations above it; no egress charge | At 40,000 sites, budget as metered storage/reads |
| Cloudflare for SaaS | 100 hostnames included; $0.10/additional; 50,000 self-service maximum | About $3,990/month for 40,000 one-hostname sites before other costs |
| Workers for Platforms | $25/month, 20M requests, 60M CPU-ms, 1,000 scripts included; $0.02/additional script plus request/CPU overage | About $805/month for 40,000 deployed scripts before usage, only if per-tenant code isolation is needed |
| Cloudflare enterprise/partner tenancy | Negotiated | Required commercial conversation for the proposed zone-management scale |

Workers Paid pricing is $5/month including 10 million requests and 30 million CPU-ms; requests to Workers Static Assets are free and unlimited, though execution and storage dependencies remain billable. [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Workers Static Assets billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/)

Workers for Platforms costs $25/month including 20 million requests, 60 million CPU-ms, and 1,000 scripts, then $0.30/million requests, $0.02/million CPU-ms, and $0.02/additional script. Forty thousand active scripts would therefore have a published script/base floor of approximately $805/month before request and CPU overages. [Workers for Platforms pricing](https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/reference/pricing/)

## Operational controls required before launch

- **Build isolation:** Treat custom or AI-generated source as untrusted. Disable ambient secrets/network access in builds, cap resources, scan dependencies/artifacts, and never place UCRM service credentials into generated sites.
- **Tenant isolation:** Exact host-to-tenant mapping, tenant-prefixed object keys, deny-by-default routing, and tests proving one tenant cannot retrieve another tenant's artifacts.
- **Atomic deploy and rollback:** Immutable releases plus one active pointer; never upload piecemeal into the live prefix.
- **Certificate state machine:** Pending, validating, active, failed, moved, and deleting states with retries and operator visibility. Certificate issuance is not instant and must be load-tested in batches.
- **Email/DNS preservation:** The previously documented mailbox-safe DNS import and rollback process remains a prerequisite before changing nameservers.
- **Abuse and cost controls:** Per-site bandwidth/build quotas, upload limits, cache policy, CPU limits, bot/rate controls, and billing alerts.
- **Observability:** Hostname-scoped request/error/cache metrics, build/deploy audit events, certificate expiry/readiness, R2 failures, and synthetic checks for apex and `www`.
- **Offboarding:** Export DNS, remove SaaS custom hostnames, revoke tokens, preserve the contractor's root mailbox records, retain artifacts for the approved period, then delete them.

## Decision for Jafar

Approve the product direction, with this correction:

> UCRM will offer contractor-owned Astro websites hosted on Cloudflare, but it will not create one free Pages project per contractor. The launch implementation will use a shared static multi-tenant delivery plane—immutable Astro builds in R2, routed by a small Worker, with Cloudflare for SaaS custom hostnames and managed TLS. Contractor DNS remains isolated under a Cloudflare partner/tenant custody model. Dynamic per-contractor Workers are introduced only when a real server-code requirement exists.

Before implementation, obtain written Cloudflare confirmation/pricing for approximately 40,000 customer zones, 40,000–80,000 custom hostnames, certificate issuance throughput, O2O/apex behavior, support, and offboarding. Then prove the design with a staged cohort and production-like tests; do not market it as free or claim 40,000-site capacity from documentation limits alone.
