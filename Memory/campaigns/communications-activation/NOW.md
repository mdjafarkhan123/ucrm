# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done (data layer + first owner API slice, all committed)
- 2C-1 top-up (36ebdd0), 2C-2 rates (09e88eb), 2C-3 readiness/registration (7da6fe3),
  2C-4 holds+promo+adjustments/refunds (3be87cb, 60/60 pgTAP).
- **2C-5a Credit top-up decision API (13788a0)** — owner confirm/reject route + 7 vitest green;
  svelte-check 0 across repo. Established the reusable owner-endpoint template and regenerated
  database.types.ts from the dev DB.

## Active part: 2C-5b Holds + promo + adjustments/refunds owner API
Copy the 2C-5a template for the remaining ORG-scoped money/control endpoints: place/release hold (org +
provider scope for one org), grant/revoke promotional credit, record adjustment, record refund. Each: owner
session + Zod (add schemas to owner.schema.ts) + step-up + org-scoped guard + P0001→409 + audit via
`recordOwnerAccessAudit`, passing `PLATFORM_OWNER_ACTOR_ID` as the command actor.

## Exact next action
Build 2C-5b. Copy `src/routes/api/jafar/organizations/[organizationId]/communications/sms/credit-topups/[requestId]/+server.ts`
+ its spec as the template. Command signatures already gathered — see the migrations; actor params are free
uuids (no FK). Verify each route with a co-located vitest spec + svelte-check.

## Deferred inside 2C-5c (do not lose)
Platform-scoped actions (platform-wide hold, global retail rates) have NO organization_id, so
`access_audit_events` (organization_id NOT NULL) can't record them. Decide a platform-audit target before
building those. Org/provider holds and per-org promo/adjustments are fine with the org audit.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C build list)
- Route + spec + actor-sentinel template: the 2C-5a files above; `$lib/server/communications/sms-owner.ts`.

Resume: `read memory and continue — communications-activation`.
