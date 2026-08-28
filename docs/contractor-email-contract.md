# Contractor Email Product Contract

Status: Approved product behavior, not yet implemented  
Approved: 2026-08-15  
Scope: Contractor operational email, inbound replies, tenant controls, and Platform Owner controls

Research evidence lives in:

- `docs/research/contractor-email-service-model.md`
- `docs/research/contractoros-email-reference.md`
- `docs/research/email-reputation-thresholds.md`
- `docs/research/ghl-email-gap-review.md`
- `docs/research/jobber-email-gap-review.md`

This contract does not reopen or alter approved phone or SMS behavior. Marketing email, broad
inbound email, and connected Gmail or Outlook mailboxes are later independently gated work.

## Product boundary

Operational email launches before marketing email. It covers request and assessment confirmations,
quotes and follow-ups, job and visit updates, invoices and reminders, payment receipts, review
requests without promotional content, and direct staff replies.

A plain post-job review request is optional operational email. A message containing a discount,
referral reward, promotion, cross-sell, or unrelated sales content is marketing.

Every package can receive replies to UCRM-sent operational email in Conversations. Starter receives
this email-thread access even though broader multichannel inbox capabilities may remain a higher
package entitlement.

## Brevo and tenant isolation

Launch with one platform-owned Brevo account and one server-held credential. Keep the email provider
behind a narrow adapter so an organization can move to a Brevo sub-account or another provider later.

Tenant isolation is enforced in UCRM:

- one verified sending subdomain and one separate receiving subdomain per organization;
- globally unique domain claims backed by database constraints;
- organization-scoped sends, callbacks, aliases, suppressions, usage, and audit history;
- an account-wide emergency pause and organization-specific pauses;
- no provider credential in browser code or contractor-visible payloads.

Platform and security email uses a separate UCRM system identity. Contractor-to-customer email never
falls back to that identity.

## Domain provisioning and sender identity

Jafar claims, verifies, replaces, restricts, and removes contractor domains. The default structure is
`mail.contractor.com` for sending and `reply.contractor.com` for receiving. Jafar may choose different
prefixes, but sending and receiving domains must differ.

Brevo verification plus passing SPF and DKIM is required before sending. DMARC with at least `p=none`
is required before higher-volume optional email. Domain health is checked at least daily and on
provider authentication failures. Suspicious changes, prolonged failure, replacement, or organization
transfer require ownership revalidation.

Organization administrators may create and disable sender addresses after domain verification.
Regular staff use only identities allowed by their role or assignment. Jafar may inspect, restrict, or
disable any sender.

Sender priority follows this order:

1. Manual email uses the logged-in staff member's assigned verified sender.
2. Automated email uses the sender explicitly configured in the automation.
3. Without an automation sender, use the contact's assigned eligible user.
4. For an unassigned contact, use the organization's default verified sender.

Manual display names default to `Staff Name | Business Name`; automated email defaults to the business
name. Inactive staff immediately lose sending eligibility. Queued manual email requires review and
reassignment rather than silently changing identity.

When a domain is replaced, verify the new domain before switching outbound mail. Keep old inbound
routing for 30 days by default. Jafar may change the transition period. Re-evaluate queued messages
against the new identity before sending.

## Warm-up and sending capacity

Newly verified domains use these editable defaults:

| Period | Maximum accepted recipients per day |
| --- | ---: |
| Days 1 through 3 | 100 |
| Days 4 through 7 | 250 |
| Days 8 through 14 | 500 |
| After day 14 | Organization limits |

Only wanted operational traffic advances warm-up. Complaints, hard bounces, suspicious spikes, or long
inactivity may pause or step back the domain. Jafar can edit platform defaults and organization values.

The default short-term organization limit is 100 recipients per 10 minutes. Valid operational email
over that limit is deferred with an estimated retry time. Abuse signals pause sending instead.

