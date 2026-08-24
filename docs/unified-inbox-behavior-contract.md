# Unified Inbox Product Contract

Status: Approved product behavior, not yet implemented  
Approved: 2026-08-23  
Scope: Contractor Conversations across Facebook Messenger, Instagram, web chat, operational email, and SMS

Research evidence lives in:

- `docs/research/ghl-unified-inbox-reference.md`
- `docs/research/contractoros-unified-inbox-audit.md`
- `docs/research/unified-inbox-gap-review.md`

This contract owns unified-inbox behavior. Channel-specific consent, billing, reputation, sender identity,
delivery, and provider rules remain in their approved channel contracts. UCRM's approved UI blueprint owns
visual layout and styling.

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

Organization administrators and roles with full Conversations access may use Team Inbox. Restricted staff use
My Inbox for assigned and followed conversations plus relevant mentions. Existing client, work, pricing, and
financial permissions still govern the data exposed inside the workspace.

The contact's eligible assigned user is the default conversation owner. Missing or inactive owners fall back
to Unassigned. Ownership, following, and mentions never substitute for one another.

## Composer and message behavior

The composer switches among eligible channels without leaving the contact workspace. Eligibility is evaluated
at send time using the connection and identity, sender permission, destination, consent or DND, package access,
allowance or balance, provider health, Meta reply window, attachment capabilities, and organization safety
controls. An unavailable channel shows the actionable reason.

Snippets remain editable after insertion. Email supports its approved preview, sender identity, recipient,
subject, reply-thread, forwarding, attachment, and secure-link rules. Each channel keeps its own capability and
attachment limits rather than pretending all composers are identical.

Every outbound intent and its outbox event commit together. Provider delivery occurs asynchronously with a
stable idempotency key. Messages expose meaningful queued, scheduled, sent, delivered, failed, bounced,
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

Missed-call text-back uses a cooldown or equivalent idempotent guard so repeated attempts do not send a flood
of duplicate texts.

### Messenger and Instagram

Messenger and Instagram are first-class Meta channels with separate page/account-scoped customer identities.
They preserve provider message identifiers and obey current Meta reply windows, media capabilities, webhook
verification, token lifecycle, and disconnection rules. Provider restrictions appear as channel eligibility,
not silent delivery failures.

### Web chat

Web chat begins as an organization-scoped anonymous visitor session. Identity capture may create or link a
lead/contact. Merge preserves the full transcript, old and new identifiers, attribution, and an idempotent audit
event. Session restoration, inactivity closure, origin allowlisting, abuse controls, and safe file handling are
part of the channel boundary.

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

