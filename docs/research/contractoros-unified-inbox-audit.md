# ContractorOs Unified Inbox Audit

Date: 2026-08-23  
Scope: read-only source audit of `D:\Projects\ContractorOs`. This is implementation evidence, not an instruction for UCRM.

## Executive conclusion

ContractorOs already contains a substantial, conversation-centric unified inbox. Its strongest reusable idea is a **contact-owned conversation whose individual messages carry their channel**. That permits SMS, email, web chat, Messenger, missed calls, and manually logged calls to appear in one chronological thread without maintaining one thread per channel. It also has useful production patterns around cursor pagination, per-filter client caches, transactional outbox events, delivery state, inbound deduplication, and contractor-work context.

UCRM should adopt those architectural patterns selectively, not copy the implementation wholesale. ContractorOs has no Instagram implementation, Messenger is text-only, assignment supports only one owner, read state is shared rather than per-user, tags are ungoverned text arrays, email attachment tagging contains acknowledged technical debt, and the “one open conversation per contact” database rule can collapse unrelated subjects/work items. The UI and schema should therefore be treated as a working reference beneath the GHL product model, not as the final product contract.

## What is implemented

### Inbox experience

- A three-area desktop inbox exists: conversation list, selected thread, and contact/work context. The route family is under `src/routes/(app)/(pages)/inbox/`, with reusable controls under `src/lib/components/inbox/`.
- The list model exposes contact, assignee, last-message channel/direction, unread count, snooze time, delivery failure, and tags (`src/lib/stores/inbox.svelte.ts:29-48`). Filters cover open/closed/snoozed/all status, all/me/unassigned/member assignment, unread-only, query text, and tag (`src/lib/stores/inbox.svelte.ts:24-27`, `151-157`).
- Search is true full-text message-body search (minimum three characters), returns the newest match per conversation, and applies assignment visibility (`src/routes/api/conversations/search/+server.ts:7-19`, `26-66`).
- The thread supports optimistic sending, status reconciliation, manual retry of failed outbound messages, open/close, snooze/unsnooze, tags, assignment, mark-read, attachments, quick replies, internal notes, and manual call logging (`src/lib/stores/inbox.svelte.ts:558-682`, `742-893`, `920-945`).
- Sending into a closed or snoozed thread automatically reopens it atomically (`src/routes/api/conversations/[id]/messages/+server.ts:175-189`, `585`; also `642`, `732`, `819`).
- The contact context includes contact status and source plus pipeline stage, latest quote, latest invoice, next appointment, and SMS quota (`src/lib/stores/inbox.svelte.ts:120-149`; assembled in `src/routes/api/conversations/[id]/+server.ts:37-111`, `223-255`). This contractor-specific context is worth retaining even if GHL’s visual design is followed.
- Client data uses a `SvelteMap` keyed by the full filter combination and a 30-second stale-while-revalidate window (`src/lib/stores/inbox.svelte.ts:177-184`, `219-238`, `415-464`). Messages and lists use cursor pagination (`src/lib/stores/inbox.svelte.ts:222-237`, `267-276`). Realtime changes are merged with optimistic state and coalesced to avoid repeated re-sorts/reloads (`src/lib/stores/inbox.svelte.ts:185-194`, `337-338`, `711`).

### Conversation and message model

- Conversation lifecycle is `open`, `closed`, or `snoozed` (`src/lib/server/db/schema/05_communication.ts:18`). A conversation belongs to an organization and contact, has one assignee, denormalized last-message metadata, inbound/outbound timestamps, first response, a shared unread counter, free-form tag array, snooze/close audit fields, and soft deletion (`src/lib/server/db/schema/05_communication.ts:55-88`).
- Channel lives on each message, not the conversation. Supported values are SMS, missed call, email, webchat, Messenger, and manual call (`src/lib/server/db/schema/05_communication.ts:20-30`). This deliberate unification replaced channel-owned conversations (`drizzle/0012_inbox_v2.sql:1-10`, `173-177`).
- Messages capture direction, body, internal-note flag, media, delivery status, provider identifiers, reply relationship, failure details, email headers/status fields, attempts, SMS cost, call outcome/duration, sender, send/read times (`src/lib/server/db/schema/05_communication.ts:94-150`).
- The current database enforces at most one open conversation per organization/contact (`drizzle/0045_conversation_open_unique.sql:21-24`). This is simple but means “thread identity” is essentially contact + open lifecycle, rather than channel, subject, property, request, job, or provider thread.
- Channel selection is derived through `resolveChannel` and the API reports `suggested_channel` plus `available_channels` (`src/lib/stores/inbox.svelte.ts:114-115`; `src/routes/api/conversations/[id]/messages/+server.ts:405`).
- Internal notes are stored as messages, inherit the last channel for display, and deliberately skip transport/outbox (`src/routes/api/conversations/[id]/messages/+server.ts:380-402`).

