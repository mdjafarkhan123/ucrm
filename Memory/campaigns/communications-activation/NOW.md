# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done (all committed)
- 2C-1..2C-5c (top-up, rates, readiness/registration, holds+promo+adjustments/refunds, owner command API —
  org-scoped and platform-scoped) — see ROADMAP for commit hashes.
- **2C-6a is done (commit 68c394c).**
  New SMS reads (mode, registrations+readiness, sender-identities) + three owner-UI components wired into
  `CommunicationsWorkspace`. 85/85 vitest, svelte-check 0/3364, svelte-autofixer clean.

## Exact next action (new session)
Build **2C-6b: Commercial access tab** — SMS credit top-up decisions, holds (place/release), promotional
credits (grant/revoke), and adjustments/refunds, as owner-UI components added to `AccessWorkspace` (the
"Access & limits" tab), next to the existing `CommercialActions`. Same shape as 2C-6a: these commands are
write-only today (built in 2C-5b), so add their GET reads first, then the components. Unlike 2C-6a, these
commands ARE on the step-up list (reuse `OwnerReconfirmDialog`, the pattern already in `CommercialActions.svelte`).

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Step-up vs routine-action rule: `docs/jafar-organization-management-mission.md` "High-impact action security"
- 2C-6a template: `src/lib/components/jafar/SmsModeActions.svelte` (query+edit form, no step-up),
  `SmsRegistrationActions.svelte` (list + dialogs), `SmsSenderCapabilitiesActions.svelte` (list + inline edit).
  For 2C-6b, `CommercialActions.svelte` is the closer template (step-up via `OwnerReconfirmDialog` on 409).
- SMS owner routes live under `src/routes/api/jafar/organizations/[organizationId]/communications/sms/*`
  (holds, credit-topups, promotional-credits, adjustments, refunds — all POST-only today, no GET yet).

Resume: `read memory and continue — communications-activation`.
