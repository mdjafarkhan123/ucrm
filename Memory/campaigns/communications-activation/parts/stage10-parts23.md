# Stage 10 Parts 2 + 3 — Buy a number, and its paperwork

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 2, § Part 3
**Stage:** Waiting to merge · **Branch / folder:** `claude/stage10-parts23` in `.worktrees/stage10-parts23` (pushed)
**Claim:** `4e0ad188b841` (owner `claude-stage10-opus`) — keep until merged.
**Done when:** a business can buy a texting number from Add number (board `qaFQf`) and send country paperwork
(board `A0URqF`), every state matches its board, then merged to main.

## Part 2 — built 2026-10-22 (not merged)

Migrations `20261222120000`/`…120100` (live); saga `sms-number-purchase.ts`; UI
`components/communications/add-number/*`. Proof: 15 saga tests; live walk, nothing bought. Open: no number prices yet (Jafar to set US local/toll-free); monthly
renewal not built (needs research + Jafar's decision before any live purchase); sweep for orders stuck
"purchasing"; bought/refusal states unscreenshotted (need a real buy).

## Part 3 — built 2026-10-22 (merging)

- DB (applied live): `20261223090000_sms_number_paperwork.sql` — sets, documents (file = protected setup document,
  fact key `texting.number_paperwork`), history. Server: `twilio-regulatory.ts`, `sms-number-paperwork*.ts`; API under
  `/api/settings/communications/sms/paperwork`; signed webhook; daily check in `trust-hub-status-cron`.
- Screens: `components/communications/paperwork/*` and routes `settings/communications/sms/paperwork`
  (list, `new`, `[id=uuid]?step=details|documents|check`). Phone & SMS has a Number paperwork button. Shared:
  `ui/RadioTile.svelte`; `ImportStepper` takes its own `steps`.
- Proof 2026-10-22 (Playwright, 1440 light+dark, Raad owner, nothing sent to Twilio): list empty/with sets; UK mobile
  (address only) and AU mobile (one register extract covers three) walked to Check and send; refused file, upload →
  Checking; Added after marking only the test PDF checked by SQL (dev file-check cron is off); field errors; sent
  back / under review / approved set by SQL. Test sets deleted. `sms-number-paperwork.spec.ts` + purchase spec pass.
- Limits: storage CORS refuses uploads from any port but 5173 (proof passed the PUT through Playwright); Send for
  review never pressed live (needs real details and Jafar's go-ahead); no Delete draft or file trash (no API).

## Next

Merge `claude/stage10-parts23` to main, push, release claim `4e0ad188b841`; then Stage 10 Part 4 (readiness per
number, board `NbWfA`).

## Questions for Jafar

- Board says "We'll email you" on a decision; nothing emails the business yet (Twilio emails Uplift). Built copy says
  "The answer shows here". Ask whether to build that email.
