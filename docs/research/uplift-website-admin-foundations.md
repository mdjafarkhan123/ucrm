# Uplift website-admin foundations

Research date: 2026-09-30
Scope: a first-pass foundation for client domain onboarding, portal access, subscription offboarding, and Astro website publishing. This note separates provider facts from product recommendations. It is not yet a final architecture or implementation plan.

## The whole lifecycle in one picture

**Recommended lifecycle:**

1. Uplift signs a contractor and records who legally owns the domain.
2. Uplift inventories the domain's existing website and email DNS records.
3. Uplift adds the domain to Cloudflare, copies and verifies all DNS records, then changes only the authoritative nameservers at the registrar.
4. Uplift creates a customer organization, its website record, and the first owner invitation.
5. The owner accepts the email invitation, creates a password, and sees only websites belonging to that organization.
6. Editing autosaves a private draft. Preview reads the draft; the public site keeps showing the last successful published release.
7. Publish creates an immutable content release, builds the Astro site, tests the uploaded Cloudflare version, and only then promotes it to the live domain.
8. Cancellation normally runs to the paid-through date. Failed payments enter a grace period. Suspension removes editing/publishing access without deleting the account, content, or domain.
9. Final offboarding exports content, safely hands over DNS/domain control, applies the agreed retention period, and only then removes Uplift's hosting attachment.

## 1. Cloudflare DNS and the client's existing email

### Official facts

