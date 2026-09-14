# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live.
SMS Stages 1/2A/2B are done and live-verified for one org. Stage 2C (money + control layer) is being built as
multi-session parts — see ROADMAP "Stage 2C parts". No live SMS is needed for 2C (the A2P wall below only
blocks flipping texting on later).

## Done this session (2026-09-14)
- **2C-2 Retail rates — DONE** (commit 09e88eb). New server-owned immutable table
  `communication_sms_retail_rates` keyed by destination/sender/message-unit + currency, plus two
  security-definer commands: `communication_sms_set_retail_rate` (publish a version) and
  `communication_sms_effective_retail_rate` (the applicable-rate lookup a send will freeze). Applicable rate =
  latest version whose effective_from has arrived; future-dated waits, retroactive refused; provider cost +
  margin are server-owned/Jafar-only. Migration applied to the dev DB; 26 pgTAP assertions green. Money model
  was already decided — do NOT re-ask (see pointers).

## Exact next action
Build **2C-3 Readiness & registration** as the next part: store supported sender capabilities, plain readiness
states, registration submission + history, effective SMS mode and country readiness. Same shape as 2C-1/2C-2 —
server-owned table(s) + RLS deny-all + security-definer command(s) + pgTAP, verified against the dev DB, then
commit. Owner API and UI are later parts (2C-5, 2C-6).

## Constraint (still current)
A2P 10DLC (US "prove you're a real business" gate) can't be completed for Jafar's own test org — needs a real
client (any country except Asia). Adopted number stays SMS-blocked until then. Model A2P as a per-contractor-org
step. Does not block any 2C data/owner work.

## Essential pointers
- Money + owner-control truth (do not re-decide): `docs/research/communications-a2-stage6-settings-owner-controls-plan.md`
- Full stage spec: `docs/communications-a2-implementation-plan.md` (Stage 2C, section on readiness/registration)
- Pattern to copy: migration `supabase/migrations/20260917100000_communications_sms_retail_rates.sql`
  + test `supabase/tests/database/communications_sms_retail_rates.sql` (or the 2C-1 topup pair)
- Verify pgTAP via Supabase MCP: run the test body in a `begin; … select * from finish(); rollback;` block
  (execute_sql returns finish()'s diagnostics; a clean run ending "ok N" = pass; a real failure raises). No
  local Supabase stack is running.

Resume: `read memory and continue — communications-activation`.
