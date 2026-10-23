# Stage 10 Part 4 — Can each number text yet?

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 4
**Stage:** 4a and 4b merged; 4c built 2026-10-23 to board `SCpaW` (Claude took over Codex's paused WIP).
**Done when:** every number shows its true steps and band (board `NbWfA`), numbers go live once their
approval passes, toll-free has its own check, merged to main.

## Slices

- **4a — merged 2026-10-22.** Readiness: `src/lib/communications/number-readiness.ts`,
  `src/lib/server/communications/sms-number-readiness.ts`; migration `20261224090000_sms_sender_readiness.sql`.
- **4b — merged 2026-10-23.** `20261225090000_sms_tollfree_verification.sql`; schema
  `validation/communications-sms-tollfree.schema.ts`; adapter `twilio-tollfree.ts`; send/sync
  `sms-tollfree-verification.ts`. Jafar's Twilio setup later: Event Streams must add the 8 toll-free event types
  and receive subaccount events.
- **4c — built 2026-10-23.** Page `settings/communications/sms/toll-free/[senderId]` on `PaperworkFrame`
  (now takes `section`/`stepNames`); steps in `components/communications/toll-free/*`, autosave
  `tollfree-draft.svelte.ts`. API `api/settings/communications/sms/toll-free/[senderId]` (+`/pictures`,
  `/send`), public proof `api/public/sms/toll-free-proof/[token]` (private R2, random token). Migration
  `20261226090000_sms_tollfree_proof_images.sql` **applied**. Toll-free answers drop contact title/position and
  number type (Twilio never reads them); `business_registration_country` added; empty US type sends EIN.

## Proof so far

- 4c (2026-10-23): toll-free schema/form + route specs 23 pass. Playwright 1440 (Raad owner, toll-free API
  simulated because no business owns a toll-free number): steps 1–4, uploading, failed + retry, send refused,
  sending, sent, fix — matched `SCpaW`; step 1 and 4 also dark.
- Focused readiness, webhook, cron and purchase specs — 65 pass. 4b communications/readiness/webhook specs —
  435 pass (2026-10-23).
- SQL switch-on proven in a rolled-back transaction on Raad's org (moved 1, second run 0).
- Playwright 1440 light/dark (Raad owner): live under-review card; mocked board/status/action states matched
  `NbWfA` after skeleton, rename and flag corrections.

## Next

1. Merge 4c to main and push.
2. Real journey (draft → picture → send) waits for a real toll-free number: buying one needs number prices and
   Jafar's go-ahead; a real send needs truthful business details and his yes.

## Limits / notes

- "Text customers in another country" link left out of the summary until Part 5 builds destination requests.
- A ready non-US number can be made default; Part 5 must stop it texting other countries (live SMS is off anyway).
- The Chrome extension wasn't connected this session, so checks used Playwright.
