# Contractor Email Product Contract

Status: Approved product behavior, not yet implemented  
Approved: 2026-08-15  
Amended: 2026-08-29 — platform-managed Cloudflare activation and per-domain Brevo inbound-webhook behavior
(the "Domain provisioning and sender identity" activation paragraph) was approved and added on this date;
it was not part of the original 2026-08-15 approval.  
Amended: 2026-09-19 — Amazon SES is the contractor operational and Marketing email provider in the dedicated
production workload account; Brevo is limited to UCRM/Jafar platform email. Contractor replies use SES receipt
rules, private S3, SNS, SQS, and the existing UCRM Conversations worker contract.
Amended: 2026-09-23 — Brevo→SES cutover decisions (Jafar): a clean switch with no Brevo fallback for contractor
email; the Platform Owner organization page shows one Email card with separate "Everyday email + replies" and
"Marketing email" rows, each with its own set-up/check action and status; a contractor without a verified sender
gets a "Request email setup" action in Settings → Email (they enter their domain; the request appears in the
Platform Owner "Needs attention" list, and the send-refusal message links there); raw inbound MIME in S3 is kept
30 days; the live-mailbox launch-gate rehearsal runs on `upliftcontractor.com` itself.
Amended: 2026-09-24 — the email setup screens (Jafar approved the designs); see "Email setup screens". Same day:
over-allowance email credit from Communication Balance; see "Package allowances and counting".
Scope: Contractor operational email, inbound replies, tenant controls, and Platform Owner controls

Research evidence lives in:

- `docs/research/contractor-email-service-model.md`
- `docs/research/contractoros-email-reference.md`
- `docs/research/email-reputation-thresholds.md`
- `docs/research/ghl-email-gap-review.md`
- `docs/research/jobber-email-gap-review.md`
- `docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md`

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

## SES and tenant isolation

Contractor-to-customer operational email and future Marketing email use Amazon SES in the dedicated UCRM
production workload account in US East (N. Virginia). Brevo is limited to UCRM/Jafar platform email. Keep the
provider behind a narrow adapter so a future reviewed provider move remains possible.

Tenant isolation is enforced in UCRM:

- one SES-verified sending subdomain and one separate SES receiving subdomain per organization;
- globally unique domain claims backed by database constraints;
- organization-scoped sends, callbacks, aliases, suppressions, usage, and audit history;
- an account-wide emergency pause and organization-specific pauses;
- no provider credential in browser code or contractor-visible payloads.

Platform and security email uses a separate Brevo-backed UCRM system identity. Contractor-to-customer email
never falls back to that identity.

## Domain provisioning and sender identity

Jafar claims, verifies, replaces, restricts, and removes contractor domains. The default structure is
`mail.contractor.com` for sending and `reply.contractor.com` for receiving. Jafar may choose different
prefixes, but sending and receiving domains must differ.

Activation is platform-managed. After the contractor's Cloudflare zone has passed a mailbox-safe import,
Jafar starts one resumable activation from the organization page. UCRM retrieves SES-issued identity and DKIM
records, writes only approved `mail`, `reply`, and optional `bounce.mail` subdomain records through a server-held,
zone-scoped Cloudflare credential, verifies the SES identities, and adds the `reply` MX for SES receipt-rule
ingestion. Customer reply MIME is stored privately in S3 and handed to the existing Conversations worker through
SNS and SQS; delivery/bounce/complaint events use a separate SES configuration-set queue. Contractors never copy
DNS records. DNS propagation and partial provider failure remain visible, retryable states; activation never
overwrites root MX, mailbox authentication, or an unexpected occupied subdomain. Provider record counts are
discovered at activation time rather than fixed in product behavior.

**Pre-first-paying-contractor launch gate (added 2026-08-29).** The internal activation fixture
(`reply.test.upliftcontractor.com`) proves Cloudflare DNS writing, SES identity and receipt-rule reconciliation,
database state, reply-alias creation, and inbound routing — but it does NOT prove preservation of a live
external root mailbox. Before onboarding the first paying contractor, rehearse the full activation on a domain
that has an ACTIVE external mailbox (Hostinger/GoDaddy/Google/Microsoft) and verify normal inbound and outbound
mailbox operation both before and after the nameserver/DNS management changes.

SES verification plus passing Easy DKIM is required before sending. A custom MAIL FROM subdomain is used for SPF
alignment and never doubles as a normal sending or reply subdomain. DMARC with at least `p=none` is required
before higher-volume optional email. Domain health is checked at least daily and on provider authentication
failures. Suspicious changes, prolonged failure, replacement, or organization transfer require ownership
revalidation.

Organization administrators may create, disable, and remove sender addresses after domain verification.
Removal (approved 2026-09-26) is a soft state change: history, reply aliases, and customer replies stay, the
address can be added again, and a sending domain can only be removed once it has no live senders. The
confirmation names the effects first (business default, assigned staff member, emails still waiting); queued
email is never re-sent from another identity -- manual email is held for review, automated email is cancelled.
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

Operational email within the package allowance is included and does not deduct Communication Balance.

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

**Over-allowance email credit (approved 2026-09-24; supersedes the two paragraph sentences above once built).**
Jafar chose a mixed approach, based on Jobber (operational email is never limited) and HighLevel (usage is taken
from a prepaid wallet):

- Essential email (requested quotes, invoices, receipts, security notices and direct human replies) never stops
  because of an allowance or the balance. It is still counted. When the protected reserve is used up, the
  organization is warned and Jafar is alerted, but essential email is no longer queued.
