# Unified Inbox Product Contract

Status: Approved product behavior, not yet implemented  
Approved: 2026-08-23  
Scope: Contractor Conversations across Facebook Messenger, Instagram, web chat, operational email, and SMS

Research evidence lives in:

- `docs/research/ghl-unified-inbox-reference.md`
- `docs/research/contractoros-unified-inbox-audit.md`
- `docs/research/unified-inbox-gap-review.md`

This contract owns unified-inbox behavior. Channel-specific consent, billing, reputation, sender identity,
delivery, and provider rules remain in their approved channel contracts. For Communications, HighLevel is
the approved source of truth for screen structure, interaction behavior, and responsive composition. UCRM's
design system owns visual tokens, component styling, and accessibility. Any departure from HighLevel requires
an explicit provider, security, tenant-isolation, or contractor-workflow reason and Jafar's approval.

## Product model

Conversations is one contact-centered workspace, following HighLevel's proven behavior. It shows a
chronological mixed-channel history while preserving channel-native identity and threading underneath:

- email keeps separate subject and reply threads;
- SMS, Messenger, and Instagram use continuous channel streams;
- web chat uses visitor sessions that may later merge into an identified contact;
- missed calls and logged calls may appear as timeline activity without becoming a customer-message channel.

Keep Contact, Conversation, Channel Connection, Channel Identity, Channel Thread or Session, Message, and
Internal Comment as separate concepts. A message records its delivery channel and origin. Human, workflow,
campaign, AI, system, and provider/app activity remain distinguishable.

The conversation workspace exposes authorized contractor context such as the client, property, request,
opportunity, quote, job, appointment, invoice, and payment. Context never bypasses the viewer's permission to
the underlying record. A conversation is not forced to belong to one work record.

## Inbox handling

Follow HighLevel for the established handling model:

- one shared source of truth with personal and team views;
- assignment, followers, mentions, unread, archive, star/priority, and SLA are independent;
- unread means “needs attention,” and opening alone does not clear it;
- replying, explicitly marking read, or an approved workflow may clear unread;
- each user retains a personal last-seen position;
- archived conversations stay archived after new inbound activity but surface in Unread;
- saved views and temporary filters remain separate;
- filters may distinguish owner, follower, mention, channel, direction, human versus automated origin, tags,
  unread, archive, date, and SLA;
- search and lists use cursor pagination and remain usable at organization-scale volume.

Permanent deletion follows HighLevel. Only a role with the permanent-delete permission may use it. The action
requires explicit confirmation and records the organization, actor, time, reason, customer, and deleted item
counts without retaining deleted message content.

## Team collaboration and permissions

Internal comments appear inside customer conversations but are never externally deliverable. Posted comments
are immutable, attachment-free, and may mention teammates. Standalone employee chat is outside launch scope.

Custom roles control these capabilities independently:

- view assigned, followed, and mentioned conversations;
- view all conversations through Team Inbox;
- send customer messages;
- assign and manage conversations;
- permanently delete conversations;
- manage channel connections and settings.

Owner and admin may send customer messages by default; every other role needs the capability granted
explicitly (`20260825160000_conversations_send_default_owner_admin.sql`, decided 2026-08-25). Being able to
message customers follows administrative standing, not a per-organization opt-in.

Organization administrators and roles with full Conversations access may use Team Inbox. Restricted staff use
My Inbox for assigned and followed conversations plus relevant mentions. Existing client, work, pricing, and
financial permissions still govern the data exposed inside the workspace.

A conversation has no default owner — it starts Unassigned until a permitted member
(`conversations.manage_assignment`) assigns it. (Corrects this contract's original assumption that the
contact's own assigned user would be the default: Jafar's 2026-08-24 decision to remove
`clients.owner_user_id` — Jobber has no client-level owner, only per-work-object ownership — left no such
user to default from. Confirmed 2026-08-25.) Missing or inactive owners fall back to Unassigned. Ownership,
following, and mentions never substitute for one another.

## Composer and message behavior

The composer switches among eligible channels without leaving the contact workspace. Eligibility is evaluated
at send time using the connection and identity, sender permission, destination, consent or DND, package access,
allowance or balance, provider health, Meta reply window, attachment capabilities, and organization safety
controls. An unavailable channel shows the actionable reason.

Snippets remain editable after insertion. Email supports its approved preview, sender identity, recipient,
subject, reply-thread, forwarding, attachment, and secure-link rules. Each channel keeps its own capability and
attachment limits rather than pretending all composers are identical.

Every outbound intent and its outbox event commit together. Provider delivery occurs asynchronously with a
stable local logical-send key. Provider-side idempotency is used only where the provider documents it. Messages expose meaningful queued, scheduled, sent, delivered, failed, bounced,
cancelled, or retry states only where that channel can prove them. Retrying never duplicates a successful send
or charge.

## Channel boundaries

### Operational email

