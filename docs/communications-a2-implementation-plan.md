# Communications A2 SMS Implementation Plan

**Status:** Approved by Jafar on 2026-09-13; Stage 2 security corrections approved 2026-09-13  
**Scope:** Manual and Automation SMS, contractor setup/usage, and existing Jafar controls  
**Authority:** Approval starts Stage 1 planning and implementation preparation only. It does not silently authorize
SQL, schema, RLS, permission, Twilio configuration, live sends, packages, or infrastructure changes; each applicable
project approval boundary still applies.

## Outcome

An eligible contractor can register and obtain an SMS-capable business number, send and receive SMS in the
existing Conversations workspace, use **Send SMS** in an eligible Automation, understand charges and delivery
results, and recover safely from holds or uncertain provider outcomes. Jafar controls provider truth, pricing,
credit and emergency pauses through the existing owner surfaces.

This follows the established production pattern already used by UCRM email: the user action and durable outbox
record commit together, a bounded worker contacts the provider outside the database transaction, signed webhooks
are stored before projection, and the browser receives IDs-only live signals before rereading authorized data.

## Build boundaries

- Extend the existing unified inbox, transactional outbox, bounded drain, Automation engine, Settings shell and
  Jafar control room. Do not create a second inbox, queue, automation engine, settings family or owner dashboard.
- Manual and Automation SMS use one server-side eligibility and enqueue command.
- Keep email behavior unchanged and make every email claim, callback, health and recovery path explicitly select
  email before SMS rows exist.
- Twilio credentials stay server-side. Ordinary Twilio calls use a least-privilege Restricted API key created in
  the owning subaccount; encrypted subaccount Auth Tokens are reserved for webhook verification and token
  lifecycle. Platform-level provisioning holds two deployment secrets: a main-account API key for listing
  subaccounts, and the master Account Auth Token used only for the two operations where Twilio returns a
  subaccount's own Auth Token (subaccount create and fetch-by-SID). The master token never enters Postgres, an
  image, a log, or a browser payload. Every contractor write uses a Zod-validated `/api/*` route.
- Required inbound STOP, START and HELP handling and delivery callbacks continue during balance, organization and
  outbound pauses.
- A2 includes operational one-to-one and automated SMS only. It adds no marketing lane, campaign audience model,
  bulk sender or early A3 groundwork.

## Approved implementation sequence

Each stage is a safe checkpoint. Do not enable live traffic until its tests and the previous stages pass.

### 1. Channel-safe shared delivery foundation

**Build:** Extend the existing communication intent, outbox and callback spine with explicit channel-aware
constraints and queries. Add only SMS-owned records needed for message snapshots, provider submission attempts,
sender identity, consent evidence/current projection, credit reservations/ledger and reconciliation. Preserve
email-only fields as email-only rather than filling them with fake values. Add tenant ownership, RLS, service-role
grants and indexes for the exact claim, inbox, callback and reconciliation reads.

**Reuse:** `communication_delivery_intents`, `communication_outbox_events`,
`communication_provider_callback_events`, worker lease/health primitives, current organization access helpers,
and the existing IDs-only inbox broadcast.

**Gate:** Existing email tests remain green; SQL tests prove cross-tenant denial, logical-send idempotency,
email/SMS claim isolation, consent ordering, one reservation/charge per source and bounded indexed claims.

### 2. Twilio organization setup and Jafar controls

Use the mature hosted-platform pattern: one Twilio subaccount per contractor, least-privilege operational
credentials, append-only money/provider history and explicit reasoned holds. Implement this as three internal
checkpoints without changing the approved product behavior.

#### 2A. Server-only credential boundary

**Build:** Add explicit Twilio provider-account and credential records. Safe identifiers and readiness belong to
the provider account; ciphertext, nonce, authentication tag, credential purpose/lifecycle, format version and key
ID belong to a server-only credential table with no contractor or browser access. Store the per-subaccount
Restricted API key secret separately from the Auth Token. Permit at most one current and one staged credential of
each purpose per subaccount; prior Auth Token material is temporary and has an explicit retirement time.

