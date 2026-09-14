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
- **2C-5c (org-scoped part) — registration/mode/sender-capability owner API (0ab257f)**: start
  registration, record carrier outcome, record readiness check, set org SMS mode, set sender
  capabilities. 25/25 vitest; svelte-check 0/3349 files.

## Blocked on Jafar — two product/architecture decisions before 2C-5c can close
1. **Who attests a registration submission?** `communication_sms_submit_registration`'s `attested_by`
   is documented as "the contractor attests the submitted info is truthful," but the stage6 plan also
   says "Jafar may... submit/resubmit registration." Building this against the Jafar-only owner API
   would record Jafar's identity as the attester of the contractor's business truthfulness — a real
   compliance-record question, not a guessable technical detail. Need: is registration submission a
   contractor-facing action (its own future route, contractor session), or does Jafar's UI capture a
   real contractor user id to pass through as the attester?
2. **Platform-audit target for platform-scoped actions.** A platform-wide hold and the global retail
   rate command have no `organization_id`, so `access_audit_events` (NOT NULL) can't record them.
   Options to weigh: a nullable `organization_id` + check constraint, a separate platform-audit table,
   or reusing the sentinel differently. Needed before building `communication_sms_place_hold` (scope
   'platform') and `communication_sms_set_retail_rate`.

## Exact next action
Ask Jafar both questions above (see full framing in this file — do not re-decide, just ask). Once
answered: build whichever of (registration submission route) / (platform hold + retail-rate routes)
the answers unblock, closing out 2C-5c. Then 2C-6: Jafar owner UI for all of Stage 2C.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Step-up vs routine-action rule: `docs/jafar-organization-management-mission.md` "High-impact action security"
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C build list)
- Route + spec + actor-sentinel template: 2C-5a/5b/5c files; `$lib/server/communications/sms-owner.ts`.

Resume: `read memory and continue — communications-activation`.
