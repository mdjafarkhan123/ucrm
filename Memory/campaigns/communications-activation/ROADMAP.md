# Communications Activation Roadmap

Permanent behavior lives in docs/contractor-email-contract.md and docs/unified-inbox-behavior-contract.md.

## Approved sequence (Jafar, updated 2026-08-29)

Email activation and realtime inbox (complete) → contractor-settings 6A/6B Automation → A2 SMS.

Marketing product ownership moved to the dedicated `marketing-growth` campaign on 2026-09-15 after its product
blueprint was approved. Communications supplies delivery, sender health, consent, callbacks, and service-message
protection; it does not duplicate Marketing audience, content, launch, or reporting ownership.

## Planning boundary — clarified by Jafar

Plan the complete product: features, user actions, visible results, exceptions, navigation, screen composition,
responsive behavior and all meaningful UI states. Present GHL behavior, proposed UCRM behavior and differences
needing a decision in everyday English. Product UI planning is not a coding plan. Implementation planning follows
only after both behavior and UI blueprints are approved. Earlier Stages 1–3 approvals remain recorded; technical
research is supporting reference, not authorization to code.

| Part | Outcome                       | State                                     | Depends on             | Completion gate                                                                                                                                                             |
| ---- | ----------------------------- | ----------------------------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1-D | Managed email-domain activation | Done — accepted 2026-08-30              | A1 outbound proof      | One owner action safely reconciles separate sending/receiving domains, Cloudflare DNS, Brevo verification and the domain webhook; the test domain passes                     |
| A1-V | Finish email live verification | Done — accepted 2026-08-30              | A1-D                   | Fresh real email reaches a real inbox and replies; attachment, bounded backlog and one-day soak pass; recovery and monitored drain remain healthy                           |
| A2   | SMS channel via Twilio        | In progress — Stages 1–3 done; Stage 4: 4A+4B done, 4C next | Country capability and tenant registration | Approved behavior and UI blueprints cover Conversations, Automation, contractor settings and Jafar controls; an eligible contractor can send and receive SMS and use SMS in an eligible automation |
| A3   | Marketing delivery dependency | Routed to `marketing-growth` 2026-09-15   | Email foundation; A2 for future SMS | Communications exposes the safe delivery and result contracts required by Marketing without owning the Marketing product                                                     |

## Stage 2C parts (money + control layer; split for multi-session, Jafar approved 2026-09-14)

