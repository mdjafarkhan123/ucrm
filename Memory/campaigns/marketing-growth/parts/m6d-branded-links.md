# M6d Branded click links: build plan (PROPOSED 2026-09-24, awaiting Jafar's approval)

Live test passed (research doc "Live test findings"). Build it into the existing Jafar-panel Marketing domain
activation (`src/lib/server/communications/marketing-domain-activation.ts`, `MarketingDomainActions.svelte`).

## Proposed behavior

1. Activate/Recheck gains a click-link step after the SES steps: write CNAME `click.news.<root>` → routing endpoint
   through the existing `reconcileRecord` (already inside `news.<root>`, so `assertUnderSubdomain` holds); find or
   create the CloudFront tenant `ucrm-org-<orgId>` with a managed certificate; once the certificate is `issued`,
   attach it with `update-distribution-tenant` (not automatic); then HEAD `/favicon.ico` must show
   `x-amz-ses-request-protocol: https`.
2. The SES config set's `CustomRedirectDomain` is set only after that check passes. Until then, links keep Amazon's
   default address, so sends never break. Recheck finishes a pending certificate (it takes minutes).
3. Status shown per organization: Not set up / Waiting for certificate / Working / Turned off / Problem (plain reason).
4. Controls: Recheck (existing button), Turn off (clear the tracking option, keep the tenant), Turn on, Remove
   (clear option → disable → delete tenant → delete CNAME).
5. Stored on the marketing domain row (new columns: click domain name, status, tenant id, last error), one new
   migration. Shared distribution/connection group/routing endpoint come from new env vars; when unset, the step
   is skipped and the panel says "Branded links not configured on this server".
6. New dependency `@aws-sdk/client-cloudfront`, same client pattern as `ses.ts`. Zod on every new POST.

## Open

- Jafar approval of this plan. Production AWS account needs the same one-time
  distribution setup (goes into the production cutover runbook).