Jafar configures total provider-period capacity. Ten percent is reserved by default for platform/system
mail and protected essential contractor mail. Jafar can edit both values. Ordinary organization mail
cannot consume the protected platform reserve.

## Package allowances and counting

Operational email is included in packages and does not deduct Communication Balance.

| Package | Billing-period allowance | Protected essential reserve |
| --- | ---: | ---: |
| Starter | 2,500 recipients | 250 recipients |
| Growth | 10,000 recipients | 1,000 recipients |
| Elite | 30,000 recipients | 3,000 recipients |

Allowances reset at the organization's subscription-period boundary. Store the boundary as an exact UTC
timestamp and display it in the organization timezone. Package changes follow explicit proration rules
and never silently create a new full allowance.

Count each unique recipient accepted for provider submission. A message to three recipients counts as
three. A retry with the same idempotency key does not count again. Validation rejection does not count.
A provider-accepted message counts even if it later bounces. Forwarded copies count consistently.

Optional email pauses at the normal allowance. The protected reserve permits requested quotes, invoices,
receipts, security notices, and direct human replies. If the reserve is exhausted, queue essential mail
temporarily, warn the organization, and alert Jafar. Re-evaluate every queued message before release.

Jafar controls all allowance values while package defaults remain visible. An organization override may
set a number, restore the package default, be effective-dated, or be unlimited subject to platform safety.
Every override shows its author, reason, start, optional end, effective value, and fallback value.

## Preferences, consent, and suppressions

Preferences are stored per contact within an organization and separately cover quote follow-ups, invoice
follow-ups, assessment and visit reminders, job follow-ups, review requests, and future marketing.

Requested quotes, invoices, receipts, security notices, and direct replies remain eligible when relevant.
Optional reminders and follow-ups honor category preferences. An authorized staff member may record a
customer's verbal preference with an audit note.

A complaint immediately suppresses non-security mail from that organization. A hard bounce prevents
further sending until the address is corrected and verified. UCRM owns an auditable suppression record
and reconciles it with Brevo.

Organization administrators may request removal of a corrected hard-bounce suppression. Only Jafar may
approve complaint-suppression removal. Removal requires a reason, evidence, and any required renewed
consent.

Marketing email later requires consent evidence, immediate one-click unsubscribe processing, list
hygiene, frequency controls, and separate readiness. A marketing opt-out never blocks valid essential
operational email.

## Reputation controls

Use rolling 24-hour and seven-day views. The initial configurable defaults are:

| Signal | Warn | Pause optional email |
| --- | ---: | ---: |
| Complaint rate | 0.05% | 0.10% |
| Hard-bounce rate | 1.00% | 2.00% |
| Marketing unsubscribe rate | 0.50% | 1.00% |

Apply rate-based pausing after at least 1,000 accepted recipients, or earlier after three complaints or
20 hard bounces. Recipient suppression happens immediately regardless of sample size.

Jafar can configure warnings, organization pause thresholds, samples, event-count triggers, and windows.
Organization overrides cannot weaken the platform safety ceiling. Changing the platform ceiling requires
separate confirmation, an impact warning, a reason, and immutable history.

Only Jafar resumes an automatic reputation pause. At or beyond a provider danger threshold, resumption
requires explicit confirmation and remediation review. Resumption never releases stale optional mail.

## Conversations and replies

First release receives replies only to UCRM-sent operational email. It does not ingest a contractor's
general mailbox or accept unrelated inbound lead email.

Replies use an opaque conversation address on the organization's receiving subdomain. No organization,
contact, staff, job, quote, or invoice identifier appears in the address.

The contact's assigned user owns the conversation. Replies remain in shared Conversations. Optional
forwarding sends a copy to the assigned user's staff mailbox. An inactive or missing owner falls back to
the shared Unassigned queue.

Conversations provides All, Mine, Unassigned, unread, starred, and saved views. Ownership, following, and
mentions remain distinct. Administrators can see all organization conversations. Ordinary staff see
authorized client/work conversations when they own, follow, or are mentioned. Staff with intake permission
may access Unassigned.

