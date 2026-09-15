# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 9 (Twilio Trust Hub ISV registration): 9A (ledger), 9B (Standard-path saga), Sole Proprietor path, and 9C
(Campaign creation + Brand/Campaign status sync) are all DONE (unit-tested against mocks). 9A+9B **COMMITTED**
(`89c347d`, `3772b2a`). 9C's roadmap write-up plus a new adapter-level test spec were completed 2026-09-15 —
see ROADMAP.md's "Stage 9" section for full detail. **Two files UNCOMMITTED** (Jafar commits explicitly, same
pattern as every prior stage): `src/lib/server/communications/twilio-trust-hub.spec.ts` (new, 22 tests) and
this campaign's `ROADMAP.md`.

9C's `syncTrustHubRegistrationStatus` (trust-hub-submission.ts) re-fetches Brand status, creates the Campaign
once (via the Messaging Service Stage 2B already provisions per org), and reflects the result onto
`communication_sms_registrations.status` using the existing 2C-3 RPCs. Campaign content (description, message
flow, sample messages) is pulled from the contractor's own attested Stage 3A `messaging` answers, not invented
copy — Jafar directed "follow what GHL does" for this content 2026-09-15. Tightened
`communications-sms-registration.schema.ts`'s messaging min-lengths to Twilio's real Campaign minimums (40/40/20
chars) so a too-short attested answer fails locally instead of on a real Twilio submission.

**Gap found while closing out 9C, not yet its own roadmap part:** `syncTrustHubRegistrationStatus` has no
owner-facing trigger — no cron poll and no Trust Hub status-callback webhook calls it yet, so today it only runs
if invoked directly. Needs scoping (poll cadence vs. webhook vs. both, mirroring `api/webhooks/twilio/status`)
before Stage 8's live proof can rely on status actually syncing.

**Hard constraint, confirmed live in Twilio Console:** neither the platform (UCRM's own Twilio account) nor any
contractor has a real registered business yet. This blocks live proof for Stage 9 and Stage 8 — build and
unit-test with mocked responses only, never spend real money firing placeholder data at Twilio's live API.

**Business-registration thread blocked 2026-09-15:** Jafar is in Bangladesh with only a website and his personal
National ID; Twilio's Sole Proprietor tier is US/Canada-resident only. He still needs a real registered legal
entity + business registration/tax number before either path can go live.

## Exact next action

Independent threads; Jafar picks which to resume:

1. Scope and build the trigger for `syncTrustHubRegistrationStatus` (poll and/or webhook) — closes the gap found
   above; this is genuinely new, unscoped work, not yet approved.
2. Business registration (blocked on Jafar's paperwork, see above).
3. Ask Jafar to review and commit the two uncommitted files above.

Stage 8 (billing reconciliation, recovery and launch proof) stays deferred behind Stage 9's live-proof
prerequisite; its non-blocked pieces (price reconciliation logic, 200-tenant load test) can start in parallel.
Full-project `svelte-check` confirmed clean 2026-09-15 with `NODE_OPTIONS="--max-old-space-size=6144"` — the
earlier OOM was a memory-limit issue, not a real error; plain `npm run check` may still OOM without that env var
on this machine. A full `vitest run` the same day showed 71 pre-existing failures across 11 files, all in
quotes/settings-business/team-invitations — unrelated to Communications, not investigated (out of scope here).

## Constraint

A2P 10DLC cannot be completed for Jafar's test org, or for the platform's own ISV profile, until a real
registered business exists for either. Provider-owned actions and any real registration fee stay Jafar's
explicit call.

Resume: `read memory and continue — communications-activation`.
