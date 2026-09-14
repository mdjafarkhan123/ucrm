# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done (all committed)
- 2C-1..2C-5c (top-up, rates, readiness/registration, holds+promo+adjustments/refunds, owner command API —
  org-scoped and platform-scoped) — see ROADMAP for commit hashes.
- 2C-6a (commit 68c394c). SMS reads (mode, registrations+readiness, sender-identities) + three owner-UI
  components wired into `CommunicationsWorkspace`.
- 2C-6b (commit 59ed7dc). Commercial access tab: GET reads on holds/promotional-credits/adjustments/
  refunds/credit-topups + 4 owner-UI components wired into `AccessWorkspace`. Ledger entries now store their
  reason (migration `20260917150000`). 97/97 vitest; browser-verified for holds and adjustments (promo
  grant/revoke and refund covered by unit tests only — not live-clicked this session).
- 2C-6c (commit 636a7c3). History & recovery tab: GET `.../sms/registration-events` (joins each append-only
  registration event with its country/sender type/use case) + read-only `SmsRegistrationHistory` component
  in `ActivityWorkspace`. Added friendly labels for the 13 SMS event types already in `access_audit_events`.
  101/101 vitest; svelte-check 0/3375; browser-verified live for Raad LTD (start + readiness check both
  appeared correctly).

## Exact next action (new session)
Start 2C-6d: platform-wide platform-holds + retail-rates owner UI, extending the existing top-level
`/jafar/communications` page (per ROADMAP "Stage 2C parts"). No open decisions carried over — same template
as 2C-6a/6b/6c (add missing GET reads first, then owner-UI components). This closes Stage 2C and A2's
Jafar-UI planning item.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Does not block any 2C work.

## Essential pointers
- Money + owner-control truth: `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Step-up vs routine-action rule: `docs/jafar-organization-management-mission.md` "High-impact action security"

Resume: `read memory and continue — communications-activation`.
