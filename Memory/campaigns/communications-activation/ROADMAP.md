# Communications Activation Roadmap

Permanent behavior lives in docs/contractor-email-contract.md and docs/unified-inbox-behavior-contract.md.

## Why this campaign exists

The Communications campaign closed having built the inbox, the outbox, allowances, suspension/closure and
Platform Owner controls — but nothing ever sends. Four facts carried forward from it (2026-08-28):

1. `src/routes/api/internal/communications/email-worker/+server.ts` returns 503 unconditionally. Its stated
   reason, "sender identities are a Part 2 dependency", is **stale** — `claim_communication_outbox_event`
   already returns `sender_email`/`sender_name`, and 1 domain + 2 senders exist.
2. `forward-worker/+server.ts` is stubbed the same way.
3. `communication_outbox_events` holds 2 stale `pending` rows and the forward queue has old work. Inspect and
   safely dispose of that backlog before activation; prove delivery with a fresh canary instead.
4. The route currently sends one email per invocation. A1 replaces this activation shape with a bounded,
   reusable outbox drain that can run under a supervised worker later.

## Approved sequence (Jafar, updated 2026-08-29)

Email activation and realtime inbox (complete) → contractor-settings 6A/6B Automation → A2 SMS → A3
marketing campaigns.

Marketing is deliberately last, and **no marketing groundwork is added early** — no purpose/lane column
until A3 scopes it. Backfilling today's rows as transactional is trivial.

## Technical decisions

- The Postgres transactional outbox is A1's durable queue and claim/finalize authority. A bounded competing
  worker drains it; the same delivery core must run locally now and as a supervised Docker worker later.
- Redis is intentionally outside A1. Automation may use it later for rebuildable dispatch, delays, or rate
  coordination only after durable workflow state is committed to Postgres.
- Twilio for SMS, direct — credentials already in `.env`; GHL runs on Twilio underneath.
- Marketing sends get their own lane so a blast cannot delay a quote or invoice.
- The contractual per-org rate limit is not proof of cross-tenant fairness. A1 must verify bounded claims and
  tenant-skew behavior before making capacity claims.
- Domain activation uses an idempotent desired-state reconciler across UCRM, Brevo, and Cloudflare. DNS
  propagation is an observable waiting state, never a long-held request or an immediate-success claim.
- UCRM preserves root mailbox DNS and manages only the approved sending/receiving subdomains. Provider record
  counts are discovered, not hardcoded; conflicting records fail closed for owner review.

## Approved A1 scope (Jafar, 2026-08-28)

Protect the stale backlog; activate and harden email and forward workers; add provider idempotency, timeouts,
bounded retry/deadline handling, and durable webhook retry behavior; then verify inbox email, quote email,
attachments, replies, forwarding, bounces, suppression, recovery, and a fresh real canary.

| Part | Outcome                       | State                                     | Depends on             | Completion gate                                                                                                                                                             |
| ---- | ----------------------------- | ----------------------------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1-D | Managed email-domain activation | Done — accepted 2026-08-30              | A1 outbound proof      | One owner action safely reconciles separate sending/receiving domains, Cloudflare DNS, Brevo verification and the domain webhook; the test domain passes                     |
| A1-V | Finish email live verification | Done — accepted 2026-08-30              | A1-D                   | Fresh real email reaches a real inbox and replies; attachment, bounded backlog and one-day soak pass; recovery and monitored drain remain healthy                           |
| A2   | SMS channel via Twilio        | Not scoped                                | 6B, 10DLC approval     | Contractor can send and receive SMS in Conversations under approved consent rules                                                                                         |
| A3   | One-click marketing campaigns | Not scoped                                | A2                     | Contractor can send a segmented bulk campaign without risking transactional deliverability                                                                                  |

## Build principle (Jafar, durable 2026-08-30)

The full unified inbox is built following GHL end-to-end — root architecture/data model, real-time
mechanism/transport, AND UI/UX — across ALL channels (email now, SMS next, then more). Every channel must work
reliably; "all should work perfectly" is the bar, not a follow-up. For each layer, establish how GHL does it,
reuse the proven pattern, depart only with a stated reason + Jafar's approval. See
[[feedback-follow-ghl-literally-communications]] and docs/unified-inbox-behavior-contract.md.

## Real-time inbox (Jafar-prioritized 2026-08-30)

