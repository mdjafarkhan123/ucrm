# Communications Activation Roadmap

Permanent behavior lives in docs/contractor-email-contract.md and docs/unified-inbox-behavior-contract.md.

## Approved sequence (Jafar, updated 2026-08-29)

Email activation and realtime inbox (complete) → contractor-settings 6A/6B Automation → A2 SMS → A3
marketing campaigns.

Marketing is deliberately last, and **no marketing groundwork is added early** — no purpose/lane column
until A3 scopes it. Backfilling today's rows as transactional is trivial.

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
| A2   | SMS channel via Twilio        | In progress — Stages 1/2A/2B/2C done (see 2C parts below); contractor-facing implementation (Conversations, Automation, Phone & SMS settings) not started | Country capability and tenant registration | Approved behavior and UI blueprints cover Conversations, Automation, contractor settings and Jafar controls; an eligible contractor can send and receive SMS and use SMS in an eligible automation |
| A3   | One-click marketing campaigns | Not scoped                                | A2                     | Contractor can send a segmented bulk campaign without risking transactional deliverability                                                                                  |

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

## Open product questions

- Q6 What is a marketing campaign for? Recommended: seasonal reminders and win-backs, selected by job history.
- Q7 Who may bulk-send? Recommended: owner and admin only.

## Known external latency

Country-specific carrier registration can take days or weeks. Because UpliftContractor sends under each
contractor's brand, A2 must complete that contractor's actual identity and required registration before
enabling traffic. Registration may run in parallel after the revised plan is approved.

## Settled, do not re-ask

Quote follow-up triggers on successful delivery, not publication, via the Automation engine's v1 Quote
catalog (contractor-settings 6A, approved). A marketing opt-out never blocks essential email
(contractor-email-contract). Redis being installed but unconnected is intentional and does not block A1.
