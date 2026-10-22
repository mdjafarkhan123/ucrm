# Stage 10 Part 4 — Can each number text yet?

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 4
**Stage:** 4a merged to main 2026-10-22; 4b next on branch `claude/stage10-part4` (worktree
`.worktrees/stage10-part4`, claim `d7269736bf63`) · **Done when:** every number shows its true steps and band (board `NbWfA`), numbers go
live once their approval passes, toll-free has its own check, merged to main.

## Slices

- **4a — merged 2026-10-22.** Rules: `src/lib/communications/number-readiness.ts` (+ spec, 13 tests). Facts join and
  switch-on helpers: `src/lib/server/communications/sms-number-readiness.ts`. API: `GET
  /api/settings/communications/sms/readiness`. DB (applied live): `20261224090000_sms_sender_readiness.sql`,
  `communication_sms_reconcile_sender_readiness(org, us_use_case)` — US local needs the approved US registration;
  other countries need approved in-date paperwork; toll-free never. Called after purchase completes
  (`sms-number-purchase-store.ts`), after paperwork/Trust Hub webhooks, and by the daily cron. UI:
  `components/communications/number-readiness/*`; Phone & SMS page now has breadcrumb + concept header, summary,
  cards two to a row, foot line; registration form, holds and compliance kept below. Old Readiness strip and
  number list removed.
- **4b — next:** toll-free check on the server (Twilio `POST messaging.twilio.com/v1/Tollfree/Verifications`; needs
  OptInImageUrls, OptInType, UseCaseCategories, MessageVolume, business registration number unless sole
  proprietor; status events `com.twilio.messaging.compliance.toll-free-verification.*`). Own table per number;
  extend the reconcile to switch toll-free on when approved.
- **4c — needs a Pencil drawing first:** the toll-free "Add business details" form (reuses registration answers,
  adds an opt-in proof picture). Until then the toll-free band has no button.

## Proof so far

- `npx vitest run` readiness spec + Twilio webhook, cron and purchase specs — 65 pass.
- SQL switch-on proven in a rolled-back transaction on Raad's org (moved 1, second run 0).
- Playwright 1440 light/dark on port 5181 (Raad owner): live under-review card; mocked four-number board,
  turned down / just bought / paused, ⋯ menu, empty, couldn't load, loading, renaming, all-ready — match `NbWfA`
  after fixing the skeleton shape, rename label/outline and off-centre round flags (`PaperworkFlag`, shared).

## Next

1. Build 4b (toll-free check on the server) in the same worktree, after `git merge main`.
2. Draw the 4c form in `concept.pen` for Jafar's approval (another session builds it).

## Limits / notes

- "Text customers in another country" link left out of the summary until Part 5 builds destination requests.
- A ready non-US number can be made default; Part 5 must stop it texting other countries (live SMS is off anyway).
- The Chrome extension wasn't connected this session, so checks used Playwright.