Full stage spec: `docs/communications-a2-implementation-plan.md` (2C) + money/UI truth in
`docs/research/communications-a2-stage6-settings-owner-controls-plan.md`. Each part = data + RLS + pgTAP,
then owner API and Jafar UI come as their own later parts. No live SMS needed (A2P wall doesn't block 2C).

- **2C-1 Credit top-up lifecycle — DONE 2026-09-14** (commit 36ebdd0). Offsite top-up request → owner
  confirm/reject, contractor cancel; confirm posts one immutable ledger credit + raises balance.
- **2C-2 Retail rates — DONE 2026-09-14** (commit 09e88eb). Immutable rate versions keyed by
  destination/sender/message-unit + currency; applicable rate = latest whose effective_from has arrived;
  future-dated waits, retroactive refused; sends freeze the rate. Provider cost + margin server-owned/Jafar-only.
  Table `communication_sms_retail_rates` + `set_retail_rate`/`effective_retail_rate` commands; 26 pgTAP green.
- **2C-3 Readiness & registration — DONE 2026-09-14** (commit 7da6fe3). `communication_sms_registrations`
  (one per org/country/sender-type/use-case; waiting_for_info→under_review→approved|action_needed) +
  append-only `communication_sms_registration_events`; sender capabilities (country/type/SMS/MMS/Voice/
  registration) added to `communication_sms_sender_identities`; `communication_sms_org_modes` (effective mode =
  chosen capped by package ceiling unless Jafar override; no row = off, modes off|operational); readiness
  computed on read via `communication_sms_readiness()`. 53 pgTAP green.
- **2C-4 Holds + promotional credit — DONE 2026-09-14** (commit 3be87cb; 60 pgTAP green, applied to dev DB).
  Migration
  `20260917120000_communications_sms_holds_promo_adjustments.sql`. `communication_sms_holds` (scope
  platform|organization|provider, one active per scope+target, reasoned place/release, provider>platform>org
  precedence, pauses OUTBOUND only) + `communication_sms_active_outbound_hold()` + `communication_sms_outbound_state()`
  (readiness 'ready' becomes 'outbound_paused' with cause when held; setup states never masked).
  `communication_sms_promotional_credits` (expiring bucket, expiry derived on read, revocable) +
  `promotional_balance`/`spendable_balance`. Standalone reasoned adjustments/refunds via
  `record_adjustment`/`record_refund` posting immutable ledger entries (pre-check gives friendly P0001, the
  accounts balances-check stays the backstop).
- **2C-5 Owner commands (API)** — /api/* + Zod + reconfirmation + immutable audit across the above.
  Split at a verified boundary; template established.
  - **2C-5a Credit top-up decision API — DONE 2026-09-14** (commit 13788a0). Owner confirm/reject at
    `/api/jafar/organizations/[organizationId]/communications/sms/credit-topups/[requestId]`; owner session
    + Zod + step-up + org-scoped 404 guard + P0001→409 mapping. Actor attribution:
    `PLATFORM_OWNER_ACTOR_ID` sentinel to the command + real email in `access_audit_events` via
    `recordOwnerAccessAudit`. 7 vitest green; svelte-check 0. Also regenerated database.types.ts
    (dev DB source of truth; carries the already-applied financial_invoice_sales_page type forward).
  - **2C-5b Holds + promo + adjustments/refunds API — DONE 2026-09-14** (commit 9480c81; 40/40 vitest).
    Org-scoped money/control endpoints (place/release hold, grant/revoke promo, record adjustment/refund),
    each copying the 2C-5a template with step-up.
  - **2C-5c Rates + readiness/registration/mode/capabilities API — DONE 2026-09-14** (org-scoped part
    commit 0ab257f, 25/25 vitest; platform-scoped part same day). Registration start/outcome/check + set
    org mode + set sender capabilities, none on the step-up list. Platform-scoped part: new
    `platform_audit_events` table (server-owned, same shape as `access_audit_events` minus the org tag --
    that table keeps organization_id NOT NULL by design) + `/api/jafar/communications/sms/platform-holds`
    (place/release, step-up required -- an emergency control) + `/api/jafar/communications/sms/retail-rates`
    (publish a rate version, routine/no step-up -- prices future sends only, same treatment as a package
    change). 11 pgTAP + 13 vitest green. Still deferred: registration *submission* has no home yet -- Twilio's
    ISV rule means `attested_by` must be the contractor's real identity, not Jafar's, so this needs its own
    roadmap part alongside the contractor-facing Phone & SMS settings page.
- **2C-6 Jafar owner UI** — extend Integrations / Commercial access / History & recovery + Operations health;
  no new dashboard. Split at a verified boundary (Jafar approved 2026-09-14), same template as 2C-5.
  - **2C-6a Integrations tab (mode, registration, sender capabilities) — DONE 2026-09-14** (commit 68c394c). 2C-5's owner
    commands were write-only, so this part first added the missing reads: GET on `.../sms/mode`
    (stored inputs + computed effective mode), GET on `.../sms/registrations` (list, each row carrying its
    computed `communication_sms_readiness`), and a new GET `.../sms/sender-identities` (list). Three
    components (`SmsModeActions`, `SmsRegistrationActions`, `SmsSenderCapabilitiesActions`) added to
    `CommunicationsWorkspace`'s Integrations section — mode edit, start/check/decide a registration, edit a
    sender's capabilities. None of these commands are on the step-up list (matches 2C-5c). 85/85 vitest
    (7 new) in the SMS owner API suite; svelte-check 0/3364 files; svelte-autofixer clean.
  - **2C-6b Commercial access tab — DONE 2026-09-14** (commit 59ed7dc). Added GET reads on the 5 write-only
    routes (holds, promotional-credits, adjustments, refunds, credit-topups — new file) + 4 components
    (`SmsCreditTopupActions`, `SmsHoldActions`, `SmsPromotionalCreditActions`, `SmsAdjustmentRefundActions`)
    wired into `AccessWorkspace`. Fixed a gap found while building: the ledger table validated an
    adjustment/refund reason but never stored it — migration `20260917150000_communications_sms_ledger_
    entry_reason.sql` adds the column. 97/97 vitest (up from 72); svelte-check/prettier clean. Browser-
    verified: all 4 GET sections render; hold place+release and a standalone adjustment round-tripped with
    step-up, reason on read-back, and audit recording. Promo-credit grant/revoke and refund were not
    live-tested (Chrome autofill made the password step-up field unreliable to automate this session) but
    share the identical pattern and are covered by passing unit tests.
  - **2C-6c History & recovery tab — DONE 2026-09-14** (commit 636a7c3). 2C-5's registration commands
    (start/check/outcome) insert into the append-only `communication_sms_registration_events` table but
    nothing read it back, so this part added the missing GET `.../sms/registration-events` (joins each
    event with its registration's country/sender type/use case) + a read-only `SmsRegistrationHistory`
    component wired into `ActivityWorkspace`'s existing "History and recovery" section. Also added friendly
    labels for the 13 SMS event types already flowing into `access_audit_events` (top-ups, holds, promo
    credits, adjustments/refunds, mode, sender capabilities, registration), which previously rendered as
    raw snake_case strings in the generic activity table. 101/101 vitest (up from 97); svelte-check 0/3375;
    browser-verified live (started a registration + recorded a readiness check for Raad LTD, both rows
    appeared correctly).
  - **2C-6d Operations health — DONE 2026-09-14** (commit b808080). Added the missing GET reads on the two
    platform-scoped write-only routes (platform-holds, retail-rates) + two components
    (`SmsPlatformHoldActions`, `SmsRetailRateActions`) wired into the top-level `/jafar/communications` page.
    Retail rates group by destination/sender/message-unit/currency, each showing its current effective
    version plus history. 109/109 vitest (up from 101); svelte-check 0/3377. Browser-verified live: rate
    publish round-tripped end to end; platform-wide hold place+release round-tripped with step-up (a wrong
    password was correctly rejected before the real one succeeded).

**Stage 2C is complete.** This also closes A2's Jafar-UI planning item.

## Stage 3 parts (contractor Settings; Jafar approved 2026-09-14)

Follow the approved HighLevel model: Phone & SMS owns setup/readiness, SMS usage owns money and lean health,
and neither duplicates Conversations or Jafar controls. Owner or administrator may attest only after explicitly
confirming they are an authorized representative; preserve their identity, wording, time and submitted answers.

- **3A Registration submission truth + contractor API — DONE 2026-09-14.** Versioned saved answers and an
  immutable snapshot for every submission/resubmission; contractor owner/admin save and attest through
  Zod-validated organization-scoped `/api/*` routes while provider submission remains Jafar's action. Gate met:
  22 pgTAP, 7 focused Vitest, and full svelte-check green.
- **3B Phone & SMS registration UI — DONE 2026-09-14 (commit a08b8f0).** Settings card, warm route, readiness
  summary and guided registration form with draft/submitted/fixes states. Submit-500 fix: attestation constants
  moved out of the submit `+server.ts` into `$lib/server/communications/sms-registration.ts`. Gate met:
  browser-verified Submit → under_review with read-only lock, svelte-check clean, SMS-registration specs pass.
  Committed scoped (SMS-only) out of an entangled tree; invoice Part 5A edits in shared files left untouched.
- **3C Phone & SMS numbers, rules and holds — DONE 2026-09-15; depended on 3B (done).** Complete the approved page
  without exposing provider-owned actions as direct contractor mutations. Jafar approved the GHL-matched scope
  (2026-09-14): numbers are view/name/set-default self-service while buy/release stay owner/provider actions;
  "Sending rules" becomes **Compliance & sender info** (opt-out text, sender ID, 1–60 day re-add) — business
  hours live in Automation (Stage 5), matching where HighLevel puts each control (research:
  help.gohighlevel.com SMS Compliance Settings + Phone Number Configuration articles). Split data → API → UI
  like 2C.
  - **3C-1 Data layer — DONE 2026-09-14 (verified local, UNAPPLIED to dev DB).** Migration
    `20260918100000_communications_sms_numbers_defaults_and_compliance.sql`: `is_default_sender` on
    sender_identities (one default per org via partial unique index) + `communication_sms_rename_sender` /
    `communication_sms_set_default_sender` (ready + SMS-capable only, clears prior default) + new
    `communication_sms_compliance_settings` (one row/org, opt-out + sender-info enable/text, 1–60 day interval)
    + `communication_sms_set_compliance_settings` upsert. All server-owned (RLS on, no client policies; grants
    to service_role only; commands are security-definer). 33/33 pgTAP green via `supabase db reset --local`.
  - **3C-2 Contractor read/write APIs — DONE 2026-09-14.** 3C-1 migration `20260918100000_...` applied to the
    remote dev DB via Supabase MCP (`apply_migration`/`execute_sql`; no CLI login needed), history row recorded
    under that version, and `database.types.ts` scoped-updated by hand (MCP raw gen is one 610k-char line the
    repo Prettier-formats, so a wholesale regen churns the whole file). Four org-scoped routes under
    `src/routes/api/settings/communications/sms/`: `numbers/` GET, `numbers/[senderId]/` PATCH (rename |
    set_default), `compliance/` GET+PATCH, `holds/` GET. `requireOrganizationAdmin('conversations.manage_
    connections')` + Zod + owner client reads + command RPCs, mirroring the 3A template. Departure: the holds
    GET returns active holds + an opt-out COUNT only (per-contact opt-out list is unbounded and scale-sensitive;
    a search endpoint is deferred to 3C-3 if the UI needs it). Gate met: 10/10 vitest, svelte-check 0/3416,
    Prettier clean, and the 3 RPC guards verified live on dev (0 stray rows). Files uncommitted (entangled tree).
  - **3C-3 UI — DONE 2026-09-15.** Added Phone numbers, Compliance & sender info, and Holds/opt-outs sections to
    `settings/communications/sms/+page.svelte`, backed by the 3C-2 endpoints, plus client lib
    `$lib/communications/sms-settings.ts`. Numbers: list, inline rename, make-default (disabled unless
    ready+SMS-capable); release/replacement have no backend yet, so they show as a "contact Jafar" notice rather
    than a fake action. Compliance: two toggles + custom wording + 1–60 day interval, explicit Save. Holds: opt-out
    count + active holds list, read-only. Gate met: svelte-check 0/3421, Prettier clean, 20/20 relevant vitest
    green, and browser-verified live on dev (rename + compliance save round-tripped, toasts, no console errors).
    3C is now fully done.
- **3D SMS usage — DONE 2026-09-15 (commit 9ee1a76).** Balance, top-up requests, lean health and ledger using
  the existing Stage 2C money truth; no schema change. Fixed during browser verification: the messaging-health
  query's `communication_delivery_intents!inner(channel)` embed was ambiguous (two FKs from
  communication_message_events to that table) and 500'd — disambiguated by naming the delivery_intent_id FK
  constraint explicitly; not catchable by the mocked-client unit tests. Gate met: svelte-check clean, Prettier
  clean, 13/13 vitest green, browser-verified live (balance strip, empty states, submit + cancel a top-up).
  **Stage 3 (contractor Settings: 3A–3D) is now fully done.**

Stages 4–8 continue in `docs/communications-a2-implementation-plan.md`: shared send/worker, signed webhooks,
Conversations SMS, Automation SMS, then reconciliation and live launch proof.

## Stage 4 parts (sending engine; Jafar approved 2026-09-15)

Use Jobber/HighLevel's familiar contractor workflow and Twilio's documented safety patterns. Stage 4 remains dark:
no contractor send UI or live traffic until Stage 5 webhooks and a country launch gate pass.

- **4A Consent-aware enqueue command — DONE, verified; both commits UNCOMMITTED (entangled tree, Jafar commits).**
  - **4A-i Consent proof foundation — DONE, verified (33 pgTAP asserts pass), applied to dev DB; files UNCOMMITTED.**
    Subject-scoped (service / work_updates / billing_updates), exact-number proof; owner/admin-only external proof
    (customer_sms / web_form / signed_agreement; verbal refused); newer opt-out is global and beats older opt-in;
    compute-on-read `communication_sms_consent_status(org,method,subject)`. Stage 1 global consent projection dropped.
    Files: `supabase/migrations/20260919100000_communications_sms_consent_subject_scoped_proof.sql` + matching test.
  - **4A-ii Atomic enqueue command — DONE 2026-09-15, verified (37/37 pgTAP), applied to dev DB; files UNCOMMITTED.**
    `communication_sms_enqueue_operational(...)` freezes recipient/sender/body/segments/rate/logical-send with the
    credit reservation + message snapshot + outbox row in one transaction; rechecks consent (exact number + subject),
    destination, readiness/holds, balance (promotional credit first, atomic reservation), and schedules `available_at`
    for a platform-configurable quiet-hours window; idempotent by (org, logical_send_key), changed payload refused.
    Helpers: `communication_sms_estimate_segments`, `communication_sms_quiet_hours_available_at`/`_set_quiet_hours_
    policy` (+ `communication_sms_quiet_hours_policy` singleton). Reservation gained `reserved_promotional_minor`/
    `reserved_purchased_minor`; delivery-intent payload check made channel-correct (SMS body lives only in snapshot).
    Files: `supabase/migrations/20260919110000_communications_sms_consent_aware_enqueue_command.sql` + matching test
    (fixed a never-run test bug: permission assertion used pgTAP `throws_ok(sql, errcode, description)`, whose 3-arg
    form treats arg 3 as the expected message — corrected to the 4-arg form with NULL errmsg to check SQLSTATE only).
- **4B Bounded Twilio worker — DONE 2026-09-15, verified, applied to dev DB; files UNCOMMITTED (entangled tree).**
  SMS claim/finalize/quarantine mirroring the email spine + a Twilio Messages submission adapter + the bounded SMS
  worker (separate lease `communications-sms-outbox`, reuses generic lease/wake-ledger). Claim rechecks live gates
  (recipient still active, global opt-out = STOP race, sender/registration readiness, outbound holds, quiet hours,
  reservation still held), records the `started` attempt atomically. Finalize: submitted keeps the reservation
  (settlement is Stage 8), cancelled releases it, submission_unknown holds it + opens a reconciliation item; lost
  responses idempotent by finalized_claim_token. Email quarantine scoped to `channel='email'` so it no longer eats
  SMS rows. Adapter classifies 2xx→submitted, 429/5xx→retry, other 4xx→cancelled, network/no-SID→submission_unknown,
  one call (no hidden retries); credential-resolution failure = safe retry. Gate met: 19/19 vitest (adapter + worker:
  idle, submit+finalize under one lease, each outcome without a 2nd send, credential-unavailable→retry, quarantine-
  once drain, lease already_running/deadline/ledger-error), svelte-check 0/3436, and a rolled-back dev-DB integration
  proof (finalize money math A–C, email/SMS quarantine channel isolation D–E, idempotent replay F, foreign lease G).
  Files: `supabase/migrations/20260919120000_communications_sms_bounded_worker.sql`, `src/lib/server/communications/
  twilio.ts` (added `submitTwilioSms`), `sms-worker.ts` + `sms-worker.spec.ts` + `twilio-sms-submit.spec.ts`.
- **4C Wake and basic owner health — DONE (commit `bcef0aa`); this roadmap entry was stale (said "Planned"
  until corrected 2026-09-15 while scoping Stage 9).** Separately authenticated SMS wake route + cron dispatch +
  wake-on-insert trigger for `channel='sms'`, and a lean SMS worker health read in the Jafar Communications
  control room.

Full approved behavior, exclusions and gates: `docs/communications-a2-implementation-plan.md` §4.

## Stage 5 (signed webhooks) — DONE 2026-09-15

- **5A Status callbacks — DONE, committed (`b41cbbd`).** Signed status webhook, token-overlap validation,
  durable dedupe, terminal-protected delivery-outcome projection.
- **5B Inbound messages — DONE, committed.** `record_communication_sms_inbound_message` (known-number match,
  unmatched → new Lead, race-safe) + `record_communication_sms_consent_event_from_reply` (STOP/START/HELP).
  Extended `communication_inbound_messages` with a `channel` column rather than forking a table.
- §5 gate (invalid signatures, forwarded-host traps, retries, malformed events, duplicates, retired senders,
  cross-tenant forgery, unresolved identity, Twilio's own keyword response) verified covered by existing
  fixture/pgTAP tests across 5A+5B — no separate acceptance round needed.

## Stage 6 parts (SMS in Conversations; Jafar approved split 2026-09-15)

Research 2026-09-15 found the DB spine already channel-agnostic: `communication_delivery_intents`,
`communication_inbound_messages`, `communication_outbox_events`, assignment/followers/read-marks, and the
realtime broadcast triggers all already accept/carry `channel='sms'` rows from Stages 1–5B. The gap is entirely
the app layer. Split into 3 parts, data → send → polish, mirroring Stage 2C/3/4:

- **6A Data/API layer — DONE 2026-09-15 (commit 66bda26).** `email-history/+server.ts` now selects
  `channel`/`recipient_phone` (outbound) and `channel`/`sender_phone` (inbound); forward rows tagged
  `channel: 'email'`. `inbox.ts` types (`InboxEmail`, `InboundInboxMessage`) carry `channel`, nullable
  email + new phone fields; `groupMessagesByContact`'s key/name/avatar helpers use a phone-guarded
  `guarded-sms:<phone>` key for an unmatched SMS sender, separate from email's `guarded:<email>`;
  `conversationCustomerEmail` skips a channel with no email address instead of returning null.
  Gate met: svelte-check 0/4196, 95/95 relevant vitest, eslint clean, Prettier clean.
- **6B Composer + send path — DONE 2026-09-15 (commit d5c3859).** New command `enqueue_conversation_reply_sms`
  (mirrors the email reply command's recipient resolution) + read-only `sms-estimate` route for the composer's
  live impact line; `ConversationComposer.svelte` gained an `sms` channel (no subject/attachments, debounced
  character/segment/cost line or blocked-send reason); reply route branches on `channel`. Found and fixed a
  live-blocking bug: the SMS outbox wake trigger raised on the scheduling migration's placeholder secret URL,
  rolling back every SMS send. Gate met: 11/11 pgTAP, 122/122 vitest, svelte-check 0/4199, Prettier clean, and
  browser-verified live (as Raad LTD admin — `office` role has no `conversations.*` permission by design and
  cannot open Communications; use owner/admin for any future Communications browser check). SMS tab renders
  correctly, blocked-send reason shows plainly, failed send renders as a Not Sent/Retry bubble. No unexpected console errors (only the expected 422 from
    the blocked send itself). **Still needs:** the commit (Jafar approves each stage's commit explicitly, per 6A).
- **6C Thread rendering + polish — DONE 2026-09-15 (commit 745bc8e).** Research found phone-based identity
  resolution already fully solved server-side (an unmatched SMS number always auto-becomes a Lead; the schema's
  unique phone index makes the ambiguous-match case Website Chat has structurally impossible for SMS) and
  "scheduled send" doesn't exist as a feature — only a platform quiet-hours hold that leaves `status='queued'`
  with a `failure_message`. Real scope became 3 fixes: (1) `+page.svelte`'s SMS bubble is now its own branch —
  no subject line, no Forward (email-only), inbound sender label falls back to phone; (2) `outboundEmailStatus`/
  `emailStatusDisplay` in `inbox.ts` now maps `sms_delivered/undelivered/failed/needs_checking` to real badges
  (every submitted SMS previously showed a permanent "Submitted"); (3) a held `queued` send now reads "Waiting
  to send" instead of the generic label. MMS explicitly descoped by Jafar 2026-09-15 (nothing parses Twilio
  media on either side yet — inbound `MediaUrl0` is never read, outbound has no attachment param at all); an
  inbound message with attachments now says so in plain language instead of silently dropping it. Gate met:
  full-project svelte-check 0 errors, 15/15 vitest (5 new covering every delivery-status label), Prettier
  clean, and browser-verified live via two temporary rows inserted through
  `record_communication_sms_inbound_message` (the same function the real Twilio webhook calls) — confirmed the
  phone-labeled bubble, the Details dialog's phone fallback, and the MMS notice — then deleted. Live
  delivery-tick states (sms_delivered etc.) can't be produced end-to-end yet (A2P still unapproved for this
  org); covered by unit tests instead.
- **6D MMS (pictures in Conversations) — Deferred by Jafar 2026-09-15, not yet scoped.** Genuinely unbuilt on
  both sides, not a UI gap: inbound Twilio webhook never parses `MediaUrl0`/`NumMedia` media (only stores the
  count), no inbound-attachment row or storage import path exists for SMS, and the outbound SMS send command/
  composer has no attachment parameter at all. Needs its own research + plan (webhook media fetch/storage,
  `communication_inbound_attachments` wiring, outbound upload + Twilio media params) before coding. The plan's
  original §6 scope ("supported MMS/secure-link behavior") is not satisfied until this lands — Stage 6 is
  otherwise done but not 100% complete against that original text.

## Stage 9 (new, added 2026-09-15): actually submit registrations to Twilio (ISV Trust Hub)

Found while scoping Stage 8: `communication_sms_registrations` captures a contractor's attested answers
(Stage 3A) but nothing ever forwards them to Twilio -- `provider_registration_sid` stays null forever (2C-5c
flagged this gap but gave it no home). As an ISV, submitting one contractor is itself a multi-step Twilio Trust
Hub saga (Secondary Customer Profile -> business/authorized-rep End Users -> Address -> entity assignments ->
evaluate -> submit -> A2P Trust Product -> Brand Registration -> Campaign), each step billable and
independently retryable. Split data -> saga -> status sync, mirroring Stage 2B/3/4's template.

**Hard constraint, confirmed live in Jafar's own Twilio Console 2026-09-15:** the platform's own Twilio account
has no real Primary Customer Profile yet either (legal_business_name still literally reads "My first Twilio
account", Business Identity is pre-set to "ISV, Reseller, or Partner" but nothing else is filled in, zero
Brands registered). Jafar confirmed he owns no real registered business at all right now (not Raad LTD, not
the platform itself) -- no EIN, no live website. **No code can get a live A2P submission approved until a real
business exists**, for the platform's own ISV profile as well as any contractor's. Jafar confirmed: build and
unit-test the real integration now; do not spend real money firing Raad LTD's placeholder data at Twilio's live
API. Twilio's Console does offer a "Virtual Phone" trial US 10DLC number (Messaging > Virtual Phone) described
as supporting real two-way SMS for prototyping without the full A2P flow -- not yet investigated for exact
restrictions; worth checking before Stage 9B/9C if Jafar wants any live send proof sooner.

- **9A Trust Hub submission ledger (data layer) — DONE 2026-09-15, applied to dev DB.** Two server-only tables,
  no contractor-facing command (pure system state, same shape as Stage 2B's account/credential split):
  `communication_sms_trust_hub_resources` (current-state, one row per (registration_id, resource_role) across
  the 7 Trust Hub/Brand/Campaign object roles, upserted by the future saga -- no delete, since Brand
  registration carries a real fee and must never be silently recreated) and
  `communication_sms_trust_hub_events` (append-only sanitized step history, mirrors
  `communication_twilio_provisioning_events`). Neither table stores a raw provider response body or secret --
  SIDs, short status strings, sanitized reasons only, to avoid spreading the contractor's attested business PII
  (already in `communication_sms_registration_submissions`) across more tables than needed. Both grant only
  service_role select/insert(/update for resources); RLS enabled, no policies (matches every sibling
  server-owned table). Gate met: 19/19 pgTAP green (`supabase test db` local), clean `supabase db reset
  --local`, applied to dev DB via Supabase MCP, advisors show only the expected "RLS enabled, no policies" note
  shared by every sibling server-owned table. Files:
  `supabase/migrations/20260920100000_communications_sms_trust_hub_submission_ledger.sql` +
  `supabase/tests/database/communications_sms_trust_hub_submission_ledger.sql`.
- **9B Submission saga (Customer Profile → Brand) — DONE 2026-09-15 (unit-tested against mocks; UNCOMMITTED).**
  Research (not memory) against Twilio's actual ISV guide found last session's 9A ledger was one resource role
  short: the A2P Trust Product bundle needs a mandatory `us_a2p_messaging_profile_information` EndUser Standard
  onboarding never has a slot for. Fixed via migration `20260920110000_communications_sms_trust_hub_a2p_profile_
  resource_role.sql` (widens both check constraints to 8 roles; applied to dev DB; local pgTAP 20/20 green;
  Jafar approved this schema change explicitly before it was written). Also confirmed: CustomerProfile and
  TrustProduct are genuinely separate bundles requiring two parallel sets of calls (not one bundle reused); the
  TrustProduct inherits business info by attaching the CustomerProfile itself via EntityAssignment, not by
  duplicating End Users.
  New files: `twilio-trust-hub.ts` (live adapter -- CustomerProfiles/EndUsers/SupportingDocuments/
  EntityAssignments/Evaluations/submit-for-review on trusthub.twilio.com, Address on the legacy 2010 API,
  BrandRegistrations on messaging.twilio.com; authenticated with the platform's main-account Restricted API key,
  matching Stage 2B's least-privilege split), `trust-hub-submission-store.ts` (port + Supabase impl over the 9A
  ledger + a read of the contractor's latest attested submission), `trust-hub-submission.ts` (the saga --
  `submitRegistrationToTrustHub`, idempotent against the ledger like `twilio-provisioning.ts`, refuses to ever
  create a second Brand Registration once one exists). `database.types.ts` hand-updated for both 9A tables (no
  types existed for them yet).
  Two fields Twilio requires that the Stage 3A contractor form never asked for turned out to be safely derivable
  without new UI: `business_industry` is a fixed `CONSTRUCTION` constant (every UCRM org is a contractor by
  product definition) and `company_type` derives from the already-collected `business_type` (nonprofit →
  non-profit, else private) -- confirmed via research, no new contractor-facing field needed.
  `business_regions_of_operation` only maps US/CA (`USA_AND_CANADA`) today; any other `country_code` throws
  rather than guessing. `job_position`/`business_registration_id_type` free-text answers map to Twilio's fixed
  enums with a safe `Other` fallback when they don't match a known value.
  No owner-facing API route or Jafar UI wraps this saga yet (deliberately out of scope, same as how 2B preceded
  2C); `isvPrimaryCustomerProfileSid`/`monitoringEmail` have no real values yet (Stage 9's hard constraint: no
  real business registered for the platform itself). Files UNCOMMITTED (Jafar commits explicitly).
- **9B-follow-up Sole Proprietor path — DONE 2026-09-15 (unit-tested against mocks; UNCOMMITTED).** Closes the
  gap 9B deliberately left open: a `sole_proprietorship` with no EIN/registration ID now goes through Twilio's
  separate "New Sole Proprietor A2P 10DLC Registration for ISVs" guide (researched fresh, not memory) instead of
  being refused. Confirmed US/Canada-only (no Tax ID program exists elsewhere) and that the ISV's own Primary
  Customer Profile prerequisite applies to this path too -- same hard-blocker as Standard, not a way around it.
  Product decision Jafar approved: the Stage 3A form's `business_registration_id_type`/`business_registration_id`
  become optional only for a sole proprietor with no ID (Zod `superRefine`, not two schemas); a new local-only
  toggle ("I have a business registration number (EIN)") shows/hides and clears those fields, and requires a
  US/CA address when off. The OTP mobile number and Starter Profile contact both reuse the already-collected
  `authorized_representative` (Twilio's own docs: "for sole proprietorships, the authorized representative is
  the sole proprietor" -- no new contractor-facing field). `mapBusinessType`'s error message corrected: a
  sole-proprietor-with-EIN is a real, rare Twilio gap needing manual review, not a "use the other guide" case.
  New saga path (`submitSoleProprietorSections` in `trust-hub-submission.ts`) reuses the same 6 ledger resource
  roles as Standard (no migration needed -- `customer_profile`/`a2p_trust_product`/`end_user_authorized_
  representative`/`end_user_a2p_messaging_profile` are reused as the equivalent Twilio graph slots, just with a
  different policy_sid/End User type per path) and the same `twilio-trust-hub.ts` adapter (added `policySid` to
  the Customer Profile/Trust Product calls and `brandType` to Brand Registration -- verified against Twilio's
  BrandRegistrations request schema: `STANDARD` | `SOLE_PROPRIETOR`). Gate met: 10/10 vitest in
  `trust-hub-submission.spec.ts` (2 new: full sole-proprietor sequence with brandType asserted, idempotent
  re-run), scoped `tsc --noEmit` clean, svelte-autofixer clean on the form, Prettier clean.
- **9C Campaign registration + status sync — DONE 2026-09-15 (unit-tested against mocks; commit `3772b2a`).**
  New `syncTrustHubRegistrationStatus(deps, { registrationId })`: re-fetches the live Brand status from Twilio,
  and once Brand reads `APPROVED`, creates the Campaign exactly once (idempotent via the 9A ledger -- an
  existing `campaign` resource is re-fetched by SID instead of recreated, since Brand/Campaign registration is
  billable and per Twilio's guide a second Campaign must never be created for the same Brand). Reflects the
  outcome onto `communication_sms_registrations.status` via the existing 2C-3 owner commands
  (`recordRegistrationOutcome`/`recordRegistrationCheck`): Brand `APPROVED`+Campaign `VERIFIED` → `approved`;
  either resource's terminal-failure status → `action_needed` with Twilio's own failure reason surfaced;
  anything still pending → `under_review`.
  Campaign content is never invented platform copy -- `buildCampaignContent` builds Twilio's required
  `description`/`messageFlow`/`messageSamples`/`hasEmbeddedLinks`/`hasEmbeddedPhone` fields entirely from the
  contractor's own attested Stage 3A `messaging` answers (Jafar directed "follow what GHL does" for this
  2026-09-15); the link/phone flags are regex-derived from the actual sample messages so what Twilio sees always
  matches what the samples show, and `usAppToPersonUsecase` is `CUSTOMER_CARE` for the Standard path or
  `SOLE_PROPRIETOR` for the Sole Proprietor path.
  Tightened `communications-sms-registration.schema.ts`'s messaging minimums to Twilio's real Campaign
  requirements (`description`/`consent_description` 40+ chars, each `sample_message` 20+ chars) so a
  too-short attested answer fails locally at Stage 3A instead of failing a real, billable Twilio submission.
  Gate met: extended `trust-hub-submission.spec.ts` (was 10, now covers sync's brand-pending/brand-failed/
  campaign-created/campaign-idempotent-refetch/campaign-failed/campaign-verified paths against mocked Twilio
  responses -- no live call, per Stage 9's hard constraint). Adapter-level spec added 2026-09-15
  (`twilio-trust-hub.spec.ts`, 22 tests, mirroring `twilio-sms-submit.spec.ts`'s pattern): every one of the 13
  `TwilioTrustHubClient` methods asserted for exact HTTP method/path/base-host/form-params (including
  `MessageSamples` sent as a repeated key, not JSON) and the provisioning-key Basic auth header, plus shared
  429/5xx-retryable, 4xx-not-retryable, network-failure-safe-to-retry-without-leaking-the-raw-error, and
  missing-SID-in-a-2xx failure classification. Full-project `svelte-check` confirmed clean (4209 files, 0
  errors) with `NODE_OPTIONS="--max-old-space-size=6144"`. Full `vitest run` shows 71 pre-existing failures in
  11 unrelated files (quotes bulk-archive/access-links/convert-to-job/lifecycle/proposal/quote-commands/
  signature/similar-and-delete, settings-business, team invitation resend) -- none touch communications; not
  investigated further as out of this campaign's scope. Completes what unblocks Stage 8's live proof once a
  real business exists to actually submit.
- **9D Automatic trigger for status sync — DONE 2026-09-15 (unit-tested against mocks; committed `7c91e84`).**
  Closes 9C's gap: `syncTrustHubRegistrationStatus` had no caller. Researched Twilio's own guidance for this
  exact ISV scenario (troubleshooting-sole-proprietor-brand-registration-failures, not memory): Twilio
  recommends a push notification (Event Streams webhook) over repeatedly polling the Brand endpoint. Jafar
  approved building both, webhook primary + a daily poll as a safety net (mirrors this project's own
  "reconcile daily" pattern already used for SMS message-status). New files: `trust-hub-status-trigger-
  store.ts` (two lookups: map an inbound Brand/Campaign SID back to a registration id; list registrations
  still `under_review` that already have a submitted Brand -- the poll's candidate set), `trust-hub-status-
  poll-cron.ts` (`runTrustHubStatusPollCron`, per-registration error isolation mirroring
  `runOrganizationClosureCron`), `api/jafar/internal/trust-hub-status-cron/+server.ts` (daily pg_cron ->
  net.http_post target, Bearer secret, mirrors `closure-cron/+server.ts` exactly), `api/webhooks/twilio/
  trust-hub-events/+server.ts` (Event Streams webhook Sink target -- HTTP Basic auth, since Event Streams
  Sinks authenticate via URL-embedded credentials, not the classic X-Twilio-Signature header; parses the
  CloudEvents array, maps brand/campaign events to a registration via the new lookup, calls
  `syncTrustHubRegistrationStatus`, and asks Twilio to redeliver only on a retryable transport failure).
  Migration `20260920120000_communications_sms_trust_hub_status_trigger.sql` (applied to dev DB): a
  `(resource_role, provider_sid)` partial index for the webhook's lookup, plus the poll's Vault secret
  bridge + `cron.schedule` (06:30 daily), mirroring `organization_closure_cron_extensions_and_vault.sql` /
  `organization-closure-daily-cron-schedule.sql` exactly. New env vars `TRUST_HUB_STATUS_CRON_SECRET` /
  `TRUST_HUB_EVENTS_WEBHOOK_SECRET` (both optional, unset = always unauthorized, matching the `*_WORKER_
  SECRET` convention). Because every contractor's Brand/Campaign lives under UCRM's single ISV Twilio
  account, only one Event Streams Sink/Subscription is ever needed platform-wide -- creating that real
  (free) Twilio Console/API resource is left to Jafar, not automated. Gate met: 19/19 new vitest (poll-cron
  sweep tallying/isolation, cron-route auth, webhook-route auth/parsing/lookup/retry-vs-accept), full-project
  `svelte-check` 0/4218, Prettier clean. Not live-tested (Stage 9's hard constraint: no real business
  registered yet on either side); the Sink itself is not yet created on the live Twilio account.

## Stage 8 parts (billing reconciliation; started 2026-09-15, non-blocked pieces run in parallel with Stage 9)

Full approved scope: `docs/communications-a2-implementation-plan.md` §8. Live proof and the 200-tenant scale
evidence need real Twilio traffic/registration and stay blocked behind Stage 9's hard constraint; the
reconciliation *logic* itself does not, so it started here.

- **8-1 Price reconciliation by known Message SID — DONE 2026-09-15 (unit-tested + typechecked; committed
  `494424e`).** Closes a real gap: nothing had ever turned a 'reserved' SMS credit hold into a real,
  final charge (Stage 4B's own code comment said so explicitly). Twilio's status callback never carries
  Price/PriceUnit (confirmed via Twilio docs research, not memory) -- only `GET /Messages/{Sid}.json` has it,
  on an undocumented delay -- so this is a bounded poll (every 30 min, created **INACTIVE** like the send
  worker, since it makes real Twilio API calls), not a webhook.
  New Postgres commands (migration `20260921100000_communications_sms_price_reconciliation.sql`, **applied to
  dev DB**): `communication_sms_list_price_reconciliation_candidates`, `communication_sms_settle_reservation_price`
  (converts the hold into the account's first-ever real charge; if Twilio billed a different segment count
  than estimated, posts a separate visible adjustment at the same frozen per-segment rate -- Twilio's own raw
  price is recorded for margin visibility only and never drives the retail charge), `communication_sms_defer_
  price_reconciliation` (1h->24h backoff, then opens a `billing_mismatch` reconciliation item after 8 attempts
  so an unresolved price surfaces in Jafar Operations instead of retrying forever).
  **Found and fixed while building this:** no promotional credit had ever been spent for good either --
  `private.communication_sms_enqueue_operational_core` (the enqueue command actually live today; the public
  wrapper is now a thin permission check that delegates to it -- a refactor this session found live on the dev
  DB, not yet reflected in any prior migration file) computed "promo already spoken for" by summing reservations
  in state `('reserved', 'submission_unknown')` only. Once a reservation can reach `'settled'` for the first
  time, that filter had to widen to include `'settled'` too, or a settled promo-funded send would silently free
  its promo dollars back up for reuse. Patched via `pg_get_functiondef` + guarded `replace()`, confirmed live
  (`prosrc` now contains the 3-state list).
  New files: `sms-price-reconciliation-store.ts`, `sms-price-reconciliation-cron.ts` (+ spec),
  `api/jafar/internal/sms-price-reconciliation-cron/+server.ts` (+ spec). `env.ts` gained
  `SMS_PRICE_RECONCILIATION_CRON_SECRET`. `database.types.ts` hand-updated (6 new reservation columns + 3 new
  RPC signatures). Gate met: 12/12 new vitest, full-project `svelte-check` 0/4224, Prettier clean, Supabase
  security/performance advisors show no new findings (checked by name -- only the pre-existing baseline lints).
  **Not live-tested** (Stage 9's hard constraint still applies: no real business registered yet).
- **8-2 Account usage-window reconciliation — DONE 2026-09-15 (unit-tested + typechecked; applied to dev DB;
  committed `494424e`).** Bounded, cursor-based cross-check against Twilio's Usage Records API (confirmed via
  Twilio's own docs, `Usage/Records/Daily.json`, `Category=sms-outbound` -- deliberately not the combined `sms`
  category, since inbound is never billed to a contractor and would manufacture false drift) that 8-1 cannot do,
  since 8-1 can only ever verify a message our own system already knows about; this catches a message Twilio
  billed with no delivery-intent/reservation row at all. Confirmed (Twilio's Restricted API Keys Permissions
  PDF, fetched and read directly) the capability string is `/twilio/billing/usage/read` -- added to
  `RESTRICTED_KEY_MESSAGING_CAPABILITIES` in twilio.ts; affects newly created/rotated keys only, moot today
  under Stage 9's hard constraint.
  Migration `20260922100000_communications_sms_usage_window_reconciliation.sql` (**applied to dev DB**): cursor
  columns (`usage_reconciled_through`, `usage_reconciliation_checked_at`) added directly to
  `communication_twilio_accounts` (a strict 1:1 with organization_id, same reasoning 8-1 used for its own
  cursor columns rather than a side table) + new append-only-per-day
  `communication_sms_usage_reconciliation_findings` table (upserted by org+date so an overlap re-check corrects
  itself) + a purpose-built partial index (`communication_delivery_intents_sms_submitted_accepted_idx`) for the
  new per-day totals query + three RPCs: `communication_sms_list_usage_reconciliation_candidates` (lag=2 days,
  overlap=3 days, max-window=14 days, oldest-checked-first), `communication_sms_usage_reconciliation_our_totals`
  (settled reservations grouped by the delivery intent's `accepted_at` date -- not price-settlement date, which
  can lag), and `communication_sms_record_usage_reconciliation_finding` (zero-tolerance match on both count and
  price; a drift opens a `usage_window_drift` reconciliation item via a synthetic `provider_message_id`
  ('usage-window:{org}:{date}'), reusing the existing `communication_sms_reconciliation_items` queue rather than
  a second parallel surface -- widened that table's reason check constraint + added a new partial unique index
  scoped to org+date items; a later match auto-resolves the item, since the only cause this system can
  distinguish is settlement lag clearing within the overlap window). New app files:
  `sms-usage-reconciliation-store.ts`, `sms-usage-reconciliation-cron.ts` (+ spec, 6 tests),
  `api/jafar/internal/sms-usage-reconciliation-cron/+server.ts` (+ spec, 6 tests) mirroring 8-1's route exactly.
  `twilio.ts` gained `fetchTwilioUsageRecords` (follows `next_page_uri`, capped at 10 pages as a safety valve --
  no dedicated adapter-level spec, matching `fetchTwilioMessagePrice`'s own precedent of being exercised only
  through the cron-level tests via dependency injection). `env.ts` gained
  `SMS_USAGE_RECONCILIATION_CRON_SECRET`. `database.types.ts` hand-updated (2 new account columns, 1 new table,
  4 new RPC signatures). Poll schedule: daily at 07:30, created **INACTIVE** like every other cron making a
  real Twilio call. Gate met: 12/12 new vitest, full-project `svelte-check` 0/4230, Prettier clean, Supabase
  security/performance advisors show only the expected baseline noise (new table's own "RLS enabled, no
  policies" note + a fresh unused-index notice). **Not live-tested** (Stage 9's hard constraint: no real
  business registered yet).
- **8-3 200-tenant scale evidence** — not started, per the approved plan's "Scale evidence" section (hot
  tenant + concurrent email; p95/p99 claim/projection latency, rows scanned, lock waits, drain recovery).
  Independent of live Twilio proof; could run once 8-1/8-2 give it something real to measure.
- **Live proof** (real test org, registered sender, controlled recipients) — blocked behind Stage 9's business
  registration constraint, unchanged.

## Build principle (Jafar, durable 2026-08-30)

The full unified inbox is built following GHL end-to-end — root architecture/data model, real-time
mechanism/transport, AND UI/UX — across ALL channels (email now, SMS next, then more). Every channel must work
reliably; "all should work perfectly" is the bar, not a follow-up. For each layer, establish how GHL does it,
reuse the proven pattern, depart only with a stated reason + Jafar's approval. See
[[feedback-follow-ghl-literally-communications]] and docs/unified-inbox-behavior-contract.md.

## Approved Automation and SMS boundary (Jafar, 2026-09-12)

- SMS is a general Communications channel, not a feature tied to a fixed list of use cases. A contractor may
  choose SMS for any eligible customer-message step, including custom workflows and editable presets.
- A workflow contains ordered steps. Presets are starting workflows; contractors may add, remove, duplicate,
  reorder, and edit up to 50 steps, mix supported channels step by step, or build a workflow from scratch.
- The 50-step ceiling is a technical safety limit, not a subscription-plan restriction. Message allowances,
  consent, provider readiness, and sending safety remain separate runtime gates.
- Reputation remains a separate feature that uses Communications and Automation. Its approved rating funnel
  follows the previously agreed HighLevel direction; it does not define or restrict the SMS channel.

## A2 product-planning sequence

1. **Business texting setup — approved:** contractor identity, business numbers, registration, supported
   countries and when texting becomes available.
2. **Consent, balance and sending rules — approved:** customer opt-outs, permitted sending hours, credit,
   charges, limits and what happens when texting is paused.
3. **Reliable message results — approved:** visible delivery/failure outcomes, checking uncertain sends,
   avoiding duplicate texts/charges, and keeping incoming replies available.
4. **SMS in Conversations — approved 2026-09-12:** writing/replying, customer and business number selection,
   saved replies, pictures/files, delivery details, team handling, older history and new/shared-number senders.
5. **SMS in Automation — approved 2026-09-12:** contractors may use a text-and-secure-link SMS action in any
   eligible workflow, with editable copied replies, Wait/window timing, sender continuity and linked results.
6. **Settings and owner controls — approved 2026-09-12:** two contractor settings pages, existing Jafar surfaces,
   plain readiness, offsite top-ups, lean usage health and the real launch scenarios.
7. **Product UI — approved 2026-09-13:** the approved blueprint defines the exact navigation, layouts,
   interactions, responsive behavior, permissions, loading/empty/error states and recovery journeys across
   Conversations SMS, Automation SMS, Phone & SMS, SMS usage, and existing Jafar SMS controls. A2 product
   planning is complete; implementation planning remains a separate, unstarted stage.

Technical reference for the later implementation phase: `docs/research/communications-a2-stage3-transport-webhooks.md`.

Revised boundary: launch for 100–200 contractor organizations globally, like GHL, wherever Twilio supports the
required behavior. Choose eligible local, mobile, toll-free, or registered alphanumeric senders by country and
use case. A one-way sender does not satisfy the two-way Conversations promise. Enable countries from real
customer demand and live verification while keeping the underlying model global from the start.

## Real-time inbox (Jafar-prioritized 2026-08-30)

The inbox uses ids-only authorized organization broadcasts and permission-filtered API rereads. Reuse that
mechanism for every channel; polling or exposing message bodies in broadcast payloads is outside the approved
pattern.

| Part | Outcome | State | Depends on | Completion gate |
| ---- | ------- | ----- | ---------- | --------------- |
| R1 | Live inbox status, no reload | Done — live-verified 2026-08-30 | — (mechanism exists) | MET: outbound flipped queued→delivered live (no reload), Gmail reply landed live in thread+list+unread, reply-alias round-trip correlated, 0 duplicate/failed Brevo webhooks |
| R2 | Instant send + optimistic UI | Done — live-verified 2026-08-30 | R1 (done) | MET: outbound dispatches immediately through the durable outbox wake trigger; cron remains the retry safety net |
| R3 | Full status ladder / receipts | Not scoped | R2 | Sent→delivered→read/opened indicators consistent across channels (email now, SMS/chat later), GHL-style |

## Marketing ownership pointer

Marketing purpose, access, workflow, UI, safe delivery, reporting, later Reputation, and deferred growth features
are settled in `docs/marketing-product-blueprint.md` and owned by `marketing-growth`. Do not re-open them from
this roadmap unless that campaign explicitly changes the shared Communications contract.

## Known external latency

Country-specific carrier registration can take days or weeks. Because UpliftContractor sends under each
contractor's brand, A2 must complete that contractor's actual identity and required registration before
enabling traffic. Registration may run in parallel after the revised plan is approved.

## Settled, do not re-ask

Quote follow-up triggers on successful delivery, not publication, via the Automation engine's v1 Quote
catalog (contractor-settings 6A, approved). A marketing opt-out never blocks essential email
(contractor-email-contract). Redis being installed but unconnected is intentional and does not block A1.
