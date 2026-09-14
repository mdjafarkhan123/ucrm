# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done (all committed)
- 2C-1 top-up (36ebdd0), 2C-2 rates (09e88eb), 2C-3 readiness/registration (7da6fe3),
  2C-4 holds+promo+adjustments/refunds (3be87cb, 60/60 pgTAP).
- 2C-5a Credit top-up decision API (13788a0).
- Retry-safety prerequisite for 2C-4's money commands (50e3435, 78/78 pgTAP).
- 2C-5b Holds + promo + adjustments/refunds owner API (9480c81, 40/40 vitest).
- **2C-5c is now fully closed (org-scoped 0ab257f + platform-scoped, both 2026-09-14).** Platform-scoped
  part: new `platform_audit_events` table (11/11 pgTAP) + `/api/jafar/communications/sms/platform-holds`
  (place/release, step-up) + `/api/jafar/communications/sms/retail-rates` (publish a rate, no step-up).
  13/13 vitest; svelte-check 0/3358 files. Not yet committed to git.

## Exact next action (new session)
1. Commit the 2C-5c platform-scoped work (staged: migration + pgTAP + owner.ts + owner.schema.ts +
   database.types.ts + the two new route folders under `src/routes/api/jafar/communications/sms/`).
2. Ask Jafar which comes next: (a) scope the contractor-facing SMS registration-submission part (Twilio's
   ISV rule means `attested_by` must be the contractor's real identity, not Jafar's — needs its own roadmap
   part, likely alongside a Phone & SMS contractor settings page), or (b) start 2C-6, the Jafar owner UI for
   all of Stage 2C's data/commands built so far.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Step-up vs routine-action rule: `docs/jafar-organization-management-mission.md` "High-impact action security"
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C build list)
- Route + spec + actor-sentinel template: 2C-5a/5b/5c files; `$lib/server/communications/sms-owner.ts`;
  platform-scoped audit via `recordPlatformAudit` in `$lib/server/access/owner.ts`.

Resume: `read memory and continue — communications-activation`.