Use Node's maintained crypto implementation for AES-256-GCM. A versioned keyring is supplied through server
secrets, outside Postgres and Docker images. Bind organization ID, credential record ID, subaccount SID, purpose and
format version as authenticated additional data; generate a fresh nonce for every encryption; fail closed on an
unknown key, changed context or invalid tag. The active key encrypts new values while older versions remain
decrypt-only until a resumable re-encryption check has completed. Never return plaintext from a database function,
API response, log, error, audit row or browser payload.

**Gate:** Crypto unit tests prove round trip, unique nonces, wrong-key failure, ciphertext swapping failure,
tamper failure, unknown-version failure and sanitized errors. Database tests prove uniqueness, lifecycle and tenant
constraints plus zero `anon`/`authenticated` access. A clean-machine exercise proves that a database backup alone
cannot decrypt credentials and that the separately restored keyring plus backup can decrypt a canary.

#### 2B. Idempotent Twilio provisioning and rotation

**Build:** Keep the platform-level provisioning credentials in deployment secrets: a main-account API key plus
the master Account Auth Token. Live testing (2026-09-14) confirmed Twilio returns a subaccount's Auth Token only
to the parent's real Account SID + Auth Token — never to any API key — on both create and fetch-by-SID, so the
master token is required for every org's onboarding, not a one-off. It is used ONLY for those two calls; the API
key does all other platform-level reads. The API-key-only alternative (Public Key Client Validation) is limited
to Enterprise/Security editions and is out of scope for launch. Create each subaccount's Restricted API key
inside that subaccount with only the exact permissions required by the implemented Messaging and setup calls;
document any provider endpoint that cannot use a Restricted key before granting a broader exception. Make provisioning a resumable state machine keyed by organization and provider operation, so a timeout
or repeated owner click reconciles known Twilio SIDs instead of creating a second subaccount, service or number.
Provider calls occur outside database transactions; each step records sanitized intent/result history.

Rotate Auth Tokens by creating and testing the secondary token before promotion. Promotion immediately retires the
old primary at Twilio; any locally retained prior token is accepted for webhook-retry compatibility only for a
short window established from the configured product's retry behavior and staging evidence. Rollback is allowed
before promotion; after promotion recovery moves forward with the new token. Restricted API keys rotate separately
through staged creation, cutover verification and revocation.

**Gate:** Adapter and API tests prove same-command idempotency, changed-command conflict, crash/timeout recovery,
cross-subaccount denial, exact Restricted-key use, no secret-bearing output, rollback before promotion and forward
recovery after promotion. Staging verifies the final webhook retry/retirement window; no duration is guessed in
code.

#### 2C. Readiness, money controls and existing owner UI

**Build:** Store supported sender capabilities, registration state/history, effective SMS mode, country readiness,
retail rates, organization credit and distinct platform/organization/provider holds. Add narrowly scoped owner
commands for provider setup, number lifecycle, credit adjustment, rate changes and emergency pause. High-impact
commands require an impact preview, reason, reconfirmation and immutable sanitized audit history. Number release
and provider suspension are separate from ordinary texting or balance holds; inbound and STOP/START/HELP remain
available during outbound holds.

**UI:** Extend the existing Jafar organization Communications workspace and Operations page. Do not add a new SMS
dashboard. Reuse the existing cards, tables, dialogs, impact preview and reconfirmation flow. Show safe identifiers,
readiness, last check and actionable errors only—never secrets or raw provider responses. Provider-owned actions
remain Jafar actions; contractor number changes remain requests.

**Gate:** Owner API and browser tests prove reconfirmation where required, immutable history, no contractor access
to owner commands or secrets, one append-only balance result per idempotency key, current-rate-only changes and
inbound/consent exceptions during outbound pauses.

### 3. Contractor Phone & SMS and SMS usage

