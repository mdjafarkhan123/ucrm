# Amazon SES architecture for opt-in marketing campaigns

**Researched:** 2026-09-18  
**Scope:** Current provider, mailbox, and legal requirements for using Amazon SES as UCRM's marketing-email delivery service. This is product/engineering guidance, not legal advice or a measured capacity claim.

## Recommendation

Use Amazon SES **only for Marketing**, while Brevo continues to carry operational email. Treat SES as the delivery pipe, not as the campaign database:

- UCRM owns consent evidence, recipient selection, immutable campaign snapshots, pacing, cancellation, unsubscribe, and recipient results.
- Create one SES **tenant per contractor organization**, with that contractor's verified sending identity and configuration set assigned to it. Enable tenant-scoped bounce-and-complaint suppression and start with SES's `Standard` automatic reputation policy.
- Send one personalized message per recipient through the SES v2 `SendEmail` API, always naming the tenant and configuration set.
- Publish SES events through the configuration set to SNS, buffer them in SQS, and project them idempotently into UCRM. Keep the SES message ID mapped to the UCRM recipient row.
- Start on SES shared IPs. Use paced application queues and a measured domain warm-up; do not buy dedicated IPs until real, regular volume shows that they are justified.

This is the established multi-tenant email-platform pattern: separate marketing from service mail, isolate each customer's reputation/resources, send only to proven subscribers, release gradually, and treat provider acceptance as `Submitted` rather than `Delivered`.

## Why UCRM must own the campaign and consent records

SES's native list management allows only **one contact list per AWS account** and no more than **20 topics** in that list. It therefore cannot represent independently auditable preferences for an open-ended number of contractor organizations. UCRM should not make SES contacts or topics its legal or product source of truth. [AWS: SES list management](https://docs.aws.amazon.com/ses/latest/dg/sending-email-list-management.html)

UCRM should instead keep an append-only marketing-consent history plus a current projection, scoped to `(organization, normalized email address, email marketing)`. At minimum, each evidence event should retain:

- granted or withdrawn state, precise event time, and the email address it covered;
- capture source (public form, staff-recorded verbal/written consent, one-click unsubscribe, complaint, or import);
- exact disclosure text/version and the contractor identity named to the person;
- who or what recorded it, and enough source metadata to prove the event without storing unnecessary personal data;
- for an online opt-in, confirmation status and time if double opt-in is used.

Consent is specific to a contractor and address; it must not silently transfer between contractors or to another address. A campaign launch freezes an immutable recipient/content snapshot, but the dispatcher must re-check current consent, contact policy, unsubscribe, suppression, contractor status, and cancellation immediately before releasing each later batch.

For the first release, require a clear affirmative opt-in everywhere and reject bought, scraped, or third-party lists. This is stricter than US CAN-SPAM alone, but it matches AWS's production-access acknowledgement, Gmail's subscriber guidance, Canada's CASL, and the safest UK/EU rule. Jurisdiction-specific “soft opt-in” or implied-consent paths should be a later, separately reviewed feature—not a shortcut in the first release.

## SES account and production-access requirements