- Optional email beyond the period allowance takes the over-allowance price from the organization's existing
  Communication Balance, the same balance and top-up flow SMS uses. With too little balance, optional email
  pauses and the contractor is shown how to add credit.
- Platform pause, organization pause, reputation pause, suppressions and consent still stop email of both
  kinds, whatever the balance.
- Jafar sets the over-allowance price per 1,000 emails on the Jafar panel, as an effective-dated setting with
  history. The setting shows UCRM's real Amazon SES cost (about $0.10 per 1,000) and reference prices from the
  industry (HighLevel about $0.675 per 1,000 from a wallet; Mailchimp adds overage blocks to the next bill;
  Jobber has no limit) so that Jafar can see the whole picture.

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
and reconciles it with SES.

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

Some mail clients reply to the From address instead of Reply-To (RFC 5322 makes Reply-To advisory). Approved
2026-09-26, following GoHighLevel's dedicated-sending-domain pattern: the operational and Marketing sending
subdomains also receive mail. A reply is matched in this order, and never guessed: the opaque conversation
address, then the sent email it answers (`In-Reply-To`), then the sender's address against the organization's
contacts. The contact-address step is trusted only when Amazon SES authenticated the sender (DKIM or DMARC
`PASS`, one From address), because a bare From header is trivially forged. A reply still unmatched, matching
several contacts, or unauthenticated enters the guarded organization review queue. The sending subdomains
receive only after SES verifies them, and removal deletes their MX records before the identities.
Receiving scales past Amazon SES's fixed 200-rule ceiling through one account-wide receipt rule; UCRM routes
each message by its recipient address. Mail that SES scans as virus or spam `FAIL` is quarantined: never shown
in Conversations, linked to a contact, or forwarded.

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

Create an application-owned outbound record before calling SES. Every logical send has a durable
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
suppression records, provider identifiers, SES identities, receipt rules, configuration sets, and queues.
Provider cleanup failure remains a retryable operation and cannot be reported as complete. The existing non-personal deletion receipt may
contain aggregate cleanup results but no recipients, content, domains, or message identifiers.

Provider cleanup covers the organization-owned SES resources UCRM actually provisions and tracks: sending and
receiving identities, sender addresses, custom MAIL FROM settings, receipt-rule entries, configuration sets, and
their opaque provider identifiers. Every receiving domain is handled by the single owned receipt-rule set and the
same secured UCRM worker path. Persist each provider identifier at provisioning and include it in retryable
replacement and permanent cleanup; deleting one organization must not alter another organization's resources or
the shared worker secrets.

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

## Email setup screens

Approved 2026-09-24 against HighLevel's self-serve dedicated-domain flow and Jobber's shared-sender model. UCRM
keeps the contractor free of DNS work: the contractor requests setup, and Jafar activates it.

**Platform Owner organization page (Communications).** One Email card replaces the separate operational and
Marketing domain cards:

- An open contractor request shows at the top of the card with its date, domain, current mailbox provider and
  optional note, plus **Set up** (activation prefilled with the requested domain) and **Close request** (Jafar
  enters a note that the contractor sees).
- An **Everyday email + replies** row shows the sending and receiving subdomains. A **Marketing email** row shows
  the Marketing subdomain and its branded-links state.
- Each row has one status (Not set up, Setting up, Ready or Problem) and one main action (Set up, Check, or See
  what's wrong). Technical records, Replace domain and Remove sit behind a row's more-actions menu.

**Contractor Settings → Email.** Until a verified domain exists, owners and admins see a "Set up your business
email" card with **Request email setup**. The request asks for the website domain, where the business's email
lives today (Google Workspace, Microsoft 365, GoDaddy, Hostinger, Other, or none), and an optional note. After
the request is sent, the card shows its date and domain, says the current mailbox keeps working and that UCRM will
make contact if domain access is needed, and offers **Cancel request**. It then moves through Setting up to Ready,
which unlocks Add sender. A closed request shows Jafar's note. A send refused for a missing verified sender links
to this page.

**Platform Owner alerting.** A new request raises a "Waiting on you" alert on the Jafar home page linking to that
organization, and adds an "Email setup requested" attention reason to the organizations list filter.

### Request lifecycle and sender fallback (approved 2026-09-26)

**A domain is required to request.** UCRM has no shared fallback sending identity, so an organization with no
website domain of its own cannot send operational email at all. The request form therefore requires a domain the
business owns; a contractor without one sees an explanation instead of a submit button and no request is created.

**Cancel, not edit.** Following Twilio toll-free verification (delete while pending, no edit, resubmit goes to the
back of the queue) and AWS Support cases (no cancel once an agent is working; resolve or reply instead):

- while the request is still waiting on Jafar, the contractor may cancel it outright;
- once Jafar starts activation the Cancel action is gone — a half-written DNS and SES provisioning must not be
  abandoned — and the card says setup is underway and to make contact;
- a request is never editable; a wrong domain is cancelled and re-requested;
- after Jafar closes a request the contractor may always send a new one.

**Sender fallback follows Jobber.** Jobber never fails a team member's email for a missing identity: all Jobber
mail leaves Jobber's own address and the contractor only chooses where replies return, defaulting to the sender
and falling back to a named team member or the company email address. UCRM matches the guarantee, not the shared
domain: when a staff member sends manual email or a Conversation reply and has no enabled manual sender assigned
to them, the send uses the organization's default manual sender rather than refusing. The customer sees the
business display name and address; the opaque per-conversation reply alias is unchanged, so the reply still
returns to the same Conversation. An organization with no usable default sender at all still refuses, because
there is nothing to send from. No nagging banner is needed, and per-person sender assignment stays available for
contractors who want named addresses.

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