Jafar: the unified inbox must feel instant like WhatsApp/Messenger/GHL. "Stuck on queued until reload" = wrong
pattern (polling) for a conversational inbox. Diagnosis: outbound send + Brevo delivery + reply-alias mint all work
live; latency + no live push is the problem. UCRM drains via pg_cron→pg_net (no persistent worker): outbox-wake
every 1m (send), provider-callback-processor every 2m (status); inbox realtime is wired ONLY for website-chat
broadcast, not email. Approved sequence: R1 first, then R2, then R3.

Proven in-repo mechanism to reuse (do NOT invent, do NOT copy ContractorOs postgres_changes row-streaming — UCRM
deliberately broadcasts ids-only on an authorized org channel and re-reads via the permission-filtered API; safer
for assigned-only staff views): Postgres trigger calls `realtime.send(payload, event, 'wc-org:'||org_id, true)`
inside the txn (WAL-based, best-effort, swallows errors so a publish never fails the write). Staff inbox already
subscribes to private channel `wc-org:{org}` and invalidates on event `website_chat_activity`
(src/routes/(app)/communications/+page.svelte). Staff-topic RLS already authorizes that channel — no new grants.

| Part | Outcome | State | Depends on | Completion gate |
| ---- | ------- | ----- | ---------- | --------------- |
| R1 | Live inbox status, no reload | Done — live-verified 2026-08-30 | — (mechanism exists) | MET: outbound flipped queued→delivered live (no reload), Gmail reply landed live in thread+list+unread, reply-alias round-trip correlated, 0 duplicate/failed Brevo webhooks |
| R2 | Instant send + optimistic UI | Done — live-verified 2026-08-30 | R1 (done) | MET: outbound dispatches immediately through the durable outbox wake trigger; cron remains the retry safety net |
| R3 | Full status ladder / receipts | Not scoped | R2 | Sent→delivered→read/opened indicators consistent across channels (email now, SMS/chat later), GHL-style |

### R1 design (finalize + build next session)

1. DB trigger AFTER INSERT on `communication_inbound_messages` → `realtime.send({message_id, client_id, review_status}, 'communication_inbox_activity', 'wc-org:'||organization_id, true)`, best-effort.
2. DB trigger AFTER UPDATE OF status ON `communication_delivery_intents` WHEN new.status IS DISTINCT FROM old.status → same `realtime.send` with {intent_id, client_id, status}. Ids only, never body.
3. Latency: in `/api/webhooks/brevo/transactional/+server.ts`, after inserting the callback event, process it on arrival (bounded call to `process_communication_provider_callbacks`, or a single-event variant) so status flips immediately; keep the 2m cron as fallback. Must stay idempotent + within the route deadline.
4. Client: in `src/routes/(app)/communications/+page.svelte`, add `.on('broadcast', {event:'communication_inbox_activity'}, ...)` to the existing `wc-org:{org}` channel → invalidate `['communications','inbox']` and the open thread's messages query. Reuse the existing channel; no new auth.
Risks/edges: publish best-effort (swallow, like website chat); ids-only (permission rule); trigger only on real status transitions; on-arrival processing idempotent + bounded. This is a scale-sensitive path (fires per webhook/org, broadcasts) → run performance-review design branch before building and verification branch after.
Dev worker (Jafar: "do what is necessary"): NOT needed for R1 (status display only); revisit in R2 where send latency lives.

## Open product questions (asked 2026-08-28, unanswered)

- Q5 Which SMS messages ship first? Recommended: appointment reminder, "on my way", missed-call auto-reply.
- Q6 What is a marketing campaign for? Recommended: seasonal reminders and win-backs, selected by job history.
- Q7 Who may bulk-send? Recommended: owner and admin only.
- Q8 Automation first release: presets only, quote follow-up first? (contractor-settings owns the answer.)
- Q9 Which Gmail address and which sender for the A1 proof send? Blocks A1 verification.

## Known external latency

US carrier 10DLC registration takes weeks and needs Jafar's legal name, tax ID and website. Start it as soon
as Q5 is answered so it runs in parallel, not on the critical path before A2.

## Settled, do not re-ask

Quote follow-up triggers on successful delivery, not publication, via the Automation engine's v1 Quote
catalog (contractor-settings 6A, approved). A marketing opt-out never blocks essential email
(contractor-email-contract). Redis being installed but unconnected is intentional and does not block A1.