### Channel coverage

- **SMS:** two-way Twilio inbound/status webhooks and asynchronous outbound worker exist. Eligibility includes communication preferences/opt-out, released-number checks, configured sending number, and prepaid credit (`src/routes/api/conversations/[id]/messages/+server.ts:405-418`, `766-838`). Inbound Twilio events use provider SID-derived idempotency keys (`src/routes/api/webhooks/twilio/sms/+server.ts:252`, `273-304`).
- **Email:** outbound email is queued to an email worker; first email requires a subject, replies derive `Re:` and preserve bounded reply references, a per-conversation reply alias correlates inbound replies, and attachment totals are capped at 20 MB (`src/routes/api/conversations/[id]/messages/+server.ts:421-537`, `542-606`). Delivery/open/bounce fields are modeled (`src/lib/server/db/schema/05_communication.ts:120-136`).
- **Web chat:** widget and session tables support one widget per org, domain allowlisting, active state, instant/asynchronous mode, visitor session/contact/conversation linkage, and activity tracking (`src/lib/server/db/schema/11_webchat.ts:8-52`). The browser widget restores a session, optimistically sends, short-polls replies, varies poll cadence with visibility/open state, and displays unread counts (`src/widget/main.ts:1116-1288`, `1293-1355`, `927-937`).
- **Messenger:** one Facebook Page connection per org, page-scoped PSID identities mapped to contacts, encrypted-secret-worthy page token storage, connection state, subscription state, and globally unique page routing are modeled (`src/lib/server/db/schema/15_messenger.ts:6-44`, `50-68`). Inbound `mid` is uniquely indexed for webhook redelivery dedup (`src/lib/server/db/schema/05_communication.ts:111-113`, `152-157`). Outbound is asynchronous but explicitly text-only (`src/routes/api/conversations/[id]/messages/+server.ts:679-751`).
- **Instagram:** absent. No Instagram channel, identity table, provider integration, webhook route, worker, or UI was found in `src` or non-snapshot migrations as of this audit.
- **Calls:** missed calls and manually logged outbound calls appear in the same timeline; logged calls support outcome and duration (`src/lib/server/db/schema/05_communication.ts:26-42`, `142-144`; `src/routes/api/conversations/[id]/calls/+server.ts:40-42`, `94-140`).

## Reliability, security, and performance

- Business writes and dispatch requests are committed together. Email, Messenger, and SMS create a queued message and an idempotent outbox event in one transaction (`src/routes/api/conversations/[id]/messages/+server.ts:542-603`, `721-749`, `807-836`). This is the best backend pattern to reuse.
- The outbox dispatcher claims batches with `FOR UPDATE SKIP LOCKED`, uses deterministic queue job IDs, marks successes, and applies exponential backoff until a dead state (`src/lib/server/workers/outboxWorker.ts:571-590`, `601-608`, `687-724`). Channel workers tolerate already-processed messages and track attempts; email and Messenger default to three attempts (`src/lib/server/workers/emailWorker.ts:128-143`, `399-406`; `src/lib/server/workers/messengerWorker.ts:85-98`, `223-229`). SMS adds rate deferral and idempotent credit reservation (`src/lib/server/workers/smsWorker.ts:319-345`).
- Tenant and permission checks exist at API level: view-all versus assigned-only governs access and `can_send_messages` gates sending/retry/logged calls (`src/routes/api/conversations/[id]/messages/+server.ts:75-83`, `281-318`; `src/routes/api/conversations/[id]/messages/[messageId]/retry/+server.ts:28-71`). Conversation RLS also checks org and assigned access (`drizzle/0025_fix_assigned_access_rls.sql:27-37`).
- Mark-read is atomic and recounts unread inbound rows to repair drift (`src/routes/api/conversations/[id]/read/+server.ts:40-58`). Detail loading also selectively self-heals recent/unread threads (`src/routes/api/conversations/[id]/+server.ts:171-188`).
- Search uses generated Postgres full-text vectors with GIN, tags use GIN, and common unread/last-message/message-thread paths are indexed (`drizzle/0021_inbox_search_tags_email_perf.sql:6-36`). Email provider correlation and reply aliases also have scoped indexes (`drizzle/0012_inbox_v2.sql:207-224`).

## Strengths UCRM should adopt

