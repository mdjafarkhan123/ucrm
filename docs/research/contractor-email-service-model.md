# Contractor email service model

Research date: 2026-08-15

## Question

How should UpliftContractor provide email for US and Canadian contractor organizations through Brevo, including operational email, marketing, replies in the unified inbox, deliverability, tenant controls, and billing?

## Recommendation

Use a **managed email service with two deliberately separate lanes**:

1. **Operational email** for requested or expected business activity: request confirmations, assessments, quotes, jobs, visits, invoices, receipts, account notices, and direct staff replies.
2. **Marketing email** for promotions, re-engagement, win-back, review requests with promotional content, newsletters, and campaigns.

Both lanes can initially use Brevo, but UCRM must give them separate policy, templates, consent checks, rate limits, suppression handling, reporting, and sender identities. Google recommends separating message categories by From address and, where needed, sending IP; the FTC determines mixed-message treatment from the message's primary purpose, while Canada requires consent, identification, and unsubscribe handling for commercial electronic messages. [Google sender guidelines](https://support.google.com/mail/answer/81126?hl=en), [FTC CAN-SPAM guide](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business), [CRTC CASL FAQ](https://crtc.gc.ca/eng/com500/faq500.htm)

Do **not** charge ordinary operational email against Communication Balance in the first release. Include a reasonable monthly email allowance and safety limits in each package, and let Jafar see provider usage and overage risk. Email is cheap enough that per-message balance deductions would add friction to quotes, invoices, and reminders that the CRM must reliably deliver. Treat high-volume marketing as a separate package entitlement or paid add-on later. HighLevel supports per-subaccount usage/rebilling, while Jobber separates client-operational emails from campaigns and continues operational reminders, quotes, and invoices after a campaign unsubscribe. [HighLevel LC Email](https://help.gohighlevel.com/support/solutions/articles/48001220605-what-is-lc-email-i-want-to-know-more), [Jobber campaigns](https://help.getjobber.com/hc/en-us/articles/19885016029207-Campaigns-Marketing-Tools)

This pricing recommendation is a product inference, not a Brevo requirement. Keep the ledger model capable of adding email charges later without pretending email usage is SMS usage.

## Proposed product model

### 1. Provider and tenant isolation

Prefer **one Brevo sub-account per UCRM organization** when the selected Brevo commercial plan makes Corporate sub-accounts available. Brevo describes sub-accounts as independent, with separate contacts, campaigns, transactional sending, reports, senders, and allocated limits; its API can create sub-accounts, set email credits, and enable or disable transactional email and email campaigns separately. This most closely matches the existing one-Twilio-subaccount-per-organization decision. [Brevo sub-account management](https://help.brevo.com/hc/en-us/articles/9003097317138-Classic-Admin-account-What-is-sub-accounts-management), [create sub-account API](https://developers.brevo.com/reference/create-a-new-sub-account-under-a-master-account), [sub-account plan API](https://developers.brevo.com/reference/update-sub-accounts-plan), [application controls API](https://developers.brevo.com/reference/enable-disable-sub-account-application-s)

Before implementation, confirm Brevo Corporate pricing and API access. If it is not commercially suitable at launch, use one UCRM-owned Brevo account only as a temporary adapter-backed arrangement. In that fallback, UCRM remains the source of tenant identity, contacts, consent, suppression, quotas, and templates; every send and callback carries an opaque organization/message correlation value. A shared provider account increases reputation and suppression blast radius, so it should not become an unexamined permanent architecture.

Never expose a provider API key to browser code or contractor users. Store organization-to-provider-account identifiers and credentials server-side, and route all sends through UCRM's application service.

### 2. Sender identity and onboarding

Offer two readiness levels:

- **Platform sender:** a UCRM-owned, authenticated sending domain for low-volume operational email while an organization onboards. The visible display name is the contractor business, but the actual From address must be honest and aligned with the authenticated UCRM domain. It should not impersonate the contractor's unauthenticated domain.
- **Verified business sender:** the recommended production state. The contractor authenticates a dedicated sending subdomain, for example `mail.contractor.com`, and selects verified From identities for operational and marketing mail.

Require SPF and DKIM verification before contractor-domain sending, recommend DMARC from the beginning, and require DMARC plus aligned authentication for bulk marketing readiness. Gmail requires SPF or DKIM for all senders and SPF, DKIM, DMARC, alignment, and one-click unsubscribe for senders over its bulk threshold. New domains must ramp volume gradually. [Google sender guidelines](https://support.google.com/mail/answer/81126?hl=en)

HighLevel similarly offers a shared fallback but recommends a dedicated authenticated domain to preserve brand identity and deliverability; it allows domains to be assigned by message purpose. [HighLevel dedicated domains](https://help.gohighlevel.com/support/solutions/articles/48001226115-lc-email-dedicated-sending-domains)

Model readiness explicitly: `Not configured`, `Platform sender available`, `DNS pending`, `Verified`, `Warm-up`, `Restricted`, and `Provider blocked`. Show exact DNS instructions and recheck results. Do not promise that DNS verification alone guarantees inbox delivery.

### 3. Replies and the unified inbox

Every customer-facing operational email should have a reply route owned by UCRM, not depend on a contractor employee's personal mailbox. Use a unique, opaque reply address or conversation token on a dedicated UCRM inbound domain. Brevo requires an inbound parsing domain different from the sending domain, delegates it through MX records, and posts parsed messages as structured JSON to a webhook. [Brevo inbound parse](https://developers.brevo.com/docs/inbound-parse-webhooks)

The inbound pipeline should:

- resolve the token to organization, customer, conversation, work item, and intended assignee;
- reject cross-tenant or expired routing without revealing tenant data;
- store the original provider identifiers and attachments safely;
- deduplicate repeated callbacks;
- show the reply in the unified inbox and related work history;
- fall back from a deactivated or unauthorized assignee to an organization inbox/administrator;
- preserve the thread while allowing reassignment.

Jobber's model supports reply routing by work type and falls back when the selected team member is deactivated or loses permission. That is a useful behavior reference, though UCRM should keep replies inside its unified inbox instead of forwarding them only to one external mailbox. [Jobber email reply settings](https://help.getjobber.com/hc/en-us/articles/9335574672151-Emails-and-Text-Messages-Settings)

Do not treat open tracking as proof a human read a message. Brevo reports proxy-open events separately, and privacy proxies make opens approximate. Delivery, bounce, click, reply, secure-link view, approval, and payment are distinct events. [Brevo transactional webhooks](https://developers.brevo.com/docs/transactional-webhooks)

### 4. Consent, unsubscribe, and suppressions

Maintain separate organization-scoped preferences for at least:

- essential operational email;
- optional operational reminders/follow-ups;
- marketing email and relevant consent source/evidence.

Marketing must always honor unsubscribe and complaint state. For Canada, record the consent basis and evidence because CASL puts the burden on the sender; a commercial electronic message generally requires consent, sender identification, and an unsubscribe mechanism. For the US, commercial email must follow CAN-SPAM, while genuinely transactional or relationship mail is treated differently; mixing promotional material into an operational email can make it commercial. [CRTC CASL guidance](https://crtc.gc.ca/eng/com500/guide.htm), [FTC CAN-SPAM guide](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business)

Always include a clear unsubscribe link and one-click unsubscribe headers in marketing/subscribed mail. Never place advertisements in password resets, security notices, receipts, or other essential messages.

Consume provider events for hard bounce, invalid address, complaint/spam, blocked, and unsubscribe. Brevo keeps campaign and transactional blocklisting distinct and can scope a transactional unsubscribe to a sender; UCRM should mirror provider suppression while keeping its own auditable source of truth so a provider change does not erase consent history. [Brevo blocklists](https://help.brevo.com/hc/en-us/articles/209458705-What-is-a-blacklisted-contact-), [Brevo unsubscribe guidance](https://help.brevo.com/hc/en-us/articles/9741388688402-Do-I-need-to-add-an-unsubscribe-link-to-my-emails)

Hard-bounced or complaint addresses must not be retried automatically. Re-enabling requires a controlled reason and, where relevant, fresh consent or corrected address evidence.

### 5. Sending, callbacks, retries, and limits

Use an application-owned outbound record before calling Brevo. Give each logical email a stable internal idempotency key, persist the provider `messageId`, and never regenerate a new key merely because the worker retried. Brevo supports an idempotency header, but its documented window is limited, so UCRM's database uniqueness remains the durable protection. [Brevo idempotency](https://developers.brevo.com/docs/heterogenous-versions-batch-emails), [send transactional email](https://developers.brevo.com/reference/send-transac-email)

Authenticate Brevo callbacks with bearer/custom-header support and network controls, validate payloads, and process them idempotently. Webhook event ordering is not a safe state machine: preserve raw events and advance a normalized delivery projection without allowing a late `sent` event to overwrite `delivered` or `hard_bounce`. [Brevo secured webhooks](https://developers.brevo.com/docs/secured-webhooks), [Brevo webhook events](https://developers.brevo.com/docs/transactional-webhooks)

Queue sends and apply per-organization and platform limits even where Brevo's API ceiling is higher. On `429`, respect provider headers and retry with bounded backoff. Use webhooks instead of polling for delivery statistics. [Brevo API limits](https://developers.brevo.com/docs/api-limits)

Suggested limits and guards:

- separate operational and marketing daily caps;
- new-domain warm-up cap;
- recipient-level frequency caps for automations;
- duplicate-content and sudden-volume alerts;
- complaint and hard-bounce thresholds that automatically pause marketing first;
- essential operational mail allowed only while the sender remains deliverability-safe;
- Jafar platform pause and per-organization pause.

### 6. Billing and usage

For launch:

- include operational email in subscription packages under a monthly usage allowance;
- give marketing email a separate entitlement and lower initial cap;
- show contractors sent, delivered, bounced, complained, unsubscribed, and remaining allowance;
- show Jafar provider allocation/cost, organization usage, overage exposure, and reputation incidents;
- do not deduct Communication Balance per ordinary email;
- do not let an exhausted marketing allowance block password resets or valid essential operational email;
- allow Jafar to add a reasoned organization override and emergency pause.

If real provider economics later justify metered email, publish versioned retail email rates and charge only from that point forward. Never silently convert historic package-included email into ledger charges.

### 7. Suspension and closure

On organization suspension:

- stop contractor-created outbound email and new marketing campaigns;
- cancel or pause queued automations safely;
- preserve message history, suppressions, consent evidence, domains, and provider callbacks;
- continue necessary provider reconciliation, inbound receipt, unsubscribe, and complaint processing;
- permit only narrowly defined platform/security notices.

On reactivation, do not release a backlog of stale reminders or campaigns. Re-evaluate each scheduled message against current work state, consent, expiry, and frequency limits.

During closure, preserve inbound routing for the approved recovery window and prevent new sends. Before provider sub-account/domain removal, preview queued mail, inbound aliases, suppressions, exports, and retention consequences. Brevo documents sub-account deletion as permanent and unrecoverable, so provider deletion must be a final, explicit cleanup step rather than the first closure action. [Brevo API changelog](https://developers.brevo.com/changelog/2026/4/17)

### 8. Jafar controls

Give the Platform Owner these organization-scoped controls:

- Operational Email: `Disabled`, `Platform Sender`, `Verified Business Sender`;
- Marketing Email: `Disabled`, `Enabled with limits`;
- provider/sub-account health and last successful reconciliation;
- domain/authentication/readiness status;
- operational and marketing caps plus package/organization override provenance;
- pause/resume with reason, impact preview, immutable history, and safe backlog handling;
- bounce, complaint, unsubscribe, and unusual-volume alerts;
- resend/retry tools that cannot bypass consent, suppression, idempotency, or tenant authorization;
- provider-blocked recovery workflow and closure cleanup status.

Contractors may choose a lower capability, configure eligible senders, templates, reply assignment, and preferences, but cannot exceed Jafar's maximum or bypass platform safety rules.

## Recommended first-release boundary

Build operational email first:

- platform fallback sender;
- one verified contractor sending domain;
- request, assessment, quote, job/visit, invoice, receipt, and direct-reply email;
- UCRM-owned inbound reply routing into the unified inbox;
- delivery/bounce/complaint/suppression events;
- package usage cap and Jafar pause/readiness controls.

Add bulk marketing only after consent evidence, unsubscribe, list hygiene, domain warm-up, campaign review, reporting, and abuse controls are complete. This follows Jobber's visible separation between operational communications and campaigns rather than treating every email automation as equivalent. [Jobber communication settings](https://help.getjobber.com/hc/en-us/articles/9335574672151-Emails-and-Text-Messages-Settings), [Jobber campaigns](https://help.getjobber.com/hc/en-us/articles/19885016029207-Campaigns-Marketing-Tools)

## Decisions still required

1. Is Brevo Corporate/sub-account pricing acceptable, or must launch use a shared Brevo account?
2. Which operational messages are essential and may continue when optional email is disabled?
3. Should platform-fallback sending be time-limited, volume-limited, or both before domain authentication is required?
4. What monthly operational and marketing email allowances belong to each package?
5. Is marketing email part of the initial contractor campaign or a later independently gated part?
6. Should contractors connect an existing mailbox for additional inbox ingestion later, or will the first release receive only replies to UCRM-sent email?
7. How long should inbound aliases and message/attachment data remain available during closure and after permanent organization deletion?

## Provider alternatives

Do not add a second provider at launch. Keep the sending/inbound adapter boundary narrow enough to replace Brevo if needed. Postmark's separate transactional and broadcast message streams, for example, reinforce the recommended separation and isolate suppressions/statistics by stream, but switching providers now would add operational complexity without resolving a current need. [Postmark message streams](https://postmarkapp.com/developer/user-guide/message-streams/message-streams-overview)