Launch receives replies to UCRM-sent operational email as approved in `docs/contractor-email-contract.md`.
General inbound email and full Gmail or Outlook synchronization are later work. Operational email allowances
never deduct Communication Balance.

### SMS

Two-way SMS remains governed by registration, number readiness, consent and STOP/HELP handling, package SMS
mode, safety controls, and Communication Balance. A legal SMS opt-out blocks texting throughout UCRM until a
valid opt-in. Required inbound and consent handling continue when ordinary outbound SMS is unavailable.

UCRM retains append-only consent evidence and derives a current send-time projection. That projection keeps
legal consent, an ordinary contractor DND/hold, and technical deliverability suppression separate even when the
composer summarizes all three as “SMS unavailable.” A carrier or handset failure is never recorded as customer
revocation. A legal STOP cannot be cleared by a workflow or an ordinary user; only a valid customer re-opt-in or
a narrowly controlled proof-review action may clear it, with immutable history.

Unknown consent blocks sending. Evidence belongs to the exact customer phone number and states which operational
subjects it covers: direct service conversations; work updates for requests, quotes, jobs and appointments; and
billing updates for invoices, receipts and payment reminders. Marketing remains separate. Accepted proof is a
customer SMS, explicit web-form consent, or a signed paper/digital agreement; verbal consent and old client-level
timestamps without number/source evidence do not silently become permission.

At launch, only the contractor owner or an administrator may record external proof. The interaction is one short
form containing the phone number, method, date, covered subjects, evidence note/location and explicit confirmation;
it does not require a new document-upload system. An inbound customer text permits a human reply in that
conversation, but does not authorize Automation or unrelated recurring messages.

Twilio's Messaging Service opt-out handling is mirrored locally. A provider-classified STOP, START, or HELP is
stored once as evidence and updates the projection idempotently; when Twilio already sent the keyword response,
UCRM sends no duplicate reply. Sender identity, opt-out wording, localized keywords, and the registered use case
must agree for that sender and country.

Every normal outbound SMS, whether manual, automated, retried, or delayed, passes a recipient-local send-time
quiet-hours policy based on destination jurisdiction and message purpose. A GHL-style workflow window remains an
additional authoring preference, not the legal boundary. Messages outside the permitted window wait until the
next permitted time and recheck current work, consent, sender, balance, caps, and pauses before release. Only a
platform-defined legally permitted purpose may bypass a normal window; contractors cannot label arbitrary
messages as essential.

Missed-call text-back uses a cooldown or equivalent idempotent guard so repeated attempts do not send a flood
of duplicate texts.

#### SMS delivery and recovery — A2 Stage 3 approved

Manual and automated texts follow the same consent, balance and safety rules. Queued, scheduled, sent,
delivered and failed messages show what is actually known; SMS never promises customer read receipts.

Failed messages do not automatically resend when a business sending restriction ends. When it is uncertain
whether a message was sent, show that it needs checking and prevent a blind resend. Repeated clicks or delivery
updates must not create duplicate customer messages or duplicate charges. Older updates cannot undo a later
confirmed delivery result; conflicting results need review.

Keep incoming replies, delivery updates and required STOP/START/HELP handling available during outgoing pauses.
A customer opt-out blocks further texting; an older opt-in cannot clear a newer opt-out. A text already on its
way cannot be guaranteed recall.

Charges remain pending until known, keep the applicable agreed rate, and show later corrections transparently.
Unknown charges and discrepancies remain available for owner review. Rechecking provider totals must not charge
the same message again.

Supporting technical research and verification requirements remain in
`docs/research/communications-a2-stage3-transport-webhooks.md` for the later implementation phase.
Stage 3 approval remains recorded; it does not authorize coding before the product plan is complete.

#### SMS in Conversations — A2 Stage 4 approved 2026-09-12

Contractors compose and reply to SMS without leaving the customer's unified conversation. The composer shows
the selected saved customer number and permitted business sending number before sending. Staff may change either
when their role permits it. Editable saved replies, required sender/opt-out wording, message length, estimated
retail cost and actionable unavailability reasons remain visible before send.

An established SMS conversation continues from the business number the customer already knows unless a permitted
staff member explicitly selects another. A new conversation starts from the staff member's assigned business
number when eligible, otherwise the organization's default. An explicit selection wins and becomes the continuity
number for later messages in that conversation. This deliberately favors customer continuity over HighLevel's
newer published staff-assignment-first ordering, whose general and composer-specific documentation conflict.

Supported pictures send and arrive as picture messages where the selected country, sender and destination allow
it. Other files use approved secure links. When picture messaging is unavailable, explain why and offer the link
path rather than silently failing or changing the content.

Incoming SMS identity follows explicit safe rules:

- one unique normalized customer-number match attaches to that customer;
- no match creates a new Lead with that phone number and an Unassigned conversation;
- several matches create an Unassigned Needs identification conversation and require staff to choose the correct
  customer or create a new Lead before replying; UCRM never silently chooses a customer or creates another
  duplicate merely to break the tie.

