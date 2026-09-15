# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 9 (Twilio Trust Hub ISV registration): 9A (ledger), 9B (Standard-path saga), Sole Proprietor path, and 9C
(Campaign creation + Brand/Campaign status sync) are all DONE 2026-09-15 (unit-tested against mocks), **and
COMMITTED** (commits `89c347d` then `3772b2a`). Full detail: ROADMAP.md's "Stage 9" section (9C entry not yet
written up there — do that first if resuming this part).

9C's `syncTrustHubRegistrationStatus` (trust-hub-submission.ts) re-fetches Brand status, creates the Campaign
once (via the Messaging Service Stage 2B already provisions per org), and reflects the result onto
`communication_sms_registrations.status` using the existing 2C-3 RPCs. Campaign content (description, message
flow, sample messages) is pulled from the contractor's own attested Stage 3A `messaging` answers, not invented
copy — Jafar directed "follow what GHL does" for this content 2026-09-15. Tightened
`communications-sms-registration.schema.ts`'s messaging min-lengths to Twilio's real Campaign minimums (40/40/20
chars) so a too-short attested answer fails locally instead of on a real Twilio submission.

**Hard constraint, confirmed live in Twilio Console:** neither the platform (UCRM's own Twilio account) nor any
contractor has a real registered business yet. This blocks live proof for Stage 9 and Stage 8 — build and
unit-test with mocked responses only, never spend real money firing placeholder data at Twilio's live API.

**Business-registration thread blocked 2026-09-15:** Jafar is in Bangladesh with only a website and his personal
National ID; Twilio's Sole Proprietor tier is US/Canada-resident only. He still needs a real registered legal
entity + business registration/tax number before either path can go live.

## Exact next action

Independent threads; Jafar picks which to resume:

1. Write up 9C in ROADMAP.md's Stage 9 section (currently only says "Planned").
2. Adapter-level spec for `twilio-trust-hub.ts` (exact HTTP method/path/param checks for every method, mirroring
   `twilio-sms-submit.spec.ts`) + a clean full-project `svelte-check` run (confirmed clean 2026-09-15 with
   `NODE_OPTIONS="--max-old-space-size=6144"` — the earlier OOM was a memory-limit issue, not a real error;
   plain `npm run check` may still OOM without that env var on this machine).
3. Business registration (blocked on Jafar's paperwork, see above).

Stage 8 (billing reconciliation, recovery and launch proof) stays deferred behind Stage 9's live-proof
prerequisite; its non-blocked pieces (price reconciliation logic, 200-tenant load test) can start in parallel.

## Constraint

A2P 10DLC cannot be completed for Jafar's test org, or for the platform's own ISV profile, until a real
registered business exists for either. Provider-owned actions and any real registration fee stay Jafar's
explicit call.

Resume: `read memory and continue — communications-activation`.