Reply aliases remain active while the conversation or related work is active and for 90 days after closure
or last activity. Jafar may configure the default. Replies to expired aliases enter a guarded organization
review queue without automatically exposing the former conversation.

Auto-response headers, delivery notices, and repeated-message patterns do not trigger customer automations
or ordinary assignment alerts. Loop protection pauses the thread and alerts an administrator.

## Recipients, forwarding, and portal access

Manual email supports CC. Every recipient is visible and counted. Contractor-entered BCC is unavailable at
launch. An administrator may configure a clearly disclosed archival destination, which is audited.

Replies from a To or CC recipient, or an address already connected to the customer, may join the guarded
thread. Unknown senders require review.

Administrators may externally forward one inbound message. Other staff require explicit permission.
Forwarding previews recipients and attachments and creates an audit event, matching HighLevel's forward
action. It neither shares the whole conversation nor grants portal access.

CC grants access only to the message and included attachments. Quote and invoice links are narrowly scoped,
expiring document links. CC never grants broad portal, appointment, history, or financial access. Broader
access requires an explicit client-contact invitation.

## Templates, snippets, and branding

Jafar manages the platform template library and controls organization or package visibility. Organization
administrators may copy a platform template, customize it, or create an organization template. A copied
template is organization-owned and is not overwritten by platform changes.

Automation steps own controlled template copies. Synchronization is off by default and requires an impact
preview. UCRM may show that a newer platform template exists and offer adoption without overwriting content.

Short, folder-organized snippets are separate from templates and remain editable before manual sending.

UCRM enforces required delivery, identity, preference, security, and legal elements around editable content.
Branding comes from the approved Business Profile and is shared by emails, forms, documents, receipts, and
the customer portal.

Manual messages always show a final preview. Quote and invoice sending previews recipients and rendered
content. Approved automations send without per-message confirmation. Missing or unsafe variables block the
send with a specific correction.

## Work-item behavior

Internal staff reminders and customer follow-ups are different records. Automated quote and invoice
follow-ups go only to eligible recipients of the original document. Auto-pay suppresses invoice chasing.

Rescheduling cancels reminders for the previous time. Staff choose whether and how to notify the customer.
For recurring work, notification applies only to the selected visit unless the series is explicitly edited.

Quote and invoice email uses a secure portal button plus a copyable fallback URL and may include a generated
PDF. Portal views, quote changes, approval, signature, deposit, invoice payment, and receipt are domain events
linked to the message and work item.

Operational automations are non-retroactive, stop when the business outcome is reached, and expose execution
history from the related message. Optional sends respect organization communication hours. Requested
documents, receipts, direct replies, and urgent account notices may send immediately.

## Attachments and tracking

Inbound attachments use private organization-scoped storage, malware scanning, authorized downloads, and a
configurable 20 MB total per message. Dangerous file types are blocked. The conversation shows blocked or
oversized attachments instead of silently discarding them.

Delivery, bounce, complaint, reply, portal view, approval, and payment are first-class events. Open tracking
is off by default, approximate if enabled by Jafar, and never evidence that a human read a message. Do not
rewrite secure quote, invoice, payment, or portal links for click tracking.

## Queueing, retries, and history

Create an application-owned outbound record before calling Brevo. Every logical send has a durable
idempotency key and retains the provider message identifier. Webhook processing is authenticated,
organization-resolved, idempotent, and safe under out-of-order delivery.

Recheck recipients, permissions, status, amounts, schedules, secure links, suppression, allowance, and
sender eligibility immediately before sending. Rebuild from current data or cancel with a clear reason.

