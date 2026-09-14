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
| A2   | SMS channel via Twilio        | In progress — Stages 1/2A/2B done; Stage 2C started (see 2C parts below) | Country capability and tenant registration | Approved behavior and UI blueprints cover Conversations, Automation, contractor settings and Jafar controls; an eligible contractor can send and receive SMS and use SMS in an eligible automation |
| A3   | One-click marketing campaigns | Not scoped                                | A2                     | Contractor can send a segmented bulk campaign without risking transactional deliverability                                                                                  |

## Stage 2C parts (money + control layer; split for multi-session, Jafar approved 2026-09-14)

Full stage spec: `docs/communications-a2-implementation-plan.md` (2C) + money/UI truth in
`docs/research/communications-a2-stage6-settings-owner-controls-plan.md`. Each part = data + RLS + pgTAP,
then owner API and Jafar UI come as their own later parts. No live SMS needed (A2P wall doesn't block 2C).

- **2C-1 Credit top-up lifecycle — DONE 2026-09-14** (commit 36ebdd0). Offsite top-up request → owner
  confirm/reject, contractor cancel; confirm posts one immutable ledger credit + raises balance.
- **2C-2 Retail rates** — Jafar-set rate versions, current + future-dated, by destination/sender/unit; new
  rates affect new sends only, historical charges keep their rate; cost/margin visible to Jafar only.
- **2C-3 Readiness & registration** — capabilities, plain readiness states, registration submission/history,
  effective SMS mode, country readiness.
- **2C-4 Holds + promotional credit** — distinct platform/org/provider holds + emergency provider suspension;
  promotional credit with expiry and standalone reasoned adjustments/refunds.
- **2C-5 Owner commands (API)** — /api/* + Zod + reconfirmation + immutable audit across the above.
- **2C-6 Jafar owner UI** — extend Integrations / Commercial access / History & recovery + Operations health;
  no new dashboard.

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