- A domain registrar and an authoritative DNS provider are different jobs. In Cloudflare's normal “full setup,” the domain can remain registered at GoDaddy or another registrar while its authoritative nameservers are changed to the two nameservers assigned by Cloudflare. Cloudflare then answers DNS queries for the domain. [Cloudflare: Onboard a domain](https://developers.cloudflare.com/fundamentals/manage-domains/add-site/)
- Cloudflare's automatic DNS scan is not guaranteed to find every existing record. Cloudflare explicitly tells customers to review the apex, subdomains, and email records and manually add anything missing **before** activating the domain. [Cloudflare: Onboard a domain](https://developers.cloudflare.com/fundamentals/manage-domains/add-site/)
- If DNSSEC is active at the old registrar, it must normally be disabled before changing nameservers; otherwise the old signatures can make the whole domain unreachable. DNSSEC can be enabled again through Cloudflare after the zone becomes active. [Cloudflare: Onboard a domain](https://developers.cloudflare.com/fundamentals/manage-domains/add-site/) and [Cloudflare Registrar: Transfer a domain](https://developers.cloudflare.com/registrar/get-started/transfer-domain-to-cloudflare/)
- Email does not have to move to Cloudflare. To keep an existing email provider, Cloudflare DNS must contain that provider's exact records. These commonly include inbound `MX`; SPF, DKIM, and DMARC `TXT`; provider-verification `TXT`; and DKIM/autodiscover `CNAME` records. The required values come from the email provider. [Cloudflare: Set up email records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/email-records/)
- `MX` records cannot be proxied. A hostname used only for SMTP, IMAP, or POP (for example, `mail.example.com`) must also be **DNS only**, because Cloudflare's ordinary web proxy does not proxy those mail protocols. Some mail-provider `CNAME` records must remain unflattened so the provider can read them as CNAMEs. [Cloudflare: Email troubleshooting](https://developers.cloudflare.com/dns/troubleshooting/email-issues/) and [Cloudflare: DNS proxy use cases](https://developers.cloudflare.com/dns/proxy-status/use-cases/)
- Cloudflare Email Routing is forwarding, not a hosted mailbox. Turning it on changes/manages the domain's `MX` records and can conflict with the client's existing mail provider. Its forwarding limitations include replies coming from the destination address rather than the custom-domain forwarding address, possible failures with restrictive DMARC policies, no internationalized local part, and no forwarded non-delivery reports. [Cloudflare: Email Routing limitations](https://developers.cloudflare.com/email-service/reference/postmaster/) and [Cloudflare: Email troubleshooting](https://developers.cloudflare.com/dns/troubleshooting/email-issues/)
- Cloudflare now documents a separate Email Sending service and authenticated SMTP submission, but it requires onboarding and authorization and still does not, by itself, give a contractor a normal inbox and mailbox UI. [Cloudflare: SMTP sending](https://developers.cloudflare.com/email-service/api/send-emails/smtp/)

### Recommendation for Uplift

Do **not** transfer the domain registration or change the email provider merely to host the website. For the first version:

1. Keep the domain legally registered to the client whenever possible.
2. Export or screenshot the complete current DNS zone and obtain the email provider's official DNS checklist.
3. Add the zone to Cloudflare and reproduce every required record. Pay special attention to `MX`, SPF, DKIM, DMARC, autodiscover, provider verification, and any `mail` host.
4. Mark web records proxied only where appropriate; keep all mail endpoints and third-party verification records DNS only.
5. Disable old DNSSEC/DS records, change the registrar's nameservers, wait for Cloudflare to show **Active**, test website resolution plus inbound and outbound email, and then enable Cloudflare DNSSEC.
6. Do not enable Cloudflare Email Routing for a client who already uses GoDaddy Email, Microsoft 365, Google Workspace, or another mailbox provider.

If the records are copied correctly, changing nameservers does not cancel the client's mailbox or remove their historical email. Missing or wrongly proxied records are what cause outages.

## 2. How an account is created and linked to the correct website

### Official facts from mature identity systems

- Mature B2B identity systems model a customer company as an **organization**, users as people who can belong to organizations, and organization membership as the place where roles are assigned. Auth0 documents email invitations that let a person either create an account or log in, require the invitation email to match, can carry organization-specific roles, and expire if unused. [Auth0: Invite organization members](https://auth0.com/docs/manage-users/organizations/configure-organizations/invite-members)
- A user identity and an organization membership are separate records. Removing someone from one Auth0 organization removes that membership, not the person's global identity. This allows the same person to belong to another organization without duplicating or destroying their account. [Auth0: Remove organization members](https://auth0.com/docs/manage-users/organizations/configure-organizations/remove-members)
- Supabase Auth can send an invitation email from a trusted server. The link confirms the address and lets the person finish account setup; the secret admin key must never be exposed in the browser. [Supabase: Users and invitations](https://supabase.com/docs/guides/auth/users)
- Supabase/Postgres Row Level Security can enforce access at the database row level. Supabase recommends enabling RLS on exposed tables, granting only needed operations, creating policies per operation, and testing both allowed and denied access—including non-member denial for shared resources. [Supabase: Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)

### Recommended data relationship

```text
person account
    ↓ accepts invitation
organization membership (owner / editor / viewer)
    ↓ organization owns
one or more website records
    ↓ website has
draft + releases + deployments + domain(s) + subscription
```

The link is made by permanent database IDs, **not** by guessing from an email address or domain name:

- `users`: the human login identity.
- `organizations`: the contractor/customer business.
- `organization_memberships`: `user_id + organization_id + role + status`.
- `websites`: each row has an `organization_id` and its Cloudflare/deployment identifiers.
- Optional `website_memberships`: add this later only if one organization needs different people on different websites.

### Recommended onboarding flow

1. Uplift creates the organization and website record during customer setup.
2. Uplift enters the customer's owner email and the server creates a one-use, expiring invitation tied to `organization_id` and role `owner`.
3. The customer clicks the link, proves control of that exact email, chooses a password, and accepts the invitation.
4. Acceptance creates the membership in a transaction and marks the invitation used. The user then sees websites whose `organization_id` appears in their memberships.
5. The owner can invite editors or viewers later. Invitations can be resent or revoked; expired/used tokens cannot be reused.
6. Every API request and database policy re-checks active membership. Hiding another customer's website in the interface is not enough—the database must deny it too.

For the first release, use invitation-only signup. Do not let arbitrary visitors create an account and claim a domain.

## 3. Cancellation, suspension, and offboarding

### Official facts

- Stripe subscriptions have distinct lifecycle states such as `active`, `past_due`, `unpaid`, and `canceled`; after retries are exhausted, settings determine whether a failed subscription becomes `canceled` or `unpaid`. Therefore a single failed charge is not the same event as final termination. [Stripe: Subscription object](https://docs.stripe.com/api/subscriptions/object)
- Stripe supports cancellation at the end of the current billing period, so access can remain active until the paid-through date. [Stripe: Cancel a subscription](https://docs.stripe.com/api/subscriptions/cancel)
- Identity access can be disabled without deleting the customer record. Auth0 documents simulating an inactive organization by disabling its connections or denying login based on organization metadata. [Auth0: Disabling organizations](https://support.auth0.com/center/s/article/Can-I-disable-Organizations-without-deleting-them)
- Removing a Cloudflare zone stops Cloudflare DNS resolution but does not change domain registration. Cloudflare says nameservers should be changed to a working DNS provider first to avoid DNS errors. [Cloudflare: Remove a domain](https://developers.cloudflare.com/fundamentals/manage-domains/remove-domain/)
- Detaching a Pages custom domain requires both removing the DNS record and removing the domain association. This would make the public site unavailable on that domain unless replacement hosting/DNS is already ready. [Cloudflare Pages: Custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/)

### Recommended customer states

| State                  | Portal                          | Editing/publishing                       | Public website                                                         |
| ---------------------- | ------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------- |
| `active`               | Full access                     | Allowed by role                          | Last successful release                                                |
| `canceling`            | Full until paid-through date    | Allowed                                  | Last successful release                                                |
| `past_due_grace`       | Access plus billing warning     | Usually allowed briefly; policy decision | Keep live                                                              |
| `suspended`            | Read-only billing/export screen | Blocked                                  | Keep live for the contractual grace period                             |
| `terminated_retention` | Export/support only             | Blocked                                  | Handover, holding page, or removal according to contract               |
| `deleted`              | None                            | None                                     | Uplift resources removed after confirmed handover and retention expiry |

### Recommended safety rules

- Billing webhooks change an internal **entitlement/subscription state**; they must not directly delete a user, website, DNS zone, content, or version history.
- Do not take a contractor's public website offline on the first failed payment. Use payment retries, clear notices, and a written grace period.
- Suspending publishing is safer than deleting data. Keep an audit trail and make reactivation reversible.
- Define in the customer contract who owns the domain, source/template license, content, media, and analytics; the grace period; export format; retention duration; and what the live domain shows after termination.
- Offboard in this order: verify the authorized owner, export content/media and DNS records, provide or accept destination DNS values, confirm the replacement site/email work, change nameservers or web records, detach the Uplift domain mapping, revoke portal memberships/tokens, then delete retained data on schedule.
- Never remove a Cloudflare zone while the client's nameservers still point to it. Email depends on the same DNS zone and can fail along with the website.

## 4. Draft, preview, publish, history, and rollback for Astro on Cloudflare

### Official facts

- Astro pages are static by default and generated at build time. Astro can also render selected routes on demand with its official Cloudflare adapter; Astro recommends beginning with static mode until on-demand rendering is actually needed. [Astro: On-demand rendering](https://docs.astro.build/en/guides/on-demand-rendering/)
- Astro content collections provide a schema and validation for structured content and can load remote CMS/database content. Build-time collections are refreshed at build time, which fits relatively static marketing content. [Astro: Content collections](https://docs.astro.build/en/guides/content-collections/)
- Mature CMS products keep unpublished drafts separate from published delivery. Contentful's production delivery API returns the last published state while its separately authenticated Preview API returns draft changes; Sanity likewise recommends a `drafts` view for preview and a `published` view for production. [Contentful: Preview API](https://www.contentful.com/developers/docs/references/content-preview-api/overview/) and [Sanity: Presenting and previewing content](https://www.sanity.io/docs/content-lake/presenting-and-previewing-content)
- Cloudflare recommends Workers for new projects. Workers can deploy an Astro static-assets directory, and a Worker version captures code, static assets, bindings, and settings as a point-in-time unit. Uploading a version and making it live can be separate actions. [Astro: Deploy to Cloudflare](https://docs.astro.build/en/guides/deploy/cloudflare/) and [Cloudflare Workers: Versions and deployments](https://developers.cloudflare.com/workers/versions-and-deployments/)
- A Cloudflare Worker Version URL allows an uploaded version to be tested before production deployment. It is public unless protected with Cloudflare Access. [Cloudflare Workers: Version URLs](https://developers.cloudflare.com/workers/versions-and-deployments/version-urls/)
- Cloudflare can roll back to a prior Worker version, but external storage such as D1, KV, and R2 is not rolled back with the Worker. Therefore Cloudflare deployment history is not a substitute for CMS content history. [Cloudflare Workers: Rollbacks](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/)

### Recommended content and deployment model

Use two deliberately separate histories:

1. **CMS history:** immutable snapshots of the client's structured content, with author, time, reason, schema/template version, and publication status.
2. **Cloudflare deployment history:** the exact Astro build/version deployed for a content snapshot.

Recommended workflow:

```text
edit fields → autosaved working draft
           → preview draft privately
           → create immutable release snapshot
           → validate content and build Astro
           → upload Cloudflare Worker version (not live)
           → test its protected Version URL
           → promote that exact version to production
           → record release ID ↔ build/deployment ID
```

Important behavior:

- The public site always serves the last **successful published release**. Draft changes never leak into production queries or builds.
- Preview does not start a terminal on demand. A terminal is a developer tool, not a customer preview system.
- For an exact pre-publication preview, the backend build worker can build the selected draft snapshot and upload it as a non-live Worker version. The portal opens its protected Version URL in a new tab or frame.
- Do not rebuild on every keystroke. Autosave the draft quickly, then generate an exact preview on request or after a sensible debounce. A later enhancement may add an authenticated on-demand preview route for near-instant editing feedback.
- Publishing is a queued server job with visible states such as `queued`, `building`, `testing`, `live`, and `failed`. Only the server holds Cloudflare credentials.
- Before promotion, run schema validation, Astro build, automated link/smoke checks, and a health request against the Version URL. If any step fails, leave production untouched and show a useful error.
- “Rollback” should select an old CMS snapshot and create a **new release** from it, then build and publish it normally. This preserves history instead of erasing the intervening versions. Cloudflare's infrastructure rollback remains an emergency tool for reverting the exact deployed artifact.

## Decisions still needed before implementation

1. Will Uplift manage Cloudflare zones in one agency account, or will each client own an account and delegate access? This materially affects support and offboarding.
2. Is public hosting included during a payment grace period, and for exactly how long?
3. After final termination, does the client receive structured content/media only, a static-site export, or transferable source code under a separate license?
4. Can clients publish directly, or do some plans require Uplift approval?
5. Does the first version need only exact on-demand build previews, or also instant live preview while typing?
6. How long are drafts, releases, deployment logs, and deleted customer data retained?

## Bottom-line recommendation

Build this as a controlled, multi-customer CMS for Uplift-built contractor websites—not a free-form page builder. Keep email at the client's existing provider, connect accounts to websites through organization membership IDs, treat billing suspension as a reversible entitlement change, and publish immutable Astro releases through a protected preview-and-promote pipeline. That gives the client an easy GoDaddy-like experience without giving the browser access to source code, DNS credentials, or deployment secrets.