**Build:** Add the approved two Settings destinations and cards. **Phone & SMS** exposes readiness, registration,
numbers, sending rules and holds. **SMS usage** exposes balance, offsite top-up instructions, reservations, settled
charges and lean health. Reuse `SettingsDestinationCard`, `SectionBlock`, shared tables/dialogs and current Settings
permission filtering.

**Data loading:** Page shells render immediately. TanStack Query owns the data; dialogs and row details prefetch on
hover and stay disabled until opened. Writes invalidate readiness, usage, Settings-card, inbox-eligibility and owner
views affected by the change. Add both routine routes to the app-shell warm list.

**Gate:** Owner/admin and restricted-role browser tests cover ready, needs setup, pending, restricted, paused, low
balance, empty, loading, error and narrow-screen states.

### 4. One SMS command and bounded Twilio worker

**Build:** Add one server command used by manual and Automation sends. It freezes recipient, sender/service, final
body, segment estimate, applicable retail rate and logical-send identity in one short transaction with the credit
reservation and outbox row. At claim time it rechecks current consent, destination, number/registration readiness,
quiet hours, workflow window, package/mode, credit, caps, pauses and work relevance.

Add a Twilio adapter to the existing bounded drain runner with a separate SMS worker lease and budget. Record an
attempt before the provider call, disable hidden create retries, finalize with the claim token, retry only proven
pre-submission transient failures, and quarantine uncertain submissions for reconciliation instead of sending
again. Immediate wake plus the scheduled safety wake remains the dispatch pattern.

**Gate:** Unit and integration tests cover duplicate clicks, changed-payload conflicts, two workers racing, stale
leases, 429 backoff, definite rejection, timeout after possible acceptance, callback-before-finalize, quiet-hour
release, a STOP racing a claim, zero balance and email/SMS concurrency.

### 5. Signed inbound and status webhooks

**Build:** Add separate form-encoded Twilio inbound and status routes. Validate the exact public URL and all received
parameters with the official Twilio SDK and the matching subaccount Auth Token. During rotation validate with the
current and staged token before promotion; after promotion allow the locally retained prior token only for the
staging-proven webhook-retry window. This is not provider-side token overlap. Persist authenticated evidence and
dedupe before returning success. Project expensive work through bounded durable work; never log bodies or
credentials.

Inbound matching uses normalized customer numbers: one match joins that customer, no match creates a Lead and
Unassigned conversation, and multiple matches create a Needs identification conversation. STOP/START/HELP is
processed before identity resolution. Status projection cannot regress confirmed outcomes and conflicting terminal
evidence becomes Needs checking.

**Gate:** Fixture and live tests cover invalid signatures, forwarded-host traps, retries, malformed authenticated
events, duplicate/out-of-order events, retired senders, cross-tenant forgery, unresolved identity and Twilio's own
keyword response without a duplicate UCRM reply.

### 6. SMS in Conversations

**Build:** Extend the existing mixed-channel message model, inbox read and conversation grouping with SMS. Extend
the existing composer to select SMS, the saved customer number and an eligible continuity/default business number;
show segment count, estimated retail cost, quiet-hour schedule and actionable blockers. Add SMS bubbles, scheduled
states, delivery/failure details, uncertain-send protection, identity resolution and supported MMS/secure-link
behavior. Do not promise read receipts.

Keep the existing three-pane desktop workspace and current mobile composition. Continue using the organization
Realtime topic: broadcast IDs only, then invalidate permission-scoped inbox/history queries. Reuse snippets,
attachments, assignment, followers, unread handling and context rather than duplicating them for SMS.

**Gate:** Svelte validation, component/API tests and browser tests cover new and established conversations, explicit
sender choice, optimistic send, scheduled send, failure, Needs checking, incoming reply, opt-out, ambiguous customer,
MMS fallback, permissions and responsive states.

### 7. SMS in Automation