1. **One chronological customer timeline, channel on message.** This matches the mental model of a unified inbox and avoids separate SMS/email silos.
2. **Transactional outbox plus idempotent workers.** Persist the user-visible message and delivery intent together, dispatch later, use stable job/event identities, and expose delivery failures/retry.
3. **Provider-specific identity adapters.** Keep Messenger PSID/page identity separate from core contacts, then link it to the canonical contact. Extend the same pattern to Instagram-scoped identities.
4. **Denormalized inbox summary fields.** `last_message_*`, unread count, and timestamps make list reads cheap; retain repair/reconciliation paths.
5. **Cursor pagination and per-filter stale caches.** This is suitable for large multi-tenant inboxes and fast navigation.
6. **Contractor work context beside the thread.** Pipeline stage, quote, invoice, appointment, property/job/request links can differentiate UCRM while retaining GHL’s proven conversation workflow.
7. **Channel-aware composer and compliance gates.** Resolve available/suggested channels, block invalid destinations/opt-outs, require first-email subject, and keep internal notes transport-free.
8. **Web chat session restoration and adaptive polling.** The visitor experience survives reloads and reduces load when hidden.

## Risks and parts to redesign

1. **Shared unread state is too coarse for teams.** `messages.read_at` and `conversations.unread_count` are global to the thread (`src/lib/server/db/schema/05_communication.ts:76`, `148`). One teammate opening a conversation effectively reads it for everyone. UCRM should decide explicitly between shared inbox read state, per-user read state, or both before schema work.
2. **One open conversation per contact can over-merge.** The unique index at `drizzle/0045_conversation_open_unique.sql:21-24` cannot distinguish two properties, simultaneous requests/jobs, unrelated email subjects, or provider threads. Follow GHL only after verifying its precise threading/merge rules; likely preserve a customer timeline while also retaining provider-thread/work-context keys.
3. **Assignment is single-owner only.** There are no followers, watchers, teams, mentions, or collision/“another agent is replying” ownership. The typing endpoint covers webchat visitor typing, not teammate composer presence.
4. **Tags are an ungoverned text array.** This is convenient but lacks tag records, color, permissions, rename/merge, usage reporting, and referential integrity (`src/lib/server/db/schema/05_communication.ts:77-80`). Adopt only if GHL research shows lightweight labels are enough.
5. **No Instagram.** Instagram cannot be represented by the current channel enum or identity/integration model. Build it as a first-class Meta channel, not a Messenger alias.
6. **Messenger is incomplete.** Only one Facebook Page per org and text-only outbound are supported (`src/lib/server/db/schema/15_messenger.ts:16-18`; `src/routes/api/conversations/[id]/messages/+server.ts:681-688`). UCRM must decide multi-page support and media/reaction/story-reply constraints from current Meta/GHL evidence.
7. **Email attachment taxonomy has known debt.** Email attachments are stored using `quote_attachment` with an inline “revisit” comment (`src/routes/api/conversations/[id]/messages/+server.ts:560-573`). Do not copy this.
8. **Internal-note channel inheritance is semantically misleading.** Notes inherit the last transport channel (`src/routes/api/conversations/[id]/messages/+server.ts:380-391`). UCRM should model timeline item type separately from delivery channel so notes cannot be mistaken for sent channel content.
9. **Search is narrow.** It searches English message bodies only, requires three characters, returns 20 with no continuation, and does not search contact fields, email subject, attachment names, notes separately, or structured work context (`src/routes/api/conversations/search/+server.ts:7-19`, `26-66`).
10. **Potential index/query mismatch needs load testing.** List ordering prioritizes unread inbound then `last_inbound_at` and last message, while published indexes mainly cover `(org_id, unread_count)` and `(org_id, last_message_at DESC)` (`src/lib/stores/inbox.svelte.ts:291-298`; `drizzle/0021_inbox_search_tags_email_perf.sql:31-36`). The final UCRM query/index pair should be designed and explained together.
11. **Secrets appear stored directly in the integration row.** `page_access_token` is a non-null text column (`src/lib/server/db/schema/15_messenger.ts:28-29`). UCRM should use its approved server-side encryption/secret-storage approach and define token rotation and revocation handling.
12. **Feature completeness is uneven.** SMS/email have deeper transport and delivery semantics than webchat/Messenger; parity must be specified per channel instead of implied by a shared composer.

## Recommended adoption boundary

Use ContractorOs as a source-code accelerator for these concepts: canonical contact linkage, message-level channels, transactional outbox, idempotency keys, provider identity tables, delivery-state UI, cursor pagination, per-filter caching, webchat restoration, opt-out gating, and contractor-work context.

Do not port schema or UI directly until the GHL research and grilling settle: thread boundaries and merging, shared versus personal unread, assignment/followers, tags, inbox/team views, collision handling, Meta account/page model, Instagram behavior, internal-note modeling, and cross-channel composer parity.

## Verification limits

- This was a static code and migration audit; no ContractorOs server, database, worker, Meta/Twilio/Brevo account, or browser session was run.
- No dedicated inbox test directory was found through the scoped file search. Behavior described above is implemented code, but not evidence of end-to-end test coverage.
- Historical migrations sometimes document superseded decisions (notably `0012` saying no unique open thread, later superseded by `0045`). Newer schema/migrations were treated as current truth.
