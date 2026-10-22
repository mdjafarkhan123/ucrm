# Stage 10 Part 4 — Can each number text yet?

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 4
**Stage:** 4a merged to main 2026-10-22; 4b merged to main 2026-10-23; 4c design approved 2026-10-23
(board `SCpaW`, branch `codex/stage10-part4c-design`, claim `e647e44c3210`, waiting to merge). · **Done when:** every number shows its true steps and band (board `NbWfA`), numbers go
live once their approval passes, toll-free has its own check, merged to main.

## Slices

- **4a — merged 2026-10-22.** Readiness rules: `src/lib/communications/number-readiness.ts`; server facts and
  reconciliation: `src/lib/server/communications/sms-number-readiness.ts`; GET:
  `/api/settings/communications/sms/readiness`; applied migration `20261224090000_sms_sender_readiness.sql`.
  US local needs approved US registration; other countries need approved in-date paperwork; toll-free has its own
  check. Reconciliation runs after purchase, webhooks and daily checks. UI: `components/communications/number-readiness/*`.
- **4b — built 2026-10-23.** DB (applied live): `20261225090000_sms_tollfree_verification.sql` — one check per
  toll-free sender + history; reconcile now switches toll-free on when its check is approved. Answers schema
  `validation/communications-sms-tollfree.schema.ts` (= registration answers + `opt_in_image_urls`; consent
  `other` refused). Twilio adapter `twilio-tollfree.ts` (subaccount creds). Send/sync/daily check
  `sms-tollfree-verification.ts` (+ store, 14 tests). Events: toll-free types handled in
  `webhooks/twilio/trust-hub-events`; daily check in `trust-hub-status-cron`. Cards: sent / turned down (reason +
  fix-by date, no button yet) / approved. No API route or row creation yet — that comes with 4c's form.
  Jafar's Twilio setup later: the Event Streams Subscription must add the 8 toll-free event types and receive
  subaccount events.
- **4c — design approved by Jafar 2026-10-23:** Pencil board `SCpaW`, option A only. A four-step form opens
  from the toll-free card: Business (prefilled from registration), Texting (consent and samples), Proof of consent
  (one to five pictures), Check and send. Saved drafts, upload progress/error, sending, under-review and rejected
  states are drawn. Option B was removed. The API and UI still need to create a draft for the sender, save,
  upload proof to a public HTTPS link, and submit through `sendTollfreeCheck`.

## Proof so far

- Focused readiness, webhook, cron and purchase specs — 65 pass. 4b communications/readiness/webhook specs —
  435 pass (2026-10-23).
- SQL switch-on proven in a rolled-back transaction on Raad's org (moved 1, second run 0).
- Playwright 1440 light/dark (Raad owner): live under-review card; mocked board/status/action states matched
  `NbWfA` after skeleton, rename and flag corrections.

## Next

1. Merge the approved 4c design and note into main after Pencil saves `concept.pen`.
2. Build the form and API against `SCpaW`; prove draft → upload → send → under review on the live app without
   starting a real verification. Live submission waits for truthful first-business details and Jafar's go-ahead.

## Limits / notes

- "Text customers in another country" link left out of the summary until Part 5 builds destination requests.
- A ready non-US number can be made default; Part 5 must stop it texting other countries (live SMS is off anyway).
- The Chrome extension wasn't connected this session, so checks used Playwright.
