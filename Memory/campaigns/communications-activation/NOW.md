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

## Decided by Jafar 2026-09-14 (both verified against real industry sources, not guessed)
1. **Registration submission is contractor-facing, not a Jafar owner action.** Twilio's own ISV rule
   ("you must use your customer's information... do not use your own") means `attested_by` on
   `communication_sms_submit_registration` must be the contractor's real identity. Jafar's owner API
   must NOT call this command. The actual contractor-facing submit action has no home yet in the
   roadmap (only "two contractor settings pages" are named, unscoped) — needs its own roadmap part
   before it's built, likely alongside the Phone & SMS contractor settings page.
2. **Platform-scoped actions get their own new audit table**, not a loosened `access_audit_events`.
   Standard multi-tenant practice keeps a tenant-scoped audit log hard-scoped (no blank-tenant rows);
   platform-wide events belong in their own small table. Not yet built.

## Exact next action (new session)
1. Design + migrate a small platform-audit-events table (who/when/what/why, no organization_id) —
   this is a schema change, confirm the shape with Jafar first per the schema-confirmation rule, then
   pgTAP it like every other 2C migration.
2. Build the two platform-scoped owner routes on top of it: `communication_sms_place_hold` (scope
   'platform') release, and `communication_sms_set_retail_rate` — same 2C-5a/5b/5c template.
3. That closes 2C-5c. Then either scope the contractor-facing registration-submission part (decision 1
   above), or move to 2C-6 (Jafar owner UI for all of Stage 2C) — ask Jafar which first.

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
