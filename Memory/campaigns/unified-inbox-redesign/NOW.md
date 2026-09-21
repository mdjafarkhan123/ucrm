# Unified inbox redesign — now

- Goal: renew the existing inbox surface in separately verified slices without inventing unsupported behavior.
- State 2026-09-21: Parts 1–7 are all built and committed (Part 7 = the commit right after `4764e45`, "Unified inbox Part 7").
- Exact next action: wait for Jafar to confirm the finance/sales login check below. Then the campaign is finished: remove its registry row in `Memory/INDEX.md` and delete `Memory/campaigns/unified-inbox-redesign/` (product truth already lives in `docs/research/ghl-inbox-dnd-controls-2026-09-21.md`).
- Jafar must do himself: sign in as the `finance` and `sales` test logins and confirm amounts are hidden without price permission (browser rules forbid me typing passwords). Server side is already proven by tests.
- Open, only if wanted later: the customer's own STOP/START as lines in the thread (needs a real customer STOP to verify against); the unlinked-sender panel was never checked because every Raad LTD conversation is linked.
- Decided: desktop app only. Send Later stays email-only; Website Chat never gets it.
- Blockers: none. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=6144` on this machine.