**Build:** Add **Send SMS** to the existing typed action catalog, recipe validator, editor, summary rail, immutable
versions and worker. The action stores copied editable text and an optional authorized sender; it uses the same SMS
enqueue command and live eligibility gates as Conversations. Link the resulting delivery intent to the enrollment,
work item and conversation. Extend History with waiting, scheduled, sent/delivered, skipped, failed and Needs
checking results.

Automation tests are real, normally charged sends restricted to the authorized user's verified team phone. Keep
the approved 50-step ceiling. No branching, AI writing, Manual SMS tasks, automated MMS or marketing is added.

**Gate:** Definition, command, worker, API and browser tests cover draft/version stability, activate impact review,
sender continuity, Wait/window interaction, customer reply suppression, no-primary-mobile skip, opt-out, balance or
restriction failure, delivery links and idempotent worker retries.

### 8. Billing reconciliation, recovery and launch proof

**Build:** Add bounded price reconciliation by known Message SID and bounded account usage-window reconciliation
with durable cursors and overlap. Keep provider cost separate from the immutable retail rate. Later corrections
append adjustments. Unknown cost keeps its reservation and appears in existing Jafar Operations until resolved.

**Live proof:** Use a real test organization, registered sender and controlled recipient phones. Prove outbound,
reply, STOP/START/HELP, delivery/failure, uncertain outcome recovery, late price, adjustment, pause behavior and
Automation links. Rehearse token rotation and webhook loss/replay. Enable one verified country/use case at a time.

**Scale evidence:** Exercise 200 test tenants with one hot tenant and concurrent email. Record submitted SMS rate,
segment mix, callback multiplier, p95/p99 claim and projection latency, oldest due age per tenant, rows scanned,
lock waits, active connections, callback size and drain recovery. Start with the existing two worker slots,
50-claim and 20-second drain budgets as test settings only. This establishes capacity only for the measured workload.

**Gate:** Security/advisor checks, clean migrations, unit/integration/browser suites, the production-like workload,
runbooks, alerts and the live scenarios pass. Unresolved or unpriced sends remain visible and cannot be blindly
resent. Jafar explicitly approves each country before contractor traffic is enabled.

## Performance design verdict

- **Growth path:** messages, segments, callbacks, retained evidence, reservations, unsettled prices, inbox history,
  open live sessions and Automation enrollments; one hot tenant may dominate shared workers.
- **Workload contract:** launch targets 100–200 organizations and operational manual/Automation traffic, not bulk
  campaigns. Peak rate, segment distribution, retention and Twilio account limits remain measurements for Stage 8,
  so no 40,000-user capacity claim is made.
- **Chosen shape:** bounded indexed Postgres claims, one shared delivery spine, channel-specific workers/adapters,
  cursor-paginated reads/reconciliation, per-tenant pacing and the existing IDs-only Realtime reread pattern.
- **Complexity cost:** SMS detail/attempt, sender/registration, consent and ledger/reconciliation records plus the
  Twilio SDK. Each exists for tenant isolation, legal evidence, provider correlation or money correctness.
- **Rejected:** Redis queue, Event Streams, partitioning, replicas, a second inbox, a second Automation engine,
  unbounded polling and bulk/campaign infrastructure. The approved launch workload does not yet earn them.
- **Failure behavior:** bounded retries only before proven submission; ambiguous sends stop for reconciliation;
  inbound consent remains available during outbound failure; hot tenants are bounded; tenant/provider identities
  are verified before projection.
- **Verification:** the Stage 8 measurements and failure scenarios above, plus query plans for every growing claim,
  inbox, consent and reconciliation read.
- **Overall:** Ready for staged implementation after Jafar approves this plan. Capacity remains unverified.

## Approval record

Jafar approved this eight-stage sequence and its boundaries on 2026-09-13, conditional on mature-industry patterns,
no guesswork, no overengineering, and beautiful, professional, modern UI/UX. Approval starts Stage 1 only. Every
later stage still must pass its own gate before the next begins, and provider/country activation remains a separate
explicit decision.
