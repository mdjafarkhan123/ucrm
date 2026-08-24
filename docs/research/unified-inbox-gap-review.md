# Unified Inbox Gap Review

Research date: 2026-08-23  
Status: Evidence and grilling input, not approved product behavior

## Sources

- `docs/research/ghl-unified-inbox-reference.md` — current first-party HighLevel behavior
- `docs/research/contractoros-unified-inbox-audit.md` — read-only implementation audit
- `docs/contractor-email-contract.md` — approved UCRM operational-email behavior
- `docs/PRODUCT.md` §11 — current UCRM unified-inbox direction

UCRM's approved visual blueprint remains authoritative. This review covers behavior and architecture only.

## Recommended product direction

Adopt HighLevel's **contact-centered workspace with channel-native threading underneath**. One customer
workspace may show a chronological mixed-channel history, but the system must preserve separate email
subjects, continuous SMS/Messenger/Instagram identities, web-chat sessions, provider identifiers, and work
context. Do not copy ContractorOs's one-open-conversation-per-contact constraint because it can merge unrelated
properties, requests, jobs, and email subjects.

Use ContractorOs as an implementation reference for message-level channels, provider identity adapters,
transactional outbox events, idempotent workers and callbacks, delivery states, cursor pagination, cached
filter views, web-chat restoration, consent gates, and contractor work context. Redesign its shared unread,
single-owner collaboration, free-form tag arrays, internal-note channel inheritance, secret storage, search,
and incomplete Meta support.

## Settled or strongly supported

These directions already match an approved UCRM contract or have strong GHL and ContractorOs evidence. They
should still be confirmed as a group before entering the permanent contract.

1. Conversations is one shared source of truth; Mine and other personal views do not become separate inboxes.
2. A message records its channel and origin. Human, workflow, campaign, AI, system, and provider/app activity
   remain distinguishable.
3. Contact, conversation/inbox item, provider/channel identity, channel thread/session, message, and internal
   comment are separate concepts.
4. Assignment, following, mentions, unread, archive, star/priority, and SLA are independent states.
5. Unread means “needs attention.” Opening alone does not clear it; reply, explicit action, or approved
   automation may clear it.
6. The composer exposes only currently eligible channels and explains blocks such as missing identity,
   provider disconnection, consent/DND, balance/allowance, Meta reply window, or attachment limit.
7. Internal comments never leave the organization and must not inherit a customer delivery channel.
8. Anonymous web-chat identification and contact merge are durable, idempotent lifecycle events.
9. Every outbound intent and its outbox event commit together; provider work happens asynchronously with
   stable idempotency keys, retries, and visible terminal failures.
10. The customer context includes contractor work: property, request, opportunity, quote/job, appointment,
    invoice, and payment, subject to the viewer's underlying record permissions.
11. Email launch remains reply-only operational email as approved. Cold inbound/general mailbox ingestion and
    Gmail/Outlook sync remain later work.
12. SMS and email keep their separately approved consent, allowance/balance, provider, and failure rules even
    though they share Conversations.

## GHL behavior that should not be copied blindly

1. Permanent conversation deletion conflicts with safer CRM history and audit expectations; choose retention
   explicitly.
2. Archived conversations receiving new inbound messages remain archived in GHL while surfacing in Unread;
   this is non-obvious and needs an explicit choice.
3. Missed-call text-back can send once per missed attempt and duplicate messages; UCRM should decide its guard.
4. GHL's incomplete public permission matrix cannot define UCRM record-level visibility.
5. Provider-specific email and Meta limitations require capability checks rather than one universal channel
   state machine.
6. GHL's visuals and layout are outside scope; the UCRM blueprint wins.

## Decisions for the grill

### Round 1 — model and retention

1. What is the primary inbox unit: contact workspace plus channel threads (recommended), or a separate inbox
   item per issue/work context?
2. When may two channel threads appear in one workspace, and when must staff deliberately split or link them?
3. Does UCRM support archive only (recommended), or permanent deletion with restricted permission and audit?
4. Does new inbound activity automatically reopen an archived conversation (recommended), or match GHL by
   keeping it archived while adding it to Unread?

### Round 2 — team handling

Depends on Round 1.

1. Is unread shared, personal, or both? Recommendation: shared “needs handling” plus a personal last-seen
   marker, so one teammate can resolve work without losing each user's reading position.
2. Who may see Team Inbox versus assigned/followed/mentioned conversations?
3. Do assignment, followers, mentions, and SLA follow GHL exactly?
4. Are internal comments immutable and attachment-free like GHL, or may privileged users correct/remove them
   with retained audit history?

### Round 3 — channel rules

Depends on the model and handling decisions.

1. Confirm channel-native threading: email subject threads; continuous SMS/Messenger/Instagram streams;
   session-led web chat.
2. Decide Meta account/page limits, rich-media scope, reply-window behavior, and disconnection handling after
   current Meta documentation is checked.
3. Decide web-chat anonymous identity, contact creation timing, transcript/session closure, and merge rules.
4. Decide missed-call text-back deduplication and cooldown.
5. Decide which delivery/read/failure/retry states are customer-visible and staff-actionable per channel.

### Round 4 — organization and automation

Depends on prior rounds.

1. Define tags versus saved views and who may create, rename, merge, and delete them.
2. Define search scope across contacts, bodies, subjects, attachments, comments, and work records.
3. Decide whether workflow/AI replies satisfy SLA and clear unread by default.
4. Define notification defaults for assignment, followers, mentions, unassigned inbound, failures, and SLA.
5. Confirm package entitlements and channel onboarding/readiness behavior.

## Implementation adoption boundary

No ContractorOs schema or UI should be ported before the grill closes. After approval, its reusable patterns
must be adapted to Supabase, UCRM permissions, organization-scoped RLS, cursor/index design, TanStack Query,
the approved email contract, Communication Balance, and the UCRM blueprint.

## Remaining factual research before implementation

- Current Meta primary documentation for Messenger/Instagram windows, media, reactions, permissions, account
  linkage, webhook verification, token rotation, and disconnection.
- Twilio/current provider rules for SMS consent, delivery events, number registration, attachments, and
  missed-call behavior.
- Complete per-channel delivery-state mapping.
- Live GHL interaction verification if an authenticated session becomes available.

