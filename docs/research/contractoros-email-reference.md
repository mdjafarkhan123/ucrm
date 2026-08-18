# ContractorOs email reference for UCRM

Research date: 2026-08-15  
Source inspected read-only: `D:/Projects/ContractorOs`

## Short conclusion

ContractorOs uses **one platform Brevo account/API key for all organizations**, while isolating identity and routing in its own database: one verified sending domain and one dedicated receiving subdomain per organization, unique domain claims, organization-scoped queries, and opaque per-conversation reply aliases. This is a practical low-cost starting model for UCRM, but it is not hard provider-level tenant isolation. All contractors still share one Brevo account, quota, reputation surface, API credential, and account-wide delivery webhook.

The strongest pattern to reuse is therefore: **shared Brevo transport, strict UCRM tenant ownership and limits, separate platform mail, and verified per-contractor domains**. UCRM should not copy ContractorOs without adding per-tenant email quotas/rate limits and platform-wide backpressure, because ContractorOs contains no email-specific allowance or rate-limit implementation.

## What ContractorOs implements

### Provider and credentials

- Brevo is the only email provider. A single server-only `BREVO_API_KEY` is documented for platform mail and all per-tenant sending/receiving domains (`.env.example:52-65`). The REST helper reads that one environment key and sends it as Brevo's `api-key` header (`src/lib/server/email/brevo/request.ts:1-35`).
- The provider boundary is small: application code calls a provider-neutral `sendEmail`, which delegates to Brevo's transactional `/smtp/email` API and returns Brevo's message ID (`src/lib/server/email/client.ts:25-42`; `src/lib/server/email/brevo/send.ts:48-69`). This seam is worth retaining even if UCRM starts with Brevo.

### Jafar/platform-owner route

- Organization domain provisioning is owned by `/api/admin/orgs/[id]/email-domain`; its comments explicitly state that it is Jafar-session-only, has no contractor organization context, and targets the organization from the route parameter (`src/routes/api/admin/orgs/[id]/email-domain/+server.ts:1-10`).
- Jafar supplies a root domain, optional sending prefix, and required receiving prefix. The server normalizes and validates them, requires sending and receiving prefixes to differ, and derives the full domains itself (`src/routes/api/admin/orgs/[id]/email-domain/+server.ts:30-82,123-140`).
- It rejects an organization that already has a domain and rejects a sending or receiving domain already claimed by another organization before contacting Brevo (`src/routes/api/admin/orgs/[id]/email-domain/+server.ts:148-173`). Database unique indexes backstop one row per organization and globally unique sending domain, receiving domain, and inbound webhook token (`src/lib/server/db/schema/14_email_domains.ts:45-111`).
- Creation registers both sending and receiving domains in Brevo, stores the DNS records and a newly generated inbound secret, and only writes the database row after provider creation succeeds (`src/routes/api/admin/orgs/[id]/email-domain/+server.ts:175-225`). Removal first deletes the per-org webhook and both Brevo domains, then deletes the local row; provider failure leaves the row available for retry (`src/routes/api/admin/orgs/[id]/email-domain/+server.ts:229-257`).

### Domain identity and verification

- Each organization currently gets one email-domain row. Sending may use the root/apex or a subdomain. Receiving must use a separate sibling subdomain so Brevo's MX records do not take over the contractor's normal mailbox (`src/lib/server/db/schema/14_email_domains.ts:14-20,52-74`).
- Readiness is an explicit state machine: `pending`, `verifying`, `verified`, or `failed`, plus separate Brevo `verified` and `authenticated` flags, persisted DNS records, and timestamps (`src/lib/server/db/schema/14_email_domains.ts:14-25,84-105`).
- Verification checks both Brevo domains, refreshes the stored DNS snapshot, separately resolves inbound MX, and considers outbound sending ready only when the sending domain is both verified and authenticated (`src/routes/api/admin/orgs/[id]/email-domain/verify/+server.ts:40-87`). It registers the per-org inbound webhook only when the receiving domain is active and registers one shared transactional-events webhook when sending is ready (`src/routes/api/admin/orgs/[id]/email-domain/verify/+server.ts:93-128`).
- Contractors cannot self-service domain structure changes. They submit a durable request that Jafar reviews; the schema records requester, desired domain/local part, note, and request status (`src/lib/server/db/schema/16_email_change_requests.ts:5-54`). Once the domain is verified, contractors may self-service extra local parts such as `sales@` or `support@` without new DNS (`src/lib/server/db/schema/17_email_sender_addresses.ts:6-41`).

### Platform mail is separate

