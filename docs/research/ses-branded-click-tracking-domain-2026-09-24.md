# SES branded click-tracking domain: how it works and what fits UCRM

Researched 2026-09-24 for the approved requirement that every real-customer Marketing send must track clicks
through a domain on the contractor's own domain instead of the shared `*.awstrack.me`. UCRM sends from
`us-east-1` (`AWS_SES_REGION` in `.env.example`); each contractor has configuration set `ucrm-marketing-<orgId>`,
identity `news.<root>`, and a zone in UCRM's Cloudflare account. No code, infrastructure, AWS or Cloudflare
setting was changed. "Proven" below means stated in a primary source; "unknown" means it needs a live test.

## Executive finding

- SES supports this natively: set `TrackingOptions.CustomRedirectDomain` (+ `HttpsPolicy`) on each contractor's
  configuration set. The domain must be a **verified SES identity**, and it must forward traffic to
  `r.us-east-1.awstrack.me` **with the visitor's `Host` header intact**.
- HTTP-only is no longer acceptable. Chrome 154 (October 2026) warns before HTTP navigations that only redirect
  to HTTPS, which is exactly what an HTTP click-tracking link is. So an HTTPS front door is required.
- AWS documents CloudFront as the front door. For thousands of contractors, **CloudFront multi-tenant
  distributions (SaaS Manager)** — one shared config plus one cheap "tenant" per contractor with an
  auto-issued certificate — is the AWS-native pattern built for this. Fronting with the Cloudflare proxy is the
  same pattern SendGrid documents for its own tracking links and costs nothing on first-level subdomains, but
  AWS does not document it for SES; it needs a live test.

## 1. How `CustomRedirectDomain` works (proven)

- API: `PutConfigurationSetTrackingOptions` (`PUT /v2/email/configuration-sets/{name}/tracking-options`) with
  `CustomRedirectDomain` and `HttpsPolicy`. [API ref](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_PutConfigurationSetTrackingOptions.html)
  / [TrackingOptions](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_TrackingOptions.html)