Required STOP, START and HELP processing runs immediately even while customer identity is unresolved. The shared
team handling, unread behavior, live updates, history and channel-specific drafts follow this contract. Message
details show sender, customer and business numbers, time, delivery evidence and useful failure information;
SMS never claims that the customer read the message.

#### SMS in Automation — A2 Stage 5 approved 2026-09-12

Automation uses the same SMS eligibility, sender continuity, consent, quiet-hours, balance, delivery and recovery
truth as a manual conversation. Its **Send SMS** action targets the customer's current primary SMS-capable number
and never silently chooses another saved number. The business sender continues an established eligible
conversation number, otherwise the organization default, unless an authorized recipe step pins another eligible
number. An unattended workflow does not derive its sender from staff assignment.

Workflow Wait steps own delays; an optional workflow-wide sending window may narrow them, while Communications'
recipient-local legal and business guard remains non-bypassable. A temporarily held message shows its next
permitted send time and rechecks current truth before release. Conversations and the Automation enrollment link to
each other: Conversations shows scheduled and delivery evidence, while Automation history shows waiting, skipped
or failed steps and their plain reason. Skipped work creates no customer-message bubble, and restored service does
not automatically release stale work.

Reusable replies copy editable text into a recipe; later source edits never silently rewrite it. Tests are real,
normally charged sends limited to the authorized user's verified team phone. The first slice is text plus approved
secure links; AI writing, Manual SMS tasks, automated MMS, branching and marketing remain outside Stage 5.

### Messenger and Instagram

Messenger and Instagram are first-class Meta channels with separate page/account-scoped customer identities.
They preserve provider message identifiers and obey current Meta reply windows, media capabilities, webhook
verification, token lifecycle, and disconnection rules. Provider restrictions appear as channel eligibility,
not silent delivery failures.

### Web chat

Approved channel behavior lives in `docs/website-chat-behavior-contract.md`. Website Chat begins as an
organization-scoped visitor session, becomes an accepted conversation only with the first successfully stored
message, and creates or safely links a Client in the Lead state. Session restoration, guarded identity,
attribution, inactivity closure, origin allowlisting, abuse controls, allowance, human availability, and safe
file handling remain channel boundaries rather than generic Conversations assumptions.

## Connections, packages, and administration

The model supports multiple Facebook Pages, Instagram accounts, web-chat widgets, phone numbers, email sender
identities, and future identities per organization. Each channel has one organization default, while authorized
staff may select another eligible identity.

Channel availability and connection quantities are configurable entitlements. Jafar may attach them to any
current or future package without hardcoded package names or package counts and may apply a reasoned,
effective-dated organization override. Removing access blocks new activity according to the channel's safety
rules while preserving history and required inbound or consent processing.

Jafar controls platform/provider readiness and emergency stops. Organization administrators connect and manage
only the identities permitted by their package, override, role, and the channel's onboarding rules. Secrets stay
server-side and use the approved encrypted secret boundary with rotation and revocation handling.

For SMS, contractor administration stays in two existing Settings destinations: **Phone & SMS** for numbers,
registration, readiness, mode, hours and blocked-number controls; and **SMS usage** for separately stated balances,
top-ups, retail ledger and lean messaging health. Provider approval, insufficient credit, outbound restriction and
platform/organization pause remain distinct visible causes. Contractors request provider-owned number lifecycle
changes; Jafar performs them through the existing organization and Operations surfaces with impact review and
history. A2 has no contractor card storage, automatic recharge, duplicate analytics suite or separate Jafar SMS
dashboard family.

## Reliability and adoption boundary

Use ContractorOs as implementation evidence for message-level channels, provider identity adapters,
transactional outbox events, idempotent workers and callbacks, delivery states, cursor pagination, per-filter
caching, web-chat restoration, consent gates, and contractor work context.

Redesign its one-open-thread-per-contact constraint, shared-only read state, single-owner collaboration,
free-form tag arrays, internal-note channel inheritance, attachment taxonomy, narrow search, secret storage,
and incomplete Meta implementation. No ContractorOs schema or UI is copied wholesale.

## Required workflow before UI design

Immediately before any unified-inbox UI design or `.svelte` implementation, present one short plan covering:

1. the exact screen or interaction being designed;
2. the approved contract behaviors it must expose;
3. existing UCRM components to reuse;
4. required data states, loading states, permissions, channel restrictions, and edge cases;
5. browser-verification and acceptance checks.

Wait for Jafar's approval of that short plan. The plan is complete only when its scope, reuse boundary, states,
and acceptance checks are explicit. Visual placement and styling then follow the approved UCRM blueprint and
design system.

## Deferred scope

- full Gmail or Outlook mailbox synchronization;
- unrelated cold inbound email;
- standalone employee chat;
- WhatsApp and other customer channels not named in this contract;
- desktop/mobile parity beyond the separately approved UI scope.
