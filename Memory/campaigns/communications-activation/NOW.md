# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done (Stage 2C data layer complete + committed)
- 2C-1 top-up lifecycle (36ebdd0), 2C-2 retail rates (09e88eb), 2C-3 readiness/registration (7da6fe3),
  **2C-4 holds + promo credit + adjustments/refunds (3be87cb, 60/60 pgTAP green, applied to dev DB).**

## Active part: 2C-5 Owner commands (API)
Wrap the 2C-1..2C-4 security-definer commands in `/api/*` routes: Zod validation, owner-only auth,
reconfirmation on money/hold actions, and an immutable audit record. Commands to expose:
- Top-up confirm/reject (2C-1), set retail rate (2C-2), registration start/submit/record-outcome +
  set org mode + set sender capabilities (2C-3), place/release hold + grant/revoke promo credit +
  record adjustment/refund (2C-4).

## Exact next action
Build 2C-5. First inspect existing owner/Jafar `/api/*` write routes to copy the proven pattern (Zod +
service_role call into the security-definer command + audit + reconfirmation). Then add the routes above,
one Zod schema per command, each posting to the immutable audit trail. Verify each route end to end.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C build list)
- Patterns to copy: existing Jafar/owner `/api/*` write routes (Zod-validated) calling security-definer
  commands with service_role; existing audit-record helper if one exists.

Resume: `read memory and continue — communications-activation`.