- `HttpsPolicy`: `OPTIONAL` (default) — open pixel on HTTP, click links keep the original link's protocol;
  `REQUIRE` — both open and click links on HTTPS; `REQUIRE_OPEN_ONLY` — open pixel HTTPS, click links keep the
  original protocol. [SES guide, Part 2](https://docs.aws.amazon.com/ses/latest/dg/configure-custom-open-click-domains.html)
- Setup steps AWS lists: create a dedicated subdomain (one per sending region), **verify it for use with SES**,
  then CNAME it (HTTP) or point it via a CDN (HTTPS) at the same-region tracking host. [SES guide, Part 1](https://docs.aws.amazon.com/ses/latest/dg/configure-custom-open-click-domains.html)
- Target for UCRM's region: `r.us-east-1.awstrack.me`. [Tracking domains table](https://docs.aws.amazon.com/general/latest/gr/ses.html#ses_tracking_domains)
- Verification is enforced: the v1 API returns `InvalidTrackingOptions` "when the tracking domain you
  specified is not verified in Amazon SES". [v1 API ref](https://docs.aws.amazon.com/ses/latest/APIReference/API_CreateConfigurationSetTrackingOptions.html)
  The v2 page lists only a generic `BadRequestException`.
- Subdomains inherit verification: after verifying `example.com`, "you don't need to create separate subdomain
  identities for a.example.com, a.b.example.com". [Creating identities](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html)
  So `click.news.<root>` should count as verified through `news.<root>`. `click.<root>` would **not**, because
  `<root>` itself is not an SES identity. *Whether the tracking-options check accepts an inherited subdomain
  is implied, not stated — confirm with one API call.*
- Links look like `https://<domain>/CL0/{encodedUrl}/{index}/{messageId}/{hmac}`. [SES guide, Part 4](https://docs.aws.amazon.com/ses/latest/dg/configure-custom-open-click-domains.html)

## 2. HTTPS requirements

- AWS's HTTPS steps: put a CDN such as CloudFront in front, with origin `r.<region>.awstrack.me`. "The CDN must
  pass the `Host` header supplied by the requester to the origin". Then CNAME the subdomain to the CDN, attach a
  trusted certificate that covers the subdomain, and test with `curl --head https://<domain>/favicon.ico`.
  Success = `x-amz-ses-region: us-east-1` and `x-amz-ses-request-protocol: https`. [SES guide, Option 2](https://docs.aws.amazon.com/ses/latest/dg/configure-custom-open-click-domains.html)
- In CloudFront, the managed origin request policy **AllViewer** forwards all viewer headers, including `Host`.
  Do not use `AllViewerExceptHostHeader`. [Managed origin request policies](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html)
  A community answer on AWS re:Post reports that switching to AllViewer fixed SES HTTP 400 errors (this is a user
  post, not AWS documentation). [re:Post](https://repost.aws/questions/QUbjB6jlKhSWCH-VWVg4vRcg/ses-config-set-with-custom-domain-getting-http-error-400)
- **This means awstrack.me routes by `Host` header** (it needs to know which custom domain the request came
  through). The path carries the encoded destination, message ID and HMAC.
- AWS warns that an HTTP tracking domain can trigger warnings when the original links use HTTPS. [SES guide, Option 1](https://docs.aws.amazon.com/ses/latest/dg/configure-custom-open-click-domains.html)
- Chrome: Chrome 115 already tries HTTPS first, then quietly falls back to HTTP if it fails. [Chromium blog](https://blog.chromium.org/2023/08/towards-https-by-default.html)
  In Chrome 154 (October 2026), "Always Use Secure Connections" becomes the default. Chrome will ask the
  user's permission before the first visit to any public HTTP site. It also calls out HTTP links that "immediately
  redirect to HTTPS" as a risk it now surfaces. [Google security blog](https://security.googleblog.com/2025/10/https-by-default.html)
- Gmail: SendGrid's 2026-08-27 changelog says "Gmail is rolling out warnings on non-HTTPS links by the end of
  October 2026". [Twilio changelog](https://www.twilio.com/en-us/changelog/ssl-for-branded-links) *No Google
  primary source was found; treat this as reported, not confirmed.* No primary source was found that
  quantifies how much HTTP links hurt spam-filter placement.
- HSTS: if the contractor's root sends HSTS with `includeSubDomains`, browsers must refuse plain HTTP to every
  subdomain, and an HTTP tracking link breaks. [RFC 6797 §6.1.2](https://www.rfc-editor.org/rfc/rfc6797#section-6.1.2)

## 3. Can Cloudflare's proxy replace CloudFront?

Proven by docs:
- Universal SSL (free) covers the apex and **first-level** subdomains only. Deeper names such as
  `click.news.<root>` "will not serve a valid certificate". The fix is Advanced Certificate Manager + Total TLS,
  or a custom certificate. [Universal SSL limitations](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/)
- Advanced Certificate Manager is a paid add-on on every plan, billed **per zone**. [ACM docs](https://developers.cloudflare.com/ssl/edge-certificates/advanced-certificate-manager/)
  It costs $10/month per zone on Free/Pro/Business. [Cloudflare blog](https://blog.cloudflare.com/advanced-certificate-manager/)
  Total TLS needs ACM. [Total TLS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/total-tls/)
- Cloudflare sends the visitor's original hostname as the `Host` header by default, which is what SES needs.
  (This is stated on the Cloudflare for SaaS custom-origin page. [Custom origin](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/advanced-settings/custom-origin/))
  A Host header **override** is Enterprise-only, and so are SNI and DNS-record overrides. [Origin Rules](https://developers.cloudflare.com/rules/origin-rules/)
  For SES, the default behaviour is the right one, so no override is needed.
- The SSL mode can be set for a single hostname with a Configuration Rule (Free plan: 10 rules per zone).
  In Flexible mode, Cloudflare talks to the origin over HTTP. In Full mode it uses HTTPS **without validating**
  the origin's certificate. [SSL modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/),
  [Configuration Rules](https://developers.cloudflare.com/rules/configuration-rules/)
- Precedent: SendGrid's official instructions for HTTPS click tracking through Cloudflare are to turn the proxy
  on (orange cloud), CNAME to `sendgrid.net`, and set SSL to **Full** for that hostname. [SendGrid + Cloudflare](https://www.twilio.com/docs/sendgrid/ui/sending-email/content-delivery-networks/using-cloudflare-as-your-content-delivery-network-cdn)
- Cloudflare caches `.gif` responses by default unless the origin sends `no-cache`/`private`. A cache-bypass
  rule for the tracking hostname protects open counts. [Default cache behavior](https://developers.cloudflare.com/cache/concepts/default-cache-behavior/)

Unknown, needs a live test: whether `r.us-east-1.awstrack.me` accepts Cloudflare's HTTPS connection when the
SNI and Host are `click.<root>` (Full mode), or only HTTP (Flexible mode); what `x-amz-ses-request-protocol`
reports in each case; and whether awstrack's responses already carry `no-cache` headers.

## 4. Per-tenant cost and quotas at thousands of contractors

| Item | Limit / price | Source |
| --- | --- | --- |
| SES configuration sets / tenants / identities per region | 10,000 each (adjustable) | [SES quotas](https://docs.aws.amazon.com/general/latest/gr/ses.html#limits_ses_quota), [identities](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html) |
| CloudFront standard distributions per account | 500 (adjustable) — one per contractor does not scale | [CloudFront quotas](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-limits.html) |
| Alternate domain names per standard distribution | 100 (adjustable) | same |
| Distribution tenants per account / multi-tenant distributions | 10,000 / 20 (both adjustable) | same |
| Distribution tenant price | reported as first 10 free, $20/month covers up to 200, then $0.10 per tenant per month — *confirm on the pricing page* | [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/) |
| ACM certificates per region | 2,500 at a time, 5,000 issued per year (adjustable via Support) | [ACM quotas](https://docs.aws.amazon.com/acm/latest/userguide/acm-limits.html) |
| Cloudflare ACM for `click.news.<root>` | $10/month × every contractor zone | [Cloudflare blog](https://blog.cloudflare.com/advanced-certificate-manager/) |
| Cloudflare Universal SSL for `click.<root>` | $0 | [Universal SSL](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/) |

A tenant's managed certificate is an ACM certificate that CloudFront obtains on your behalf, validated over
HTTP. [Managed tenant certificates](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/managed-cloudfront-certificates.html)
*Whether these count toward the 2,500 ACM quota is not stated; assume yes until AWS confirms.* A multi-tenant
distribution has no endpoint of its own. Each tenant gets its own domain, and the DNS record is a CNAME to the
connection group endpoint. [Multi-tenant distributions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-config-options.html)

## 5. How mature senders do it

- **SendGrid**: CNAME the branded link subdomain to `sendgrid.net`. An "Auto provision SSL Certificate" toggle
  (two extra DNS records) means SendGrid issues and hosts the certificate. [Link branding](https://www.twilio.com/docs/sendgrid/ui/account-and-settings/how-to-set-up-link-branding),
  [changelog](https://www.twilio.com/en-us/changelog/ssl-for-branded-links). Before that, customers had to supply
  HTTPS themselves through a CDN such as Cloudflare (see §3).
- **Mailgun**: CNAME the tracking domain to `mailgun.org`; switching the protocol to HTTPS makes Mailgun issue a
  Let's Encrypt certificate and terminate TLS itself. Cloudflare's proxy must be **off** for that record. [Mailgun help](https://help.mailgun.com/hc/en-us/articles/360011566033-HTTPS-Tracking-Links)
  (That page blocked automated fetching; the details come from its search summary.)
- **Postmark**: its default tracking domain is always HTTPS. The company has written that "certificates for
  HTTPS connections are associated with specific domains", which is why it could not support arbitrary CNAMEs
  at the time it built link tracking. [Postmark blog](https://postmarkapp.com/blog/how-we-built-link-tracking-to-be-reliable-fast-and-secure),
  [tracking links](https://postmarkapp.com/developer/user-guide/tracking-links)
- **HighLevel (LC Email)**: dedicated sending domains, where "the SSL certificate is automatically generated when
  your domain is verified". The tracking record details are not published. [HighLevel](https://help.gohighlevel.com/support/solutions/articles/48001226115-dedicated-email-sending-domains-overview-setup)

**The proven pattern:** the provider runs one shared edge. The customer adds a CNAME, and the provider
automatically issues and renews a certificate for each customer hostname, validated through that CNAME. For
UCRM on SES, the AWS-native equivalent is CloudFront multi-tenant distributions with managed certificates. The
Cloudflare-proxy equivalent is the older, SendGrid-documented "bring your own CDN" pattern.

## Recommended options for UCRM

| | A. CloudFront multi-tenant (recommended) | B. Cloudflare proxy on `click.<root>` | C. Cloudflare ACM on `click.news.<root>` |
| --- | --- | --- | --- |
| Hostname | `click.news.<root>` (inherits SES verification) | `click.<root>` (first-level, so free certificate) | `click.news.<root>` |
| Extra SES identity | none | yes: verify `click.<root>` (3 DKIM CNAMEs; uses a 2nd identity from the 10,000 quota) | none |
| Monthly cost | about $0.10/contractor + request fees | $0 | $10/contractor |
| Effort | One-time setup: multi-tenant distribution (origin `r.us-east-1.awstrack.me`, AllViewer, caching off, HTTPS-only). Then per contractor: create a tenant, write a grey-cloud CNAME, wait for the certificate, set tracking options | Per contractor: proxied CNAME, a Configuration Rule (SSL mode), a Cache Rule (bypass), a new identity, then set tracking options | Buy ACM on every zone, proxied CNAME, rules, then tracking options |
| Risk | Documented by AWS end to end; needs new CloudFront + ACM IAM permissions; certificate-quota question | Not documented by AWS for SES; depends on awstrack accepting Cloudflare's connection | Documented pieces, but the cost does not scale |

Recommendation: **A**, with **B** as a zero-cost fallback if the live tests pass and cost matters more than
staying on AWS's documented path. Use `HttpsPolicy: REQUIRE`. Keep the send gate closed until the curl check
returns `x-amz-ses-request-protocol: https` for that contractor.

## Open questions that need a live test (sandbox contractor zone)

1. Does `PutConfigurationSetTrackingOptions` accept `click.news.<root>` through inherited verification?
   Does it reject `click.<root>` until that name is verified?
2. With Cloudflare proxy + Full mode, does `curl --head https://click.<root>/favicon.ico` return
   `x-amz-ses-region: us-east-1`? What about Flexible mode? What does `x-amz-ses-request-protocol` show?
3. Do real clicks and opens through each front door produce CLICK and OPEN events on the SNS → SQS pipeline and
   redirect correctly? Are awstrack responses marked non-cacheable?
4. Do CloudFront tenant managed certificates count against the 2,500 ACM quota? What is the exact tenant price
   on the pay-as-you-go pricing page?
5. Does a multi-tenant distribution accept a custom origin `r.us-east-1.awstrack.me` with AllViewer, and does a
   managed certificate issue while the CNAME stays DNS-only (grey cloud) in Cloudflare?
6. Does any contractor root already send HSTS `includeSubDomains`? (This only matters if HTTP is ever used.)

## Live test findings (2026-09-24, Raad LTD test domain `click.news.test.upliftcontractor.com`)

- `create-distribution-tenant` with `ManagedCertificateRequest ValidationTokenHost=cloudfront` issued the ACM
  certificate within ~5 minutes of the CNAME existing, but the domain stayed `inactive` and HTTPS timed out.
  The certificate is **not** attached automatically: an `update-distribution-tenant` setting
  `Customizations.Certificate.Arn` to the issued certificate (what the console's final "Submit" does) turned the
  domain `active`; the tenant redeployed in under a minute. Automation must poll `get-managed-certificate-details`
  for `issued`, then make that update.
- Host forwarding + HTTPS origin to `r.us-east-1.awstrack.me` works: `HEAD /favicon.ico` returned 200 with
  `x-amz-ses-request-protocol: https`.
- `put-configuration-set-tracking-options` accepted `click.news.<root>` with `HttpsPolicy REQUIRE` without a
  separate SES identity, confirming inherited verification through `news.<root>`.
- End-to-end send (campaign `9b331950-…`, one recipient, real Gmail): the CTA link and the open pixel were both
  rewritten to `https://click.news.test.upliftcontractor.com/…` (CL0 and CI0 paths); the unsubscribe link stayed
  untracked. The click and the open both reached `marketing_campaign_recipients` and the Results API
  (`clicked_count 1`). SES events can arrive a few minutes late, so a Results check right after a click may lag.
- The worker's IAM user cannot read or edit its own IAM policies; tightening happens in the AWS console.
- In-app remove-then-turn-on test: `create-distribution-tenant` right after writing a fresh CNAME failed with
  `InvalidArgument` ("Could not verify Domain Name ownership"). CloudFront checks the domain's public DNS at create
  time, so the reconciler waits until public resolvers show the CNAME (and treats that error as "waiting") before
  creating the tenant. Deleting a disabled tenant succeeded on the first attempt right after the disable.

## Scoped IAM policy for `ucrm-branded-click-domain` (replaces the temporary `cloudfront:*`)

Covers everything the per-organization automation needs (create, check, attach certificate, disable, remove a
tenant) and nothing that can change or delete the shared distribution or connection group.

The policy lives in `scripts/aws/ucrm-branded-click-domain-policy.json`; it keeps the test policy's ACM and
SES statements and swaps `cloudfront:*` for the tenant actions only.
