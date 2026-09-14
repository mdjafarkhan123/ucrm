# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B are done and live-verified for one org. Stage 2C (money + control layer) is now being
built as multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall
below only blocks flipping texting on later).

## Done this session (2026-09-14)
- Committed the finished Stage 2B master-Auth-Token work (commit 4c884e7; 117 comms unit tests green).
- **2C-1 Credit top-up lifecycle — DONE** (commit 36ebdd0). New server-owned table
  `communication_sms_credit_topup_requests` + four security-definer commands (request / confirm / reject /
  cancel). Confirm posts one immutable purchased-credit entry into the Stage 1 ledger and raises the settled
  balance atomically; contractor cancels only awaiting; reject needs a reason. Migration applied to the dev
  DB; 29 pgTAP assertions green. Money model was already decided — do NOT re-ask (see pointers).

## Exact next action
Build **2C-2 Retail rates** as the next part: Jafar-set retail rate versions, current + future-dated, keyed by
destination/sender/message-unit; new rates affect new sends only and historical charges keep their original
rate; provider cost and margin visible to Jafar only. Same shape as 2C-1 — server-owned table(s) + RLS +
security-definer command(s) + pgTAP, verified against the dev DB, then commit. Owner API and UI are later parts.

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C)
- Pattern to copy: migration `supabase/migrations/20260917090000_communications_sms_credit_topup_requests.sql`
  + test `supabase/tests/database/communications_sms_credit_topup_requests.sql`
- Verify pgTAP via Supabase MCP: run the test body in a `begin; … select * from finish(); rollback;` block
  (execute_sql returns finish()'s diagnostics; empty/"ok N" = pass). No local Supabase stack is running.

Resume: `read memory and continue — communications-activation`.
