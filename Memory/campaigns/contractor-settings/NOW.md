# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Current part

Part 6D (engine). 6D-1, 6D-2a, 6D-3a, 6D-3b, 6D-4, 6D-5 closed. **6D-2b code done + verified 2026-08-31**
(untracked): `src/lib/server/automation/worker.ts` + `worker.spec.ts` (20/20), route
`src/routes/api/internal/automation/worker/+server.ts` (Bearer, timing-safe), `AUTOMATION_WORKER_SECRET` in
`env.ts`; prettier-clean, no new check reds. **6D-6 partly done**: plan evidence for the 4 hot query/index
pairs recorded (docs/automation-behavior-contract.md § 6D-6), and a confirmed claim bottleneck fixed —
migration `20260831065617_automation_claim_bounded_candidate_window` (applied + repo synced) bounds the
fairness ranking to the candidate slice (~135×, no disk spill), behavior-identical, 6D-2 pgTAP claim/lease/
recovery all pass (4 `action_not_available` failures are pre-existing 6D-3 drift, not this change).

## Exact next action — 6D-2b ACTIVATED (dev); 6D-6 still Jafar-gated

**6D-2b ACTIVATED 2026-08-31 (dev), engine live & proven end-to-end:** shared secret matches in `.env`
`AUTOMATION_WORKER_SECRET` and vault `automation_worker_secret` (48 chars); vault
`automation_worker_target_url` = `https://app.upliftcontractor.com/api/internal/automation/worker` (tunnel);
cron job 8 `automation-worker-wake-one-minute` now `active=true`. Proof: manual
`dispatch_automation_worker_wake()` → ledger row `route_outcome=idle`, 0 claimed (auth accepted, worker ran,
reported back). Journey flag still false so it idles — nothing sends.

**Bug found + fixed during activation:** `dispatch_automation_worker_wake()` raised 42702 (ambiguous
`worker_name`: local const vs ledger column) on its prune DELETE — never hit before because the fn had never
run. Fixed by renaming locals to the `v_` convention the sibling `request_automation_worker_wake()` already
uses. Migration `20260831071500_automation_worker_wake_dispatch_ambiguous_column_fix` (applied to remote +
repo file synced to live body). **NOTE: the same v_-rename should be verified in the repo copy of the
ORIGINAL 20260831022758 body if that file is ever the source of a fresh DB rebuild** — remote is correct now.

**Next real action = 6D-6 close (Jafar-gated env)** and eventual journey-flag flip (carry-forward).

2. **6D-6 close** (blocked on a production-like isolated env — Jafar's staging/cutover gate): sustained
   250 ev/s + 100 due/s bursts 5 min, 100k backlog drain/restart, concurrent-claim-no-double-claim under
   contention, connection/lock + p95-under-load. Capacity NOT established until these pass off the shared
   remote. Plus the batched browser pass over 6D-3b/6D-4/6D-5 surfaces (needs a temporary journey-flag flip).
   Load fixture: scratchpad/6d6_claim_plans.sql.

Uncommitted: all Part 6D automation code + migrations `20260831065617` and `20260831071500` + `.env` secret
line + this doc/memory. Commit only when Jafar says so.

## Follow-ups (not blockers)

- Update `supabase/tests/database/automation_6d2_claims_and_recovery.sql` action assertions to expect
  `action_due` (6D-3 superseded the park; 4 stale checks).
- `automation_work_items_attention_idx` is DESC but `resume_automation_work_items` orders ASC — revisit only
  if recovery latency matters.

## Carry-forward

- Flip `AUTOMATION_JOURNEY_READY` (`src/lib/automation/journey.ts`) to reveal the Settings card and the Quote
  automation card together; warm `/settings/automation` when the engine is real.
- Pre-existing `npm run check` reds (own follow-up): `recipes/+server.ts` 191/192 and
  `recipes/[id]/activate/+server.ts` 107 (nullable-RPC-arg — fix `default null` on those SQL params);
  `quotes/[id]/+page.svelte` ~532 onclick implicit-any.

## Blockers

- 6D-6 load close is blocked on a production-like isolated environment. (6D-2b activation is DONE.)

## Essential pointers

- docs/automation-behavior-contract.md (§ 6D-6 engine query evidence; § Enrollment, re-entry, and overlap)
- Memory/campaigns/contractor-settings/ROADMAP.md — read only when opening or closing a 6D slice
