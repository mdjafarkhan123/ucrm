# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B are done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done this session (2026-09-14)
- **2C-3 Readiness & registration — DONE** (commit 7da6fe3). `communication_sms_registrations` (one per
  org/country/sender-type/use-case; waiting_for_info→under_review→approved|action_needed, evidence tied to
  status) + append-only `communication_sms_registration_events`; sender capabilities added to
  `communication_sms_sender_identities`; `communication_sms_org_modes` (effective mode = chosen capped by
  package ceiling unless Jafar override; no row = off; modes off|operational); readiness computed on read via
  `communication_sms_readiness()`. Migration applied to dev DB; 53 pgTAP green. Product model already decided —
  do NOT re-ask (see pointers). One deliberate implementation choice to flag to Jafar: SMS mode enum is
  off|operational only, since A2 excludes marketing; marketing widens the enum in its own migration later.

## Exact next action
Build **2C-4 Holds + promotional credit** as the next part: distinct platform/org/provider holds + emergency
provider suspension (release/suspension separate from ordinary texting/balance holds; inbound + STOP/START/HELP
stay available during outbound holds); promotional credit with expiry; standalone reasoned adjustments/refunds.
Same shape as 2C-1/2C-2/2C-3 — server-owned table(s) + RLS deny-all + security-definer command(s) + pgTAP,
verified against the dev DB, then commit. Owner API and UI are later parts (2C-5, 2C-6).

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
  (Money → promotional/reserved/outstanding + adjustments/refunds; "Jafar: organization controls" → holds/suspension)
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C build list)
- Pattern to copy: migration `supabase/migrations/20260917090000_communications_sms_credit_topup_requests.sql`
  (lifecycle + ledger) + `20260917110000_communications_sms_readiness_registration.sql` (state machine + history);
  tests are the matching files in `supabase/tests/database/`
- Verify pgTAP via Supabase MCP: run the test body in a `begin; … select * from finish(); rollback;` block
  (execute_sql returns finish()'s diagnostics; a clean run's only note is the planned-vs-ran count, which must
  match — otherwise real failures show as "not ok"). No local Supabase stack is running.

Resume: `read memory and continue — communications-activation`.