The worker claims work only through one atomic database command. That command rechecks the current
organization state and email pause, confirms that the recorded recipient is still an active email method for
the same customer, resolves the applicable normal or protected-essential allowance, and resolves an enabled
sender on a verified healthy domain. The sender and eligibility decision come from stored UCRM authority,
never from caller-supplied claims. A passing row is claimed and returned with its resolved sender in the same
transaction. A temporary failure remains unclaimed and deferred; a permanently stale recipient or an
automated send whose configured sender is permanently invalid is cancelled with a safe reason. Manual email
whose original sender is no longer eligible is held for review and is never silently reassigned. Every retry
repeats the same checks. Provider submission and usage counting
remain outside the claim transaction; usage is recorded once only after provider acceptance.

Transient failures retry with increasing delays:

- direct replies, requested quotes, and invoices retry for up to 24 hours;
- payment receipts retry for up to 72 hours;
- appointment reminders expire when their useful window passes;
- optional follow-ups expire at the next scheduled boundary or after 24 hours, whichever is sooner;
- permanent rejection, complaint, and hard bounce never retry automatically.

Resend creates a new visible attempt linked to the original, uses current state and a new idempotency key,
and cannot bypass policy or authorization.

One history links queued, deferred, sent, delivered, bounced, complained, replied, cancelled, and resent
events. It records the actor, template version, sender, recipients, related CRM record, provider identifier,
automation execution, forwarding, and administrative intervention without exposing provider secrets.

## Suspension, closure, and deletion

Organization suspension stops contractor-created outbound email and optional automations. Inbound replies,
unsubscribes, complaints, delivery callbacks, reconciliation, and narrowly necessary platform/security
notices continue. Reactivation re-evaluates queued messages and never releases a stale backlog.

Recoverable organization closure preserves inbound routing and provider resources for 30 days. Early
permanent deletion previews active aliases, queued messages, and recent replies.

Permanent purge removes messages, bodies, attachments, aliases, sender addresses, templates, consent and
suppression records, provider identifiers, Brevo domains, and webhooks. Provider cleanup failure remains a
retryable operation and cannot be reported as complete. The existing non-personal deletion receipt may
contain aggregate cleanup results but no recipients, content, domains, or message identifiers.

Provider cleanup covers the organization-owned Brevo resources UCRM actually provisions and tracks: its
sending/receiving domains and sender addresses. Brevo's inbound webhook is a single shared,
account-level registration — UCRM does not provision or persist a per-organization webhook today, so
purge reports webhook cleanup as not applicable and leaves the shared registration untouched. If a
domain-scoped inbound webhook lifecycle is introduced later, persist its opaque Brevo webhook id at
provisioning and include it in this same retryable cleanup.

## Platform Owner controls

Jafar can inspect and control:

- provider health, capacity, reconciliation, and emergency pause;
- organization operational mode, domain readiness, and sending eligibility;
- package defaults, organization allowances, essential reserves, and short-term rates;
- warm-up stages, reputation thresholds, sample rules, and observation windows;
- sender restrictions, suppressions, unusual volume, and provider incidents;
- reasoned, effective-dated overrides with immutable history;
- retry and recovery actions that still enforce consent, suppression, authorization, and idempotency;
- closure impact and provider cleanup.

Contractors may choose stricter settings but cannot exceed Jafar's maximum, weaken platform safety, or bypass
an organization or platform pause.

## Campaign ownership

The Communications campaign owns provider transport, domains, sender identities, allowances, safety,
Conversations, reply ingestion, templates, snippets, and shared email history.

Domain campaigns own their work behavior and default recipients:

- Clients and Properties owns contacts, contact roles, and category preferences.
- Requests and Assessments owns intake confirmations and assessment reminders.
- Quotes owns document recipients, follow-ups, secure quote access, and approval events.
- Jobs owns job confirmations and completion follow-ups.
- Scheduling owns visit reminders, rescheduling, and communication windows.
- Invoices and Payments owns invoice recipients, reminders, receipts, and payment events.
- Reputation owns the Magic Review Funnel and review-request eligibility.
- Contractor Settings owns organization-facing configuration surfaces.
- Client Portal owns authenticated and secure-link customer access.

Each of those major features is an individual campaign with its own roadmap and completion gates.