- Password resets, admin notices, and billing receipts use a distinct, outbound-only platform domain stored as a singleton and managed through Jafar-only admin routes. It has no organization scope, inbound MX, or reply parsing (`src/lib/server/email/platformEmailDomain.ts:1-10`; `src/routes/api/admin/platform/email-domain/+server.ts:1-17`).
- System sending uses that domain only after verification and otherwise falls back to `SYSTEM_FROM_EMAIL`, with a short in-process cache (`src/lib/server/email/senderAddresses.ts:67-109`). Contractor-to-customer mail never uses the shared platform address as a fallback: the worker marks it undeliverable if that contractor lacks a verified domain (`src/lib/server/workers/emailWorker.ts:189-224`).

### Multi-contractor routing and isolation

- Customer mail selects the organization by `messages.org_id`, loads only that organization's domain, and builds the From address from the organization name, local part, and verified domain (`src/lib/server/workers/emailWorker.ts:189-224,288-309`; `src/lib/server/email/senderAddresses.ts:41-65`).
- Replies go to an opaque per-conversation alias on the organization's receiving subdomain. Alias lookup is scoped by `org_id`, and internal identifiers are not exposed in the email address (`src/lib/server/email/replyAlias.ts:20-29,80-98`; `src/lib/server/email/conversationEmails.ts:13-23`).
- The inbound endpoint authenticates by the combination of receiving domain and a stored per-org token, then passes the resolved `org_id` into processing (`src/routes/api/webhooks/brevo/inbound/[token]/[domain]/+server.ts:35-65`). Inbound provider events are deduplicated using organization plus provider event ID, and successful processing records the audit marker only after the business write, allowing provider retry after failure (`src/lib/server/email/brevo/inboundProcessor.ts:152-184,493-507`).
- Outbound provider message IDs are stored and the account-wide delivery webhook maps Brevo events back to the local message, whose row supplies the organization (`src/lib/server/workers/emailWorker.ts:311-340`; `src/routes/api/webhooks/brevo/events/[secret]/+server.ts:40-56,176-194`).

### Reliability and allowances

- Email sends run in a worker. It claims queued messages, retries transient errors, stores the provider message ID on success, treats permanent provider failures as terminal, and records failure events/preferences (`src/lib/server/workers/emailWorker.ts:130-143,295-410`).
- No email-specific organization allowance, monthly quota, per-minute throttle, or platform-wide Brevo cap was found. The environment file documents such controls only for SMS (`.env.example:37-44`), while the email section contains only worker concurrency and Brevo credentials (`.env.example:52-65`). This is the main gap for a shared multi-contractor Brevo account.

## Applicability to UCRM

### Reuse

1. Start with one server-held Brevo account/API key and keep a provider-neutral email adapter.
2. Keep platform/system email completely separate from contractor-to-customer identity. Never fall back to the platform From address for contractor mail.
3. Let Jafar claim and verify each contractor's sending domain. Enforce one current owner for every sending and receiving domain with database uniqueness, not only UI checks.
4. Use a dedicated receiving subdomain when UCRM owns reply ingestion. Do not place inbound MX on the contractor's apex domain.
5. Permit contractor self-service local parts only after the underlying domain is verified; keep domain/DNS changes Jafar-approved.
6. Resolve every send, reply, provider event, and audit record back to an organization in UCRM. Use opaque reply aliases and idempotent webhook processing.

### Add before production

1. Add organization email allowances separately from Brevo's account allowance: at minimum per-minute, per-day, and billing-period caps, plus a platform-wide cap. Define whether over-cap mail is deferred or rejected and surface it clearly.
2. Track usage from accepted provider sends and reconcile delivery events. Do not use worker concurrency as a quota; it limits parallelism, not volume.
3. Add abuse/spam suspension at both organization and platform levels. One bad contractor can affect the shared Brevo account's reputation and sending availability.
4. Treat the single Brevo key and account-wide webhook secret as high-blast-radius secrets. Rotate them, keep them server-only, redact logs, and plan an account/subaccount migration seam if Brevo plan features later justify stronger isolation.
5. Decide whether UCRM needs inbound replies now. If it only needs outbound transactional email, omit the receiving-domain, MX, webhook, and forwarding complexity until approved.

## Bottom line for the grill

Brevo is applicable as the first shared provider for multiple contractors, and ContractorOs proves the basic architecture. The next product decision is not simply “Brevo or another provider.” It is whether Jafar wants a **shared provider account with UCRM-enforced per-contractor allowances and reputation controls**, accepting that a provider-account incident can affect everyone. ContractorOs chose the shared-account side but has not yet implemented email allowances, so that missing control should be decided explicitly in the UCRM email grill.
