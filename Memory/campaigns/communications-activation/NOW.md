# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B/2C are all done and live-verified for one org. Stage 2C (money + control layer) is
complete — see ROADMAP "Stage 2C parts" for the full history.

## Done (all committed)
- 2C-1..2C-5c (top-up, rates, readiness/registration, holds+promo+adjustments/refunds, owner command API —
  org-scoped and platform-scoped) — see ROADMAP for commit hashes.
- 2C-6a/6b/6c (Integrations, Commercial access, History & recovery owner-UI tabs) — see ROADMAP.
- 2C-6d (commit b808080). Operations health: platform-wide platform-holds + retail-rates GET reads +
  `SmsPlatformHoldActions`/`SmsRetailRateActions` wired into `/jafar/communications`. 109/109 vitest;
  svelte-check 0/3377; browser-verified live (rate publish, hold place+release with step-up).

**Stage 2C is now fully complete.** This also closed A2's Jafar-UI planning item.

## Exact next action (needs Jafar first)
No dependency-ready next atomic action exists yet. What remains for A2 is the contractor-facing
implementation (Conversations SMS, Automation SMS, the Phone & SMS settings page) — a separate,
not-yet-scoped implementation stage (ROADMAP "A2 product planning is complete; implementation planning
remains a separate, unstarted stage"). Before starting it, resolve the deferred question from 2C-5c: where
registration *submission* lives, since Twilio's ISV rule requires `attested_by` to be the contractor's own
identity, not Jafar's — this needs its own roadmap part alongside the Phone & SMS settings page. Bring this
to Jafar to scope before coding.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then.

## Essential pointers
- Money + owner-control truth: `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Product/UI blueprint: ROADMAP "A2 product-planning sequence" (approved 2026-09-12/13)

Resume: `read memory and continue — communications-activation`.
