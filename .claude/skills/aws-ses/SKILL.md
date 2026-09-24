---
name: aws-ses
description: Send, receive, and manage email at scale with Amazon Simple Email Service (SES). Use when building email sending, identity verification, deliverability monitoring, email validation, tenant management, or multi-tenant email platforms. Covers V2 API patterns, DKIM/SPF/DMARC authentication, configuration sets, suppression lists, bounce/complaint handling, and dedicated IP management.
license: CC-BY-SA-4.0
compatibility: Requires AWS credentials (AWS Identity and Access Management (IAM) user, role, or environment variables) and an AWS account with Amazon SES access. SDK required - Python (boto3), Node.js (@aws-sdk/client-sesv2), or Java (software.amazon.awssdk:sesv2).
metadata:
  author: aws
  version: "1.0"
  service: ses
---

# Amazon Simple Email Service (SES)

<!-- Local edit of amazon-ses/skills@58f234e: upstream links a repo-root AGENTS.md and a scripts/ folder that
upstream never shipped. Their useful parts (workflow order, simulator addresses, guide index) are folded into
this file; script pointers are removed. Reapply after any reinstall. -->

Amazon SES is a cloud-based email sending and receiving service. It provides APIs and SMTP access for transactional, marketing, and notification email, designed to scale with your needs.

## Key Capabilities

- **Email Sending** — V2 API (`sesv2`), SMTP interface, templated and bulk sends
- **Email Receiving** — For inbound email processing, see the Mail Manager Agent Context Pack (coming soon)
- **Identity Management** — Domain and email verification with DKIM, SPF, DMARC, BIMI
- **Tenants** — Isolated workloads with per-tenant reputation monitoring and enforcement
- **Configuration Sets** — Event tracking, suppression management, IP pool assignment
- **Email Validation** — Validate addresses before sending to reduce bounces
- **Deliverability** — VDM dashboard, reputation monitoring, dedicated IP management
- **Suppression Lists** — Global, account-level, and configuration-set-level suppression

## When to Use This Skill

- Building email sending into an application
- Setting up transactional email (password resets, order confirmations, notifications)
- Building a multi-tenant email platform (ISV/SaaS)
- Migrating from another email service (SendGrid, Postmark, Mailgun)
- Setting up email authentication (DKIM, SPF, DMARC)
- Monitoring email deliverability and sender reputation
- Validating email addresses for deliverability

## Common Mistakes (Quick Reference)

| Mistake | Fix |
|---------|-----|
| Using V1 API (`ses`) | Use `sesv2` — V1 is legacy |
| Sending before verifying identity | Verify domain/email first |
| Ignoring sandbox mode | Use simulator addresses for testing; request production access before going live |
| Skipping DKIM/SPF/DMARC | Gmail and Yahoo reject unauthenticated bulk email |
| No configuration set | You lose all observability — always create one |
| No tenants | Isolate mail streams from day one — tenants provide per-stream reputation monitoring |
| Misdiagnosing throttling | TPS limit is a ceiling; check your own app's rate limiting first |
| Ignoring bounces/complaints | Bounce > 5% or complaint > 0.1% triggers enforcement |
| No delivery delay events | Gmail defers for up to 14 hours — enable notifications |
| SPF on wrong domain | SPF checks MAIL FROM, not From header — use custom MAIL FROM |
| Cold dedicated IPs | Warm up 2-4 weeks or use managed dedicated IPs |
| Sending to invalid addresses | Validate with `GetEmailAddressInsights` first |

## Workflow — Follow This Order

1. **Verify identity** — the domain or address must be verified before sending. Check with `GetEmailIdentity`.
2. **Check sandbox status** — new accounts send only to verified recipients. Check with `GetAccount`.
3. **Create a configuration set** — event tracking, metrics, and suppression.
4. **Create a tenant** — isolates workload reputation.
5. **Implement** — with the Node.js V2 client, `SESv2Client` from `@aws-sdk/client-sesv2`.
6. **Validate addresses** — `GetEmailAddressInsights` before sending.
7. **Verify end-to-end** — the send is done when bounce, complaint, and delivery events arrive through the event destination, not when the API returns 200.

## Testing

SES simulator addresses work in the sandbox without recipient verification:

| Address | Result |
|---------|--------|
| `success@simulator.amazonses.com` | Successful delivery |
| `bounce@simulator.amazonses.com` | Hard bounce |
| `complaint@simulator.amazonses.com` | Spam complaint |

## Reference Guides

| Task | Guide |
|------|-------|
| Send your first email | [references/quickstart/send-first-email.md](references/quickstart/send-first-email.md) |
| Verify domain + DKIM/SPF/DMARC | [references/identity/verify-domain-identity.md](references/identity/verify-domain-identity.md) |
| Send with V2 SDK | [references/sending/send-with-sdk.md](references/sending/send-with-sdk.md) |
| Send with SMTP | [references/sending/send-with-smtp.md](references/sending/send-with-smtp.md) |
| Send bulk/templated | [references/sending/send-bulk-email.md](references/sending/send-bulk-email.md) |
| Configuration sets + bounce/complaint events | [references/configuration/configuration-sets.md](references/configuration/configuration-sets.md) |
| Suppression lists | [references/configuration/suppression-lists.md](references/configuration/suppression-lists.md) |
| Tenants (one per customer on a multi-tenant platform) | [references/tenants/tenant-setup.md](references/tenants/tenant-setup.md) |
| Email validation | [references/validation/email-validation.md](references/validation/email-validation.md) |
| Reputation + VDM | [references/deliverability/reputation-management.md](references/deliverability/reputation-management.md) |
| Dedicated IPs | [references/deliverability/dedicated-ips.md](references/deliverability/dedicated-ips.md) |
| Troubleshooting | [references/troubleshooting/common-issues.md](references/troubleshooting/common-issues.md) |

## What This Skill Does NOT Cover

- **Mail Manager / Inbound Email** — SES Mail Manager handles inbound email processing (ingress, routing, archiving, SMTP relay). Classic SES receipt rules (V1 API) are not covered by this skill. See the Mail Manager Agent Context Pack (coming soon) for inbound use cases.
- **Global Endpoints** — Cross-region failover configuration is an advanced topic.
- **V1 API** — Intentionally excluded. All guidance and examples use V2.

## Resource Links

- [Developer Guide](https://docs.aws.amazon.com/ses/latest/dg/llms.txt)
- [API Reference (V2)](https://docs.aws.amazon.com/ses/latest/APIReference-V2/llms.txt)