SES is regional. New accounts start in the sandbox in each Region: recipients must be verified (apart from the mailbox simulator), with a limit of 200 messages per rolling 24 hours and 1 message per second. Production access permits unverified recipients, but all From/Source/Sender/Return-Path identities still need verification. Quotas remain region- and account-specific. [AWS: request production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html), [AWS: SES quotas](https://docs.aws.amazon.com/ses/latest/dg/quotas.html)

Before applying, UCRM should have a real public website, privacy/acceptable-use information, a working abuse contact, a verified test domain, operational bounce/complaint processing, and the opt-in/unsubscribe design. In the request, truthfully select **Marketing**, provide the website, and acknowledge that mail goes only to people who explicitly requested it and that bounces and complaints are processed. AWS says its initial response normally arrives within 24 hours, but additional review can take longer; approval is not guaranteed. [AWS: request production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html)

Published API limits are ceilings, not safe campaign speed. The post-sandbox 24-hour and per-second allowances vary by account and Region, count recipients rather than API calls, and may be increased later. The dispatcher must read the account's live quota, reserve headroom, pace below it, and retry throttling with backoff. Do not translate a registered-user count into a delivery or concurrency promise. [AWS: managing SES sending limits](https://docs.aws.amazon.com/ses/latest/dg/manage-sending-quotas.html)

## Domain authentication and sender readiness

Each contractor must finish domain onboarding before Marketing can launch:

1. Verify the contractor's domain identity in the chosen SES Region.
2. Enable SES Easy DKIM with the default 2048-bit key and publish the returned CNAME records.
3. Configure a dedicated custom MAIL FROM subdomain, such as `bounce.example.com`, and publish SES's MX and SPF records. Do not use that subdomain to send normal From addresses or receive ordinary mail.
4. Publish DMARC on the visible From domain, beginning with reporting and at least `p=none`; verify alignment, collect reports, then tighten policy only after legitimate senders are inventoried.
5. Use a stable marketing From address and a real monitored Reply-To. Keep operational and marketing identities/queues separate.

Easy DKIM signs mail automatically; SES currently defaults it to 2048 bits. A custom MAIL FROM gives SPF alignment when its domain matches or is a subdomain of the visible From domain. DMARC passes when aligned SPF or DKIM passes; configuring both is the safe baseline. [AWS: DKIM](https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dkim.html), [AWS: custom MAIL FROM](https://docs.aws.amazon.com/ses/latest/dg/mail-from.html), [AWS: DMARC](https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dmarc.html)

Gmail requires SPF or DKIM for all senders; a sender crossing roughly 5,000 messages to personal Gmail accounts in 24 hours must use SPF, DKIM, DMARC (`p=none` is accepted), aligned From authentication, and one-click unsubscribe for promotional/subscription mail. Google permanently retains bulk-sender classification once reached. Yahoo requires SPF or DKIM for all senders and, for bulk senders, SPF, DKIM, passing DMARC with From alignment, body unsubscribe, and list unsubscribe. Yahoo deliberately does not publish a numeric bulk threshold. Design every marketing sender to the bulk standard from day one. [Gmail sender guidelines](https://support.google.com/mail/answer/81126), [Gmail sender FAQ](https://support.google.com/mail/answer/14229414), [Yahoo sender requirements](https://senders.yahooinc.com/best-practices/), [Yahoo sender FAQ](https://senders.yahooinc.com/faqs/)

## Tenant and reputation isolation

Create one SES tenant per contractor and assign at least one dedicated verified identity and one dedicated configuration set. SES validates on every tenant send that its identity, configuration set, and template are associated with that tenant. Use opaque stable organization-derived names rather than customer-visible names or database secrets. [AWS: SES tenants](https://docs.aws.amazon.com/ses/latest/dg/tenants.html)

Configure each tenant with:

- `SuppressionScope=TENANT` and both `BOUNCE` and `COMPLAINT` reasons;
- the `Standard` reputation policy initially, which automatically pauses on high-severity findings;
- EventBridge alerts for reputation findings and tenant sending-status changes;
- an application-level pause that stops unreleased marketing independently of SES.

Tenant suppression prevents one contractor's bounce or complaint from suppressing that address for every other contractor. This setting is **not the default**; without it, tenants share the account-level suppression list. Tenant isolation is defense-in-depth, not a guarantee for the whole platform: AWS explicitly says combined tenant activity still affects the account's reputation and can put the entire account at risk. [AWS: tenant suppression](https://docs.aws.amazon.com/ses/latest/dg/sending-email-suppression-list-tenant-level.html), [AWS: SES tenants](https://docs.aws.amazon.com/ses/latest/dg/tenants.html)

The default SES quota is currently 10,000 tenants and 10,000 verified identities per Region; those are resource defaults, **not evidence that UCRM supports that many organizations or any particular traffic level**. Tenant quota is adjustable; identity planning needs confirmation with AWS. [AWS: SES quotas](https://docs.aws.amazon.com/ses/latest/dg/quotas.html)

## Unsubscribe and legal suppression

Every marketing message must contain both:

- a clear visible unsubscribe link in the body; and
- RFC 8058 headers: `List-Unsubscribe: <https://...>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`.

The signed, opaque URL must work without login, accept the mailbox provider's POST without confirmation, reveal no internal IDs, be idempotent, and withdraw that recipient's marketing consent for that contractor immediately. A preferences page may be offered separately, but it cannot replace one-click unsubscribe. Never send an unsubscribe confirmation email to an address that has complained. [Gmail one-click requirements](https://support.google.com/mail/answer/81126), [Yahoo sender requirements](https://senders.yahooinc.com/best-practices/), [AWS complaint guidance](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html)

Do not use SES `ListManagementOptions` as UCRM's primary unsubscribe system. Although SES can add compliant headers and manage preference updates, its one-account/20-topic list limit does not provide contractor-scale preference isolation. UCRM-owned one-click handling also permits the required organization-scoped audit event and immediate suppression before the next batch. SES supports the required header fields. [AWS: SES subscription management](https://docs.aws.amazon.com/ses/latest/dg/sending-email-subscription-management.html), [AWS: SES list limits](https://docs.aws.amazon.com/ses/latest/dg/sending-email-list-management.html), [AWS: supported headers](https://docs.aws.amazon.com/ses/latest/dg/header-fields.html)

Keep suppression meanings separate:

- unsubscribe or withdrawal: block future **marketing** for that contractor;
- complaint: immediately block future marketing for that contractor and investigate the source/list;
- hard bounce/invalid address: stop all email attempts to that contractor/address until the address is legitimately corrected;
- temporary delay: retry only under the delivery policy; it is not consent withdrawal.

SES tenant suppression is additional protection, but UCRM must keep its own durable record and check it before send. SES notes that Gmail does not provide complaint addresses to SES, so Gmail Postmaster Tools/domain reputation monitoring is also required; tenant suppression alone cannot see every complaint. [AWS: tenant suppression limitations](https://docs.aws.amazon.com/ses/latest/dg/sending-email-suppression-list-tenant-level.html), [Gmail Postmaster guidance](https://support.google.com/mail/answer/81126)

## Events, status, and automatic safety

Give each tenant configuration set an event destination covering at least send, reject, delivery, hard bounce, complaint, delivery delay, and rendering failure. A `Send` event means SES will attempt delivery; only a `Delivery` event means the recipient's mail server accepted it. Open/click events are optional analytics and must never redefine delivery. [AWS: SES event destinations](https://docs.aws.amazon.com/ses/latest/dg/event-destinations-manage.html)

Recommended flow:

`SES configuration set -> SNS topic -> SQS queue + dead-letter queue -> idempotent UCRM event worker`

SNS is a supported SES event destination, and AWS documents SNS-to-SQS subscriptions. This buffer lets the VPS or worker restart without requiring SES to call it directly. Store raw provider events first, deduplicate/project by stable event identity and recipient state, tolerate duplicates and out-of-order arrival, and never downgrade a terminal result because an older event arrived late. Use SES message tags only for opaque campaign/recipient correlation, and retain the returned SES message ID because complaint reports can redact the recipient address. [AWS: SES event publishing](https://docs.aws.amazon.com/ses/latest/dg/monitor-using-event-publishing.html), [AWS: SNS to SQS](https://docs.aws.amazon.com/sns/latest/dg/subscribe-sqs-queue-to-sns-topic.html), [AWS: SES complaint mapping](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html)

Immediate recipient suppression is required even before a rate threshold is meaningful. At the contractor and whole-account levels, monitor bounce, complaint, reject, deferral, and throttle signals. AWS's current guidance is:

- keep hard bounces below 2%; review begins at 5% and sending may be paused at 10%;
- keep complaints below 0.1%; review begins at 0.1% and sending may be paused at 0.5%.

These are enforcement boundaries, not targets. Gmail recommends staying below 0.1% user-reported spam and never reaching 0.3%; Yahoo requires below 0.3%. UCRM should warn and pause earlier based on representative samples and measured production behavior, with Jafar review before resuming a risky contractor. A tiny sample must not pretend to be a stable percentage, but one complaint or hard bounce still suppresses that recipient immediately. [AWS: sending-review thresholds](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html), [Gmail spam guidance](https://support.google.com/mail/answer/81126), [Yahoo sender requirements](https://senders.yahooinc.com/best-practices/)

## Shared versus dedicated IPs and warm-up

Start with SES shared IPs. AWS recommends shared IPs when volume is not large, regular, and predictable. A new contractor campaign is typically irregular and does not yet have evidence to justify its own IP. Shared IPs do share some reputation risk, but contractor domains, SES tenants, per-tenant pauses, and the separate Brevo operational lane limit the blast radius. [AWS: shared and dedicated IP comparison](https://docs.aws.amazon.com/ses/latest/dg/dedicated-ip.html)

A dedicated IP is not an automatic deliverability upgrade. Standard dedicated IPs need gradual warming; AWS says this may take roughly two to six weeks and its automatic standard-IP warm-up progresses over 45 days. They also need consistent continuing volume. Managed dedicated IPs automate ISP-specific warm-up and scaling and are the later option for irregular high volume, but only after measured traffic and cost justify them. [AWS: dedicated IP warm-up](https://docs.aws.amazon.com/ses/latest/dg/dedicated-ip-warming.html), [AWS: managed dedicated IPs](https://docs.aws.amazon.com/ses/latest/dg/managed-dedicated-sending.html)

Shared IPs do not remove domain warm-up. Gmail says to start with low volume to the most engaged subscribers, send at a consistent rate rather than bursts, increase slowly, and reduce volume when bounces or deferrals rise. Therefore UCRM needs a per-contractor warm-up state and adaptive queue limits; there is no universal “emails per day” schedule that is safe for every contractor. [Gmail sender guidelines](https://support.google.com/mail/answer/81126)

## Minimum legal product baseline

The product should use the strictest common baseline by default and still obtain legal review before a worldwide launch:

| Market | Official minimum that materially affects UCRM |
| --- | --- |
| United States | CAN-SPAM requires accurate headers and subjects, clear ad identification, a valid postal address, a clear opt-out, an opt-out mechanism available for at least 30 days, and honoring opt-out within 10 business days. The promoted business and sending provider can both be responsible. It does not generally require prior opt-in, but AWS does. [FTC CAN-SPAM guide](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business) |
| Canada | CASL applies to commercial messages received in Canada even when sent abroad. It requires provable express or valid implied consent, identification of the sender and anyone on whose behalf it is sent, contact information, and an easy unsubscribe kept valid at least 60 days and processed without delay/no later than 10 business days. [CRTC CASL FAQ](https://crtc.gc.ca/eng/com500/faq500.htm), [CRTC implied-consent guidance](https://crtc.gc.ca/eng/com500/guide.htm) |
| United Kingdom | PECR normally requires affirmative, specific, informed consent for unsolicited email to individuals, sole traders, and some partnerships, unless every “soft opt-in” condition is met. The soft opt-in requires direct collection during a sale/negotiation, only the sender's similar services, and an opt-out both at collection and in every message. Consent evidence should show who, when, how, and the specific channel. Corporate subscribers differ, but identity and opt-out still apply. [ICO electronic-mail guidance](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guidance-on-direct-marketing-using-electronic-mail/how-do-we-comply-with-the-pecr-electronic-mail-marketing-rules/) |
| European Union | The ePrivacy Directive establishes prior consent for direct-marketing email to natural persons, with a limited existing-customer exception for the sender's own similar products/services when easy, free objection is offered at collection and in every message. Member States implement the details, so a global product cannot safely infer permission from “customer” status alone. [EU ePrivacy Directive, Article 13](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX:02002L0058-20091219) |

Operationally, process unsubscribe immediately—faster than every quoted legal/provider window—retain the suppression event rather than deleting the person, show the contractor's legal/business identity and postal address in every marketing footer, and require each contractor to certify that its recipients and content are lawful. Contracts and an acceptable-use/enforcement process are still needed because platform controls do not transfer legal responsibility away from the contractor or UCRM.

## Safe phased rollout

### Phase 0 — approve the boundary

Approve SES as Marketing-only, one tenant per contractor, one Region initially, shared IPs, UCRM-owned consent/unsubscribe, and no purchased lists. Get counsel to approve customer terms, privacy roles, first-release consent wording, and supported countries. This approval authorizes a plan, not infrastructure changes.

### Phase 1 — sandbox proof

Using a platform test domain and internal test tenant, configure DKIM/SPF/DMARC/custom MAIL FROM, tenant suppression, configuration set events, SNS/SQS/DLQ, IAM least privilege, and alarms. Prove success, hard bounce, complaint, delay/retry, duplicate/out-of-order event handling, one-click and body unsubscribe, cancellation, and worker restart using verified recipients and SES simulator addresses.

### Phase 2 — production access and controlled pilot

Apply truthfully for Marketing production access. Pilot with one approved contractor, a small recent double-opt-in audience, manual campaign approval, a platform emergency pause, and a conservative per-tenant cap below live SES quotas. Start with engaged recipients and spread release steadily. Verify authentication in real Gmail/Yahoo headers and monitor Postmaster/reputation signals.

### Phase 3 — evidence-led expansion

Add contractors in small cohorts only after the prior cohort's delivery, bounce, complaint, unsubscribe, event lag, cancellation, and operational-email latency stay healthy. New domains receive their own warm-up limits. Automatically slow or stop on deferrals, bounces, complaints, SES tenant findings, missing DNS, stale consent, or quota pressure. Never auto-resume a reputation pause.

### Phase 4 — production readiness

Before broad availability, rehearse provider outage, SQS/DLQ backlog, account/tenant pause, quota exhaustion, compromised tenant, bad-list import, DNS breakage, unsubscribe during an active campaign, and clean recovery. Load-test the dispatcher/event path with production-like shapes while confirming Brevo operational mail remains unaffected. Capacity statements may cover only the workloads actually measured.

### Phase 5 — revisit IP strategy only with evidence

Consider managed or standard dedicated IP pools only when measurements show regular volume, clear isolation needs, affordable cost, and the ability to warm and sustain each IP. Do not make dedicated IPs a launch dependency.

## Decision and unresolved checks

SES is a sound leading choice for the blueprint's per-recipient, per-contractor Marketing path **if** production access is approved and the sandbox pilot proves event, suppression, unsubscribe, and domain onboarding behavior. Before implementation, Jafar still needs to approve the concrete AWS topology and account/Region choice under the project's infrastructure boundary.

Also confirm with AWS before committing the release plan:

- the account's granted production quota and increase path for the measured pilot workload;
- tenant/identity quota expectations for the near-term organization count;
- the selected SES pricing plan and tenant charges current at purchase time; pricing changed in July 2026 and should not be copied from older estimates. [AWS SES pricing](https://aws.amazon.com/ses/pricing/)

No source supports an inbox-placement promise, a fixed completion time, or capacity derived from UCRM's 40,000-user target. Those claims require staged, production-like evidence.
