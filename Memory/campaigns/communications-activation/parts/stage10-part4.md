# Stage 10 Part 4 — Can each number text yet?

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 4
**Stage:** 4a merged to main 2026-10-22; 4b merged to main 2026-10-23; 4c design approved and merged 2026-10-23
(board `SCpaW`). 4c build paused by Jafar 2026-10-23, unmerged WIP branch `codex/stage10-part4c-build`,
worktree `.worktrees/stage10-part4c-build`, claim `af28d8dfeb32`. · **Done when:** every number shows its true steps and band (board `NbWfA`), numbers go
live once their approval passes, toll-free has its own check, merged to main.

## Slices

- **4a — merged 2026-10-22.** Readiness: `src/lib/communications/number-readiness.ts`,
  `src/lib/server/communications/sms-number-readiness.ts`; migration `20261224090000_sms_sender_readiness.sql`
  applied. US local needs approved registration; other local needs in-date paperwork; toll-free its own check.
- **4b — merged 2026-10-23.** Applied `20261225090000_sms_tollfree_verification.sql`: one check per sender,
  history and approval switch-on. Schema `validation/communications-sms-tollfree.schema.ts`; adapter
  `twilio-tollfree.ts`; send/sync/check `sms-tollfree-verification.ts`. Webhook and daily checks handle outcomes.
  Jafar's Twilio setup later: the Event Streams Subscription must add the 8 toll-free event types and receive
  subaccount events.
- **4c — design approved by Jafar 2026-10-23:** Pencil board `SCpaW`, option A only. A four-step form opens
  from the toll-free card: Business (prefilled from registration), Texting (consent and samples), Proof of consent
  (one to five pictures), Check and send. Saved drafts, upload progress/error, sending, under-review and rejected
  states are drawn. Option B was removed.

## Proof so far

- Focused readiness, webhook, cron and purchase specs — 65 pass. 4b communications/readiness/webhook specs —
  435 pass (2026-10-23).
- SQL switch-on proven in a rolled-back transaction on Raad's org (moved 1, second run 0).
- Playwright 1440 light/dark (Raad owner): live under-review card; mocked board/status/action states matched
  `NbWfA` after skeleton, rename and flag corrections.

## Next

1. Resume the WIP branch. Draft/save, private R2 proof upload with durable public token URL, public proof read,
   send API, form and number-card link are coded. Migration `20261226090000_sms_tollfree_proof_images.sql` is
   **not applied**; do not use these routes before it is applied. No real verification was started.
2. Fix the form/API defects and add meaningful focused tests. Focused `tsc` found no new TS errors after fixes;
   its remaining two errors are missing generated `PUBLIC_SUPABASE_*` types in this worktree. Full `npm run check`
   hit Node's 4 GB heap limit; the 6 GB retry was interrupted when Jafar requested a pause. Svelte autofixer
   flagged `fileInput` not reactive; fixed, but re-run autofixer. Review CSS warnings (likely nested SCSS).
3. Apply the migration through the project's psql command, verify with Supabase reads, then screen-check the
   page against `SCpaW` and prove draft → picture upload → save on the live app. Do not press Send with a real
   business until Jafar authorizes that submission. Merge and push main after checks pass.

## Limits / notes

- "Text customers in another country" link left out of the summary until Part 5 builds destination requests.
- A ready non-US number can be made default; Part 5 must stop it texting other countries (live SMS is off anyway).
- The Chrome extension wasn't connected this session, so checks used Playwright.
