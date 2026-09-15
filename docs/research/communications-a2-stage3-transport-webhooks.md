# Communications A2 Stage 3 — SMS transport and webhooks

Status: Approved by Jafar; durable behavior promoted to the unified inbox contract. Research date: 2026-09-12.
Scope: Manual and Automation SMS for the approved initial 100–200 organizations. Planning only.
Stages 1–2 remain governed by `docs/PRODUCT.md` §11 and `docs/unified-inbox-behavior-contract.md`.

## Evidence and GHL boundary

**GHL fact:** Failed SMS appears in Conversations with an error code. Staff correct the cause before retrying.
[HighLevel delivery errors](https://help.gohighlevel.com/support/solutions/articles/48001208912).

**GHL fact:** Outbound restrictions preserve inbound conversations. A workflow SMS reached during a restriction
can fail; lifting that restriction does not automatically retry it or universally pause/resume the workflow.
[HighLevel messaging policy](https://help.gohighlevel.com/support/solutions/articles/48001213941).

**Limit:** These public documents do not establish GHL's internal queue, database transactions, provider-call
idempotency, or billing reconciliation algorithm. The mechanisms below are UCRM proposals using its approved
transactional outbox and Twilio's documented API, not claims about unpublished GHL internals. No new confirmed
GHL departure is proposed. Unknown-outcome handling is a reliability proposal whose exact GHL UX is unverified;
Stage 4 must review its presentation. Existing Stage 2 departures remain approved.

## Existing implementation and extension boundary

Read current code before implementation; the older A1 research contains obsolete migration timestamps and a
historical claim that worker routes are stubbed. Current evidence:

- `supabase/migrations/20260823080611_communications_email_delivery_foundation.sql`: shared-named intent,
  outbox and callback records, but email-only channel/provider constraints and required email payload fields.
- `supabase/migrations/20260824102123_communications_email_capacity_claim.sql`: token-checked finalize and
  stale-claim quarantine. Its quota reservations and usage events are email-specific.
- `supabase/migrations/20260828022617_communications_retry_deadline_claim.sql`: bounded claim candidates and
  deadline checks; email pause behavior must not silently become SMS behavior.
- `src/lib/server/communications/email-worker.ts` and `drain.ts`: working claim/call/finalize and monitored,
  bounded drains. `src/routes/api/webhooks/brevo/transactional/+server.ts` persists before projection.

**Proposal:** Extend the existing intent/outbox/callback spine. Add SMS detail and durable submission-attempt
identity only where SMS needs them. Preserve email validation with channel-specific constraints; never populate
fake email addresses or subjects. Explicit channel predicates must protect email workers, callback processors,
quarantine, health reads and recovery commands from consuming SMS. Use the shared drain runner with an SMS
adapter, not a second queue or a wholesale email rewrite. Schema details require the later approved build plan.

## Sending transaction and worker

1. One server command serves manual sends and Automation. Authenticated `/api/*` requests validate with Zod;
   organization, contact, conversation and permission checks precede enqueue. Automation supplies its existing
   execution identity and uses the same eligibility command under its authorized system context.
2. Atomically create one logical send, immutable final text/recipient/service snapshot, retail reservation and
   outbox row. Include required identity/opt-out text in segment estimates. Repeating a logical key returns the
   original result; the same key with a different payload is a conflict. No external call runs in this transaction.
3. Quiet-hour and workflow-window delays remain locally scheduled. At claim, recheck the approved Stage 2 gates,
   current work relevance, expiry and reservation coverage. A newly blocked business/consent/balance/registration
   send ends with its reason; lifting a restriction never bulk-replays failed SMS. Technical pacing can defer an
   eligible send within its deadline. Quiet-hour waiting is the already-approved scheduling exception.
4. Atomically claim a due SMS, record its attempt and lease token, and commit. Serialize the recipient's local
   STOP gate with dispatch authorization; persist an inbound STOP hard-stop before acknowledging it. A STOP that
   wins that transaction prevents a new claim. A request already in flight cannot be recalled by a database lock;
   keep this gap small, retain Twilio opt-out protection, and verify the race explicitly.
5. Submit once to the contractor subaccount with the selected Messaging Service. Put an opaque attempt ID in
   the per-message status callback URL; it is correlation, never authentication. Use the established eligible
   sender policy, recording the actual provider-selected sender when available. Freeze provider body/options for
   this attempt and disable hidden SDK/HTTP retries of message creation.
6. Finalize in a short token-checked transaction. Record the Message SID and initial status, and make repeat
   finalization harmless. A callback arriving first can establish acceptance; late worker finalization must not
   downgrade it or charge twice. A conflicting SID is an incident, never a replacement.

**Twilio facts:** The create response supplies the initial status; Twilio does not send a callback for that initial
state. Later callbacks distinguish sent, delivered and failure. SMS has no read receipt promise.
[Twilio status transitions](https://www.twilio.com/docs/messaging/guides/outbound-message-status-in-status-callbacks).

**Proposal:** Keep submission, delivery and billing states distinct. Accepted by Twilio is not delivered to a
handset. Keep scheduled work in UCRM so current gates run before submission. Set provider queue validity no
longer than the remaining intent deadline and approved send window, within provider limits. This bounds Twilio
queue time, not carrier/handset arrival time; do not promise recall or a hard delivery deadline.
[Twilio queueing guidance](https://www.twilio.com/docs/messaging/guides/scaling-queueing-latency).

## Retry and unknown outcomes

| Evidence | Proposed action |
| --- | --- |
| Verified pre-submission local failure | Retry only if transient and still eligible; otherwise expose the reason. |
| Twilio 429 rejection | Store bounded exponential backoff with jitter in Postgres; honor a documented retry delay when supplied. Recheck all gates before another attempt. |
| Definitive invalid recipient, opt-out, registration or policy rejection | End this send with its code; no automatic replay when configuration changes. |
| Timeout/reset after submission may have begun, ambiguous 5xx, malformed success, crash before recording acceptance | `submission_unknown`; retain reservation and reconcile. Never automatically POST again. |
| Accepted SID, then undelivered/failed | Update delivery evidence, reconcile actual billing, expose failure; no automatic new SMS. |
| Finalization database failure after a known SID | Retry recording the same result, never the provider submission. |

Twilio documents 429 responses as safe to retry. This is distinct from GHL business sending restrictions.
[Twilio 429 guidance](https://help.twilio.com/hc/en-us/articles/360044308153-Twilio-API-response-Error-429-Too-Many-Requests-).

**Evidence limit:** The reviewed classic Message-create API does not document a client-provided idempotency key.
Do not copy Brevo's key/TTL behavior or mistake a webhook retry header for outbound send idempotency.
[Twilio Message resource](https://www.twilio.com/docs/messaging/api/message-resource).

**Proposal:** A signed callback bearing the matching attempt ID and subaccount can resolve a missing SID. With a
known SID, fetch that exact resource. Without one, bounded account/destination/time searches provide operator
candidates only: identical content is not proof of identity, and an empty search is not proof no send happened.
Unresolved attempts stay visible for owner investigation, including reservation age. Releasing credit requires
proof of no provider cost or an audited adjustment; it does not authorize a resend. Never timeout-release a
reservation and quietly retry the customer message. Administrative recovery must preserve late callbacks.

## Signed inbound and status receivers

**Twilio facts:** Validate the exact public URL and every received form parameter with the official SDK.
JSON validation, if later supported, uses the raw body and its matching SDK method. Parameters can be added.
[Twilio webhook security](https://www.twilio.com/docs/usage/webhooks/webhooks-security).

**Proposal:** Two `/api/webhooks/twilio/*` receivers, inbound and status, use POST form payloads. Bound body size,
parse without stripping signature inputs, then validate typed fields with Zod. A syntactically valid AccountSid
or opaque connection ID may select a server-side credential; it grants no authority before signature success.
Use that subaccount's Auth Token, including an explicit rotation overlap. Verify account, service, sender and
attempt all belong to the same organization before projection. Preserve historical ownership for delayed events
and retired senders. Never route by destination number alone or trust forwarded host headers for the public URL.

Persist authenticated event evidence and dedupe atomically before success. Invalid signatures get 403; transient
storage failure gets retryable 5xx, never success. Configure supported retry overrides for connection/read timeout
and 5xx, with bounded attempts; verify them against the actual endpoint during live proof. Return empty TwiML
`<Response/>` for inbound and 204 for status. Expensive projection/reconciliation runs through bounded durable work.
A malformed authenticated event is quarantined with an alert; ordinary logs contain IDs, not message bodies/tokens.

Twilio supports connection overrides for these Programmable Messaging webhooks. Its idempotency header describes
retry attempts; use business identities for dedupe. Event Streams' retry guarantees do not apply here.
[Twilio connection overrides](https://www.twilio.com/docs/usage/webhooks/webhooks-connection-overrides).

### Idempotency, consent and ordering

- Inbound identity: provider + AccountSid + MessageSid + inbound kind. Retry/fallback delivery creates one message,
  one consent evidence event, one usage source, and one unread effect. Preserve conflicting payloads for review.
- Status identity: provider + AccountSid + MessageSid + status + error code + relevant provider event facts.
  Preserve distinct corrections; repeated receipt never repeats a ledger entry or Automation signal.
- Store provider occurrence time when supplied and receipt time separately. Never invent a provider timestamp
  from receipt time. Nonterminal status cannot regress a terminal outcome. Conflicting terminal observations
  trigger a bounded fetch by SID and preserve both observations; do not rank delivered and undelivered numerically.
- Callback-first, callback-after-quarantine and worker-first paths converge on the same attempt/SID and billing
  identity. Unknown provider statuses are retained and flagged rather than misreported as delivered.
- STOP commits an immediate local hard-stop even if timeline projection lags. Duplicate or old START must not clear
  a newer STOP. Ambiguous consent order fails closed until provider state and valid opt-in evidence agree. HELP
  changes no consent. Consent remains contractor-scoped and protects every matching destination in that tenant.
- Ordinary inbound projection uses the existing tenant contact/timeline path; ambiguous contact matches stay
  visible for resolution. Inbound, consent and status work continue through zero balance and outbound pauses.
  Stage 4 owns exact contact-matching and conversation UI acceptance.

Twilio explicitly warns that callbacks can arrive out of order.
[Twilio status tracking](https://www.twilio.com/docs/messaging/guides/track-outbound-message-status).
When `OptOutType` is present, Twilio has already sent its keyword confirmation; UCRM must not send another.
[Twilio Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out).

## Provider usage and settlement

**Twilio facts:** Message price may arrive after send/receive, and Messaging Service segment counts can initially
be zero. Treat absent price as pending, not free. [Message resource](https://www.twilio.com/docs/messaging/api/message-resource).
Usage Records provide account/category/time aggregates; they are reconciliation inputs, not an individual-message
receipt. [Twilio Usage Records](https://www.twilio.com/docs/usage/api/usage-record).

**Proposal:** Bounded workers fetch pending message prices by subaccount/SID with backoff, and settle using the
reservation's immutable retail rate. Preserve original provider amount/currency, normalize its debit sign once,
and keep provider cost separate from retail charge. Every settlement/adjustment has a unique source identity;
repeat callbacks or overlapping reconciliation cannot charge twice. Later corrections append adjustments.

Reconcile account/category/time windows with a durable cursor and overlapping rechecks for late data. Message
charges and non-message charges (numbers, registration, provider confirmations) need distinct supported source
identities. Deduplicate overlapping usage categories; never charge both a Message price and its aggregate total.
Unattributed differences create an owner discrepancy with age and evidence, not an invented per-message fee.
Inbound debt and purchased/promotional credit ordering follow Stage 2. Price/usage outages remain visible and
cannot release uncertain reservations. Live proof must demonstrate each enabled charge category before billing it.

## Performance design verdict

- **Growth:** Sends, segments, callback multiplicity, retained payload bytes, unsettled messages and account usage
  windows. Tenant count alone does not establish throughput; peak sends/sec, payload distribution, retention and
  delivery targets are not yet measured. Assume manual/Automation traffic only, no campaign batches.
- **Shape:** Existing Postgres outbox and RPC access, short claims, bounded SMS worker slots, bounded projections
  and paginated reconciliation. Immediate wake plus the existing scheduled safety wake; no infrastructure change.
  Reuse ids-only authorized inbox broadcasts after projection, with permission-filtered API reads in Stage 4.
- **Bounds to verify:** Start from the existing drain's 2 slots, 50 claims and 20-second admission budget as test
  settings, with an explicit provider timeout below the wake deadline. These are not provider throughput values.
  Reconciliation limits requests/pages/time per run and rotates tenants; cursor progress prevents full-history
  rescans. Keep separate budgets so reconciliation cannot occupy outbound slots or delay STOP acceptance.
- **Contention:** Claim query must select SMS with due/status/order predicates and a bounded candidate set. Check
  matching indexes in the build review. Per-organization reservations/caps serialize spending. Limit per-tenant
  in-flight work; measure oldest-due age under skew and adjust candidate selection if hot rows starve quiet tenants.
  Keep provider pacing at the actual account/service/sender limits; do not assume adding numbers increases limits.
- **Cost:** SMS detail/attempt evidence and provider/account callback identity earn their cost through correlation
  and tenant isolation. No Redis queue, Event Streams subscription, partitioning or new realtime transport without
  measured need. No fake global SMS rate or 40,000-user capacity claim.
- **Evidence required:** Duplicate concurrent enqueue/finalize; stale lease and callback-before-finalize; timeout
  after acceptance; 429/5xx; late/conflicting statuses; replayed START after STOP; cross-tenant forgery; token rotation;
  zero balance; double settlement; late prices; usage-category overlap; lost webhook and resumed reconciliation.
  Exercise 200 test tenants with one hot tenant and concurrent email, recording submitted load, segment mix,
  callback multiplier, p95/p99 claim/projection latency, oldest queue age per tenant, rows scanned, lock waits,
  active connections, callback bytes and drain recovery. Include realistic retained history and outage backlog.
- **Overall:** Planning approved. Capacity and live behavior remain unverified. The A2 build/proof stage
  owns numerical delivery targets, retention settings, provider limits and production-like measurements before
  country activation. If these reveal a different design requirement, return to Jafar with the measured trade-off.

## Completion boundary

Stage 3 planning is approved. Durable reliability rules are in the inbox contract; Stage 4 Conversations planning
is next. All A2 planning must be approved before SMS code,
schema or provider changes. No live sends or infrastructure changes are authorized by this note.
